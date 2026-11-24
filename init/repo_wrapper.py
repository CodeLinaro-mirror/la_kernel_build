# Copyright (C) 2024 The Android Open Source Project
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

"""Wrapper for repo operations."""

import dataclasses
import logging
import pathlib
import subprocess
import textwrap
import xml.dom.minidom
import xml.parsers.expat

from init.init_errors import KleafProjectSetterError
from init.repo_manifest_parser import RepoManifestParser, ProjectState

# Name of repo sub-manifest that holds the Kleaf projects.
_KLEAF_MANIFEST = "kleaf.xml"


@dataclasses.dataclass(frozen=True)
class ProjectAbsState:
    # Original path in the repo manifest in the build, relative to repo root.
    original_path: pathlib.Path

    # Fixed up path, an absolute path
    fixed_abs_path: pathlib.Path


@dataclasses.dataclass
class ProjectSyncStates:
    states: set[ProjectAbsState]
    synced: bool


@dataclasses.dataclass
class RepoWrapper:
    """Wrapper for repo operations."""

    kleaf_repo: pathlib.Path
    ddk_workspace: pathlib.Path | None
    repo_manifest_of_build: str | None
    sync: bool

    def run(self) -> ProjectSyncStates:
        """Updates manifest and run repo sync if requested.

        Returns:
            set of ProjectSyncState, each describing the original
            path, fixed up path; and whether they were synced.
        """
        if not self._update_manifest():
            return ProjectSyncStates(states=set(), synced=False)
        return self._do_sync()

    def _update_manifest(self) -> bool:
        """Populates kleaf_repo by adding and syncing Git projects.

        Returns:
            True if the manifest was updated, False otherwise.
        """
        self._superproject_root = self._find_repo_root()

        project_states = self._populate_kleaf_repo_manifest()
        if project_states is None:
            return False
        self._project_states = project_states
        self._modify_main_repo_manifest()
        return True

    def _find_repo_root(self) -> pathlib.Path:
        """If --kleaf_repo is under a repo manifest, return repo root.

        Otherwise raise, because we cannot infer a sensible `--manifest-url`
        for `repo init`.
        """
        curdir = self.kleaf_repo
        while curdir.parent != curdir:  # is not root
            maybe_repo_main = curdir / ".repo"
            if maybe_repo_main.is_dir():
                return curdir
            curdir = curdir.parent

        raise KleafProjectSetterError(textwrap.dedent(f"""\
            ERROR: repo not initialized at or above {self.kleaf_repo}.
            Please set up a repo manifest project, then initialize it.
            For details, please visit
                https://gerrit.googlesource.com/git-repo/+/HEAD/README.md
            For example:
                cd {self._get_prospect_superproject_root()} && repo init -u ...
        """))

    def _get_prospect_superproject_root(self):
        """Returns a sensible default for superproject root."""
        if (self.ddk_workspace and
                self.kleaf_repo.is_relative_to(self.ddk_workspace)):
            return self.ddk_workspace
        else:
            return self.kleaf_repo

    def _populate_kleaf_repo_manifest(self) -> set[ProjectState] | None:
        """Populates .repo/manifests/kleaf.xml.

        Returns:
            set of ProjectState objects describing old and new paths, or None
            if the manifest could not be populated.
        """
        if not self.repo_manifest_of_build:
            logging.warning(
                "Unable to infer the list of projects from repo manifest "
                "because there is no repo manifest")
            return None

        fixup_groups = {"ddk"}
        preserve_groups = {"ddk-external"}

        kleaf_repo_rel = self.kleaf_repo.relative_to(self._superproject_root)

        with open(
                self._superproject_root / f".repo/manifests/{_KLEAF_MANIFEST}",
                "w") as kleaf_manifest:
            return RepoManifestParser(
                project_prefix=kleaf_repo_rel,
                manifest=self.repo_manifest_of_build,
                fixup_groups=fixup_groups,
                preserve_groups=preserve_groups,
            ).write_transformed_dom(kleaf_manifest)

    def _modify_main_repo_manifest(self):
        manifest_path = (self._superproject_root /
                         ".repo/manifests/default.xml")

        try:
            with open(manifest_path, "r+") as manifest:
                with xml.dom.minidom.parse(manifest) as dom:
                    root: xml.dom.minidom.Element = dom.documentElement
                    for include in root.getElementsByTagName("include"):
                        if include.getAttribute("name") == _KLEAF_MANIFEST:
                            return
                    include = dom.createElement("include")
                    include.setAttribute("name", _KLEAF_MANIFEST)
                    root.appendChild(include)

                    manifest.seek(0)
                    dom.writexml(manifest)
                    manifest.truncate()
        except FileNotFoundError as err:
            raise KleafProjectSetterError(
                f"Unable to modify repo manifest {manifest_path}. "
                f"Did you run repo init with a different --manifest-name? "
                f"If so, please file a bug to support your use case.") from err
        except xml.parsers.expat.ExpatError as err:
            raise KleafProjectSetterError(
                f"Unable to parse repo manifest {manifest_path}") from err

    def _do_sync(self) -> ProjectSyncStates:
        """Syncs project_paths below superproject_root.

        Returns:
            set of ProjectSyncState, each describing the original
            path, fixed up path; and whether they were synced.
        """
        project_abs_states = {ProjectAbsState(
            original_path=state.original_path,
            fixed_abs_path=self._superproject_root / state.fixed_path)
            for state in self._project_states}

        if not self.sync:
            logging.warning("`repo sync` is skipped because --nosync.")
            manifest = (self._superproject_root /
                        ".repo/manifests" / _KLEAF_MANIFEST)
            logging.warning(
                "Generated manifest is at %s, included in default.xml",
                manifest)
            logging.warning("** DON'T FORGET to commit the manifest change and "
                            "run `repo sync` !**")
            return ProjectSyncStates(
                states=project_abs_states, synced=False)

        if not self._project_states:
            logging.info("No Kleaf projects to sync.")
            return ProjectSyncStates(states=project_abs_states, synced=True)

        subprocess_args = ["repo", "sync", "-c"]
        subprocess_args.extend(
            str(state.fixed_path) for state in self._project_states)
        subprocess.check_call(subprocess_args, cwd=self._superproject_root)
        return ProjectSyncStates(states=project_abs_states, synced=True)
