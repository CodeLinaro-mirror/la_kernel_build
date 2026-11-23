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

"""Unit tests for checkpatch_presubmit_bazel."""

import argparse
import json
import os
import pathlib
import subprocess
import sys
import tempfile
from unittest import mock

from absl.testing import absltest
from absl.testing import parameterized

import checkpatch_presubmit_bazel

# pylint: disable=protected-access


class CheckpatchPresubmitBazelTest(parameterized.TestCase):

    def setUp(self):
        super().setUp()
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.root = pathlib.Path(self.temp_dir.name).resolve()
        self.workspace_dir = self.root / "workspace"
        self.workspace_dir.mkdir()
        self.dist_dir = self.root / "dist"
        self.dist_dir.mkdir()
        self.bazel_wrapper = self.root / "bazel_wrapper"

    def _write_change_info(self, data: dict) -> pathlib.Path:
        change_info = self.root / "change_info.json"
        change_info.write_text(json.dumps(data), encoding="utf-8")
        return change_info

    def test_load_arguments_relative_dist_dir_and_forwarded_args(self):
        change_info = self.root / "change_info.json"
        argv = [
            "checkpatch_presubmit",
            "--dist_dir=out/dist",
            f"--change_info={change_info}",
            "--bid=P12345",
            f"--bazel_wrapper={self.bazel_wrapper}",
            "--nofail_on_violations",
            "--strict",
        ]
        with (
            mock.patch.dict(
                os.environ,
                {"BUILD_WORKSPACE_DIRECTORY": str(self.workspace_dir)},
            ),
            mock.patch.object(sys, "argv", argv),
        ):
            known, checkpatch_args = checkpatch_presubmit_bazel.load_arguments()

        self.assertEqual(known.dist_dir, self.workspace_dir / "out/dist")
        self.assertEqual(known.change_info, change_info)
        self.assertEqual(known.bid, "P12345")
        self.assertEqual(known.bazel_wrapper, self.bazel_wrapper)
        self.assertEqual(
            checkpatch_args, ["--nofail_on_violations", "--strict"]
        )

    def test_load_arguments_absolute_dist_dir(self):
        change_info = self.root / "change_info.json"
        argv = [
            "checkpatch_presubmit",
            f"--dist_dir={self.dist_dir}",
            f"--change_info={change_info}",
        ]
        with mock.patch.object(sys, "argv", argv):
            known, checkpatch_args = checkpatch_presubmit_bazel.load_arguments()

        self.assertEqual(known.dist_dir, self.dist_dir)
        self.assertEqual(known.change_info, change_info)
        self.assertIsNone(known.bid)
        self.assertEqual(checkpatch_args, [])

    def test_load_arguments_relative_change_info_fails(self):
        argv = [
            "checkpatch_presubmit",
            f"--dist_dir={self.dist_dir}",
            "--change_info=relative/change_info.json",
        ]
        with mock.patch.object(sys, "argv", argv):
            with self.assertRaises(SystemExit):
                checkpatch_presubmit_bazel.load_arguments()

    def test_require_absolute_path(self):
        self.assertEqual(
            checkpatch_presubmit_bazel._require_absolute_path("/abs/path"),
            pathlib.Path("/abs/path"),
        )
        with self.assertRaises(argparse.ArgumentTypeError):
            checkpatch_presubmit_bazel._require_absolute_path("rel/path")

    def test_find_repo_found_at_current_dir(self):
        (self.root / ".repo").mkdir()
        self.assertEqual(
            checkpatch_presubmit_bazel._find_repo(self.root), self.root
        )

    def test_find_repo_found_in_ancestor(self):
        (self.root / ".repo").mkdir()
        nested = self.root / "a" / "b"
        nested.mkdir(parents=True)
        self.assertEqual(
            checkpatch_presubmit_bazel._find_repo(nested), self.root
        )

    def test_find_repo_ignores_non_dir_dot_repo(self):
        (self.root / ".repo").mkdir()
        sub = self.root / "sub"
        sub.mkdir()
        (sub / ".repo").write_text("not a dir", encoding="utf-8")
        self.assertEqual(checkpatch_presubmit_bazel._find_repo(sub), self.root)

    def test_find_repo_not_found(self):
        self.assertIsNone(
            checkpatch_presubmit_bazel._find_repo(pathlib.Path("/"))
        )

    def test_get_package_path_with_kleaf_repo_manifest_same_root(self):
        env = {
            "BUILD_WORKSPACE_DIRECTORY": str(self.workspace_dir),
            "KLEAF_REPO_MANIFEST": f"{self.workspace_dir}:/tmp/manifest.xml",
        }
        with mock.patch.dict(os.environ, env, clear=True):
            self.assertEqual(
                checkpatch_presubmit_bazel._get_package_path(
                    pathlib.Path("common")
                ),
                pathlib.Path("common"),
            )

    def test_get_package_path_workspace_below_repo_root(self):
        env = {
            "BUILD_WORKSPACE_DIRECTORY": str(self.workspace_dir),
            "KLEAF_REPO_MANIFEST": f"{self.root}:/tmp/manifest.xml",
        }
        with mock.patch.dict(os.environ, env, clear=True):
            self.assertEqual(
                checkpatch_presubmit_bazel._get_package_path(
                    pathlib.Path("workspace/common")
                ),
                pathlib.Path("common"),
            )
            self.assertIsNone(
                checkpatch_presubmit_bazel._get_package_path(
                    pathlib.Path("other_project")
                )
            )

    @parameterized.named_parameters(
        ("unset", {}),
        ("empty_repo_root", {"KLEAF_REPO_MANIFEST": ":/tmp/manifest.xml"}),
    )
    def test_get_package_path_falls_back_to_find_repo(self, extra_env):
        (self.root / ".repo").mkdir()
        env = {
            "BUILD_WORKSPACE_DIRECTORY": str(self.workspace_dir),
            **extra_env,
        }
        with mock.patch.dict(os.environ, env, clear=True):
            self.assertEqual(
                checkpatch_presubmit_bazel._get_package_path(
                    pathlib.Path("workspace/common")
                ),
                pathlib.Path("common"),
            )

    def test_get_package_path_no_repo_root_returns_none(self):
        env = {"BUILD_WORKSPACE_DIRECTORY": str(self.workspace_dir)}
        with (
            mock.patch.dict(os.environ, env, clear=True),
            mock.patch.object(
                checkpatch_presubmit_bazel, "_find_repo", return_value=None
            ),
        ):
            self.assertIsNone(
                checkpatch_presubmit_bazel._get_package_path(
                    pathlib.Path("common")
                )
            )

    def test_env_for_recursive_bazel_calls(self):
        original_env = {
            "PYTHONSAFEPATH": "1",
            "KLEAF_BAZELRC_SUBDIR": "integration_test",
            "KEEP_ME": "value",
        }
        with mock.patch.dict(os.environ, original_env, clear=True):
            recursive_env = (
                checkpatch_presubmit_bazel._env_for_recursive_bazel_calls()
            )
            self.assertEqual(os.environ["PYTHONSAFEPATH"], "1")
            self.assertEqual(
                os.environ["KLEAF_BAZELRC_SUBDIR"], "integration_test"
            )

        self.assertEqual(recursive_env["PYTHONSAFEPATH"], "")
        self.assertEqual(recursive_env["KLEAF_BAZELRC_SUBDIR"], "checkpatch")
        self.assertEqual(recursive_env["KEEP_ME"], "value")

    @parameterized.parameters(
        "external/foo",
        "bootable/recovery",
        "prebuilts/fuchsia_sdk",
        "prebuilts/fuchsia_sdk/sub",
        "test/dittosuite",
        "test/dittosuite/sub",
    )
    def test_find_checkpatch_targets_skips_deny_list(self, denied_path):
        pkg_dir = self.workspace_dir / denied_path
        pkg_dir.mkdir(parents=True)
        (pkg_dir / "BUILD.bazel").write_text("", encoding="utf-8")

        with (
            mock.patch.dict(
                os.environ,
                {"BUILD_WORKSPACE_DIRECTORY": str(self.workspace_dir)},
            ),
            mock.patch.object(subprocess, "check_output") as mock_check_output,
        ):
            targets = checkpatch_presubmit_bazel._find_checkpatch_targets(
                self.bazel_wrapper, pathlib.Path(denied_path)
            )

        self.assertEqual(targets, [])
        mock_check_output.assert_not_called()

    def test_find_checkpatch_targets_skips_missing_build_file(self):
        (self.workspace_dir / "no_build").mkdir()
        with (
            mock.patch.dict(
                os.environ,
                {"BUILD_WORKSPACE_DIRECTORY": str(self.workspace_dir)},
            ),
            mock.patch.object(subprocess, "check_output") as mock_check_output,
        ):
            targets = checkpatch_presubmit_bazel._find_checkpatch_targets(
                self.bazel_wrapper, pathlib.Path("no_build")
            )

        self.assertEqual(targets, [])
        mock_check_output.assert_not_called()

    @parameterized.parameters("BUILD.bazel", "BUILD")
    def test_find_checkpatch_targets_queries_bazel(self, build_filename):
        pkg_dir = self.workspace_dir / "common"
        pkg_dir.mkdir()
        (pkg_dir / build_filename).write_text("", encoding="utf-8")

        with (
            mock.patch.dict(
                os.environ,
                {
                    "BUILD_WORKSPACE_DIRECTORY": str(self.workspace_dir),
                    "PYTHONSAFEPATH": "1",
                },
            ),
            mock.patch.object(
                subprocess,
                "check_output",
                return_value="  //common:checkpatch \n\n//common:checkpatch2\n",
            ) as mock_check_output,
        ):
            targets = checkpatch_presubmit_bazel._find_checkpatch_targets(
                self.bazel_wrapper, pathlib.Path("common")
            )

        self.assertEqual(
            targets, ["//common:checkpatch", "//common:checkpatch2"]
        )
        mock_check_output.assert_called_once()
        args, kwargs = mock_check_output.call_args
        self.assertEqual(
            args[0],
            [
                str(self.bazel_wrapper.absolute()),
                "query",
                "--ui_event_filters=-info",
                "--noshow_progress",
                'kind("^checkpatch rule$", //common:all)',
            ],
        )
        self.assertTrue(kwargs["text"])
        self.assertEqual(kwargs["cwd"], self.workspace_dir)
        self.assertEqual(kwargs["env"]["PYTHONSAFEPATH"], "")
        self.assertEqual(kwargs["env"]["KLEAF_BAZELRC_SUBDIR"], "checkpatch")

    @parameterized.named_parameters(
        ("normal", False, None, None),
        ("silent", True, subprocess.DEVNULL, subprocess.STDOUT),
    )
    def test_run_checkpatch(self, silent, expected_stdout, expected_stderr):
        log_path = self.dist_dir / "checkpatch.log"
        mock_result = mock.MagicMock(returncode=3)
        with (
            mock.patch.dict(
                os.environ,
                {
                    "BUILD_WORKSPACE_DIRECTORY": str(self.workspace_dir),
                    "PYTHONSAFEPATH": "1",
                },
            ),
            mock.patch.object(
                subprocess, "run", return_value=mock_result
            ) as mock_run,
        ):
            rc = checkpatch_presubmit_bazel._run_checkpatch(
                bazel_wrapper=self.bazel_wrapper,
                target="//common:checkpatch",
                git_sha1="deadbeef",
                log=log_path,
                checkpatch_args=["--nofail_on_violations"],
                silent=silent,
            )

        self.assertEqual(rc, 3)
        mock_run.assert_called_once()
        args, kwargs = mock_run.call_args
        self.assertEqual(
            args[0],
            [
                str(self.bazel_wrapper.absolute()),
                "run",
                "--show_result=0",
                "--ui_event_filters=-info",
                "--noshow_progress",
                "//common:checkpatch",
                "--",
                "--nofail_on_violations",
                "--log",
                log_path,
                "--git_sha1",
                "deadbeef",
            ],
        )
        self.assertTrue(kwargs["text"])
        self.assertEqual(kwargs["cwd"], self.workspace_dir)
        self.assertEqual(kwargs["stdout"], expected_stdout)
        self.assertEqual(kwargs["stderr"], expected_stderr)
        self.assertEqual(kwargs["env"]["PYTHONSAFEPATH"], "")
        self.assertEqual(kwargs["env"]["KLEAF_BAZELRC_SUBDIR"], "checkpatch")

    def test_main_skips_postsubmit(self):
        missing_change_info = self.root / "does_not_exist.json"
        with (
            mock.patch.object(subprocess, "check_output") as mock_query,
            mock.patch.object(subprocess, "run") as mock_run,
        ):
            rc = checkpatch_presubmit_bazel.main(
                checkpatch_args=[],
                dist_dir=self.dist_dir,
                bid="12345678",
                change_info=missing_change_info,
                bazel_wrapper=self.bazel_wrapper,
            )

        self.assertEqual(rc, 0)
        mock_query.assert_not_called()
        mock_run.assert_not_called()

    @parameterized.named_parameters(
        ("presubmit_bid", "P9876543"),
        ("no_bid", None),
    )
    def test_main_runs_checkpatch_and_full_log(self, bid):
        pkg_dir = self.workspace_dir / "common"
        pkg_dir.mkdir()
        (pkg_dir / "BUILD.bazel").write_text("", encoding="utf-8")

        change_info = self._write_change_info({
            "changes": [{
                "project": "kernel/common",
                "projectPath": "common",
                "latestRevision": "abc123",
            }],
        })

        out_dir = self.dist_dir / "checkpatch" / "kernel__common" / "abc123"
        out_dir.mkdir(parents=True)
        stale_log = out_dir / "checkpatch.log"
        stale_full_log = out_dir / "checkpatch_full.log"
        stale_log.write_text("stale", encoding="utf-8")
        stale_full_log.write_text("stale_full", encoding="utf-8")

        env = {
            "BUILD_WORKSPACE_DIRECTORY": str(self.workspace_dir),
            "KLEAF_REPO_MANIFEST": f"{self.workspace_dir}:/tmp/manifest.xml",
        }
        with (
            mock.patch.dict(os.environ, env, clear=True),
            mock.patch.object(
                subprocess, "check_output", return_value="//common:checkpatch\n"
            ),
            mock.patch.object(
                subprocess,
                "run",
                side_effect=[
                    mock.MagicMock(returncode=0),
                    # Full log failures must not fail presubmit.
                    mock.MagicMock(returncode=1),
                ],
            ) as mock_run,
        ):
            rc = checkpatch_presubmit_bazel.main(
                checkpatch_args=["--extra"],
                dist_dir=self.dist_dir,
                bid=bid,
                change_info=change_info,
                bazel_wrapper=self.bazel_wrapper,
            )

        self.assertEqual(rc, 0)
        self.assertFalse(stale_log.exists())
        self.assertFalse(stale_full_log.exists())
        self.assertEqual(mock_run.call_count, 2)

        first_cmd, first_kwargs = mock_run.call_args_list[0]
        self.assertIn("--extra", first_cmd[0])
        self.assertNotIn("--ignored_checks", first_cmd[0])
        self.assertIn(stale_log, first_cmd[0])
        self.assertIsNone(first_kwargs["stdout"])
        self.assertIsNone(first_kwargs["stderr"])

        second_cmd, second_kwargs = mock_run.call_args_list[1]
        self.assertIn("--extra", second_cmd[0])
        self.assertIn("--ignored_checks", second_cmd[0])
        self.assertIn("", second_cmd[0])
        self.assertIn(stale_full_log, second_cmd[0])
        self.assertEqual(second_kwargs["stdout"], subprocess.DEVNULL)
        self.assertEqual(second_kwargs["stderr"], subprocess.STDOUT)

    def test_main_skips_incomplete_or_unmatched_changes(self):
        pkg_no_target = self.workspace_dir / "no_target"
        pkg_no_target.mkdir()
        (pkg_no_target / "BUILD.bazel").write_text("", encoding="utf-8")

        change_info = self._write_change_info({
            "changes": [
                {"project": "missing/path", "latestRevision": "aaa"},
                {
                    "project": "empty/path",
                    "projectPath": "",
                    "latestRevision": "bbb",
                },
                {"project": "missing/rev", "projectPath": "workspace/common"},
                {
                    "project": "outside/workspace",
                    "projectPath": "other_repo",
                    "latestRevision": "ccc",
                },
                {
                    "project": "denied/proj",
                    "projectPath": "workspace/external/foo",
                    "latestRevision": "ddd",
                },
                {
                    "project": "no/target",
                    "projectPath": "workspace/no_target",
                    "latestRevision": "eee",
                },
            ],
        })

        env = {
            "BUILD_WORKSPACE_DIRECTORY": str(self.workspace_dir),
            "KLEAF_REPO_MANIFEST": f"{self.root}:/tmp/manifest.xml",
        }
        with (
            mock.patch.dict(os.environ, env, clear=True),
            mock.patch.object(
                subprocess, "check_output", return_value=""
            ) as mock_query,
            mock.patch.object(subprocess, "run") as mock_run,
        ):
            rc = checkpatch_presubmit_bazel.main(
                checkpatch_args=[],
                dist_dir=self.dist_dir,
                bid="P1",
                change_info=change_info,
                bazel_wrapper=self.bazel_wrapper,
            )

        self.assertEqual(rc, 0)
        mock_query.assert_called_once()
        mock_run.assert_not_called()

    def test_main_handles_missing_changes_key(self):
        change_info = self._write_change_info({})
        with (
            mock.patch.object(subprocess, "check_output") as mock_query,
            mock.patch.object(subprocess, "run") as mock_run,
        ):
            rc = checkpatch_presubmit_bazel.main(
                checkpatch_args=[],
                dist_dir=self.dist_dir,
                bid="P1",
                change_info=change_info,
                bazel_wrapper=self.bazel_wrapper,
            )

        self.assertEqual(rc, 0)
        mock_query.assert_not_called()
        mock_run.assert_not_called()

    def test_main_multiple_shas_and_nonzero_exit_aggregation(self):
        pkg_dir = self.workspace_dir / "common"
        pkg_dir.mkdir()
        (pkg_dir / "BUILD.bazel").write_text("", encoding="utf-8")

        change_info = self._write_change_info({
            "changes": [
                {
                    "project": "kernel/common",
                    "projectPath": "common",
                    "latestRevision": "sha1",
                },
                {
                    "project": "kernel/common",
                    "projectPath": "common",
                    "latestRevision": "sha2",
                },
            ],
        })

        env = {
            "BUILD_WORKSPACE_DIRECTORY": str(self.workspace_dir),
            "KLEAF_REPO_MANIFEST": f"{self.workspace_dir}:/tmp/manifest.xml",
        }
        with (
            mock.patch.dict(os.environ, env, clear=True),
            mock.patch.object(
                subprocess, "check_output", return_value="//common:checkpatch\n"
            ),
            mock.patch.object(
                subprocess,
                "run",
                side_effect=[
                    mock.MagicMock(returncode=0),  # sha1 normal
                    mock.MagicMock(returncode=0),  # sha1 full
                    mock.MagicMock(returncode=2),  # sha2 normal (failure)
                    mock.MagicMock(returncode=0),  # sha2 full
                ],
            ) as mock_run,
        ):
            rc = checkpatch_presubmit_bazel.main(
                checkpatch_args=[],
                dist_dir=self.dist_dir,
                bid="P42",
                change_info=change_info,
                bazel_wrapper=self.bazel_wrapper,
            )

        self.assertEqual(rc, 1)
        self.assertEqual(mock_run.call_count, 4)
        self.assertTrue(
            (self.dist_dir / "checkpatch" / "kernel__common" / "sha1").is_dir()
        )
        self.assertTrue(
            (self.dist_dir / "checkpatch" / "kernel__common" / "sha2").is_dir()
        )


if __name__ == "__main__":
    absltest.main()
