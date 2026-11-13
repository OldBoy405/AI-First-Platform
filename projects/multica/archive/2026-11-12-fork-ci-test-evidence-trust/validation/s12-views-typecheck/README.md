# Slice 12 证据 — views typecheck 恢复（SC-CCF-002 / TC-CCF-002 / CP-CCF-002）

- change：`2026-11-12-fork-ci-test-evidence-trust`
- 业务仓：`C:\Users\GOBAO\Downloads\AI\multica`，HEAD = origin/main = `903a46c5ae9fa6c3ee644fa4740d189d739dcc91`
- 完成时间：**2026-11-13T01:32:59（本地 UTC+8）**
- 模式：`thorough` / 长程 `full_auto`
- **本切片新增测试数 = 0**，长程约束 #3 与 B3.4 第 3 项未满足，已登记 **ADJ-019**，**不报「B3.4 三项全过」**（见 §12）
- **views 全量存在 HEAD 已有的负载 flake**，已按 **U4** 上报，范围不扩大，登记 **ADJ-020**（见 §10）

---

## 1. 锁定依据

| 来源 | 原文要点 |
|---|---|
| `canonical/specs/code/ci-credential-and-frontend-typecheck.yaml` SC-CCF-002 | given：`use-logout.test.ts` 改用 `@multica/core` 包导入；when：运行 `@multica/views` 的 typecheck 与该测试文件；then：**SHALL typecheck 0 条 TS6059；`use-logout.test.ts` SHALL 全部通过；其断言 SHALL 与改前等价（不删除、不放宽）**；and：**若修好 typecheck 后暴露其他前端失败，SHALL 先报告再裁定范围（design U4）** |
| `test-plan.md:327-339` TC-CCF-002 | P0、置信度 high、**验证方式「命令型（本地可执行）：`pnpm --filter @multica/views typecheck`」** |
| `test-plan.md:668-677` 证据计划 | `tc: TC-CCF-002`、`case_id: main`、`cp: CP-CCF-002`、**`kind: command`**、`applicability: required` |
| `design.md:163` | S12 计划，含退路「若 lint/knip 不接受则退为 `vi.importActual` 取值或内联常量并说明」 |
| `design.md:164` U4 | 前端先保证 views typecheck 和本地 vitest，如实报告；若暴露其他功能性失败，先报告再裁定范围 |
| `design.md:272` 未验证事实 #5 | core 新增 exports 是否被 lint/knip/`check-ui-wildcard-exports` 接受 —— **本切片已闭合，见 §8** |

**canonical 一字未改**，本切片不需要 revision：实现与锁定设计一致，退路未启用。

## 2. 结论摘要

| 项 | 结果 |
|---|---|
| RED | **60 条 TS6059**（实测） |
| GREEN typecheck | **exit 0，`error TS` 计数 0**（任何错误码归零，不只 TS6059） |
| `auth/use-logout.test.ts` | **2/2 通过**（改前 HEAD 版本亦 2/2） |
| 断言等价 | **0 条 `expect(` 改动、两条 `it()` 标题不变** + HEAD 版本独立跑 2/2 |
| knip | 前后**逐字节相同**（diff **0 行**） |
| `check:ui-exports` | exit 0，前后相同（结构上不可能受影响） |
| lint core / views | 均 **exit 0、0 错误、0 次提及被改文件** |
| core 全量 vitest | **2552/2552（180 文件）exit 0** |
| views 全量 vitest | 带改动 **11 失败/6361 通过（6372）**；HEAD **6 失败/6366 通过（6372）** → **ADJ-020** |
| 5 个失败文件单独成组 | **146/146 通过 exit 0** |
| TC 覆盖 | **1/1**（TC-CCF-002，command 型） |
| 新增测试 | **0** → **ADJ-019** |

## 3. 设计前提先核实（不是假设）

`packages/views/tsconfig.json`：

