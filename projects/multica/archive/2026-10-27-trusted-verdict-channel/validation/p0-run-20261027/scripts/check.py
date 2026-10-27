#!/usr/bin/env python3
"""Fail-closed checker for the P0 evidence run. Exit 0 only if every claim holds
and every negative control turns red."""
import json, re, sys
from pathlib import Path

out = Path(sys.argv[1])
LAUNCHER = "/usr/local/lib/aifi45/launch.sh"
IDS = {"aifi45-worker": (995, 994), "aifi45-reader": (994, 993)}
DENY = ["cross_read", "write_launcher", "write_entrypoint", "replace_entrypoint", "sudo", "setuid0"]
results = []

def claim(name, ok, detail):
    results.append({"claim": name, "pass": bool(ok), "detail": detail})

def probes(path):
    rows = {}
    for line in path.read_text().splitlines():
        if line.startswith("PROBE status "):
            k, _, v = line[len("PROBE status "):].partition(":")
            rows["status." + k] = v.strip()
        elif line.startswith("PROBE "):
            k, _, v = line[6:].partition(" ")
            rows[k] = v.strip()
    return rows

for role, user in (("worker", "aifi45-worker"), ("reader", "aifi45-reader")):
    p = probes(out / f"probes-{role}.txt")
    uid, gid = IDS[user]
    claim(f"{role}.identity",
          f"user={user} uid={uid} gid={gid} groups={gid}" == p.get("identity")
          and p.get("status.Uid") == f"{uid} {uid} {uid} {uid}",
          p.get("identity"))
    claim(f"{role}.no_caps", p.get("status.CapEff") == "0000000000000000"
          and p.get("status.CapPrm") == "0000000000000000", p.get("status.CapEff"))
    claim(f"{role}.no_new_privs", p.get("status.NoNewPrivs") == "1", p.get("status.NoNewPrivs"))
    for k in DENY:
        claim(f"{role}.{k}_denied", p.get(k) == "denied", p.get(k))
    claim(f"{role}.own_root_writable", p.get("own_root_write") == "ok", p.get("own_root_write"))

allow = (out / "launcher-allowlist.txt").read_text().splitlines()
claim("launcher.allowlist", len(allow) == 4 and all(l.startswith("LAUNCH denied rc=64 ") for l in allow), allow)

ctl = probes(out / "probes-rootctl.txt")
claim("control.probes_can_turn_red", all(ctl.get(k) == "ok" for k in DENY), {k: ctl.get(k) for k in DENY})

def trace(name):
    text = (out / f"trace-{name}.txt").read_text()
    if re.search(r"(?i)lost \d+ events", text):
        return None, "events lost"
    events = []
    for line in text.splitlines():
        m = re.match(r"^(FORK|EXEC) (\d+) (.*)$", line)
        if m:
            events.append((int(m.group(2)), m.group(1), m.group(3).split(" ", 2)))
    events.sort(key=lambda e: e[0])
    allowed, launches, sanctioned, violations = set(), 0, 0, []
    targets = {str(v[0]) for v in IDS.values()}
    for _, kind, f in events:
        if kind == "FORK":
            if f[0] in allowed:
                allowed.add(f[1])
            continue
        pid, uid, path = f[0], f[1], f[2] if len(f) > 2 else ""
        if path == LAUNCHER and uid == "0":
            allowed.add(pid); launches += 1
        elif uid in targets:
            if pid in allowed:
                sanctioned += 1
            else:
                violations.append({"pid": pid, "uid": uid, "file": path})
    return {"events": len(events), "launches": launches, "sanctioned_execs": sanctioned,
            "violations": violations}, None

clean, err = trace("clean")
claim("trace.clean_only_via_launcher",
      err is None and clean["launches"] >= 6 and clean["sanctioned_execs"] > 0 and not clean["violations"],
      err or clean)
control, err = trace("control")
claim("control.second_path_detected",
      err is None and any(v["file"] == "/usr/bin/id" and v["uid"] == "995" for v in control["violations"]),
      err or control)

summary = {"pass": sum(r["pass"] for r in results), "fail": sum(not r["pass"] for r in results), "results": results}
(out / "check-result.json").write_text(json.dumps(summary, indent=2) + "\n")
for r in results:
    print(("PASS " if r["pass"] else "FAIL ") + r["claim"])
print(f"RESULT pass={summary['pass']} fail={summary['fail']}")
sys.exit(0 if summary["fail"] == 0 else 1)
