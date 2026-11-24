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

"""Tests for repo_wrapper.py."""

import logging
import pathlib
import subprocess
import tempfile
import textwrap
from unittest import mock
import xml.dom.minidom

from absl.testing import absltest
from absl.testing import parameterized
from init.init_errors import KleafProjectSetterError
from init.repo_wrapper import ProjectAbsState, ProjectSyncStates, RepoWrapper


_SAMPLE_MANIFEST = textwrap.dedent("""\
    <?xml version="1.0" encoding="UTF-8"?>
    <manifest>
        <remote name="aosp" fetch=".." review="https://android-review.googlesource.com/" />
        <default revision="main" remote="aosp" />
        <superproject name="kernel/superproject" remote="aosp" revision="common-android-mainline" />
        <project path="build/kernel" name="kernel/build" groups="ddk">
            <linkfile src="kleaf/bazel.sh" dest="tools/bazel" />
            <linkfile src="kleaf/bzlmod/bazel.MODULE.bazel" dest="MODULE.bazel" />
        </project>
        <project path="common" name="kernel/common" revision="android-mainline" />
        <project path="external/bazel-skylib" name="platform/external/bazel-skylib" groups="ddk-external" />
    </manifest>
""")

_DEFAULT_MANIFEST = textwrap.dedent("""\
    <?xml version="1.0" encoding="UTF-8"?>
    <manifest>
    </manifest>
""")