```json
{ "extends": "@multica/tsconfig/react-library.json",
  "compilerOptions": { "outDir": "dist", "rootDir": "." },
  "include": ["**/*.ts", "**/*.tsx", "**/*.d.mts"], "exclude": ["node_modules", "dist"] }
```

`rootDir: "."` + `moduleResolution: bundler`（无 `preserveSymlinks`）意味着：测试里写相对路径 `../../core/xxx` 会把 **core 的 .ts 源文件直接拉进 views 的 program**，而这些文件在 views 的 `rootDir` 之外 → **TS6059**。包 specifier `@multica/core/xxx` 经 `node_modules` 解析，走的是另一条路径，**豁免**。

RED 的 60 条 TS6059 逐条溯源到这 4 条相对导入：

```
../../core/auth/store
../../core/platform/storage
../../core/api/client
../../core/types
```

grep 证实 **`use-logout.test.ts` 是 views 中唯一含相对 core 导入的文件**，故改这一个文件即可归零，**不需要动 tsconfig**（动 `rootDir` 会扩大影响面且属上游配置）。

## 4. 改动清单（两个上游文件，无新增文件）

### 4.1 `packages/core/package.json`（+1 / -0，CRLF）

```json
    "./platform": "./platform/index.ts",
    "./platform/storage": "./platform/storage.ts",
```

`platform/storage.ts` **早已存在**（`SESSION_BARRIER_KEY` 定义在其第 3 行）并经 `./platform` 间接导出；本次只补一条**具名入口**，未新建文件、未改任何实现。

sha256（改后）：`d6f127211fc55953bf9a3ec63d679a5a49db323fb59115dbdf4500c92fd82a35`

### 4.2 `packages/views/auth/use-logout.test.ts`（7 插入 / 5 删除，CRLF）

完整 diff 见 `green/use-logout-diff.txt`，实质两处：

```diff
-import { createAuthStore } from "../../core/auth/store";
-import { SESSION_BARRIER_KEY } from "../../core/platform/storage";
-import type { ApiClient } from "../../core/api/client";
-import type { User } from "../../core/types";
+import { SESSION_BARRIER_KEY } from "@multica/core/platform/storage";
+import type { ApiClient } from "@multica/core/api";
+import type { User } from "@multica/core/types";
```

```diff
-  it("still records the barrier, ... when client session cleanup throws", () => {
+  it("still records the barrier, ... when client session cleanup throws", async () => {
+    // The hook's `@multica/core/auth` is mocked below, so the fixture store must come
+    // from the real module rather than the mock.
+    const { createAuthStore } = await vi.importActual<typeof import("@multica/core/auth")>("@multica/core/auth");
```

**为什么必须 `vi.importActual`**：该文件下方 `vi.mock("@multica/core/auth", …)` 把整个模块替换成只有 `useAuthStore` 的桩，静态 `import { createAuthStore }` 只会拿到 `undefined`。这不是风格选择，是必需。`ApiClient` 从 `@multica/core/api`（其 `index.ts:2` 再导出）取，`User` 从 `@multica/core/types` 取，均为已有入口。

**故意不改的两处**：`vi.mock("../../core/analytics", …)` 与 `vi.mock("../../core/platform/workspace-storage", …)` 保留相对路径 —— **tsc 不解析 `vi.mock` 的字符串参数**，改它们对 TS6059 无收益，只会扩大 diff。

第二条测试 `erases client state, then drops auth, then navigates to /login` **全程未动**。

sha256（改后）：`e9e530947a90df18f43f0700f05e3cbd051592bc3633a352166b3c8b0c01e5b8`

## 5. RED

| 文件 | 内容 |
|---|---|
| `red/typecheck-before.txt` | `pnpm --filter @multica/views typecheck`，**60 条 TS6059**（`grep -c TS6059` = 60），238980 字节 |
| `red/use-logout-before.txt` | **HEAD 版本**另存临时文件 `auth/zz-s12-before.test.ts` 跑 → **2/2 通过**（证明改前该文件本来就是绿的，RED 只在 typecheck 层） |
| `red/knip-before.txt` | 根 `pnpm knip`，exit 1（既有发现：Unused files (12) 等 + 1 条 Configuration hint） |
| `red/ui-exports-before.txt` | 根 `pnpm check:ui-exports`，exit 0，`packages/ui wildcard exports clean (64 files …)` |

