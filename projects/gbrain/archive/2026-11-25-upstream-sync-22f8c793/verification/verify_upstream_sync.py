#!/usr/bin/env python3
"""验证 GBrain upstream sync 候选（2026-11-25 / 22f8c793b1）。

动作：freeze / bilateral / migrations / generated / quality / final。
每个动作把命令、rc、耗时和输出写入 verification/runs/<run_id>/<action>/，
并对关键结论打印稳定的 key=value 供 CP 断言匹配。
"""
from __future__ import annotations

import argparse
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
DEFAULT_ROOT = Path("C:/Users/GOBAO/Downloads/AI/gbrain-sync-2026-11-25-22f8c793")
MAIN_ROOT = Path("C:/Users/GOBAO/Downloads/AI/gbrain")
FORK = "2e50b638f28a338b6687ffb0a620f4c4ca659552"
UPSTREAM = "22f8c793b1fa56bb46835801878b2053be940098"
BASE = "17b68cef4f4267ca0e5710b42f6ddc95acf9fe51"
ROLLBACK = "pre-sync/2026-11-25-2e50b638f2"
BRANCH = "sync/upstream-2026-11-25-22f8c793"
EXPECTED_VERSION = "0.60.772.0"
EXPECTED_FORK_COMMITS = 62
EXPECTED_UPSTREAM_COMMITS = 2434
EXPECTED_FORK_PATHS = 527
EXPECTED_UPSTREAM_PATHS = 5879
EXPECTED_BILATERAL = 67
EXPECTED_BASE_MAX = 336
EXPECTED_FORK_MIGRATION = 337

TARGETED_TESTS = [
    "test/ingestion/ingest-capture.test.ts",
    "test/inbox-workflow.test.ts",
    "test/serve-http-admin-route-guard.test.ts",
    "test/query-trace.test.ts",
    "test/operation-manifest.test.ts",
    "test/parity.test.ts",
    "test/mcp-tool-defs.test.ts",
    "test/cli-goldens.test.ts",
    "test/export-surface-golden.test.ts",
    "test/engine-sql-sql-text.test.ts",
    "test/cli-dispatch-phase.test.ts",
]
E2E_TESTS = ["test/e2e/source-isolation-pglite.test.ts"]


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
        child_env.setdefault("GBRAIN_TEST_MODE", "1")
        gbrain_home = self.log_dir / "gbrain-home"
        gbrain_home.mkdir(parents=True, exist_ok=True)
        child_env.setdefault("GBRAIN_HOME", str(gbrain_home))
        if env:
            child_env.update(env)
        index = len(self.commands) + 1
        stem = f"{index:03d}-{label or Path(argv[0]).name}"
        stdout_path = self.log_dir / f"{stem}.stdout.txt"
        stderr_path = self.log_dir / f"{stem}.stderr.txt"
        started = datetime.now(timezone.utc)
        monotonic = time.monotonic()
        timed_out = False
        rc = 0
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

    def git(self, *args: str, cwd: Path | None = None, require_ok: bool = True) -> dict[str, Any]:
        result = self.run(["git", *args], cwd=cwd)
        if require_ok and (result["rc"] != 0 or result["timeout"]):
            raise VerificationError(f"git {' '.join(args)} failed: rc={result['rc']} timeout={result['timeout']}")
        return result

    def git_text(self, *args: str, cwd: Path | None = None, require_ok: bool = True) -> str:
        return self.git(*args, cwd=cwd, require_ok=require_ok)["stdout"].strip()

    def junit(self, argv: list[str], outfile: Path, **kwargs: Any) -> tuple[dict[str, Any], list[dict[str, Any]]]:
        result = self.run([*argv, "--reporter=junit", f"--reporter-outfile={outfile}"], **kwargs)
        return result, parse_junit(outfile)

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
        elif node.find("failure") is not None or node.find("error") is not None:
            status = "failed"
        cases.append({
            "name": node.attrib.get("name", ""),
            "classname": node.attrib.get("classname", ""),
            "file": node.attrib.get("file", ""),
            "full_name": f"{node.attrib.get('classname', '')} {node.attrib.get('name', '')}".strip(),
            "status": status,
        })
    return cases


