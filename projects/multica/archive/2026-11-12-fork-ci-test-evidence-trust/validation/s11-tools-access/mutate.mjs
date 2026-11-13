// AIFIRST: S11 mutation verification driver (STDD 2026-11-12-fork-ci-test-evidence-trust).
// Evidence tooling, not product code: neuter one guard at a time, prove the suite goes red,
// restore byte-exact and verify the digest. A surviving mutation is reported as SURVIVED.
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repo = "C:/Users/GOBAO/Downloads/AI/multica";
const target = join(repo, "scripts/aifi45-disposable/tools-access.mjs");
const testFile = "scripts/aifi45-disposable/tools-access.test.mjs";
const pristine = readFileSync(target);
const digest = (b) => createHash("sha256").update(b).digest("hex");
const original = digest(pristine);

const MUTATIONS = [
  ["M01-missing-short-circuit", "  if (!hasCredential(token)) return missingCredential();\n", ""],
  ["M02-whitespace-trim", 'token.trim() !== ""', 'token !== ""'],
  ["M03-401-mapping", "if (status === 401) {", "if (status === 402) {"],
  ["M04-404-mapping", "if (status === 403 || status === 404) {", "if (status === 403) {"],
  ["M05-ok-exit-zero", 'verdict("ok", `${target} is readable with ${TOKEN_ENV}`, 0)', 'verdict("ok", `${target} is readable with ${TOKEN_ENV}`)'],
  ["M06-network-catch", '  } catch {\n    // Proxy, TLS and DNS failures can echo the request headers into error.message, so the\n    // rejection is deliberately not reported verbatim.\n    return verdict("inconclusive", "the request to api.github.com did not complete");\n  }', "  } catch (failure) {\n    throw failure;\n  }"],
  ["M07-other-status-fallback", 'return verdict("inconclusive", `${status} from api.github.com; unexpected status`);', 'return verdict("ok", `${status} from api.github.com; unexpected status`, 0);'],
  ["M08-authorization-header", "headers: { Authorization: `Bearer ${token}` },", 'headers: { Authorization: "Bearer" },'],
  ["M09-token-in-url", "const url = `https://api.github.com/repos/${TOOLS_REPO}/commits/${revision}`;", "const url = `https://api.github.com/repos/${TOOLS_REPO}/commits/${revision}?access_token=${token}`;"],
  ["M10-echo-error-message", '  } catch {\n    // Proxy, TLS and DNS failures can echo the request headers into error.message, so the\n    // rejection is deliberately not reported verbatim.\n    return verdict("inconclusive", "the request to api.github.com did not complete");\n  }', '  } catch (failure) {\n    return verdict("inconclusive", String(failure?.message ?? failure));\n  }'],
  ["M11-pin-before-request", "  const revision = parsePin(pin);", "  const revision = pin;"],
  ["M12-cli-credential-order", '  if (!hasCredential(token)) {\n    const result = missingCredential();\n    error(result.message);\n    return result.exitCode;\n  }\n  try {\n    const { pin, pinFile } = parseArgs(argv);\n    const result = await checkToolsAccess({ token, pin: pin ?? readPinFile(pinFile), fetchImpl });', '  try {\n    const { pin, pinFile } = parseArgs(argv);\n    const resolved = pin ?? readPinFile(pinFile);\n    if (!hasCredential(token)) {\n      const result = missingCredential();\n      error(result.message);\n      return result.exitCode;\n    }\n    const result = await checkToolsAccess({ token, pin: resolved, fetchImpl });'],
  ["M13-unknown-argument", "if (flag !== \"--pin\" && flag !== \"--pin-file\") throw new Error(`unknown argument ${flag}`);", 'if (flag !== "--pin" && flag !== "--pin-file") continue;'],
  ["M14-valueless-flag", "if (value === undefined) throw new Error(`${flag} requires a value`);", "if (value === undefined) break;"],
  ["M15-result-exposes-token", 'if (status === 200) return verdict("ok", `${target} is readable with ${TOKEN_ENV}`, 0);', 'if (status === 200) return { ...verdict("ok", `${target} is readable with ${TOKEN_ENV}`, 0), token };'],
  ["M16-main-module-guard", "if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {\n  process.exitCode = await runToolsAccessCli(process.argv.slice(2));\n}", "process.exitCode = await runToolsAccessCli(process.argv.slice(2));"],
];

const rows = [];
for (const [id, from, to] of MUTATIONS) {
  const text = pristine.toString("utf8");
  const hits = text.split(from).length - 1;
  if (hits !== 1) throw new Error(`${id}: anchor found ${hits} times, expected exactly 1`);
  const dir = join(here, "mutation", id);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "patch.txt"), `--- anchor\n${from}\n--- replacement\n${to}\n`);
  writeFileSync(target, text.replace(from, to));
  const run = spawnSync(process.execPath, ["--test", "--test-reporter=tap", testFile], { cwd: repo, encoding: "utf8" });
  const tap = `${run.stdout ?? ""}${run.stderr ?? ""}`;
  writeFileSync(join(dir, "red.tap"), tap);
  const failed = [...tap.matchAll(/^not ok \d+ - (.+)$/gm)].map((m) => m[1]);
  const counts = Object.fromEntries([...tap.matchAll(/^# (tests|pass|fail|skipped) (\d+)$/gm)].map((m) => [m[1], Number(m[2])]));
  writeFileSync(target, pristine);
  const restored = digest(readFileSync(target));
  if (restored !== original) throw new Error(`${id}: restore digest mismatch`);
  writeFileSync(join(dir, "restored-sha256.txt"), `${restored}  tools-access.mjs\n`);
  const detected = run.status !== 0;
  rows.push({ id, detected, exit: run.status, ...counts, failed, restored });
  console.log(`${detected ? "DETECTED" : "SURVIVED"} ${id} exit=${run.status} pass=${counts.pass} fail=${counts.fail} :: ${failed.join(" | ") || "(no named failure)"}`);
}

writeFileSync(join(here, "mutation", "summary.json"), `${JSON.stringify({ original, rows }, null, 2)}\n`);
const survived = rows.filter((r) => !r.detected);
console.log(`\n${rows.length} mutations, ${rows.length - survived.length} detected, ${survived.length} survived`);
console.log(`pristine sha256 ${original}`);
if (survived.length > 0) console.log(`SURVIVED: ${survived.map((r) => r.id).join(", ")}`);