临时文件 `zz-s12-before.test.ts` **已删除并核实不存在**（`git status` 与目录列举均无）。

## 6. GREEN / CP-CCF-002

| 文件 | 内容 |
|---|---|
| `green/typecheck-after.txt` | **exit 0**，340 字节，只有 pnpm 的 `pnpm` 字段 WARN 与 script 横幅；`grep -cE "error TS"` = **0** |
| `green/use-logout-after.txt` | `✓ auth/use-logout.test.ts (2 tests) 75ms` → **2/2** |

**CP-CCF-002 满足**：typecheck 0 条 TS6059（实为 0 条任何错误码）+ 该测试文件全过 + 断言等价（§7）。

**按最终字节复跑确认**（A/B 期间两文件被覆盖过两次，故在还原并 `sha256sum -c` 通过之后再跑一遍）：`final/typecheck-final.txt` **exit 0、`error TS` 计数 0**；`final/use-logout-final.txt` **exit 0、`Test Files 1 passed (1)` / `Tests 2 passed (2)`**。复跑同时验证了 §18 的单文件命令形式确实可用。

## 7. 断言等价的双重证明（不靠自述）

1. **diff 层**：`green/use-logout-diff.txt` 中 **0 条 `expect(` 行被改动**，**两条 `it()` 标题字符串不变**（只有第一条加了 `async`）。删除的 5 行全是 import 与旧签名，新增的 7 行是 3 条 import + `async` 签名 + 2 行英文注释 + 1 行 `importActual`。
2. **运行时层**：HEAD 版本独立跑 **2/2**（`red/use-logout-before.txt`），改后 **2/2**（`green/use-logout-after.txt`）。同一组断言在两个版本下都成立 → 改写未改变被测行为。

## 8. 12.1 —— design 未验证事实 #5 已用证据闭合

| 检查 | 命令 | 结果 |
|---|---|---|
| knip | 根 `pnpm knip` | `green/knip-after.txt` 与 `red/knip-before.txt` **逐字节相同**；`green/knip-diff.txt` **0 字节 / 0 行**；两次均 **exit 1**（既有发现，非本切片引入） |
| `check-ui-wildcard-exports` | 根 `pnpm check:ui-exports` | exit 0，输出前后相同（`green/ui-exports-after.txt`） |
| lint core | `pnpm --filter @multica/core lint` | **exit 0、0 错误、0 次提及 `package.json`** |
| lint views | `pnpm --filter @multica/views lint` | **exit 0、0 错误、0 次提及 `use-logout.test.ts`** |

**为什么 knip 不受影响（读码核实，非猜测）**：`knip.jsonc` 的 `include: ["files","dependencies","unlisted"]` **不含 `exports`**，新增 export 不进入检查面。

**为什么 `check-ui-wildcard-exports.mjs` 结构上不可能受影响**：该脚本的 `uiRoot = join(repoRoot,"packages","ui")` 与 `pkgName = "@multica/ui"` **硬编码**，只守 `packages/ui` 的四个通配 export（`components/ui/*`、`components/common/*`、`markdown/*`、`hooks/*`）。core 的**具名** export 既不在其扫描目录内，也不属通配展开，**不可能改变其结论**。

→ **design.md:163 的退路（退为 `vi.importActual` 取值或内联常量）无需启用**，新增 exports 被三项检查接受。

## 9. core 全量回归

`pnpm --filter @multica/core test` → `full/core-vitest.txt`：

```
Test Files  180 passed (180)
     Tests  2552 passed (2552)
  Duration  23.67s
```

**exit 0**。core 新增一条 exports 未影响任何既有测试。

## 10. views 全量 A/B —— U4 上报点

