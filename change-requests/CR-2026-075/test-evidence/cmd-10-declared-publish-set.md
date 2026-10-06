---
id: CR-2026-075-cmd-10-declared-publish-set
type: EVIDENCE
cr-ref: CR-2026-075
source-task: CR-2026-075-TASK-10
target-version: 0.48
updated: 2026-10-06T04:53:15.085Z
---

# `cmd-10` 本 CR 声明发布集（30 项）逐文件核对

期望集来源：`plan.md` §6.2 `cmd-10` 的 `EXPECT`（crctl 12 + engineering-docs 6 + 其余 12 个各 `SKILL.md`）。**先断言线上存在，再逐文件与仓库目标按 LF 全等比对**（`cmd-10` 自身口径：尾换行宽容）。本文件是本轮 `cmd-10` 的从属记录：线上值由 `multica skill get <id> --with-content` 现读，仓库目标取 tools CR worktree；两列 sha256 相等即 LF（尾换行宽容）全等。

- 线上存在且与仓库目标 LF 全等：**30 / 30**
- 缺失或不等：0

| # | Skill | 文件（仓库相对路径） | 线上存在 | LF 全等 | 线上 sha256（LF 归一） | 仓库目标 sha256 |
|---|---|---|---|---|---|---|
| 1 | crctl | `skills/shared/crctl/SKILL.md` | 是 | 是 | `53e3f39895f2cc81716e733b091d9c489435470d9bf5d987df3d136f6d53db99` | `53e3f39895f2cc81716e733b091d9c489435470d9bf5d987df3d136f6d53db99` |
| 2 | crctl | `skills/shared/crctl/scripts/crctl.mjs` | 是 | 是 | `d6c12c3748cac38e6c42469276e58d3e67745773950d88a5db43b7333d99eec6` | `d6c12c3748cac38e6c42469276e58d3e67745773950d88a5db43b7333d99eec6` |
| 3 | crctl | `skills/shared/crctl/scripts/lib/durable-tx.mjs` | 是 | 是 | `57d5b5023591c797db06b5fa3c91089ef8f1cc7d4cd73d9042cad87b365a223e` | `57d5b5023591c797db06b5fa3c91089ef8f1cc7d4cd73d9042cad87b365a223e` |
| 4 | crctl | `skills/shared/crctl/scripts/lib/planning-entry.mjs` | 是 | 是 | `ba0f7161da42e5b383292370618b5a47b791799975072d71fe92de49f16e6806` | `ba0f7161da42e5b383292370618b5a47b791799975072d71fe92de49f16e6806` |
| 5 | crctl | `skills/shared/crctl/scripts/lib/competitive-report.mjs` | 是 | 是 | `865857bb6a2284795962ed35543c6d5142101c19d205029185cece5dfac4bef0` | `865857bb6a2284795962ed35543c6d5142101c19d205029185cece5dfac4bef0` |
| 6 | crctl | `skills/shared/crctl/scripts/test/crctl.test.mjs` | 是 | 是 | `76bf5ed91620e55271a8cfdff04df90aebdaeeafa97c8afbca9ac4d7721a0a38` | `76bf5ed91620e55271a8cfdff04df90aebdaeeafa97c8afbca9ac4d7721a0a38` |
| 7 | crctl | `skills/shared/crctl/scripts/test/planning-entry.test.mjs` | 是 | 是 | `7541d7b23a680865fcbe981454490c75e61572537ac81996e86e854a3097471c` | `7541d7b23a680865fcbe981454490c75e61572537ac81996e86e854a3097471c` |
| 8 | crctl | `skills/shared/crctl/scripts/test/competitive-report.test.mjs` | 是 | 是 | `7d8d84cfb88a37c56d8e150357b4295cf9e13fe229ddfb872cecbd3f5d92c89f` | `7d8d84cfb88a37c56d8e150357b4295cf9e13fe229ddfb872cecbd3f5d92c89f` |
| 9 | crctl | `skills/shared/crctl/scripts/test/caller-contract.test.mjs` | 是 | 是 | `8c391329d0bbde33c009cedfbdc88794e7eb264a9b177dfd19e274237d521617` | `8c391329d0bbde33c009cedfbdc88794e7eb264a9b177dfd19e274237d521617` |
| 10 | crctl | `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` | 是 | 是 | `6504a3c3fa3b4fbe461445e0a962454d9157b8df3a72d493a12f85ffbd6af65d` | `6504a3c3fa3b4fbe461445e0a962454d9157b8df3a72d493a12f85ffbd6af65d` |
| 11 | crctl | `skills/shared/crctl/scripts/test/durable-tx.test.mjs` | 是 | 是 | `4d30b7b1ffda58331f1128f95c7edd267a54aff4e81bbeea788c3aff99221b70` | `4d30b7b1ffda58331f1128f95c7edd267a54aff4e81bbeea788c3aff99221b70` |
| 12 | crctl | `skills/shared/crctl/scripts/test/gate-registry.json` | 是 | 是 | `f0eaaa944d1a658b4b4c9657289635aa92f9d9a6914c40133ae3234ee10c5db2` | `f0eaaa944d1a658b4b4c9657289635aa92f9d9a6914c40133ae3234ee10c5db2` |
| 13 | validate-doc | `skills/shared/validate-doc/SKILL.md` | 是 | 是 | `c8601d37171b10b8b1e15432fcd9edb0a003dbe9f11099dbdc126872900821a0` | `c8601d37171b10b8b1e15432fcd9edb0a003dbe9f11099dbdc126872900821a0` |
| 14 | engineering-docs | `skills/shared/engineering-docs/SKILL.md` | 是 | 是 | `51043b283e8ef6cbb02cab29dc08c2dc9e1a073837350982f4afbbf0f642b1f6` | `51043b283e8ef6cbb02cab29dc08c2dc9e1a073837350982f4afbbf0f642b1f6` |
| 15 | engineering-docs | `skills/shared/engineering-docs/scripts/src/utils/slug.ts` | 是 | 是 | `2359edc2745946452e1cb4b19e78b5b9a371508a6467df47352ab9acafae142c` | `2359edc2745946452e1cb4b19e78b5b9a371508a6467df47352ab9acafae142c` |
| 16 | engineering-docs | `skills/shared/engineering-docs/scripts/src/generators/base.ts` | 是 | 是 | `78882032b8470926a994c570483e541110c7f906ff9c28d218771d2baab6800f` | `78882032b8470926a994c570483e541110c7f906ff9c28d218771d2baab6800f` |
| 17 | engineering-docs | `skills/shared/engineering-docs/scripts/src/validators/index-sync.ts` | 是 | 是 | `075b29e9c2ede6f4308b5cd9978b635ffb6f1567886981eac0c149237a21a5d6` | `075b29e9c2ede6f4308b5cd9978b635ffb6f1567886981eac0c149237a21a5d6` |
| 18 | engineering-docs | `skills/shared/engineering-docs/scripts/src/__tests__/generators.test.ts` | 是 | 是 | `43115442dcb919e47ad6aaaa20ae78113056aa239f8a94016b29ce8517cfd211` | `43115442dcb919e47ad6aaaa20ae78113056aa239f8a94016b29ce8517cfd211` |
| 19 | engineering-docs | `skills/shared/engineering-docs/scripts/src/__tests__/validators.test.ts` | 是 | 是 | `a26a097021b1e51c1d6229e1225ed3e2de6f4ce0ececc21dbfa571f5e8ae7b40` | `a26a097021b1e51c1d6229e1225ed3e2de6f4ce0ececc21dbfa571f5e8ae7b40` |
| 20 | cr-review-record | `skills/cr/cr-review-record/SKILL.md` | 是 | 是 | `f02c076c221e2f2cc20b7df3d8deb356a23b71ae29c55664369616fc2ed9d299` | `f02c076c221e2f2cc20b7df3d8deb356a23b71ae29c55664369616fc2ed9d299` |
| 21 | review-code | `skills/develop/review-code/SKILL.md` | 是 | 是 | `20f803ad16193d8646213fbce8c6d43b2a7c893d5763cc2f8f48622e76f96ac2` | `20f803ad16193d8646213fbce8c6d43b2a7c893d5763cc2f8f48622e76f96ac2` |
| 22 | review-dev-plan | `skills/develop/review-dev-plan/SKILL.md` | 是 | 是 | `4812a020cd1b2ebcb61c3d1c2836a08d30c9eff44f0a0c6aa8b726fe5a09d57a` | `4812a020cd1b2ebcb61c3d1c2836a08d30c9eff44f0a0c6aa8b726fe5a09d57a` |
| 23 | review-tech-design | `skills/develop/review-tech-design/SKILL.md` | 是 | 是 | `6f9fe499cb3608c26596cd6f049c0c839735c8b7346848c692f0f63c3fd4c9fe` | `6f9fe499cb3608c26596cd6f049c0c839735c8b7346848c692f0f63c3fd4c9fe` |
| 24 | write-dev-tasks | `skills/develop/write-dev-tasks/SKILL.md` | 是 | 是 | `ca0c0aa5a2e92472f5f90d9b4d2c4b85d62612e078414763216d9ca637e1a2ff` | `ca0c0aa5a2e92472f5f90d9b4d2c4b85d62612e078414763216d9ca637e1a2ff` |
| 25 | write-tech-design | `skills/develop/write-tech-design/SKILL.md` | 是 | 是 | `0e4f0c44b9c0bcfc1e6ff38d5adfd7862dc482a6ef3b637a1d6e6692d485b45e` | `0e4f0c44b9c0bcfc1e6ff38d5adfd7862dc482a6ef3b637a1d6e6692d485b45e` |
| 26 | review-requirement | `skills/requirement/review-requirement/SKILL.md` | 是 | 是 | `9cc8d6f5d490ef4646210c1357e0207ba0ef1cebcda06a2837343b01a7af0e82` | `9cc8d6f5d490ef4646210c1357e0207ba0ef1cebcda06a2837343b01a7af0e82` |
| 27 | write-planning-entry | `skills/planning/write-planning-entry/SKILL.md` | 是 | 是 | `6bfad97b627fdc4a1bb1bf0ba6f9a30eced090af3778b88e41405fff192e955e` | `6bfad97b627fdc4a1bb1bf0ba6f9a30eced090af3778b88e41405fff192e955e` |
| 28 | planning-draft | `skills/planning/planning-draft/SKILL.md` | 是 | 是 | `77528dfd05b44677b977e6e619512f11060e7154e5592f053e13ad01caf20257` | `77528dfd05b44677b977e6e619512f11060e7154e5592f053e13ad01caf20257` |
| 29 | write-competitive-report | `skills/competitive/write-competitive-report/SKILL.md` | 是 | 是 | `04c626267429bb2201d18f5b4dab14fde9e4a517419e53a32b37608ac52744c6` | `04c626267429bb2201d18f5b4dab14fde9e4a517419e53a32b37608ac52744c6` |
| 30 | requirement-register | `skills/requirement/requirement-register/SKILL.md` | 是 | 是 | `2368164029dc5e5946781a843035fd9d972ff0367e4b173cf3f61a03ed5cbfdd` | `2368164029dc5e5946781a843035fd9d972ff0367e4b173cf3f61a03ed5cbfdd` |

