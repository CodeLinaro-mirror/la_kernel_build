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

"""Tests for repo_manifest_parser.py."""

import io
import logging
import pathlib
import textwrap
import xml.dom.minidom

from absl.testing import absltest
from absl.testing import parameterized
from init.init_errors import KleafProjectSetterError
from init.repo_manifest_parser import ProjectState, RepoManifestParser


_SAMPLE_MANIFEST = textwrap.dedent("""\
    <?xml version="1.0" encoding="UTF-8"?>
    <manifest>
        <remote name="aosp" fetch=".." review="https://android-review.googlesource.com/" />
        <default revision="main" remote="aosp" sync-j="4" />
        <superproject name="kernel/superproject" remote="aosp" revision="common-android-mainline" />
        <project path="build/kernel" name="kernel/build" groups="ddk">
            <linkfile src="kleaf/bazel.sh" dest="tools/bazel" />
            <linkfile src="kleaf/bzlmod/bazel.MODULE.bazel" dest="MODULE.bazel" />
        </project>
        <project path="common" name="kernel/common" revision="android-mainline" />
        <project path="external/bazel-skylib" name="platform/external/bazel-skylib" groups="ddk-external">
            <linkfile src="some/file" dest="preserved/link" />
        </project>
        <project path="external/other" name="platform/external/other" groups="other" />
    </manifest>
""")