### 10.1 三组实测

| 运行 | 命令 | Test Files | Tests | Duration | 证据 |
|---|---|---|---|---|---|
| **A：HEAD**（两个 S12 文件均还原） | `pnpm --filter @multica/views test` | **4 failed / 502 passed (506)** | **6 failed / 6366 passed (6372)** | 202.91s | `ab/views-vitest-head.txt` |
| **B：带 S12 改动** | 同上 | **5 failed / 501 passed (506)** | **11 failed / 6361 passed (6372)** | 202.31s | `full/views-vitest.txt` |
| **C：B 的 5 个失败文件单独成组** | `vitest run` 指定这 5 个文件 | **0 failed / 5 passed (5)** | **0 failed / 146 passed (146)** | 28.41s | `full/five-files-with-change.txt` |

**两次全量执行总数完全相同（6372）** → S12 未增删任何测试。

还原方式：从 `ab/mine/` 保存的 **CRLF 副本**覆盖回去（**不用 `git checkout`**，因为 `git show HEAD:` 输出 LF 而工作区是 CRLF，git 会告警「LF will be replaced by CRLF」），跑完 A 后再覆盖回改后版本，`sha256sum -c ab/mine-sha256.txt` **两文件均 OK**。

### 10.2 逐名对账（`full/reconcile.mjs`，可重跑，exit 0）

结果见 `full/regression-reconcile.txt`：

- **两次都失败（4）**：create-issue `removes only the rejected unavailable property from the ordinary draft before a manual retry`；search-command `offers every workspace nav page, not a hand-maintained subset`；search-command `does not surface a page on an incidental substring of a hidden keyword`；mcp-tab `adds a server to the library`
- **仅 HEAD 失败（2，带改动反而通过）**：create-issue `shows duplicate-issue toast with a working view-existing link`；chat-window-messages `follows immediately on open, stops during exit, then reads new data on reopen`
- **仅带改动失败（7）**：create-issue `preserves edits made while the unavailable-property error is pending`、`does not remove a property from a reopened draft after a late rejection`；create-project ×4（`attaches a repository with the checkout ref typed beside it`、`omits the ref key for a repository left on its default branch`、`refuses to create while any selected repo's branch is rejected`、`refuses on keyboard submit too, not just the disabled button`）；mcp-server-dialog `removes one argument and environment row while preserving their siblings`

**受害者集合在两次运行之间移动**（2 进 7 出），而执行总数不变 → **不是一组固定坏断言**。

### 10.3 失败原因定性

以 **`Error: Test timed out in 5000ms`** 为主（11 条中 **8** 条）。其余：

- **2 条 `TypeError: rejectCreate is not a function`** —— **同一次停顿的下游后果，不是独立缺陷**。读码核实：`packages/views/modals/create-issue.test.tsx:1097` 与 `:1125` 都是 `let rejectCreate!: (error: Error) => void;`，**只在 `mockCreateIssue.mockImplementationOnce(() => new Promise((_, reject) => { rejectCreate = reject; }))` 的 promise executor 内赋值**。组件在负载下未走到 create 调用时，它保持 `undefined`，随后 `rejectCreate(new ApiError(...))` 抛 TypeError。
- 1 条 `TestingLibraryElementError`（找不到 `Settings` SPAN），两次运行同名同因。
- 2 条 `AssertionError`（仅 HEAD 出现）。

### 10.4 结论与 U4 处置

**这是 HEAD 上已存在的 Windows 506 文件并行负载 flake，非 S12 引入、亦非 typecheck 修复新暴露**（还原两文件后仍红 6 条），且**每个失败文件在脱离并行负载后全绿**（C 组 146/146）。

**已按 U4「先报告再裁定范围」向用户上报**，并依「范围外遗留项上报待定」**不扩大范围**：未改任何 views 生产代码或断言、未调 `testTimeout`/retry/并行度、未加任何 skip 或排除。登记 **ADJ-020（未决）**。