def counts(cases: list[dict[str, Any]]) -> dict[str, int]:
    return {
        "pass": sum(c["status"] == "passed" for c in cases),
        "fail": sum(c["status"] == "failed" for c in cases),
        "skip": sum(c["status"] == "skipped" for c in cases),
    }


def junit_file_passed(cases: list[dict[str, Any]], path: str) -> bool:
    target = path.replace("\\", "/")
    return any(target in case.get("file", "").replace("\\", "/") and case["status"] == "passed" for case in cases)


def no_skip_marker(output: str) -> bool:
    return not re.search(r"GBRAIN_CHECK_SKIPPED|skipping [a-z]", output, re.IGNORECASE)


def changed_paths(runner: Runner, ref: str) -> set[str]:
    output = runner.git_text("diff", "--name-only", "-M", BASE, ref)
    return {line for line in output.splitlines() if line}


def ledger_section(root: Path, marker: str = "22f8c793") -> str:
    path = root / "CUSTOM-LEDGER.md"
    if not path.exists():
        return ""
    text = path.read_text(encoding="utf-8", errors="replace")
    index = text.find(marker)
    return text[index:] if index >= 0 else ""


def freeze(runner: Runner) -> tuple[dict[str, Any], bool]:
    head = runner.git_text("rev-parse", "HEAD")
    merge_head_result = runner.git("rev-parse", "MERGE_HEAD", require_ok=False)
    merge_head = merge_head_result["stdout"].strip() if merge_head_result["rc"] == 0 else ""
    merge_base = runner.git_text("merge-base", FORK, UPSTREAM)
    counts_text = runner.git_text("rev-list", "--left-right", "--count", f"{FORK}...{UPSTREAM}")
    fork_commits, upstream_commits = (int(x) for x in counts_text.split())
    version = runner.git_text("show", f"{UPSTREAM}:VERSION")
    anchor = runner.git_text("rev-parse", f"{ROLLBACK}^{{commit}}")
    branch = runner.git_text("branch", "--show-current")
    main_head = runner.git_text("rev-parse", "HEAD", cwd=MAIN_ROOT)
    main_status = runner.git_text("status", "--porcelain", "--untracked-files=no", cwd=MAIN_ROOT)
    merge_started_ok = merge_head in {"", UPSTREAM}
    parents = runner.git_text("rev-list", "--parents", "-n", "1", head).split()
    delivered = (
        len(parents) == 3 and parents[1:] == [FORK, UPSTREAM] and head != FORK
    )
    candidate_ok = (head == FORK and merge_started_ok) or delivered
    main_ok = (main_head == FORK or (delivered and main_head == head)) and main_status == ""
    ok = all([
        candidate_ok,
        merge_base == BASE,
        fork_commits == EXPECTED_FORK_COMMITS,
        upstream_commits == EXPECTED_UPSTREAM_COMMITS,
        version == EXPECTED_VERSION,
        anchor == FORK,
        branch == BRANCH,
        main_ok,
    ])
    return {
        "freeze_ok": ok,
        "fork_commits": fork_commits,
        "upstream_commits": upstream_commits,
        "upstream_version": version,
        "rollback_anchor_ok": anchor == FORK,
        "main_worktree_unchanged": main_ok,
        "merge_delivered": delivered,
    }, ok


