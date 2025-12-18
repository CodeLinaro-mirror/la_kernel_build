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

"""Tests for bazelrc_writer."""

from absl.testing import absltest
from contextlib import contextmanager
import doctest
import pathlib
import random
import string
import time
from typing import Generator, List
import unittest
import multiprocessing
import multiprocessing.connection
import tempfile

import bazelrc_writer


def _recv(conn, msg: str):
    """Checks that conn.recv() returns the given msg."""
    received = conn.recv()
    if isinstance(received, BaseException):
        raise received
    assert msg == received, f"expected {msg} got {received}"


def _mimic_bazel_command(conn: multiprocessing.connection.Connection,
                         gen_bazelrc_dir: str,
                         try_acquire_timeouts: List[float], clean: bool):
    """Child process that mimics a bazel.py execution flow.

    Args:
        conn: pipe to talk to parent process on break points
        gen_bazelrc_dir: directory to initialize BazelrcWriter
        try_acquire_timeouts: For each element, additionally calls
            acquire_lock(timeout) and expects that it throws a TimeoutError.
        clean: whether to clean at the end (mimics `bazel clean`)
    """
    try:
        characters = string.ascii_lowercase
        content = "".join(random.choice(characters) for _ in range(4096))

        _recv(conn, "START_OPENING_LOCKFD")
        writer = bazelrc_writer.BazelrcWriter(pathlib.Path(gen_bazelrc_dir))
        conn.send("END_OPENING_LOCKFD")

        _recv(conn, "START_TRY_ACQUIRE_LOCK")
        for i, timeout in enumerate(try_acquire_timeouts):
            try:
                writer.acquire_lock(timeout)
                raise RuntimeError(
                    f"Shouldn't be able to acquire! i={i}, timeout={timeout}")
            except TimeoutError:
                conn.send(f"END_TRY_ACQUIRE_LOCK{i}")
        writer.acquire_lock()
        conn.send("END_TRY_ACQUIRE_LOCK")

        _recv(conn, "START_WRITING")
        with writer.open_file() as f:
            f.write(content)
        conn.send("END_WRITING")

        _recv(conn, "START_EXEC")
        with open(writer._generated_file, "r") as f:
            assert f.read() == content, "race seen in generated file"
        conn.send("END_EXEC")

        _recv(conn, "START_RELEASING")
        if clean:
            writer.clean()
        writer.release_lock()
        conn.send("END_RELEASING")
    except BaseException as ex:
        conn.send(ex)


@contextmanager
def _fork_bazel_command(gen_bazelrc_dir: str,
                        try_acquire_timeouts: List[float], clean: bool):
    """Wrapper of _mimic_bazel_command.

    This helps the host process to control the stages of the child process.

    Returns:
        A context manager. __enter__()ing the context manager yields a
        generator that represents a state machine of the child process.
        Calling next() on the generator advances the state.

        Advancing to the START_ states means requesting the child process
        to resume execution and run a certain code section. Advancing to
        the END_ states means waiting on the child process to finish the
        given code section.
    """

    parent_conn, child_conn = multiprocessing.Pipe()
    p = multiprocessing.Process(
        target=_mimic_bazel_command,
        args=(child_conn, gen_bazelrc_dir, try_acquire_timeouts, clean))
    p.start()
    time.sleep(0.01)  # yield to the other process

    def _state_generator() -> Generator[str, None, None]:
        yield "START_OPENING_LOCKFD"
        parent_conn.send("START_OPENING_LOCKFD")
        _recv(parent_conn, "END_OPENING_LOCKFD")
        yield "END_OPENING_LOCKFD"

        yield "START_TRY_ACQUIRE_LOCK"
        parent_conn.send("START_TRY_ACQUIRE_LOCK")
        for i, _ in enumerate(try_acquire_timeouts):
            _recv(parent_conn, f"END_TRY_ACQUIRE_LOCK{i}")
            yield f"END_TRY_ACQUIRE_LOCK{i}"
        _recv(parent_conn, "END_TRY_ACQUIRE_LOCK")
        yield "END_TRY_ACQUIRE_LOCK"

        yield "START_WRITING"
        parent_conn.send("START_WRITING")
        _recv(parent_conn, "END_WRITING")
        yield "END_WRITING"

        yield "START_EXEC"
        parent_conn.send("START_EXEC")
        _recv(parent_conn, "END_EXEC")
        yield "END_EXEC"

        yield "START_RELEASING"
        parent_conn.send("START_RELEASING")
        _recv(parent_conn, "END_RELEASING")
        yield "END_RELEASING"

    try:
        yield _state_generator()
    except:
        p.kill()
        raise
    finally:
        p.join()


class BazelrcWriterTest(unittest.TestCase):
    def test_single_process(self):
        with tempfile.TemporaryDirectory() as gen_bazelrc_dir:
            with _fork_bazel_command(gen_bazelrc_dir, [], True) as proc:
                for _ in proc:
                    pass

    def test_multi_process(self):
        with tempfile.TemporaryDirectory() as gen_bazelrc_dir:
            # Process 1: `bazel clean`
            # Process 2: `bazel build`
            # Process 3: `bazel build`
            with _fork_bazel_command(gen_bazelrc_dir, [], True) as proc1, \
                    _fork_bazel_command(gen_bazelrc_dir, [], False) as proc2, \
                    _fork_bazel_command(gen_bazelrc_dir, [2], False) as proc3:

                # Advance proc1 to END_EXEC state when the actual
                # `bazel clean` finishes before we deletes the generated file.
                while next(proc1) != "END_EXEC":
                    pass

                # Advance proc2 to END_OPENING_LOCKFD. proc2 has the same
                # lockfd as proc1
                while next(proc2) != "END_OPENING_LOCKFD":
                    pass

                # Finishes proc1; cleans up files.
                for _ in proc1:
                    pass

                # Advance proc3 to END_OPENING_LOCKFD. Even though proc1
                # cleans up, proc3 should refer to the same lockfile.
                while next(proc3) != "END_OPENING_LOCKFD":
                    pass

                # Let proc2 acquire the lock and write the bazelrc file.
                while next(proc2) != "END_WRITING":
                    pass

                # proc3 tries to acquire lock, and it should throw TimeoutError
                # (it should not be able to acquire the lock).
                while next(proc3) != "END_TRY_ACQUIRE_LOCK0":
                    pass

                # Finishes proc2; this releases the lock.
                for _ in proc2:
                    pass

                # Proc3 should be able to proceed.
                for _ in proc3:
                    pass


def load_tests(_loader, tests, _ignore):
    tests.addTests(doctest.DocTestSuite(bazelrc_writer))
    return tests


if __name__ == "__main__":
    absltest.main()
