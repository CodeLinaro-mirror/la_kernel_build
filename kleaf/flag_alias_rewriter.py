# Copyright (C) 2026 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Emulates negated flag aliases, which Bazel 9 no longer supports.

Up to Bazel 8, `--flag_alias=no<name>=no<label>` made `--no<name>` set the
boolean build setting `<label>` to false. Bazel 9 rejects `no<label>` as a
label (b/495395547, https://github.com/bazelbuild/bazel/issues/31161).

FlagAliasRewriter re-implements the feature in the Bazel wrapper. Given the
aliases from flags.bazelrc and from device / user bazelrc files, it rewrites
`--no<name>` to `--no<label>`, which Bazel accepts for boolean build
settings, and drops negated alias definitions so that Bazel never sees them.
"""

import dataclasses
import pathlib
import shlex
from collections.abc import Iterable, Iterator
from typing import Optional

_WORKSPACE_PREFIX = "%workspace%/"
_IMPORT_COMMANDS = ("import", "try-import")

_FLAG_ALIAS_PREFIX = "--flag_alias="
_NEGATION_PREFIX = "no"
# "@" covers @kleaf//... flags; "//" covers root-workspace flags in
# device.bazelrc or user.bazelrc.
_LABEL_PREFIXES = ("//", "@")


@dataclasses.dataclass(frozen=True)
class RcLine:
    """A logical, non-empty line of a bazelrc file.

    Attributes:
        command: The first token, e.g. `build`, `build:myconfig` or `import`.
        args: The remaining tokens, with quotes and comments removed.
        raw: The original text of the line, with line continuations joined
            and surrounding whitespace stripped. Suitable for emitting back
            into a bazelrc file unchanged.
    """
    command: str
    args: tuple[str, ...]
    raw: str


def read_rc_file(
        path: pathlib.Path,
        workspace_dir: pathlib.Path,
        *,
        optional: bool = False,
) -> list[RcLine]:
    """Reads a bazelrc file and recursively inlines `import` / `try-import`."""
    try:
        return _read(path, workspace_dir, import_stack=())
    except OSError:
        if optional:
            return []
        raise


def _read(
        path: pathlib.Path,
        workspace_dir: pathlib.Path,
        import_stack: tuple[pathlib.Path, ...],
) -> list[RcLine]:
    content = path.read_text(encoding="utf-8")
    content = content.replace("\\\r\n", "").replace("\\\n", "")
    import_stack = (*import_stack, path.resolve())

    lines = []
    for raw in content.split("\n"):
        raw = raw.strip()
        try:
            words = shlex.split(raw, comments=True)
        except ValueError:
            words = raw.split()
        if not words:
            continue
        line = RcLine(command=words[0], args=tuple(words[1:]), raw=raw)
        if line.command in _IMPORT_COMMANDS and len(line.args) == 1:
            lines.extend(_import(line, workspace_dir, import_stack))
        else:
            lines.append(line)
    return lines


def _import(
        line: RcLine,
        workspace_dir: pathlib.Path,
        import_stack: tuple[pathlib.Path, ...],
) -> list[RcLine]:
    target = line.args[0]
    if target.startswith(_WORKSPACE_PREFIX):
        target_path = workspace_dir / target[len(_WORKSPACE_PREFIX):]
    else:
        target_path = pathlib.Path(target)

    if target_path.resolve() in import_stack:
        return [line]
    try:
        return _read(target_path, workspace_dir, import_stack)
    except OSError:
        if line.command == "try-import":
            return []
        return [line]


def _parse_flag_alias(option: str) -> Optional[tuple[str, str]]:
    """Returns (name, target) for `--flag_alias=<name>=<target>`, else None."""
    if not option.startswith(_FLAG_ALIAS_PREFIX):
        return None
    name, sep, target = option[len(_FLAG_ALIAS_PREFIX):].partition("=")
    if not sep or not name or not target:
        return None
    return name, target


def _is_negated_target(target: str) -> bool:
    """Whether a flag alias target has the form `no<label>`."""
    return (target.startswith(_NEGATION_PREFIX) and
            target[len(_NEGATION_PREFIX):].startswith(_LABEL_PREFIXES))


class FlagAliasRewriter:
    """Rewrites `--no<name>` for known flag aliases into `--no<label>`."""

    def __init__(self):
        # Targets of `--flag_alias=<name>=<label>`, keyed by name.
        self._aliases: dict[str, str] = {}
        # Targets of `--flag_alias=<name>=no<label>`, keyed by name.
        self._negated_aliases: dict[str, str] = {}

    def add_alias(self, name: str, target: str) -> None:
        """Registers `--flag_alias=<name>=<target>`. The last one wins."""
        if _is_negated_target(target):
            self._aliases.pop(name, None)
            self._negated_aliases[name] = target[len(_NEGATION_PREFIX):]
        elif target.startswith(_LABEL_PREFIXES):
            self._negated_aliases.pop(name, None)
            if not name.startswith(_NEGATION_PREFIX):
                self._negated_aliases.pop(_NEGATION_PREFIX + name, None)
            self._aliases[name] = target

    def add_aliases_from(self, lines: Iterable[RcLine]) -> None:
        """Registers all `--flag_alias` options found in the given lines."""
        for line in lines:
            for option in line.args:
                if alias := _parse_flag_alias(option):
                    self.add_alias(*alias)

    def rewrite_option(self, option: str) -> str:
        """Rewrites a single `--<name>` or `--no<name>` option if known.

        Aliases that map to a positive target, like `--notrim`, are left
        untouched. Options that are not known aliases, including native
        Bazel options like `--nobuild`, are left untouched.
        """
        if not option.startswith("--") or "=" in option:
            return option
        name = option[2:]
        if name in self._aliases:
            return option
        if name in self._negated_aliases:
            return f"--no{self._negated_aliases[name]}"
        if name.startswith(_NEGATION_PREFIX):
            positive_name = name[len(_NEGATION_PREFIX):]
            if positive_name in self._aliases:
                return f"--no{self._aliases[positive_name]}"
        return option

    def rewrite_rc_line(self, line: RcLine) -> Optional[str]:
        """Returns the bazelrc text for `line`, or None to drop the line.

        Negated alias definitions are removed and `--no<name>` options are
        rewritten. Lines that need no change are returned verbatim.
        """
        changed = False
        options = []
        for option in line.args:
            alias = _parse_flag_alias(option)
            if alias and _is_negated_target(alias[1]):
                changed = True
                continue
            rewritten = self.rewrite_option(option)
            changed = changed or rewritten != option
            options.append(rewritten)

        if not changed:
            return line.raw
        if not options and ":" not in line.command:
            return None
        return " ".join([line.command, *(shlex.quote(opt) for opt in options)])

    def rewrite_rc_lines(self, lines: Iterable[RcLine]) -> Iterator[str]:
        """Rewrites bazelrc lines, dropping the ones that become empty."""
        for line in lines:
            if (text := self.rewrite_rc_line(line)) is not None:
                yield text
