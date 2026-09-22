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

"""Unit tests for flag_alias_rewriter."""

import pathlib
import tempfile
import textwrap
from absl.testing import absltest

import flag_alias_rewriter


class FlagAliasRewriterTest(absltest.TestCase):

    def setUp(self):
        super().setUp()
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.root = pathlib.Path(self.temp_dir.name)

    def test_read_rc_file(self):
        nested_rc = self.root / "sub/nested.bazelrc"
        nested_rc.parent.mkdir(parents=True, exist_ok=True)
        nested_rc.write_text(
            textwrap.dedent("""\
                build:debug_config \\
                  --copt=-DDEBUG=1 # trailing comment
            """),
            encoding="utf-8",
        )

        main_rc = self.root / "main.bazelrc"
        main_rc.write_text(
            textwrap.dedent("""\
                # Comment line
                import "%workspace%/sub/nested.bazelrc"
                try-import "%workspace%/sub/missing.bazelrc"
                build --define="FOO=bar baz"
            """),
            encoding="utf-8",
        )

        lines = flag_alias_rewriter.read_rc_file(main_rc, self.root)
        self.assertEqual(
            [(line.command, line.args) for line in lines],
            [
                ("build:debug_config", ("--copt=-DDEBUG=1",)),
                ("build", ("--define=FOO=bar baz",)),
            ],
        )


if __name__ == "__main__":
    absltest.main()