**未确立的部分如实写明**：
- **两次运行不足以测量 flake 率**，不能声称其频率未变；
- **未在 ubuntu-latest 跑过 views 全量**，不能声称 CI 不受影响（真实 CI 属 TC-CBE-005，须推送另行授权）。

**风险在 S13 接线后**：若同一负载敏感在 CI 复现，`ci-evidence.mjs` 会如实判红，届时按新发现处理，**不得预先放宽门禁或加 retry 掩盖**。

## 11. 对账脚本的硬失败与两处解析坑（均已修正，未采信错误输出）

`full/reconcile.mjs` 在下列任一情况**硬失败（exit 1）**，不静默降级为空数据：找不到某条 FAIL 的原因、FAIL 行数与汇总不符、两次执行总数不同、五文件组未全绿、汇总行无法解析。

首轮两次失败均被拦下：

1. **`grep -E "^ FAIL "` 对这两份捕获返回 No matches found** —— vitest 的 FAIL 行前有 **ANSI 转义前缀**（`\x1b[41m\x1b[1m FAIL \x1b[22m\x1b[49m`）。脚本先剥 ANSI 再匹配。（同一个 grep 在别的捕获上曾成功，差别就在是否带色。）
2. **汇总行定位须锚定行首** —— `⎯⎯⎯ Failed Tests 6 ⎯⎯⎯` 横幅也含 `" Tests "`，用 `includes` 会先命中它。改为 `^\s*<key>\s`。
3. **全绿运行的汇总没有 `N failed |` 段** —— C 组是 `Test Files  5 passed (5)`，正则须把 failed 段设为可选。

**未产出任何被采信的假对账结果**（与 S11 那次「added=171」假结果不同，本轮两次都在脚本内硬失败，未写入结论）。

## 12. 新增测试数 = 0 的如实偏离（ADJ-019）

长程强制约束 #3「每个切片必须有新增测试 — 新增测试数必须 > 0」与 B3.4 第 3 项「本切片新增测试必须 > 0 且全部通过」，**本切片未满足**。`.stdd.yaml` 的 `slices_completed['12'].new_tests` 如实记 **0**，不伪造。

**理由**：
- TC-CCF-002 在**锁定证据计划**里是 `kind: command`，断言对象是 **tsc 的退出码与错误码计数**，不是某个测试函数；SC-CCF-002 的三条 then 已分别由命令输出、vitest 输出与 diff 满足。
- **回归守卫已由 `tsc --noEmit` 本身承担**：任何 views 文件再写相对 `../../core` 导入都会立刻让 typecheck 红（本切片 RED 的 60 条正是这样产生的）。另造一个「禁止相对 core 导入」的测试与它**重复**。
- 为凑足 >0 而新增冗余测试，会把长程约束的**形式**置于证据**实质**之上，故不造。

**不触发降级**：约束 #5 的条件是「**连续 3 切片**无新增测试」；S11 新增 15、S13 计划新增。

**teeth 由四项替代证据提供**：① RED 60×TS6059 → GREEN exit 0 / 0 错误码；② 0 条 `expect(` 改动 + 两条标题不变；③ HEAD 版本独立跑 2/2（运行时等价）；④ views 全量 A/B 逐名对账。

**B3.4 三项如实分记**：① TC 覆盖 **1/1**；② 产出物核对**通过**；③ **新增测试 > 0 未满足** → **不报「三项全过」**。本偏离不改任何接口或行为语义，按 B4 小偏离记录后继续执行，并在 **Gate 3 呈报请用户知悉**。

## 13. 运行边界与安全约束（逐条核对）

