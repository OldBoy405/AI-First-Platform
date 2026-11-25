#!/usr/bin/env python3
from __future__ import annotations

import sys
import tempfile
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any
from unittest import mock

import verify_upstream_sync as verify


class StubRunner:
    def __init__(self, unit: dict[str, Any]):
        self.unit = unit
        self.calls: list[tuple[list[str], dict[str, Any]]] = []

    def run(self, argv: list[str], **kwargs: Any) -> dict[str, Any]:
        self.calls.append((argv, kwargs))
        if argv == ["bun", "run", "typecheck"]:
            return {"rc": 0, "timeout": False}
        return self.unit


def unit_result(stderr: str, *, rc: int = 0, timeout: bool = False) -> dict[str, Any]:
    return {"rc": rc, "timeout": timeout, "stdout": "", "stderr": stderr, "output": stderr}


class CoreTests(unittest.TestCase):
    def test_final_unit_summary_is_authoritative(self) -> None:
        stderr = (
            "[unit-parallel] elapsed=10s | pass=3 fail=9 skip=8\n"
            "shard 1/8: pass=3 fail=9 skip=8 rc=1\n"
            "[unit-parallel] elapsed=20s | pass=30 fail=0 skip=2 | oom_rescued=1files(3p serial)\n"
        )
        runner = StubRunner(unit_result(stderr))

        summary, ok = verify.core(runner)

        self.assertTrue(ok)
        self.assertEqual(summary["unit_fail"], 0)
        self.assertEqual(summary["unit_skips"], 2)
        self.assertTrue(summary["unit_skips_classified"])
        self.assertEqual(runner.calls[1], (["bun", "run", "test"], {"timeout": None}))

    def test_core_rejects_incomplete_wrapper_markers(self) -> None:
        summary_line = "[unit-parallel] elapsed=20s | pass=30 fail=0 skip=2\n"
        for marker in ("WEDGED", "EXIT-HANG", "KILLED externally"):
            with self.subTest(marker=marker):
                detail = f"shard 1/8: {marker}"
                if marker == "EXIT-HANG":
                    detail += " - warn-pass"
                runner = StubRunner(unit_result(f"{detail}\n{summary_line}"))

                summary, ok = verify.core(runner)

                self.assertFalse(ok)
                self.assertEqual(summary["unit_fail"], 0)
                self.assertTrue(summary["unit_skips_classified"])

    def test_core_rejects_missing_failed_or_timed_out_summary(self) -> None:
        cases = {
            "missing": unit_result("pass=1 fail=0 skip=0\n"),
            "failed": unit_result("[unit-parallel] elapsed=20s | pass=30 fail=1 skip=2\n"),
            "nonzero_rc": unit_result(
                "[unit-parallel] elapsed=20s | pass=30 fail=0 skip=2\n", rc=1
            ),
            "timeout": unit_result(
                "[unit-parallel] elapsed=20s | pass=30 fail=0 skip=2\n", timeout=True
            ),
        }
        for name, result in cases.items():
            with self.subTest(name=name):
                _, ok = verify.core(StubRunner(result))
                self.assertFalse(ok)


class RunnerTests(unittest.TestCase):
    def test_run_streams_output_to_logs_before_exit(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            release = root / "release"
            script = (
                "import sys,time\n"
                "from pathlib import Path\n"
                "print('stdout-live', flush=True)\n"
                "print('stderr-live', file=sys.stderr, flush=True)\n"
                "while not Path(sys.argv[1]).exists():\n"
                "    time.sleep(0.01)\n"
            )
            with mock.patch.object(verify, "CHANGE", root):
                runner = verify.Runner(root, "test", "stream")
                stdout_path = runner.log_dir / "001-stream.stdout.txt"
                stderr_path = runner.log_dir / "001-stream.stderr.txt"
                with ThreadPoolExecutor(max_workers=1) as executor:
                    future = executor.submit(
                        runner.run,
                        [sys.executable, "-c", script, str(release)],
                        timeout=None,
                        label="stream",
                    )
                    try:
                        deadline = time.monotonic() + 5
                        while True:
                            if stdout_path.exists() and stderr_path.exists():
                                stdout_live = stdout_path.read_text(encoding="utf-8", errors="replace")
                                stderr_live = stderr_path.read_text(encoding="utf-8", errors="replace")
                                if "stdout-live" in stdout_live and "stderr-live" in stderr_live:
                                    break
                            if future.done():
                                future.result()
                                self.fail("process exited before live logs were observed")
                            if time.monotonic() >= deadline:
                                self.fail("logs were not written while the process was running")
                            time.sleep(0.01)
                        self.assertFalse(release.exists())
                    finally:
                        release.touch()
                    result = future.result(timeout=5)

                self.assertEqual(result["rc"], 0)
                self.assertFalse(result["timeout"])
                self.assertEqual(result["stdout"], "stdout-live\n")
                self.assertEqual(result["stderr"], "stderr-live\n")
                self.assertEqual(stdout_path.read_text(encoding="utf-8"), result["stdout"])
                self.assertEqual(stderr_path.read_text(encoding="utf-8"), result["stderr"])


if __name__ == "__main__":
    unittest.main()
