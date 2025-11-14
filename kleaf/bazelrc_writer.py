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
import errno
import fcntl
import os
import pathlib
import random
import sys
import time
from typing import TextIO

_WARN_SECONDS = 10
_WAIT_RECHECK_MAX_SECONDS = 1


@dataclasses.dataclass
class _Lockf(object):
    """Wraps a lockf() call.

    Despite the name, the class itself is not thread-safe.

    The lock can only be successfully acquire()d once then release()d once.
    After release(), it cannot be acquire()d again.
    """
    lockfile: pathlib.Path

    def __post_init__(self):
        self._lock_fd = os.open(self.lockfile, os.O_WRONLY | os.O_CREAT)

        # Intentionally disable FD_CLOEXEC so that the execve won't
        # release the lock. The lock is released:
        # - If execve(), when the process exits
        # - If using subprocess, when BazelWrapper.__exit__
        flags = fcntl.fcntl(self._lock_fd, fcntl.F_GETFD)
        flags = flags & ~fcntl.FD_CLOEXEC
        fcntl.fcntl(self._lock_fd, fcntl.F_SETFD, flags)

        self._is_locked = False

    def acquire(self, timeout=None):
        """Acquires lock."""
        assert self._lock_fd
        assert not self._is_locked

        lock_flag = fcntl.LOCK_EX | fcntl.LOCK_NB
        start_time = time.time()
        warned = False
        while True:
            try:
                fcntl.lockf(self._lock_fd, lock_flag)
                # Lock acquired successfully
                self._is_locked = True
                return self
            except OSError as e:
                if e.errno not in (errno.EAGAIN, errno.EACCES):
                    raise

                # Lock is held by another process, wait and retry
                elapsed_time = time.time() - start_time

                if elapsed_time > _WARN_SECONDS and not warned:
                    print(f"WARNING: Still waiting on lock for generated "
                          f"bazelrc directory. For details, run\n"
                          f"    lsof {self.lockfile}",
                          file=sys.stderr)
                    warned = True

                if timeout is not None and elapsed_time > timeout:
                    raise TimeoutError

                if elapsed_time > max(_WARN_SECONDS, timeout or 0):
                    lock_flag = lock_flag & ~fcntl.LOCK_NB

                # Sleep for a random number of seconds so we have some jittering
                # and avoid too much contention.
                time.sleep(random.random() * _WAIT_RECHECK_MAX_SECONDS)

    def release(self):
        """Releases lock."""
        if self._lock_fd is not None:
            os.close(self._lock_fd)
        self._lock_fd = None

        self._is_locked = False

    @property
    def is_locked(self) -> bool:
        return self._lock_fd is not None and self._is_locked


@dataclasses.dataclass
class BazelrcWriter(object):
    """Helper class to write bazelrc files.

    Expected call sequence:

    >>> gen_bazelrc_dir = pathlib.Path("/tmp/testdir")
    >>> writer = BazelrcWriter(gen_bazelrc_dir)
    >>> writer.acquire_lock()
    >>> with writer.open_file() as f:
    ...     _ = f.write("# content")
    ...
    >>> # Execute Bazel commands
    >>> # If `bazel clean`, calls clean()
    >>> writer.clean()
    >>>
    >>> # Release lock. If it is not called, lock is released upon process exit.
    >>> writer.release_lock()
    """

    gen_bazelrc_dir: pathlib.Path

    def __post_init__(self):
        """Initializes the writer."""
        self.gen_bazelrc_dir.mkdir(parents=True, exist_ok=True)

        self._lock = _Lockf(self.gen_bazelrc_dir / "lockfile")

    @property
    def _generated_file(self):
        return self.gen_bazelrc_dir / "generated.bazelrc"

    def open_file(self) -> TextIO:
        """Opens the generated bazelrc file for writing.

        Lock must be acquired before calling this method.
        """
        if not self._lock.is_locked:
            raise ValueError(f"Lock not acquired for {self._generated_file}")

        f = self._generated_file
        f.parent.mkdir(parents=True, exist_ok=True)
        return f.open("w")

    def clean(self):
        """Delete all generated files.

        The lockfile cannot be deleted; see
        BazelrcWriterTest.test_multi_process.
        """
        self._generated_file.unlink()

    def acquire_lock(self, timeout=None):
        """Acquires the lock.

        On successful acquisition, prevents other `bazel.py` to proceed."""
        self._lock.acquire(timeout)

    def release_lock(self):
        """Releases the lock.

        This allows another `bazel.py` to proceed with modifying the bazelrc
        file and running another bazel command.
        """
        self._lock.release()