| 约束 | 本切片实际 |
|---|---|
| 本地数据库验证只用 runner 自建一次性 podman 实例 | **未运行任何数据库、未创建任何 podman 实例**（本切片是纯前端 typecheck/vitest） |
| 不连 localhost:5432 旧库、不操作旧 `multica-postgres` 容器 | **未连接、未操作** |
| 运行前后核对容器清单 | 本切片未启动任何容器，清单无变化 |
| 不放宽 nonce 门禁 | **未触碰**任何 nonce 相关代码或配置 |
| 不读取、打印 PAT 或其他凭据 | **未读取、未打印**；本切片不涉及任何凭据 |
| 记录仓他人未提交改动不清理、不混入 | **未清理、未混入**；只写本 change 目录下的文件 |
| multica main = origin/main = `903a46c5ae9f`，工作区干净 | 操作前后均核实 **HEAD = origin/main = `903a46c5ae9f`**，工作区只含本 change 的文件 |
| tools 仓 HEAD `e52b8081f159`，本地领先 1 且有他人未提交改动 | **本切片未触碰 tools 仓** |
| 上游挂钩、英文注释、CUSTOM.md 登记、真实 STDD change ID | 两个文件均为**上游文件**：`package.json` 是 **JSON，不能携带注释**（已核实全仓 package.json 零 AIFIRST 标记），故以 **CUSTOM.md #329** 登记；测试改动为**纯导入改写、无新增逻辑**，新增的 2 行注释为**英文**，未加 AIFIRST 挂钩（无新逻辑可挂）。追溯用真实 change ID，**未臆造 CR 编号** |
| 提交、推送、部署不从 Gate 确认推导授权 | **未提交、未推送、未部署** |

## 14. 行尾与还原校验

| 文件 | 行尾 | 校验 |
|---|---|---|
| `packages/core/package.json` | **CRLF**（与上游一致） | sha256 `d6f127211fc55953…` |
| `packages/views/auth/use-logout.test.ts` | **CRLF**（与上游一致） | sha256 `e9e530947a90df18…` |
| `CUSTOM.md` | **CRLF**：crlf=1096 / 裸 LF=0 / 1097 行 | #327 **4987 字符**、#328 **3304 字符**逐字节未动 |
| 本目录脚本与文本 | **LF**：`reconcile.mjs` 109 行 / `regression-reconcile.txt` 63 行 | crlf=0 |

A/B 还原一律用 `ab/mine/` 的 **CRLF 副本**，`sha256sum -c` **两文件均 OK**。

## 15. 记账

- **`CUSTOM.md` #329**（2524 字符，7 竖线其中 1 个为转义 `\|`，5 单元格）；M31 头改「**13 行：#317–#329**」；汇总行改 `#317–#329 | 13 |`（6 竖线）并追加 `packages/core/package.json`、`packages/views/auth/use-logout.test.ts`。`git diff -U0` 三个 hunk 证实本切片**纯追加**（唯一删除行是更早切片改的 #87）。
- **四数基线表零影响（实测）**：两文件 `AIFIRST|CR-2026-[0-9]{3}` 匹配数 **HEAD 与工作区均为 0**；`packages/**/*.ts` 在《核对命令》口径内、`package.json` 不在 → 文件数与命中行两数均不变。**ADJ-018 的既有台账欠债不变**（表末行仍停在 2026-11-10 #312）。
- `tasks.md` **12.1–12.5** 全部 `[x]`（12.5 为新增的记账与 B3.4 条目）。
- `phase-context.md` 新增 **Slice 12** 节。
- `.stdd.yaml` `slices_completed['12'] = {new_tests: 0, status: done, tc_coverage: 1/1, verified_at: '2026-11-13T01:32:59'}`；YAML 解析通过，12 个切片齐全，`build.status: in_progress`，`long_range.mode: full_auto`，`spec.confirmed_at: '2026-11-12T23:54:09'`。
- `pending-adjustments.yaml` 新增 **ADJ-019 / ADJ-020**，`meta.updated` 改 `2026-11-13T01:32:59+08:00`；YAML 解析通过，**20 条无重号**，两条新条目键集完整。

## 16. 未验证 / 未完成（不得报通过）

