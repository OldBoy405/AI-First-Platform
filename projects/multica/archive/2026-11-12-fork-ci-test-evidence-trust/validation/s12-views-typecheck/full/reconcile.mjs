#!/usr/bin/env node
// Reconciles the two full views vitest runs by test name, not by count.
//
// Counting failures alone cannot distinguish "S12 broke five tests" from "the same
// load-sensitive tests fail at HEAD too, and the victim set moves between runs".
// Names can. Run: node full/reconcile.mjs  (from validation/s12-views-typecheck)
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");

function parse(file) {
  const text = readFileSync(join(root, file), "utf8").replace(/\r\n/g, "\n");
  // vitest colourises its summary; the escape prefix is why a plain `^ FAIL ` grep
  // silently finds nothing in these captures.
  const lines = text.replace(/\x1b\[[0-9;]*m/g, "").split(/\r?\n/);
  const failures = [];
  for (let i = 0; i < lines.length; i += 1) {
    const m = lines[i].match(/^\s*FAIL\s+(.+)$/);
    if (!m) continue;
    let reason = null;
    for (let j = i + 1; j < Math.min(i + 40, lines.length); j += 1) {
      const s = lines[j].trim();
      if (/^(Error|TypeError|AssertionError|TestingLibraryElementError)\b/.test(s) || /timed out/.test(s)) {
        reason = s;
        break;
      }
    }
    if (reason === null) throw new Error(`no failure reason found for ${m[1]} in ${file}`);
    failures.push({ name: m[1].trim(), reason });
  }
  const totals = {};
  for (const key of ["Test Files", "Tests"]) {
    // Anchored at line start: the "⎯⎯ Failed Tests 6 ⎯⎯" banner also contains " Tests ".
    const line = lines.find((l) => new RegExp(`^\\s*${key}\\s`).test(l));
    if (!line) throw new Error(`no "${key}" summary line in ${file}`);
    // An all-pass run prints "5 passed (5)" with no "N failed |" segment.
    const m = line.replace(new RegExp(`^\\s*${key}\\s+`), "").match(/^(?:(\d+) failed\s*\|\s*)?(\d+) passed\s*\((\d+)\)/);
    if (!m) throw new Error(`cannot parse "${key}" summary in ${file}: ${line}`);
    totals[key] = { failed: Number(m[1] ?? 0), passed: Number(m[2]), total: Number(m[3]) };
  }
  if (failures.length !== totals.Tests.failed) {
    throw new Error(`${file}: ${failures.length} FAIL lines but summary says ${totals.Tests.failed}`);
  }
  return { failures, totals };
}

const head = parse("ab/views-vitest-head.txt");
const change = parse("full/views-vitest.txt");
const five = parse("full/five-files-with-change.txt");

const headNames = new Set(head.failures.map((f) => f.name));
const changeNames = new Set(change.failures.map((f) => f.name));
const common = [...changeNames].filter((n) => headNames.has(n));
const headOnly = [...headNames].filter((n) => !changeNames.has(n));
const changeOnly = [...changeNames].filter((n) => !headNames.has(n));

if (head.totals.Tests.total !== change.totals.Tests.total) {
  throw new Error("the two runs did not execute the same number of tests");
}
const reasonOf = (n) => change.failures.find((f) => f.name === n)?.reason ?? head.failures.find((f) => f.name === n).reason;
const out = [];
const say = (s) => out.push(s);

say("S12 views full-suite A/B, reconciled by test name");
say("================================================");
say("");
say("Run A (HEAD, both S12 files reverted): ab/views-vitest-head.txt");
say(`  Test Files ${head.totals["Test Files"].failed} failed | ${head.totals["Test Files"].passed} passed (${head.totals["Test Files"].total})`);
say(`  Tests      ${head.totals.Tests.failed} failed | ${head.totals.Tests.passed} passed (${head.totals.Tests.total})`);
say("");
say("Run B (with S12): full/views-vitest.txt");
say(`  Test Files ${change.totals["Test Files"].failed} failed | ${change.totals["Test Files"].passed} passed (${change.totals["Test Files"].total})`);
say(`  Tests      ${change.totals.Tests.failed} failed | ${change.totals.Tests.passed} passed (${change.totals.Tests.total})`);
say("");
say(`Total tests executed is identical (${head.totals.Tests.total}); S12 added and removed no test.`);
say("");
say(`Failed in both runs (${common.length}):`);
for (const n of common) say(`  - ${n}\n      ${reasonOf(n)}`);
say("");
say(`Failed only at HEAD (${headOnly.length}) — passed with the change:`);
for (const n of headOnly) say(`  - ${n}\n      ${reasonOf(n)}`);
say("");
say(`Failed only with the change (${changeOnly.length}):`);
for (const n of changeOnly) say(`  - ${n}\n      ${reasonOf(n)}`);
say("");
say("Run C (the five Run-B failing files, re-run as a group): full/five-files-with-change.txt");
say(`  Test Files ${five.totals["Test Files"].failed} failed | ${five.totals["Test Files"].passed} passed (${five.totals["Test Files"].total})`);
say(`  Tests      ${five.totals.Tests.failed} failed | ${five.totals.Tests.passed} passed (${five.totals.Tests.total})`);
if (five.totals.Tests.failed !== 0) throw new Error("the five-file group did not pass; the load explanation does not hold");
say("");
say("Verdict");
say("-------");
say("The failures pre-exist at HEAD: reverting both S12 files still produced 6 failures.");
say("The victim set moves between runs (2 HEAD-only, 7 change-only, 4 shared) while the");
say("executed test count stays at " + head.totals.Tests.total + ", so this is not a fixed set of broken assertions.");
say("Every file that failed in Run B passes in Run C, away from 506-file parallel load.");
say("Reasons are dominated by `Test timed out in 5000ms`. The two `rejectCreate is not a");
say("function` TypeErrors are downstream of the same stall: create-issue.test.tsx:1097 and");
say(":1125 declare `let rejectCreate!` and assign it only inside the promise executor of");
say("`mockCreateIssue.mockImplementationOnce`, so it stays undefined when the component");
say("never reaches the create call.");
say("");
say("NOT established by this evidence: that the flake is harmless in CI, or that its rate");
say("is unchanged. Two runs cannot measure a rate. Reported for the U4 ruling, not absorbed.");

const text = out.join("\n") + "\n";
process.stdout.write(text);