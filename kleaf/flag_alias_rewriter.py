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

"""Reads bazelrc files and recursively inlines import directives."""

import dataclasses
import pathlib
import shlex

_WORKSPACE_PREFIX = "%workspace%/"
_IMPORT_COMMANDS = ("import", "try-import")


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
