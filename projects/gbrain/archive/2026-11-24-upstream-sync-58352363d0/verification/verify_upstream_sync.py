#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

CHANGE = Path(__file__).resolve().parents[1]
DEFAULT_ROOT = Path("C:/Users/GOBAO/Downloads/AI/gbrain-sync-2026-11-24-17b68cef")
MAIN_ROOT = Path("C:/Users/GOBAO/Downloads/AI/gbrain")
FORK = "8f0e2d99983885d980fef98d6d5088c2649b38e5"
UPSTREAM = "17b68cef4f4267ca0e5710b42f6ddc95acf9fe51"
BASE = "553b5473344af4b8d9e09ebb8078e4e51a6d15eb"
ROLLBACK = "pre-sync/2026-11-24-58352363d0"
BRANCH = "sync/upstream-2026-11-24-17b68cef"
BASH = "C:/Program Files/Git/bin/bash.exe"
BILATERAL = {
    "llms-full.txt",
    "plugin/README.md",
    "scripts/module-size-limits.tsv",
    "scripts/page-body-readers-baseline.tsv",
    "skills/RESOLVER.md",
    "skills/skills.lock.json",
}
UPSTREAM_TESTS = [
    "test/sync-restored-file-purge.test.ts",
    "test/purge-eval-fixes.test.ts",
    "test/cycle-world-fence-rows.test.ts",
    "test/extract-atoms-world-fence-rows.test.ts",
    "test/repair-atom-fence-rows.test.ts",
    "test/repair-explicit-only.test.ts",
    "test/fix-wave-5-integration.test.ts",
    "test/sync-classify-6712.test.ts",
]
INBOX_CASES = [
    "managed capture persists prepared content and provenance",
    "unmanaged capture persists prepared content and provenance",
    "managed auto-link uses the committed snapshot and permission guard",
]
ADMIN_CASES = [
    "unauthenticated op request is rejected before dispatch",
    "authenticated op request dispatches with remote context",
    "admin op emits exactly one independent audit event",
]
TRACE_CASES = [
    "trace on preserves the complete emitted retrieval metadata",
    "trace off preserves the upstream result array",
    "empty trace result preserves envelope and diagnostics",
    "remote page cap remains available in trace retrieval metadata",
    "MCP query trace preserves response metadata",
    "CLI JSON preserves trace retrieval metadata",
    "MCP client preserves ToolResult response metadata",
    "Ask merges retrieval metadata into the visible trace",
]
GRAPH_CASES = [
    "graphOverview excludes private nodes origins and degree contributions",
    "graphOverview applies source scope to degree nodes and edges",
    "remote graphOverview excludes private pages while local retains them",
    "graphOverview privacy parity excludes hidden endpoints and origins",
    "both direction retains target metadata and frontier cap parity",
]
REMAINING_TESTS = [
    "test/ai/build-gateway-config.test.ts",
    "test/ai/gateway-chat.test.ts",
    "test/ai/gateway.test.ts",
    "test/compile-truth.test.ts",
    "test/minions.test.ts",
    "test/operation-manifest.test.ts",
    "test/parity.test.ts",
    "test/mcp-tool-defs.test.ts",
    "test/skill-brain-first.test.ts",
    "test/doctor-categories.test.ts",
    "test/build-llms.test.ts",
    "test/init-env-detection.test.ts",
    "test/embedding-dim-check.test.ts",
    "test/model-pricing.test.ts",
    "test/takes-reservation-callers.test.ts",
]
ALLOWED_NEW_PATHS = {
    "test/query-trace.test.ts",
    # Slice 4/5 tests added in this merge window; the files themselves pre-date the window.
    "test/dispatch-response-meta.serial.test.ts",
    "test/g6-ingestion-strict.test.ts",
    "test/search-remote-page-cap.test.ts",
    "test/serve-http-admin-route-guard.test.ts",
    # Windows harness fixes and their regression tests (candidate-only in this window).
    "scripts/lib/test-env.sh",
    "scripts/run-unit-parallel.sh",
    "scripts/run-unit-shard.sh",
    "test/scripts/run-unit-shard.test.ts",
    "test/scripts/run-with-receipt.test.ts",
    # Rebuilt Admin bundle hashes.
    "admin/dist/assets/Graph-D_P74igH.js",
    "admin/dist/assets/index-BDpCk3iZ.js",
    "admin/dist/assets/index-BQYdck_L.css",
}


