# Copyright (C) 2025 The Android Open Source Project
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

"""Helper classes to support writing bazelrc files."""

import dataclasses
import pathlib
import shutil
from typing import TextIO


@dataclasses.dataclass
class BazelRcWriter(object):
    gen_bazelrc_dir: pathlib.Path

    def __post_init__(self):
        self.gen_bazelrc_dir.mkdir(parents=True, exist_ok=True)

    def open(self, subpath: pathlib.Path | str) -> TextIO:
        f = self.gen_bazelrc_dir / subpath
        f.parent.mkdir(parents=True, exist_ok=True)
        return f.open("w")

    def clean(self):
        """Deletes all generated bazelrc files and the lockfile.

        Note: This must be executed AFTER the actual `bazel clean` has
        finished:
        - The bazelrc files are needed for `bazel clean` to be executed.
        """
        shutil.rmtree(self.gen_bazelrc_dir, ignore_errors=True)