def bilateral(runner: Runner) -> tuple[dict[str, Any], bool]:
    fork_paths = changed_paths(runner, FORK)
    upstream_paths = changed_paths(runner, UPSTREAM)
    both = fork_paths & upstream_paths
    table_path = CHANGE / "adjudication.tsv"
    rows: list[list[str]] = []
    if table_path.exists():
        for line in table_path.read_text(encoding="utf-8").splitlines():
            if not line.strip() or line.startswith("#") or line.startswith("path\t"):
                continue
            rows.append(line.split("\t"))
    covered = {row[0] for row in rows if row}
    missing = sorted(both - covered)
    extra = sorted(covered - both)
    gate_results = {}
    for name, script in [
        ("module_size_gate", "check:module-size"),
        ("page_body_gate", "check:page-body-readers"),
        ("core_world_reads_gate", "check:core-world-reads"),
        ("resolver_gate", "check:resolver"),
    ]:
        result = runner.run(["bun", "run", script], timeout=900)
        gate_results[name] = "ok" if result["rc"] == 0 and not result["timeout"] and no_skip_marker(result["output"]) else "fail"
    resolver_rows = [
        r.strip()
        for r in (runner.root / "skills/RESOLVER.md").read_text(encoding="utf-8", errors="replace").splitlines()
        if r.strip().startswith("|") and "skills/" in r
    ]
    duplicates = len(resolver_rows) - len(set(resolver_rows))
    freshness = runner.run(["bun", "run", "check:regen-all"], timeout=1200)
    lock = runner.run(["git", "diff", "--exit-code", "--", "skills/skills.lock.json"], timeout=120)
    generated = (
        freshness["rc"] == 0
        and not freshness["timeout"]
        and no_skip_marker(freshness["output"])
        and lock["rc"] == 0
        and gate_results["resolver_gate"] == "ok"
    )
    ok = (
        both == fork_paths & upstream_paths
        and len(both) == EXPECTED_BILATERAL
        and len(fork_paths) == EXPECTED_FORK_PATHS
        and len(upstream_paths) == EXPECTED_UPSTREAM_PATHS
        and len(rows) == EXPECTED_BILATERAL
        and not missing
        and not extra
        and all(v == "ok" for v in gate_results.values())
        and duplicates == 0
        and generated
    )
    return {
        "both_changed_paths": len(both),
        "fork_delta_paths": len(fork_paths),
        "upstream_delta_paths": len(upstream_paths),
        "adjudication_rows": len(rows),
        "adjudication_missing": len(missing),
        "adjudication_extra": len(extra),
        **gate_results,
        "duplicate_skill_routes": duplicates,
        "generated_from_sources": generated,
        "assert": (
            f"module_size_gate={gate_results['module_size_gate']} page_body_gate={gate_results['page_body_gate']} "
            f"core_world_reads_gate={gate_results['core_world_reads_gate']} duplicate_skill_routes={duplicates} "
            f"generated_from_sources={generated}"
        ),
    }, ok