class RepoManifestParserTest(parameterized.TestCase):

    def _parse_and_transform(
        self,
        manifest: str,
        project_prefix: pathlib.Path = pathlib.Path("external/kleaf"),
        fixup_groups: set[str] | None = None,
        preserve_groups: set[str] | None = None,
    ) -> tuple[set[ProjectState], xml.dom.minidom.Document]:
        out = io.StringIO()
        states = RepoManifestParser(
            manifest=manifest,
            project_prefix=project_prefix,
            fixup_groups=fixup_groups,
            preserve_groups=preserve_groups,
        ).write_transformed_dom(out)
        dom = xml.dom.minidom.parseString(out.getvalue())
        self.addCleanup(dom.unlink)
        return states, dom

    def test_filter_ddk_and_preserve_external(self):
        states, dom = self._parse_and_transform(
            _SAMPLE_MANIFEST,
            fixup_groups={"ddk"},
            preserve_groups={"ddk-external"},
        )
        self.assertEqual(
            states,
            {
                ProjectState(
                    pathlib.Path("build/kernel"),
                    pathlib.Path("external/kleaf/build/kernel"),
                ),
                ProjectState(
                    pathlib.Path("external/bazel-skylib"),
                    pathlib.Path("external/bazel-skylib"),
                ),
            },
        )
        root = dom.documentElement
        self.assertFalse(root.getElementsByTagName("superproject"))
        self.assertFalse(root.getElementsByTagName("default"))
        self.assertLen(root.getElementsByTagName("remote"), 1)

        projects = {
            p.getAttribute("name"): p
            for p in root.getElementsByTagName("project")
        }
        self.assertCountEqual(
            projects.keys(),
            ["kernel/build", "platform/external/bazel-skylib"],
        )
        self.assertEqual(
            projects["kernel/build"].getAttribute("path"),
            "external/kleaf/build/kernel",
        )
        self.assertEqual(
            projects["platform/external/bazel-skylib"].getAttribute("path"),
            "external/bazel-skylib",
        )

    def test_fixup_groups_none_keeps_all_and_preserves_external(self):
        states, dom = self._parse_and_transform(
            _SAMPLE_MANIFEST,
            fixup_groups=None,
            preserve_groups={"ddk-external"},
        )
        self.assertEqual(
            states,
            {
                ProjectState(
                    pathlib.Path("build/kernel"),
                    pathlib.Path("external/kleaf/build/kernel"),
                ),
                ProjectState(
                    pathlib.Path("common"),
                    pathlib.Path("external/kleaf/common"),
                ),
                ProjectState(
                    pathlib.Path("external/bazel-skylib"),
                    pathlib.Path("external/bazel-skylib"),
                ),
                ProjectState(
                    pathlib.Path("external/other"),
                    pathlib.Path("external/kleaf/external/other"),
                ),
            },
        )
        project_paths = [
            p.getAttribute("path")
            for p in dom.documentElement.getElementsByTagName("project")
        ]
        self.assertCountEqual(
            project_paths,
            [
                "external/kleaf/build/kernel",
                "external/kleaf/common",
                "external/bazel-skylib",
                "external/kleaf/external/other",
            ],
        )

    def test_preserve_groups_precedence_over_fixup_groups(self):
        manifest = textwrap.dedent("""\
            <?xml version="1.0" encoding="UTF-8"?>
            <manifest>
                <project path="external/dual" name="dual" groups="ddk,ddk-external" />
            </manifest>
        """)
        states, dom = self._parse_and_transform(
            manifest,
            fixup_groups={"ddk"},
            preserve_groups={"ddk-external"},
        )
        self.assertEqual(
            states,
            {
                ProjectState(
                    pathlib.Path("external/dual"),
                    pathlib.Path("external/dual"),
                ),
            },
        )
        projects = dom.documentElement.getElementsByTagName("project")
        self.assertLen(projects, 1)
        self.assertEqual(projects[0].getAttribute("path"), "external/dual")

    def test_empty_groups_deletes_all(self):
        states, dom = self._parse_and_transform(
            _SAMPLE_MANIFEST,
            fixup_groups=set(),
            preserve_groups=set(),
        )
        self.assertEmpty(states)
        self.assertEmpty(dom.documentElement.getElementsByTagName("project"))

    @parameterized.named_parameters(
        ("CommaSeparated", "foo,ddk,bar"),
        ("SpaceSeparated", "foo ddk bar"),
        ("MixedDelimiters", "foo, ddk bar"),
    )
    def test_group_delimiters(self, groups_attr: str):
        manifest = textwrap.dedent(f"""\
            <?xml version="1.0" encoding="UTF-8"?>
            <manifest>
                <project path="build/kernel" name="kernel/build" groups="{groups_attr}" />
            </manifest>
        """)
        states, _ = self._parse_and_transform(
            manifest,
            fixup_groups={"ddk"},
            preserve_groups=set(),
        )
        self.assertEqual(
            states,
            {
                ProjectState(
                    pathlib.Path("build/kernel"),
                    pathlib.Path("external/kleaf/build/kernel"),
                ),
            },
        )

    def test_default_attributes_inherited_and_not_overridden(self):
        _, dom = self._parse_and_transform(
            _SAMPLE_MANIFEST,
            fixup_groups=None,
            preserve_groups={"ddk-external"},
        )
        projects = {
            p.getAttribute("name"): p
            for p in dom.documentElement.getElementsByTagName("project")
        }
        # build/kernel had no revision/remote/sync-j -> inherits all defaults.
        self.assertEqual(projects["kernel/build"].getAttribute("revision"), "main")
        self.assertEqual(projects["kernel/build"].getAttribute("remote"), "aosp")
        self.assertEqual(projects["kernel/build"].getAttribute("sync-j"), "4")

        # common had explicit revision -> preserved; remote/sync-j inherited.
        self.assertEqual(
            projects["kernel/common"].getAttribute("revision"),
            "android-mainline",
        )
        self.assertEqual(projects["kernel/common"].getAttribute("remote"), "aosp")
        self.assertEqual(projects["kernel/common"].getAttribute("sync-j"), "4")

        # preserved project also inherits defaults.
        self.assertEqual(
            projects["platform/external/bazel-skylib"].getAttribute("revision"),
            "main",
        )
        self.assertEqual(
            projects["platform/external/bazel-skylib"].getAttribute("remote"),
            "aosp",
        )

    def test_project_path_defaults_to_name(self):
        manifest = textwrap.dedent("""\
            <?xml version="1.0" encoding="UTF-8"?>
            <manifest>
                <project name="kernel/build" groups="ddk" />
                <project name="platform/external/skylib" groups="ddk-external" />
            </manifest>
        """)
        states, dom = self._parse_and_transform(
            manifest,
            fixup_groups={"ddk"},
            preserve_groups={"ddk-external"},
        )
        self.assertEqual(
            states,
            {
                ProjectState(
                    pathlib.Path("kernel/build"),
                    pathlib.Path("external/kleaf/kernel/build"),
                ),
                ProjectState(
                    pathlib.Path("platform/external/skylib"),
                    pathlib.Path("platform/external/skylib"),
                ),
            },
        )
        projects = {
            p.getAttribute("name"): p
            for p in dom.documentElement.getElementsByTagName("project")
        }
        self.assertEqual(
            projects["kernel/build"].getAttribute("path"),
            "external/kleaf/kernel/build",
        )
        self.assertFalse(
            projects["platform/external/skylib"].hasAttribute("path")
        )

    def test_linkfile_prefix_and_tools_bazel_exception(self):
        _, dom = self._parse_and_transform(
            _SAMPLE_MANIFEST,
            fixup_groups={"ddk"},
            preserve_groups={"ddk-external"},
        )
        projects = {
            p.getAttribute("name"): p
            for p in dom.documentElement.getElementsByTagName("project")
        }
        kernel_links = {
            link.getAttribute("src"): link.getAttribute("dest")
            for link in projects["kernel/build"].getElementsByTagName("linkfile")
        }
        self.assertEqual(
            kernel_links,
            {
                # b/355523169: tools/bazel stays at the top directory.
                "kleaf/bazel.sh": "tools/bazel",
                "kleaf/bzlmod/bazel.MODULE.bazel": "external/kleaf/MODULE.bazel",
            },
        )
        # Preserved project's linkfile dest stays untouched.
        skylib_links = {
            link.getAttribute("src"): link.getAttribute("dest")
            for link in projects[
                "platform/external/bazel-skylib"
            ].getElementsByTagName("linkfile")
        }
        self.assertEqual(skylib_links, {"some/file": "preserved/link"})

    def test_malformed_xml_raises(self):
        with self.assertRaises(KleafProjectSetterError):
            self._parse_and_transform(
                "<manifest><unclosed>",
                fixup_groups={"ddk"},
                preserve_groups={"ddk-external"},
            )


# This could be run as:
#   tools/bazel test //build/kernel:repo_manifest_parser_test --test_output=all
if __name__ == "__main__":
    logging.basicConfig(
        level=logging.DEBUG, format="%(levelname)s: %(message)s"
    )
    absltest.main()
