// AIFIRST: S11 regression reconciliation by test name (evidence tooling).
// The S10 baseline used the spec reporter, the S11 run used TAP; parse both, compare sets.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const validation = resolve(here, "..");

function names(file) {
  const text = readFileSync(file, "utf8").replaceAll("\r\n", "\n");
  const out = [];
  for (const line of text.split(/\r?\n/)) {
    const tap = /^ok \d+ - (.+)$/.exec(line);
    if (tap) { out.push(tap[1].trim()); continue; }
    const spec = /^\u2714 (.+) \([\d.]+ms\)$/.exec(line);
    if (spec) { out.push(spec[1].trim()); continue; }
    const fail = /^(?:not ok \d+ - |\u2716 )(.+?)(?: \([\d.]+ms\))?$/.exec(line);
    if (fail) out.push(`FAIL ${fail[1].trim()}`);
  }
  if (out.length === 0) throw new Error(`no test names parsed from ${file}`);
  return out;
}

const before = names(join(validation, "s10-wsd-no-recreate/regression-directory.tap"));
const after = names(join(here, "final/regression-directory.tap"));
const b = new Set(before);
const a = new Set(after);
const added = after.filter((n) => !b.has(n)).sort();
const removed = before.filter((n) => !a.has(n)).sort();
const lines = [
  `baseline (S10, spec reporter) = ${before.length} names`,
  `current  (S11, TAP reporter)  = ${after.length} names`,
  `added = ${added.length}   removed = ${removed.length}`,
  "",
  "--- added ---",
  ...added,
  "",
  "--- removed ---",
  ...removed,
  "",
];
const text = lines.join("\n");
writeFileSync(join(here, "final/regression-reconcile.txt"), text);
console.log(text);