def migrations(runner: Runner) -> tuple[dict[str, Any], bool]:
    order = runner.run(
        ["bun", "run", "check:schema-migration-order"],
        env={"GBRAIN_MIGRATION_BASE_REF": UPSTREAM},
        timeout=300,
    )
    registry_report = runner.log_dir / "registry.junit.xml"
    registry, cases = runner.junit(["bun", "test", "--timeout=60000", "test/schema-migration-registry.test.ts"], registry_report, timeout=900)
    c = counts(cases)
    files = sorted((runner.root / "src/core/schema-migrations").glob("v*.ts"))
    versions = [int(m.group(1)) for p in files if (m := re.match(r"v(\d+)-", p.name))]
    fork_versions = sorted(v for v in versions if v > EXPECTED_BASE_MAX)
    base_match = re.search(r"latest v(\d+)", order["output"])
    base_max = int(base_match.group(1)) if base_match else -1
    new_match = re.search(r"(\d+) new migration", order["output"])
    new_migrations = int(new_match.group(1)) if new_match else -1
    latest_text = (runner.root / "src/core/schema-migrations/latest.generated.ts").read_text(encoding="utf-8")
    version_match = re.search(r"LATEST_SCHEMA_VERSION = (\d+)", latest_text)
    registry_version = int(version_match.group(1)) if version_match else -1
    duplicates = len(versions) - len(set(versions))
    import tempfile
    probe_dir = tempfile.mkdtemp(prefix="pglite-empty-", dir=str(runner.log_dir)).replace("\\", "/")
    probe_script = (
        "import { PGLiteEngine } from './src/core/pglite-engine.ts';"
        "import { runMigrations } from './src/core/migrate.ts';"
        f"const engine = new PGLiteEngine();"
        f"await engine.connect({{ engine: 'pglite', database_path: '{probe_dir}' }});"
        "try {"
        "await engine.initSchema();"
        "const first = await runMigrations(engine);"
        "const second = await runMigrations(engine);"
        "console.log(`empty_db_applied_to=${first.current}`);"
        "console.log(`second_run_applied=${second.applied}`);"
        "} finally { await engine.disconnect(); }"
    )
    probe = runner.run(["bun", "-e", probe_script], cwd=runner.root, timeout=900)
    probe_applied = re.search(r"empty_db_applied_to=(\d+)", probe["output"])
    probe_second = re.search(r"second_run_applied=(\d+)", probe["output"])
    empty_db_applied_to = int(probe_applied.group(1)) if probe_applied else -1
    second_run_applied = int(probe_second.group(1)) if probe_second else -1
    ledger = ledger_section(runner.root)
    old_db_gap_recorded = "attest_read" in ledger and "v337" in ledger
    skipped = not no_skip_marker(order["output"])
    import hashlib
    def sql_payload(ref: str, path: str) -> str | None:
        result = runner.git("show", f"{ref}:{path}", require_ok=False)
        if result["rc"] != 0:
            return None
        match = re.search(r"sql: `([\s\S]*?)`,\n", result["stdout"])
        return hashlib.sha256(match.group(1).encode()).hexdigest() if match else None
    fork_sql = sql_payload(FORK, "src/core/schema-migrations/v298-inbox-workflow-frontmatter.ts")
    current_file = runner.root / "src/core/schema-migrations/v337-inbox-workflow-frontmatter.ts"
    current_text = current_file.read_text(encoding="utf-8") if current_file.exists() else ""
    current_match = re.search(r"sql: `([\s\S]*?)`,\n", current_text)
    current_sql = hashlib.sha256(current_match.group(1).encode()).hexdigest() if current_match else None
    sql_unchanged = fork_sql is not None and fork_sql == current_sql
    ok = (
        order["rc"] == 0
        and not order["timeout"]
        and not skipped
        and base_max == EXPECTED_BASE_MAX
        and new_migrations == 1
        and fork_versions == [EXPECTED_FORK_MIGRATION]
        and registry["rc"] == 0
        and not registry["timeout"]
        and c["fail"] == 0
        and c["skip"] == 0
        and c["pass"] > 0
        and registry_version == EXPECTED_FORK_MIGRATION
        and duplicates == 0
        and probe["rc"] == 0
        and not probe["timeout"]
        and empty_db_applied_to == EXPECTED_FORK_MIGRATION
        and second_run_applied == 0
        and old_db_gap_recorded
        and sql_unchanged
    )
    return {
        "migration_order_rc": order["rc"],
        "migration_order_skipped": skipped,
        "base_max": base_max,
        "fork_versions": fork_versions,
        "new_migrations": new_migrations,
        "registry_rc": registry["rc"],
        "registry_version": registry_version,
        "registry_duplicates": duplicates,
        "registry_fail": c["fail"],
        "empty_db_applied_to": empty_db_applied_to,
        "second_run_applied": second_run_applied,
        "old_db_gap_recorded": old_db_gap_recorded,
        "sql_payload_sha256_match": sql_unchanged,
        "database_upgrade_verified": False,
        "assert": f"migration_order_rc={order['rc']} base_max={base_max} fork_versions={fork_versions} new_migrations={new_migrations}",
    }, ok