class VerificationError(RuntimeError):
    pass


class Runner:
    def __init__(self, root: Path, action: str, run_id: str):
        self.root = root
        self.action = action
        self.run_id = run_id
        self.log_dir = CHANGE / "verification" / "runs" / run_id / action
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self.commands: list[dict[str, Any]] = []
        self.timeout = False

    def run(
        self,
        argv: list[str],
        *,
        cwd: Path | None = None,
        env: dict[str, str] | None = None,
        timeout: int | None = 600,
        label: str | None = None,
    ) -> dict[str, Any]:
        cwd = cwd or self.root
        child_env = {
            k: v
            for k, v in os.environ.items()
            if v is not None
            and not re.search(r"_API_KEY$|_API_TOKEN$", k)
            and k not in {"DATABASE_URL", "GBRAIN_DATABASE_URL"}
        }
        if env:
            child_env.update(env)
        index = len(self.commands) + 1
        stem = f"{index:03d}-{label or Path(argv[0]).name}"
        stdout_path = self.log_dir / f"{stem}.stdout.txt"
        stderr_path = self.log_dir / f"{stem}.stderr.txt"
        started = datetime.now(timezone.utc)
        monotonic = time.monotonic()
        timed_out = False
        with stdout_path.open("wb") as stdout_log, stderr_path.open("wb") as stderr_log:
            try:
                proc = subprocess.Popen(
                    argv,
                    cwd=str(cwd),
                    env=child_env,
                    stdout=stdout_log,
                    stderr=stderr_log,
                    start_new_session=os.name != "nt",
                )
            except OSError as exc:
                rc = 127
                stderr_log.write(str(exc).encode("utf-8", "replace"))
            else:
                try:
                    rc = proc.wait(timeout=timeout)
                except subprocess.TimeoutExpired:
                    timed_out = True
                    self.timeout = True
                    if os.name == "nt":
                        subprocess.run(
                            ["taskkill", "/F", "/T", "/PID", str(proc.pid)],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                            check=False,
                        )
                    else:
                        try:
                            os.killpg(proc.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                    proc.wait()
                    rc = 124
        ended = datetime.now(timezone.utc)
        stdout = stdout_path.read_text(encoding="utf-8", errors="replace")
        stderr = stderr_path.read_text(encoding="utf-8", errors="replace")
        record = {
            "argv": argv,
            "cwd": str(cwd),
            "started_at": started.isoformat(),
            "ended_at": ended.isoformat(),
            "duration_ms": round((time.monotonic() - monotonic) * 1000),
            "rc": rc,
            "timeout": timed_out,
            "status": "timeout" if timed_out else "pass" if rc == 0 else "fail",
            "stdout_file": f"{stem}.stdout.txt",
            "stderr_file": f"{stem}.stderr.txt",
        }
        self.commands.append(record)
        return {**record, "stdout": stdout, "stderr": stderr, "output": stdout + stderr}

    def git(self, *args: str, cwd: Path | None = None) -> str:
        result = self.run(["git", *args], cwd=cwd)
        require(result, "git " + " ".join(args))
        return result["stdout"].strip()

    def junit(self, argv: list[str], outfile: Path, **kwargs: Any) -> tuple[dict[str, Any], list[dict[str, Any]]]:
        result = self.run([*argv, "--reporter=junit", f"--reporter-outfile={outfile}"], **kwargs)
        cases = parse_junit(outfile)
        return result, cases

    def finish(self, summary: dict[str, Any], ok: bool) -> int:
        payload = {
            "action": self.action,
            "run_id": self.run_id,
            "root": str(self.root),
            "ok": ok,
            "timeout": self.timeout,
            "summary": summary,
            "commands": self.commands,
        }
        (self.log_dir / "result.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        print(" ".join(f"{k}={value}" for k, value in summary.items()))
        print(f"run_id={self.run_id} action={self.action} ok={ok} log_dir={self.log_dir}")
        return 0 if ok else 1


def require(result: dict[str, Any], label: str) -> None:
    if result["rc"] != 0 or result["timeout"]:
        raise VerificationError(f"{label} failed: rc={result['rc']} timeout={result['timeout']}")


def parse_junit(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        return []
    cases: list[dict[str, Any]] = []
    for node in root.iter("testcase"):
        status = "passed"
        if node.find("skipped") is not None:
            status = "skipped"
        elif node.find("failure") is not None:
            status = "failed"
        elif node.find("error") is not None:
            status = "failed"
        cases.append({
            "name": node.attrib.get("name", ""),
            "classname": node.attrib.get("classname", ""),
            "file": node.attrib.get("file", ""),
            "full_name": f"{node.attrib.get('classname', '')} {node.attrib.get('name', '')}".strip(),
            "status": status,
        })
    return cases


def parse_vitest(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    cases: list[dict[str, Any]] = []
    for file_result in payload.get("testResults", []):
        for assertion in file_result.get("assertionResults", []):
            status = assertion.get("status", "unknown")
            if status in {"pending", "todo", "skipped"}:
                status = "skipped"
            elif status != "passed":
                status = "failed"
            name = assertion.get("fullName") or assertion.get("title", "")
            cases.append({"name": name, "classname": file_result.get("name", ""), "full_name": name, "status": status})
    return cases


def counts(cases: list[dict[str, Any]]) -> dict[str, int]:
    return {
        "pass": sum(c["status"] == "passed" for c in cases),
        "fail": sum(c["status"] == "failed" for c in cases),
        "skip": sum(c["status"] == "skipped" for c in cases),
    }


def case_map(cases: list[dict[str, Any]], required: list[str]) -> tuple[dict[str, bool], int]:
    found = {
        name: any((case["full_name"] == name or case["full_name"].endswith(" " + name)) and case["status"] == "passed" for case in cases)
        for name in required
    }
    return found, sum(not passed for passed in found.values())


def no_skip_marker(output: str) -> bool:
    return not re.search(r"skipping|GBRAIN_CHECK_SKIPPED", output, re.IGNORECASE)


def changed_paths(runner: Runner, ref: str) -> set[str]:
    output = runner.git("diff", "--name-only", BASE, ref)
    return {line for line in output.splitlines() if line}


def freeze(runner: Runner) -> tuple[dict[str, Any], bool]:
    head = runner.git("rev-parse", "HEAD")
    merge_head = runner.git("rev-parse", "MERGE_HEAD")
    merge_base = runner.git("merge-base", FORK, UPSTREAM)
    counts_text = runner.git("rev-list", "--left-right", "--count", f"{FORK}...{UPSTREAM}")
    fork_commits, upstream_commits = (int(x) for x in counts_text.split())
    version = runner.git("show", f"{UPSTREAM}:VERSION")
    anchor = runner.git("rev-parse", f"{ROLLBACK}^{{commit}}")
    branch = runner.git("branch", "--show-current")
    main_head = runner.git("rev-parse", "HEAD", cwd=MAIN_ROOT)
    main_status = runner.git("status", "--porcelain", "--untracked-files=no", cwd=MAIN_ROOT)
    fork_paths = len(changed_paths(runner, FORK))
    upstream_paths = len(changed_paths(runner, UPSTREAM))
    ok = all([
        head == FORK,
        merge_head == UPSTREAM,
        merge_base == BASE,
        fork_commits == 59,
        upstream_commits == 13,
        version == "0.60.638.0",
        anchor == FORK,
        branch == BRANCH,
        main_head == FORK,
        main_status == "",
        fork_paths == 516,
        upstream_paths == 72,
    ])
    return {
        "freeze_ok": ok,
        "fork_commits": fork_commits,
        "upstream_commits": upstream_commits,
        "upstream_version": version,
        "rollback_anchor_ok": anchor == FORK,
        "main_worktree_unchanged": main_head == FORK and main_status == "",
        "candidate_commit_created": head != FORK,
        "fork_paths": fork_paths,
        "upstream_paths": upstream_paths,
    }, ok


def bilateral(runner: Runner) -> tuple[dict[str, Any], bool]:
    fork_paths = changed_paths(runner, FORK)
    upstream_paths = changed_paths(runner, UPSTREAM)
    both = fork_paths & upstream_paths
    module_rows = [r for r in (runner.root / "scripts/module-size-limits.tsv").read_text(encoding="utf-8").splitlines() if "GBrain Custom" in r]
    page_rows = [r for r in (runner.root / "scripts/page-body-readers-baseline.tsv").read_text(encoding="utf-8").splitlines() if "GBrain Custom" in r]
    baseline_rows = (runner.root / "scripts/page-body-readers-baseline.tsv").read_text(encoding="utf-8").splitlines()
    atom_rows = [r for r in baseline_rows if "atom-fence-rows.ts" in r or "atomFenceRows" in r]
    resolver_rows = [r.strip() for r in (runner.root / "skills/RESOLVER.md").read_text(encoding="utf-8").splitlines() if r.startswith("|") and "skills/" in r]
    duplicates = len(resolver_rows) - len(set(resolver_rows))
    trailing = sum(r != r.rstrip() for r in atom_rows)
    freshness = runner.run(["bun", "run", "check:regen-all"], timeout=600)
    skills = runner.run([BASH, "scripts/check-skills-manifest-fresh.sh"], timeout=120)
    lock_drift = runner.run(["git", "diff", "--exit-code", "--", "skills/skills.lock.json"], timeout=120)
    generated = all(r["rc"] == 0 and not r["timeout"] and no_skip_marker(r["output"]) for r in [freshness, skills, lock_drift])
    ok = both == BILATERAL and len(module_rows) == 11 and len(page_rows) == 11 and len(atom_rows) == 2 and duplicates == 0 and trailing == 0 and generated
    return {
        "both_changed_paths": len(both),
        "bilateral_paths_match": both == BILATERAL,
        "module_size_fork_rows": len(module_rows),
        "page_body_fork_rows": len(page_rows),
        "atom_fence_rows": len(atom_rows),
        "duplicate_skill_routes": duplicates,
        "atom_fence_trailing_whitespace": trailing,
        "generated_from_sources": generated,
        "fork_paths": len(fork_paths),
        "upstream_paths": len(upstream_paths),
    }, ok


def junit_file_passed(cases: list[dict[str, Any]], path: str) -> bool:
    target = path.replace("\\", "/")
    return any(target in case.get("file", "").replace("\\", "/") and case["status"] == "passed" for case in cases)


def upstream(runner: Runner) -> tuple[dict[str, Any], bool]:
    report = runner.log_dir / "upstream.junit.xml"
    result, cases = runner.junit(["bun", "test", "--timeout=60000", *UPSTREAM_TESTS], report, timeout=900)
    c = counts(cases)
    missing = sum(not junit_file_passed(cases, test) for test in UPSTREAM_TESTS)
    ok = result["rc"] == 0 and not result["timeout"] and c["fail"] == 0 and c["skip"] == 0 and c["pass"] > 0 and missing == 0
    return {
        "upstream_rc": result["rc"],
        "upstream_fail": c["fail"],
        "upstream_skips": c["skip"],
        "upstream_timeout": result["timeout"],
        "upstream_required_cases_missing": missing,
        "upstream_pass": c["pass"],
    }, ok


def migrations(runner: Runner) -> tuple[dict[str, Any], bool]:
    order = runner.run(["bun", "run", "check:schema-migration-order"], env={"GBRAIN_MIGRATION_BASE_REF": UPSTREAM}, timeout=300)
    registry_report = runner.log_dir / "registry.junit.xml"
    registry, cases = runner.junit(["bun", "test", "--timeout=60000", "test/schema-migration-registry.test.ts"], registry_report, timeout=600)
    c = counts(cases)
    files = sorted((runner.root / "src/core/schema-migrations").glob("v*.ts"))
    versions = [int(re.match(r"v(\d+)-", p.name).group(1)) for p in files if re.match(r"v(\d+)-", p.name)]
    fork_versions = sorted(v for v in versions if v > 297)
    base_match = re.search(r"latest v(\d+)", order["output"])
    base_max = int(base_match.group(1)) if base_match else -1
    fork_files = {p.name for p in (runner.root / "src/core/schema-migrations").glob("v*.ts")}
    fork_before = runner.run(["git", "ls-tree", "--name-only", f"{FORK}:src/core/schema-migrations"], timeout=120)
    before = set(fork_before["stdout"].splitlines()) if fork_before["rc"] == 0 else set()
    new_migrations = len(fork_files - before)
    skipped = not no_skip_marker(order["output"])
    ok = order["rc"] == 0 and not order["timeout"] and not skipped and base_max == 297 and fork_versions == [298] and new_migrations == 0 and registry["rc"] == 0 and c["fail"] == 0 and c["skip"] == 0 and c["pass"] > 0
    return {
        "migration_order_rc": order["rc"],
        "migration_order_skipped": skipped,
        "base_max": base_max,
        "fork_versions": fork_versions,
        "new_migrations": new_migrations,
        "registry_rc": registry["rc"],
        "registry_fail": c["fail"],
        "registry_skips": c["skip"],
        "database_upgrade_verified": False,
    }, ok


def generated(runner: Runner) -> tuple[dict[str, Any], bool]:
    dist = runner.root / "admin/dist/index.html"
    admin_dist_present = dist.exists()
    regen = runner.run(["bun", "run", "regen:all"], timeout=900)
    freshness = runner.run(["bun", "run", "check:regen-all"], timeout=900)
    build = runner.run(["bun", "run", "build:admin"], timeout=900)
    embedded = runner.run(["bun", "run", "check:admin-embedded"], timeout=300)
    before = runner.run(["git", "diff", "--binary"], timeout=300)
    second = runner.run(["bun", "run", "regen:all"], timeout=900)
    after = runner.run(["git", "diff", "--binary"], timeout=300)
    drift = before["stdout"] != after["stdout"]
    admin_skipped = not no_skip_marker(embedded["output"])
    checks = [regen, freshness, build, embedded, second]
    ok = admin_dist_present and not admin_skipped and not drift and all(r["rc"] == 0 and not r["timeout"] for r in checks)
    return {
        "admin_dist_present": admin_dist_present,
        "admin_embedded_skipped": admin_skipped,
        "regen_rc": regen["rc"],
        "freshness_rc": freshness["rc"],
        "admin_build_rc": build["rc"],
        "admin_embedded_rc": embedded["rc"],
        "second_regen_rc": second["rc"],
        "second_regen_drift": drift,
        "generated_stable": ok,
    }, ok


def inbox(runner: Runner) -> tuple[dict[str, Any], bool]:
    report = runner.log_dir / "inbox.junit.xml"
    files = ["test/ingestion/ingest-capture.test.ts", "test/g6-ingestion-strict.test.ts", "test/inbox-workflow.test.ts"]
    result, cases = runner.junit(["bun", "test", "--timeout=60000", *files], report, timeout=900)
    c = counts(cases)
    found, missing = case_map(cases, INBOX_CASES)
    ok = result["rc"] == 0 and not result["timeout"] and c["fail"] == 0 and c["skip"] == 0 and missing == 0
    return {
        "inbox_rc": result["rc"],
        "inbox_fail": c["fail"],
        "inbox_skips": c["skip"],
        "inbox_timeout": result["timeout"],
        "inbox_required_cases_missing": missing,
        "managed_case_passed": found[INBOX_CASES[0]],
        "unmanaged_case_passed": found[INBOX_CASES[1]],
        "auto_link_guard_case_passed": found[INBOX_CASES[2]],
        "inbox_pass": c["pass"],
    }, ok


def admin(runner: Runner) -> tuple[dict[str, Any], bool]:
    report = runner.log_dir / "admin.junit.xml"
    files = ["test/serve-http-admin-route-guard.test.ts", "test/admin-embed-spawn.test.ts"]
    result, cases = runner.junit(["bun", "test", "--timeout=60000", *files], report, timeout=900)
    c = counts(cases)
    found, missing = case_map(cases, ADMIN_CASES)
    ok = result["rc"] == 0 and not result["timeout"] and c["fail"] == 0 and c["skip"] == 0 and missing == 0
    return {
        "admin_rc": result["rc"],
        "admin_fail": c["fail"],
        "admin_skips": c["skip"],
        "admin_timeout": result["timeout"],
        "admin_required_cases_missing": missing,
        "denied_before_dispatch_case_passed": found[ADMIN_CASES[0]],
        "authenticated_dispatch_case_passed": found[ADMIN_CASES[1]],
        "audit_once_case_passed": found[ADMIN_CASES[2]],
        "admin_pass": c["pass"],
    }, ok


def trace(runner: Runner) -> tuple[dict[str, Any], bool]:
    root_report = runner.log_dir / "trace-root.junit.xml"
    root_files = ["test/query-trace.test.ts", "test/search-remote-page-cap.test.ts"]
    root, root_cases = runner.junit(["bun", "test", "--timeout=60000", *root_files], root_report, timeout=900)
    serial_report = runner.log_dir / "trace-serial.junit.xml"
    serial, serial_cases = runner.junit(["bun", "test", "--timeout=60000", "test/dispatch-response-meta.serial.test.ts"], serial_report, timeout=900)
    admin_report = runner.log_dir / "trace-admin.json"
    admin_result = runner.run([
        "bun", "x", "vitest", "run", "src/lib/mcp-client.test.ts", "src/pages/brain/__tests__/Ask.page.test.tsx",
        "--reporter=json", f"--outputFile={admin_report}",
    ], cwd=runner.root / "admin", timeout=900)
    admin_cases = parse_vitest(admin_report)
    cases = root_cases + serial_cases + admin_cases
    c = counts(cases)
    found, missing = case_map(cases, TRACE_CASES)
    ok = all(r["rc"] == 0 and not r["timeout"] for r in [root, serial, admin_result]) and c["fail"] == 0 and c["skip"] == 0 and missing == 0
    return {
        "trace_root_rc": root["rc"],
        "trace_serial_rc": serial["rc"],
        "trace_admin_rc": admin_result["rc"],
        "trace_skips": c["skip"],
        "trace_timeout": any(r["timeout"] for r in [root, serial, admin_result]),
        "trace_on_case_passed": found[TRACE_CASES[0]],
        "trace_off_case_passed": found[TRACE_CASES[1]],
        "empty_trace_case_passed": found[TRACE_CASES[2]],
        "page_cap_case_passed": found[TRACE_CASES[3]],
        "mcp_meta_case_passed": found[TRACE_CASES[4]],
        "cli_trace_case_passed": found[TRACE_CASES[5]],
        "admin_meta_case_passed": found[TRACE_CASES[6]],
        "ask_trace_case_passed": found[TRACE_CASES[7]],
        "trace_required_cases_missing": missing,
        "trace_fail": c["fail"],
    }, ok


def graph(runner: Runner) -> tuple[dict[str, Any], bool]:
    database_url = os.environ.get("GBRAIN_SYNC_TEST_DATABASE_URL") or os.environ.get("DATABASE_URL")
    if not database_url:
        raise VerificationError("graph requires GBRAIN_SYNC_TEST_DATABASE_URL or DATABASE_URL")
    pglite_report = runner.log_dir / "graph-pglite.junit.xml"
    pglite_files = [
        "test/graph-overview.test.ts",
        "test/traverse-paths-metadata.test.ts",
        "test/traverse-paths-row-cap.test.ts",
        "test/e2e/source-isolation-pglite.test.ts",
        "test/e2e/engine-content-privacy.test.ts",
    ]
    pglite, pglite_cases = runner.junit(["bun", "test", "--timeout=60000", *pglite_files], pglite_report, timeout=1200)
    postgres_report = runner.log_dir / "graph-postgres.junit.xml"
    postgres_files = ["test/e2e/engine-content-privacy.test.ts", "test/e2e/engine-parity.test.ts"]
    postgres, postgres_cases = runner.junit(["bun", "test", "--timeout=60000", *postgres_files], postgres_report, env={"DATABASE_URL": database_url}, timeout=1800)
    pc = counts(pglite_cases)
    pgc = counts(postgres_cases)
    cases = pglite_cases + postgres_cases
    found, missing = case_map(cases, GRAPH_CASES)
    postgres_executed = any("postgres" in case["full_name"].lower() and case["status"] == "passed" for case in postgres_cases)
    ok = all(r["rc"] == 0 and not r["timeout"] for r in [pglite, postgres]) and pc["fail"] == 0 and pgc["fail"] == 0 and pc["skip"] == 0 and pgc["skip"] == 0 and postgres_executed and missing == 0
    return {
        "pglite_rc": pglite["rc"],
        "postgres_rc": postgres["rc"],
        "pglite_skips": pc["skip"],
        "postgres_skips": pgc["skip"],
        "postgres_executed": postgres_executed,
        "graph_timeout": any(r["timeout"] for r in [pglite, postgres]),
        "overview_privacy_case_passed": found[GRAPH_CASES[0]],
        "source_scope_case_passed": found[GRAPH_CASES[1]],
        "remote_policy_case_passed": found[GRAPH_CASES[2]],
        "privacy_parity_case_passed": found[GRAPH_CASES[3]],
        "both_metadata_case_passed": found[GRAPH_CASES[4]],
        "graph_required_cases_missing": missing,
        "pglite_fail": pc["fail"],
        "postgres_fail": pgc["fail"],
    }, ok


def remaining(runner: Runner) -> tuple[dict[str, Any], bool]:
    report = runner.log_dir / "remaining.junit.xml"
    root, cases = runner.junit(["bun", "test", "--timeout=60000", *REMAINING_TESTS], report, timeout=1200)
    c = counts(cases)
    missing = sum(not junit_file_passed(cases, test) for test in REMAINING_TESTS)
    duplicate = runner.run([
        "bun", "-e",
        "import { operations } from './src/core/operations.ts'; const names=operations.map(o=>o.name); const duplicates=names.filter((n,i)=>names.indexOf(n)!==i); console.log(`duplicate_operation_registrations=${new Set(duplicates).size}`); process.exit(duplicates.length?1:0);",
    ], timeout=300)
    admin_report = runner.log_dir / "remaining-admin.json"
    admin = runner.run(["bun", "x", "vitest", "run", "--reporter=json", f"--outputFile={admin_report}"], cwd=runner.root / "admin", timeout=1800)
    admin_cases = parse_vitest(admin_report)
    ac = counts(admin_cases)
    jobs_passed = any("minions.test.ts" in case.get("file", "").replace("\\", "/") and case["status"] == "passed" for case in cases)
    duplicate_count_match = re.search(r"duplicate_operation_registrations=(\d+)", duplicate["output"])
    duplicate_count = int(duplicate_count_match.group(1)) if duplicate_count_match else -1
    ok = all(r["rc"] == 0 and not r["timeout"] for r in [root, duplicate, admin]) and c["fail"] == 0 and ac["fail"] == 0 and c["pass"] > 0 and ac["pass"] > 0 and missing == 0 and jobs_passed and duplicate_count == 0
    return {
        "remaining_root_rc": root["rc"],
        "remaining_admin_rc": admin["rc"],
        "remaining_timeout": any(r["timeout"] for r in [root, admin]),
        "remaining_required_cases_missing": missing,
        "jobs_suite_passed": jobs_passed,
        "duplicate_operation_registrations": duplicate_count,
        "remaining_root_fail": c["fail"],
        "remaining_admin_fail": ac["fail"],
        "remaining_root_skips_classified": c["skip"],
        "remaining_admin_skips_classified": ac["skip"],
    }, ok


def parse_unit_summary(output: str) -> tuple[int | None, int | None]:
    matches = re.findall(
        r"^\[unit-parallel\] elapsed=\d+s \| pass=\d+ fail=(\d+) skip=(\d+)(?:[ \t].*)?\r?$",
        output,
        re.MULTILINE,
    )
    if not matches:
        return None, None
    fail, skip = matches[-1]
    return int(fail), int(skip)


def core(runner: Runner) -> tuple[dict[str, Any], bool]:
    typecheck = runner.run(["bun", "run", "typecheck"], timeout=1200)
    unit = runner.run(["bun", "run", "test"], timeout=None)
    unit_fail, unit_skips = parse_unit_summary(unit["output"])
    incomplete = any(marker in unit["output"] for marker in ("WEDGED", "EXIT-HANG", "KILLED externally"))
    ok = (
        typecheck["rc"] == 0
        and unit["rc"] == 0
        and not typecheck["timeout"]
        and not unit["timeout"]
        and unit_fail == 0
        and unit_skips is not None
        and not incomplete
    )
    return {
        "typecheck_rc": typecheck["rc"],
        "unit_rc": unit["rc"],
        "unit_timeout": unit["timeout"],
        "unit_fail": unit_fail,
        "unit_skips_classified": unit_skips is not None,
        "unit_skips": unit_skips,
        "typecheck_timeout": typecheck["timeout"],
    }, ok


def added_whitespace(runner: Runner, parent: str) -> set[tuple[str, str]]:
    diff = runner.run(["git", "diff", "--cached", "--unified=0", parent], timeout=300)
    require(diff, f"diff {parent}")
    path = ""
    found: set[tuple[str, str]] = set()
    for line in diff["stdout"].splitlines():
        if line.startswith("+++ b/"):
            path = line[6:]
        elif line.startswith("+") and not line.startswith("+++") and line[1:] != line[1:].rstrip():
            found.add((path, line[1:]))
    return found


def final(runner: Runner) -> tuple[dict[str, Any], bool]:
    unmerged = runner.run(["git", "ls-files", "-u"], timeout=120)
    fork_check = runner.run(["git", "diff", "--cached", "--check", FORK], timeout=300)
    upstream_check = runner.run(["git", "diff", "--cached", "--check", UPSTREAM], timeout=300)
    new_whitespace = added_whitespace(runner, FORK) & added_whitespace(runner, UPSTREAM)
    fork_paths = changed_paths(runner, FORK)
    upstream_paths = changed_paths(runner, UPSTREAM)
    candidate = runner.git("diff", "--cached", "--name-only", "-M", BASE)
    candidate_paths = set(candidate.splitlines())
    unexpected = candidate_paths - (fork_paths | upstream_paths | ALLOWED_NEW_PATHS)
    head = runner.git("rev-parse", "HEAD")
    merge_head = runner.git("rev-parse", "MERGE_HEAD")
    branch = runner.git("branch", "--show-current")
    main_head = runner.git("rev-parse", "HEAD", cwd=MAIN_ROOT)
    main_status = runner.git("status", "--porcelain", "--untracked-files=no", cwd=MAIN_ROOT)
    delivery = head == FORK and merge_head == UPSTREAM and branch == BRANCH and main_head == FORK and main_status == ""
    parent_ok = not unexpected and fork_check["rc"] in {0, 2} and upstream_check["rc"] in {0, 2}
    ok = unmerged["stdout"].strip() == "" and len(new_whitespace) == 0 and parent_ok and delivery
    return {
        "final_audit_ok": ok,
        "unmerged_paths": len([x for x in unmerged["stdout"].splitlines() if x]),
        "new_whitespace_warnings": len(new_whitespace),
        "fork_parent_diff_ok": parent_ok,
        "upstream_parent_diff_ok": parent_ok,
        "delivery_boundary_ok": delivery,
        "unexpected_candidate_paths": sorted(unexpected),
        "candidate_paths": len(candidate_paths),
        "fork_check_rc": fork_check["rc"],
        "upstream_check_rc": upstream_check["rc"],
    }, ok


ACTIONS = {
    "freeze": freeze,
    "bilateral": bilateral,
    "upstream": upstream,
    "migrations": migrations,
    "generated": generated,
    "inbox": inbox,
    "admin": admin,
    "trace": trace,
    "graph": graph,
    "remaining": remaining,
    "core": core,
    "final": final,
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=ACTIONS)
    parser.add_argument("--root", type=Path, default=Path(os.environ.get("GBRAIN_SYNC_ROOT", DEFAULT_ROOT)))
    parser.add_argument("--run-id", default=os.environ.get("GBRAIN_SYNC_RUN_ID") or datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
    args = parser.parse_args()
    runner = Runner(args.root.resolve(), args.action, args.run_id)
    try:
        summary, ok = ACTIONS[args.action](runner)
    except VerificationError as exc:
        summary = {"error": str(exc)}
        ok = False
    return runner.finish(summary, ok)


if __name__ == "__main__":
    sys.exit(main())
