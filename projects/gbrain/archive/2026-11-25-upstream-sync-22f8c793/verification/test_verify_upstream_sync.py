#!/usr/bin/env python3
"""verify_upstream_sync.py 纯函数自测（无需 git/网络）。"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import verify_upstream_sync as v  # noqa: E402


class ParseJunitTest(unittest.TestCase):
    def test_parse_junit_status_and_file(self) -> None:
        xml = """<?xml version="1.0"?>
<testsuites><testsuite>
<testcase name="a" classname="f.test.ts" file="test/f.test.ts"/>
<testcase name="b" classname="f.test.ts" file="test/f.test.ts"><skipped/></testcase>
<testcase name="c" classname="f.test.ts" file="test/f.test.ts"><failure message="x"/></testcase>
</testsuite></testsuites>"""
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "r.xml"
            path.write_text(xml, encoding="utf-8")
            cases = v.parse_junit(path)
        self.assertEqual([c["status"] for c in cases], ["passed", "skipped", "failed"])
        self.assertEqual(v.counts(cases), {"pass": 1, "fail": 1, "skip": 1})
        self.assertTrue(v.junit_file_passed(cases, "test/f.test.ts"))
        self.assertFalse(v.junit_file_passed(cases, "test/missing.test.ts"))

    def test_parse_junit_missing_or_broken(self) -> None:
        self.assertEqual(v.parse_junit(Path("/nonexistent/x.xml")), [])
        with tempfile.TemporaryDirectory() as tmp:
            broken = Path(tmp) / "b.xml"
            broken.write_text("not xml", encoding="utf-8")
            self.assertEqual(v.parse_junit(broken), [])


class SkipMarkerTest(unittest.TestCase):
    def test_skip_marker(self) -> None:
        self.assertTrue(v.no_skip_marker("ok (694 baseline rows)"))
        self.assertFalse(v.no_skip_marker("GBRAIN_CHECK_SKIPPED: no dist"))
        self.assertFalse(v.no_skip_marker("skipping module x"))


class LedgerSectionTest(unittest.TestCase):
    def test_section_starts_at_marker(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "CUSTOM-LEDGER.md").write_text("old 未跑\n| 22f8c793 | v337 |\n", encoding="utf-8")
            section = v.ledger_section(root)
        self.assertTrue(section.startswith("22f8c793"))
        self.assertIn("v337", section)
        self.assertNotIn("old", section)


if __name__ == "__main__":
    unittest.main()