def generated(runner: Runner) -> tuple[dict[str, Any], bool]:
    dist = runner.root / "admin/dist/index.html"
    admin_dist_present = dist.exists()
    regen = runner.run(["bun", "run", "regen:all"], timeout=1800)
    check_regen = runner.run(["bun", "run", "check:regen-all"], timeout=1800)
    build = runner.run(["bun", "run", "build:admin"], timeout=1800)
    runner.run(["git", "add", "admin/dist", "src/admin-embedded.ts"], timeout=300)
    embedded = runner.run(["bun", "run", "check:admin-embedded"], timeout=600)
    before = runner.run(["git", "diff", "--binary"], timeout=600)
    second = runner.run(["bun", "run", "regen:all"], timeout=1800)
    after = runner.run(["git", "diff", "--binary"], timeout=600)
    drift = before["stdout"] != after["stdout"]
    version_file = (runner.root / "VERSION").read_text(encoding="utf-8").strip()
    package_version = json.loads((runner.root / "package.json").read_text(encoding="utf-8"))["version"]
    changelog_head = (runner.root / "CHANGELOG.md").read_text(encoding="utf-8", errors="replace").splitlines()[:60]
    changelog_version_ok = any(re.search(r"^## \[" + re.escape(EXPECTED_VERSION) + r"\]", line) for line in changelog_head)
    admin_lock = runner.run(["bun", "install", "--lockfile-only", "--frozen-lockfile"], cwd=runner.root / "admin", timeout=600)
    checks = [regen, check_regen, build, embedded, second, admin_lock]
    ok = (
        admin_dist_present
        and not drift
        and version_file == EXPECTED_VERSION
        and package_version == EXPECTED_VERSION
        and changelog_version_ok
        and all(r["rc"] == 0 and not r["timeout"] for r in checks)
    )
    return {
        "regen_rc": regen["rc"],
        "check_regen_rc": check_regen["rc"],
        "second_regen_drift": drift,
        "admin_embedded_rc": embedded["rc"],
        "admin_dist_present": admin_dist_present,
        "version": version_file,
        "changelog_version_ok": changelog_version_ok,
        "admin_lock_frozen_rc": admin_lock["rc"],
    }, ok


def quality(runner: Runner) -> tuple[dict[str, Any], bool]:
    typecheck = runner.run(["bun", "run", "typecheck"], timeout=1800)
    targeted_report = runner.log_dir / "targeted.junit.xml"
    targeted, targeted_cases = runner.junit(
        ["bun", "test", "--timeout=60000", *TARGETED_TESTS], targeted_report, timeout=1800
    )
    tc = counts(targeted_cases)
    missing = sum(not junit_file_passed(targeted_cases, test) for test in TARGETED_TESTS)
    e2e_report = runner.log_dir / "e2e.junit.xml"
    e2e, e2e_cases = runner.junit(["bun", "test", "--timeout=120000", *E2E_TESTS], e2e_report, timeout=1800)
    ec = counts(e2e_cases)
    admin = runner.run(["bun", "run", "test"], cwd=runner.root / "admin", timeout=2400)
    unrun = {
        "postgres_e2e": "未跑：本机无 DATABASE_URL/Docker Postgres；engine-parity 需要真实数据库。",
        "admin_playwright": "未跑：本轮未要求浏览器 E2E。",
        "old_fork_db_probe": "未跑：需要对运行中的 298 库做只读副本；由操作者在安全窗口执行，台账已登记偏差。",
    }
    (runner.log_dir / "unrun.json").write_text(json.dumps(unrun, ensure_ascii=False, indent=2), encoding="utf-8")
    ledger = ledger_section(runner.root)
    unrun_recorded = "未跑" in ledger
    source_isolation_passed = junit_file_passed(e2e_cases, E2E_TESTS[0])
    ok = (
        typecheck["rc"] == 0
        and not typecheck["timeout"]
        and targeted["rc"] == 0
        and not targeted["timeout"]
        and tc["fail"] == 0
        and tc["skip"] == 0
        and missing == 0
        and e2e["rc"] == 0
        and not e2e["timeout"]
        and ec["fail"] == 0
        and ec["skip"] == 0
        and source_isolation_passed
        and admin["rc"] == 0
        and not admin["timeout"]
        and unrun_recorded
    )
    return {
        "typecheck_rc": typecheck["rc"],
        "targeted_rc": targeted["rc"],
        "targeted_skips": tc["skip"],
        "targeted_missing_files": missing,
        "admin_suite_rc": admin["rc"],
        "source_isolation_passed": source_isolation_passed,
        "e2e_skips": ec["skip"],
        "unrun_recorded": unrun_recorded,
        "assert": f"typecheck_rc={typecheck['rc']} targeted_rc={targeted['rc']} targeted_skips={tc['skip']} admin_suite_rc={admin['rc']}",
    }, ok