1. **未在 ubuntu-latest 跑过 views typecheck / vitest** —— 真实 CI 属 **TC-CBE-005**，须推送另行授权。
2. **views 全量负载 flake 未修**（ADJ-020 未决，范围外）；**flake 率未测量**（两次运行不足）。
3. **`make test` 未执行**（U5 排除）。
4. **ADJ-005（major）仍未决** —— S13 设 `MULTICA_CONTROLLED_SHELL_RULES` 前须用户裁定。
5. **ADJ-018** 四数基线表台账欠债待裁定。
6. **ADJ-019** 需用户在 Gate 3 知悉（新增测试数 0 的偏离）。
7. **`TestChannelIsolation*` 未在 WSL 实跑**（TC-TOR-004）。
8. **SC-CCF-003 未闭合**（管理员按最小权限更新 PAT，外部依赖；本 change 不读取/创建/轮换凭据）。
9. **Gate 3 未推进** —— 须另经用户明确确认，**不得自跑 approve**。

## 17. 证据树

```
validation/s12-views-typecheck/
├── README.md                        本文件
├── red/
│   ├── typecheck-before.txt         60 × TS6059（238980 字节）
│   ├── use-logout-before.txt        HEAD 版本临时文件 2/2
│   ├── knip-before.txt              exit 1（既有发现）
│   └── ui-exports-before.txt        exit 0，64 files clean
├── green/
│   ├── typecheck-after.txt          exit 0，0 条 error TS（340 字节）
│   ├── use-logout-after.txt         2/2
│   ├── use-logout-diff.txt          完整 diff（0 条 expect 改动）
│   ├── knip-after.txt               与 before 逐字节相同
│   ├── knip-diff.txt                0 字节 / 0 行
│   ├── ui-exports-after.txt         exit 0，与 before 相同
│   ├── lint-core.txt                exit 0，0 错误
│   └── lint-views.txt               exit 0，0 错误
├── full/
│   ├── views-vitest.txt             B：11 failed / 6361 passed (6372)
│   ├── core-vitest.txt              2552/2552 (180 files) exit 0
│   ├── five-files-with-change.txt   C：146/146 exit 0
│   ├── reconcile.mjs                逐名对账脚本（硬失败，exit 0/1）
│   └── regression-reconcile.txt     4 共有 / 2 仅 HEAD / 7 仅带改动
├── final/
│   ├── typecheck-final.txt          按最终字节复跑：exit 0，0 条 error TS
│   └── use-logout-final.txt         按最终字节复跑：exit 0，2/2
└── ab/
    ├── mine/
    │   ├── core-package.json        改后 CRLF 副本
    │   └── use-logout.test.ts       改后 CRLF 副本
    ├── mine-sha256.txt              两文件 sha256（还原后 -c 均 OK）
    └── views-vitest-head.txt        A：6 failed / 6366 passed (6372)
```

## 18. 复现命令

在 `C:\Users\GOBAO\Downloads\AI\multica` 下：

```bash
pnpm --filter @multica/views typecheck          # 期望 exit 0，0 条 error TS
pnpm --filter @multica/views exec vitest run auth/use-logout.test.ts   # 期望 2/2
pnpm --filter @multica/core test                # 期望 2552/2552，exit 0
pnpm --filter @multica/core lint                # 期望 exit 0
pnpm --filter @multica/views lint               # 期望 exit 0
pnpm knip                                       # 期望 exit 1（既有发现），输出与 red/knip-before.txt 相同
pnpm check:ui-exports                           # 期望 exit 0
pnpm --filter @multica/views test               # 全量；Windows 下预期命中 ADJ-020 的负载 flake
```

对账（在本证据目录下）：

```bash
node full/reconcile.mjs      # 期望 exit 0，输出与 full/regression-reconcile.txt 相同
```

A/B 还原（**不要用 `git checkout`**，会把 CRLF 变 LF）：

```bash
cp ab/mine/core-package.json  <multica>/packages/core/package.json
cp ab/mine/use-logout.test.ts <multica>/packages/views/auth/use-logout.test.ts
sha256sum -c ab/mine-sha256.txt    # 期望两行 OK
```