## `out-of-scope-drift`（R8：本 CR 未声明改动的既有漂移，单列、不计入本 CR 通过判定）

```text
out-of-scope-drift crctl N=4（R8 范围外既有漂移，单列、不参与本 CR 通过判定）: scripts/test/fault-harness.test.mjs,scripts/test/merge-fixture.mjs,scripts/test/register-tx.test.mjs,scripts/test/test-cr.test.mjs
```

## 规划 / 竞品两个业务调用方 Agent（与仓库目标 LF 全等）

```text
agent-in-sync product-planning-agent sha256=317d5e31d9eb91277b8c3e9bac7ee0de49d25c2113820073696779ad52c9adfb
agent-in-sync competitive-analyst-agent sha256=d899dbe978db7ac2394af5ec0fa568c5984d8353196f1226515abef7bbcce366
```

## `cmd-10` 逐 Skill 复合值（该命令自身口径：`sha256(EXPECT 顺序 "<skill 内相对路径>:<sha256>" 以 LF 连接)`，仅该命令对账用）

```text
skill-in-sync crctl expected=12 online=65 sha256=32b64ffe4d52f4c46226ed0a41e6a87eb19583b0502325b0e77654ef67019ed7
skill-in-sync validate-doc expected=1 online=1 sha256=81fe35097c7183358287279d5591469e0480f99dc3a7255c38478bcbf5af23ac
skill-in-sync engineering-docs expected=6 online=46 sha256=786931349b65656121ecd7ace84710d5eb5f4b0993bfd57af0a02cdad5c83c5b
skill-in-sync cr-review-record expected=1 online=1 sha256=85efa748526d46e30928246786bfe93db74a94ba5af4f2989ef98a349af9615b
skill-in-sync review-code expected=1 online=1 sha256=b376a8fbceaa6c836ddb85e5690800999a51b7127159257a1bd69359032e6ca4
skill-in-sync review-dev-plan expected=1 online=1 sha256=21c3ce2a62409f6ab668c62a441507d22f863310a28e42f353df7172c118b264
skill-in-sync review-tech-design expected=1 online=1 sha256=ad232d7bae285ab1c2603aa0fae35275d341e6cec5f385cabaa5d1c471658129
skill-in-sync write-dev-tasks expected=1 online=1 sha256=5988d3907a49ad2e0247d3c23007a87e0e716df20b8fa2563b3eb373810420fa
skill-in-sync write-tech-design expected=1 online=1 sha256=a35d5cb3ccc464421bd306de99efac4e53ded0a5a09b5b38a5ac96fec922adf4
skill-in-sync review-requirement expected=1 online=1 sha256=d1da5aae30b98ca2fe72eb3db19d0163723ae19bac4c71216d226f781926848b
skill-in-sync write-planning-entry expected=1 online=1 sha256=5926803104836c1dcb08dd7b2b0b22a0ac62fc0545bbd62bf79a6b6e58550e8c
skill-in-sync planning-draft expected=1 online=1 sha256=3a375992069a882126e38a2f90bfaaf68c3098c1626a013fa062ede71435885f
skill-in-sync write-competitive-report expected=1 online=1 sha256=48a5a66f7ed9c9f5389c8f29a085c213ff9ccb14b5d601371e61c2631e7b33bc
skill-in-sync requirement-register expected=1 online=3 sha256=1c955be7799b69cbd4400edb1bbe6a4bcf0bf8789a031e8f2c0863053f8a7fe7
```