def added_whitespace(runner: Runner, parent: str) -> set[tuple[str, str]]:
    diff = runner.run(["git", "diff", "--cached", "--unified=0", parent], timeout=600)
    if diff["rc"] not in {0, 1}:
        raise VerificationError(f"diff {parent} failed: rc={diff['rc']}")
    path = ""
    found: set[tuple[str, str]] = set()
    for line in diff["stdout"].splitlines():
        if line.startswith("+++ b/"):
            path = line[6:]
        elif line.startswith("+") and not line.startswith("+++") and line[1:] != line[1:].rstrip():
            found.add((path, line[1:]))
    return found


def allowed_new_paths() -> set[str]:
    path = CHANGE / "allowed-new-paths.txt"
    if not path.exists():
        return set()
    return {line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip() and not line.startswith("#")}


def final(runner: Runner) -> tuple[dict[str, Any], bool]:
    unmerged = runner.run(["git", "ls-files", "-u"], timeout=120)
    fork_check = runner.run(["git", "diff", "--cached", "--check", FORK], timeout=600)
    upstream_check = runner.run(["git", "diff", "--cached", "--check", UPSTREAM], timeout=600)
    new_whitespace = added_whitespace(runner, FORK) & added_whitespace(runner, UPSTREAM)
    fork_paths = changed_paths(runner, FORK)
    upstream_paths = changed_paths(runner, UPSTREAM)
    candidate_paths = {
        line for line in runner.git_text("diff", "--cached", "--name-only", "-M", BASE).splitlines() if line
    }
    unexpected = candidate_paths - (fork_paths | upstream_paths | allowed_new_paths())
    head = runner.git_text("rev-parse", "HEAD")
    merge_head_result = runner.git("rev-parse", "MERGE_HEAD", require_ok=False)
    merge_head = merge_head_result["stdout"].strip() if merge_head_result["rc"] == 0 else ""
    branch = runner.git_text("branch", "--show-current")
    main_head = runner.git_text("rev-parse", "HEAD", cwd=MAIN_ROOT)
    main_status = runner.git_text("status", "--porcelain", "--untracked-files=no", cwd=MAIN_ROOT)
    upstream_tracking = runner.git("rev-parse", "--abbrev-ref", "@{u}", require_ok=False)
    remote_branch = runner.git("rev-parse", "--verify", f"refs/remotes/origin/{BRANCH}", require_ok=False)
    parents = runner.git_text("rev-list", "--parents", "-n", "1", head).split()
    delivered = len(parents) == 3 and parents[1:] == [FORK, UPSTREAM] and head != FORK
    remote_sha = remote_branch["stdout"].strip() if remote_branch["rc"] == 0 else ""
    if delivered:
        delivery = (
            branch == BRANCH
            and main_head == head
            and main_status == ""
            and remote_sha == head
        )
    else:
        delivery = (
            head == FORK
            and merge_head == UPSTREAM
            and branch == BRANCH
            and main_head == FORK
            and main_status == ""
            and upstream_tracking["rc"] != 0
            and remote_branch["rc"] != 0
        )
    ledger = ledger_section(runner.root)
    ledger_updated = "22f8c793" in ledger and "v337" in ledger and "未跑" in ledger
    parent_ok = not unexpected and fork_check["rc"] in {0, 2} and upstream_check["rc"] in {0, 2}
    ok = unmerged["stdout"].strip() == "" and len(new_whitespace) == 0 and parent_ok and delivery and ledger_updated
    return {
        "final_audit_ok": ok,
        "unmerged_paths": len([x for x in unmerged["stdout"].splitlines() if x]),
        "new_whitespace_warnings": len(new_whitespace),
        "fork_parent_diff_ok": parent_ok,
        "upstream_parent_diff_ok": parent_ok,
        "ledger_updated": ledger_updated,
        "delivery_boundary_ok": delivery,
        "merge_delivered": delivered,
        "unexpected_candidate_paths": sorted(unexpected),
        "candidate_paths": len(candidate_paths),
        "fork_check_rc": fork_check["rc"],
        "upstream_check_rc": upstream_check["rc"],
    }, ok


ACTIONS = {
    "freeze": freeze,
    "bilateral": bilateral,
    "migrations": migrations,
    "generated": generated,
    "quality": quality,
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