class RepoWrapperTest(parameterized.TestCase):

    @staticmethod
    def _init_fake_repo(
        repo_root: pathlib.Path,
        default_manifest: str | None = _DEFAULT_MANIFEST,
    ) -> pathlib.Path:
        manifests_dir = repo_root / ".repo/manifests"
        manifests_dir.mkdir(parents=True, exist_ok=True)
        default_xml = manifests_dir / "default.xml"
        if default_manifest is not None:
            default_xml.write_text(default_manifest, encoding="utf-8")
        return default_xml

    @staticmethod
    def _read_manifest_project_paths(manifest_path: pathlib.Path) -> list[str]:
        with xml.dom.minidom.parse(str(manifest_path)) as dom:
            return [
                p.getAttribute("path") or p.getAttribute("name")
                for p in dom.documentElement.getElementsByTagName("project")
            ]

    @staticmethod
    def _read_manifest_includes(manifest_path: pathlib.Path) -> list[str]:
        with xml.dom.minidom.parse(str(manifest_path)) as dom:
            return [
                inc.getAttribute("name")
                for inc in dom.documentElement.getElementsByTagName("include")
            ]

    def test_find_repo_root_at_ancestor(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace = pathlib.Path(tmp) / "workspace"
            self._init_fake_repo(workspace)
            kleaf_repo = workspace / "external/kleaf"
            kleaf_repo.mkdir(parents=True)

            states = RepoWrapper(
                kleaf_repo=kleaf_repo,
                ddk_workspace=workspace,
                repo_manifest_of_build=_SAMPLE_MANIFEST,
                sync=False,
            ).run()

            self.assertFalse(states.synced)
            self.assertEqual(
                states.states,
                {
                    ProjectAbsState(
                        pathlib.Path("build/kernel"),
                        workspace / "external/kleaf/build/kernel",
                    ),
                    ProjectAbsState(
                        pathlib.Path("external/bazel-skylib"),
                        workspace / "external/bazel-skylib",
                    ),
                },
            )

    def test_find_repo_root_at_kleaf_repo(self):
        with tempfile.TemporaryDirectory() as tmp:
            kleaf_repo = pathlib.Path(tmp) / "kleaf_repo"
            self._init_fake_repo(kleaf_repo)

            states = RepoWrapper(
                kleaf_repo=kleaf_repo,
                ddk_workspace=None,
                repo_manifest_of_build=_SAMPLE_MANIFEST,
                sync=False,
            ).run()

            self.assertEqual(
                states.states,
                {
                    ProjectAbsState(
                        pathlib.Path("build/kernel"),
                        kleaf_repo / "build/kernel",
                    ),
                    ProjectAbsState(
                        pathlib.Path("external/bazel-skylib"),
                        kleaf_repo / "external/bazel-skylib",
                    ),
                },
            )

    @parameterized.named_parameters(
        ("KleafInsideWorkspace", True),
        ("KleafOutsideWorkspace", False),
    )
    def test_find_repo_root_missing_raises(self, kleaf_inside_workspace: bool):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            ddk_workspace = tmp_path / "workspace"
            kleaf_repo = (
                ddk_workspace / "external/kleaf"
                if kleaf_inside_workspace
                else tmp_path / "other/kleaf"
            )
            kleaf_repo.mkdir(parents=True)

            expected_root = (
                ddk_workspace if kleaf_inside_workspace else kleaf_repo
            )
            with self.assertRaises(KleafProjectSetterError) as cm:
                RepoWrapper(
                    kleaf_repo=kleaf_repo,
                    ddk_workspace=ddk_workspace,
                    repo_manifest_of_build=_SAMPLE_MANIFEST,
                    sync=False,
                ).run()
            self.assertIn(f"cd {expected_root} && repo init", str(cm.exception))

    def test_update_manifest_ddk_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace = pathlib.Path(tmp) / "workspace"
            default_xml = self._init_fake_repo(workspace)
            kleaf_repo = workspace / "external/kleaf"
            kleaf_repo.mkdir(parents=True)

            with mock.patch.object(subprocess, "check_call") as mock_call:
                states = RepoWrapper(
                    kleaf_repo=kleaf_repo,
                    ddk_workspace=workspace,
                    repo_manifest_of_build=_SAMPLE_MANIFEST,
                    sync=False,
                ).run()

            mock_call.assert_not_called()
            self.assertFalse(states.synced)
            kleaf_xml = workspace / ".repo/manifests/kleaf.xml"
            self.assertTrue(kleaf_xml.is_file())
            self.assertCountEqual(
                self._read_manifest_project_paths(kleaf_xml),
                ["external/kleaf/build/kernel", "external/bazel-skylib"],
            )
            self.assertEqual(
                self._read_manifest_includes(default_xml),
                ["kleaf.xml"],
            )

    def test_modify_main_repo_manifest_idempotent(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace = pathlib.Path(tmp) / "workspace"
            default_xml = self._init_fake_repo(workspace)
            kleaf_repo = workspace / "external/kleaf"
            kleaf_repo.mkdir(parents=True)

            for _ in range(2):
                RepoWrapper(
                    kleaf_repo=kleaf_repo,
                    ddk_workspace=workspace,
                    repo_manifest_of_build=_SAMPLE_MANIFEST,
                    sync=False,
                ).run()

            self.assertEqual(
                self._read_manifest_includes(default_xml),
                ["kleaf.xml"],
            )

    def test_modify_main_repo_manifest_truncates_shorter_xml(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace = pathlib.Path(tmp) / "workspace"
            default_xml = self._init_fake_repo(
                workspace,
                default_manifest=textwrap.dedent("""\
                    <?xml version="1.0" encoding="UTF-8"?>
                    <manifest>
                        <project                                         name="foo" />
                    </manifest>
                """),
            )
            kleaf_repo = workspace / "external/kleaf"
            kleaf_repo.mkdir(parents=True)

            RepoWrapper(
                kleaf_repo=kleaf_repo,
                ddk_workspace=workspace,
                repo_manifest_of_build=_SAMPLE_MANIFEST,
                sync=False,
            ).run()

            self.assertEqual(
                self._read_manifest_includes(default_xml),
                ["kleaf.xml"],
            )

    def test_modify_main_repo_manifest_missing_default_xml_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace = pathlib.Path(tmp) / "workspace"
            self._init_fake_repo(workspace, default_manifest=None)
            kleaf_repo = workspace / "external/kleaf"
            kleaf_repo.mkdir(parents=True)

            with self.assertRaises(KleafProjectSetterError):
                RepoWrapper(
                    kleaf_repo=kleaf_repo,
                    ddk_workspace=workspace,
                    repo_manifest_of_build=_SAMPLE_MANIFEST,
                    sync=False,
                ).run()

    def test_modify_main_repo_manifest_malformed_default_xml_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace = pathlib.Path(tmp) / "workspace"
            self._init_fake_repo(workspace, default_manifest="<manifest><bad")
            kleaf_repo = workspace / "external/kleaf"
            kleaf_repo.mkdir(parents=True)

            with self.assertRaises(KleafProjectSetterError):
                RepoWrapper(
                    kleaf_repo=kleaf_repo,
                    ddk_workspace=workspace,
                    repo_manifest_of_build=_SAMPLE_MANIFEST,
                    sync=False,
                ).run()

    def test_sync_true_calls_repo_sync(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace = pathlib.Path(tmp) / "workspace"
            self._init_fake_repo(workspace)
            kleaf_repo = workspace / "external/kleaf"
            kleaf_repo.mkdir(parents=True)

            with mock.patch.object(subprocess, "check_call") as mock_call:
                states = RepoWrapper(
                    kleaf_repo=kleaf_repo,
                    ddk_workspace=workspace,
                    repo_manifest_of_build=_SAMPLE_MANIFEST,
                    sync=True,
                ).run()

            self.assertEqual(
                states,
                ProjectSyncStates(
                    states={
                        ProjectAbsState(
                            pathlib.Path("build/kernel"),
                            workspace / "external/kleaf/build/kernel",
                        ),
                        ProjectAbsState(
                            pathlib.Path("external/bazel-skylib"),
                            workspace / "external/bazel-skylib",
                        ),
                    },
                    synced=True,
                ),
            )
            mock_call.assert_called_once()
            cmd = mock_call.call_args.args[0]
            self.assertEqual(cmd[:3], ["repo", "sync", "-c"])
            self.assertCountEqual(
                cmd[3:],
                ["external/kleaf/build/kernel", "external/bazel-skylib"],
            )
            self.assertEqual(mock_call.call_args.kwargs, {"cwd": workspace})

    def test_sync_true_propagates_subprocess_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace = pathlib.Path(tmp) / "workspace"
            self._init_fake_repo(workspace)
            kleaf_repo = workspace / "external/kleaf"
            kleaf_repo.mkdir(parents=True)

            with mock.patch.object(
                subprocess,
                "check_call",
                side_effect=subprocess.CalledProcessError(1, ["repo", "sync"]),
            ):
                with self.assertRaises(subprocess.CalledProcessError):
                    RepoWrapper(
                        kleaf_repo=kleaf_repo,
                        ddk_workspace=workspace,
                        repo_manifest_of_build=_SAMPLE_MANIFEST,
                        sync=True,
                    ).run()

    def test_missing_repo_manifest_skips_default_xml_and_sync(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace = pathlib.Path(tmp) / "workspace"
            default_xml = self._init_fake_repo(workspace)
            kleaf_repo = workspace / "external/kleaf"
            kleaf_repo.mkdir(parents=True)

            with mock.patch.object(subprocess, "check_call") as mock_call:
                states = RepoWrapper(
                    kleaf_repo=kleaf_repo,
                    ddk_workspace=workspace,
                    repo_manifest_of_build=None,
                    sync=True,
                ).run()

            mock_call.assert_not_called()
            self.assertFalse((workspace / ".repo/manifests/kleaf.xml").exists())
            self.assertEmpty(self._read_manifest_includes(default_xml))
            self.assertEqual(states, ProjectSyncStates(states=set(), synced=False))

    def test_empty_project_list_skips_repo_sync(self):
        manifest = textwrap.dedent("""\
            <?xml version="1.0" encoding="UTF-8"?>
            <manifest>
                <project path="common" name="kernel/common" />
            </manifest>
        """)
        with tempfile.TemporaryDirectory() as tmp:
            workspace = pathlib.Path(tmp) / "workspace"
            self._init_fake_repo(workspace)
            kleaf_repo = workspace / "external/kleaf"
            kleaf_repo.mkdir(parents=True)

            with mock.patch.object(subprocess, "check_call") as mock_call:
                states = RepoWrapper(
                    kleaf_repo=kleaf_repo,
                    ddk_workspace=workspace,
                    repo_manifest_of_build=manifest,
                    sync=True,
                ).run()

            mock_call.assert_not_called()
            self.assertEqual(states, ProjectSyncStates(states=set(), synced=True))


# This could be run as:
#   tools/bazel test //build/kernel:repo_wrapper_test --test_output=all
if __name__ == "__main__":
    logging.basicConfig(
        level=logging.DEBUG, format="%(levelname)s: %(message)s"
    )
    absltest.main()
