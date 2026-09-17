# AC-14 / AC-20 冒烟与启用顺序取证（CR-2026-069 TASK-10）

## 0. 口径与前提（先读本节）

- **AC-14 的真实冒烟要求**：每个已启用 Runtime 至少一次真实会话冒烟，覆盖拒绝 / 裁剪 / 逃生 / 损坏降级四类行为；挂载面逐 provider 可区分，且「手工安装是否真的生效」由安装期检查读数 + 四类行为观测共同判定，**不由部署过程自证**（SDD §1.4.2 / AC-14）。
- **本节点的实际前提**：五个 Runtime 的原生配置面（宿主级 `~/.pi/agent/settings.json#extensions`、`~/.claude/settings.json`、`~/.codebuddy/settings.json`、`~/.lingma/settings.json`、`~/.codex/hooks.json` + `/hooks` 信任）与 Multica 每任务 env **均未在当前环境建立**——按 `dep-1` FR-1 第 10 项，安装动作是**部署动作**，不在 CR 过程中执行。
- **逃生阀措辞的口径边界（回修期补记）**：§1～§5 的「逃生阀合法 ⇒ 跳过 OutputGuard 封顶」在回修前**只被 Pre 面的“无决策”证据支撑**（Post 面当时仍会写回填）；回修后该句由两侧同断言（Pre 面无决策 + Post 面无回填，向量 `dec-05`）支撑，真实会话冒烟部分仍为未执行。
- **宿主级配置面的实测补正（M4 取证期现读，2026-09-17）**：上一句读的是**安装面**（OutputGuard 的 extension / hooks 条目是否建立），**不是**配置文件本身是否存在。本节点现读事实：`~/.pi/agent/settings.json`（2,645 B）、`~/.claude/settings.json`（1,185 B）、`~/.codebuddy/settings.json`（101 B）、`~/.qoder/settings.json`（1,812 B）**四面文件存在但 0 处 OutputGuard 安装痕迹**；`~/.codex/hooks.json` 与设计所钉的 `~/.lingma/settings.json` **两面文件本身不存在**（codex 仅有 `~/.codex/config.toml`，3,719 B）。**结论不受影响**：五面的 OutputGuard 安装一律未建立 ⇒ 五个 Runtime 仍全部记为**未启用**，仍按 `ENVIRONMENT_MISMATCH` + 所需建立动作登记，真实会话冒烟仍待部署窗口执行。另：`qodercli` 实为 `D:\tools\npm-global\qodercli.ps1`（同目录另有 `qodercli.cmd` / `qoder.cmd` / `qoder.ps1`）；本机**不存在** `qoder-cn` 目录（`C:\Users\GOBAO.qoder-cn\…` 与 `C:\Users\GOBAO\.qoder-cn\…` 两种读法均 False，`C:\Users` / `D:\tools` / `%APPDATA%` / `%LOCALAPPDATA%` 下无任何 `qoder-cn` 目录）。
- 因此本文件对每个 Runtime 登记两件事：① 本节点**可执行**的离线等价观测（`output-guard/test/adapters-contract.test.mjs` 以真实子进程、按该 Runtime 原生 payload 驱动同一组 conformance 向量）；② 真实会话冒烟的 `ENVIRONMENT_MISMATCH` 中止段与**所需建立动作**。
- **禁止**把离线观测当作真实会话冒烟：下方每条离线观测均显式标注「离线（adapters-contract）」，启用状态一律记为**未启用**。

## 1. pi

```text
output-guard runtime=pi coverage=full policy=v1
```

- **拒绝**：离线（adapters-contract）——`tool_call` 面命中 `grep` 族且可判定 ⇒ 返回 `{ block: true, reason }`，reason 含可执行替代写法（缩小范围 + 上限）。真实会话冒烟：未执行。
- **裁剪**：离线（adapters-contract）——`tool_result` 面超阈值 ⇒ 返回 `{ content }` 局部 patch，追加 `[output-guard action=truncate complete=false …]` trailer，正文按类收窄且保留可执行取样写法。真实会话冒烟：未执行。
- **逃生**：离线（adapters-contract）——命令首行 `# output-guard: full reason=<一句话>` ⇒ Pre 面无决策（放行原调用），Post 面无回填（本调用结果逐字进入会话，不写 patch、不追加 trailer；向量 `dec-05`，两侧同断言）；四条负向（git 白名单 / 受控路径 / 审批 / 账本写入）逐条断言逃生阀不产生 deny。真实会话冒烟：未执行。
- **降级**：离线（adapters-contract）——`policy` 指向不可解析文件 ⇒ 无决策 + stderr 一行降级码（`OUTPUT_GUARD_UNAVAILABLE` + 该 Runtime 标识 + `reason=POLICY_INVALID`），退出码仍为 0（fail-open，不误伤调用）。真实会话冒烟：未执行。
- **ENVIRONMENT_MISMATCH**：宿主级扩展面未安装（`~/.pi/agent/settings.json#extensions` 未指向 `output-guard/adapters/pi`），且无 Multica 真实任务环境可观测「安装是否真的生效」。
- **所需建立动作**：由 owner 在部署窗口按 `output-guard/adapters/pi/README.md` 把该目录写入宿主级 `extensions[]`；随后在**真实 Multica 任务**内执行四类行为各一次并把读数贴回本文件。
- **启用前置三件**：conformance 通过 = 是（`adapters-contract.test.mjs` 中 pi 全部向量通过）；真实冒烟通过 = 否；降级验证通过 = 是（离线）。⇒ **启用状态：未启用（停在第 2 项）**。

## 2. claude

```text
output-guard runtime=claude coverage=full policy=v1
```

- **拒绝**：离线（adapters-contract）——`PreToolUse` 面 ⇒ `hookSpecificOutput.permissionDecision=deny` + 可执行替代写法。真实会话冒烟：未执行。
- **裁剪**：离线（adapters-contract）——`PostToolUse` 面 ⇒ `hookSpecificOutput.updatedToolOutput` 替换为裁剪后正文 + `complete=false` trailer。真实会话冒烟：未执行。
- **逃生**：离线（adapters-contract）——逃生阀合法 ⇒ Pre 面无决策（不写 `permissionDecision`、不 deny），Post 面无回填（不写 `updatedToolOutput`、正文逐字、无 trailer；向量 `dec-05`）；四条负向逐条断言。真实会话冒烟：未执行。
- **降级**：离线（adapters-contract）——policy 不可解析 ⇒ 无决策 + stderr 一行降级码；launcher 与 daemon 合成分支均为 fail-open。真实会话冒烟：未执行。
- **ENVIRONMENT_MISMATCH**：Managed 面（Multica 每任务 env 内的 `{workDir}/.claude/settings.json`）与 Project/User 面都未建立；本机无 Multica 真实任务。
- **所需建立动作**：owner 部署窗口内 ① 让 daemon 的 `MULTICA_OUTPUT_GUARD_TOOLS_ROOT` 指向 Tools Release 根并触发一次真实任务（TASK-09 的单写入点合成）；② 或在 Project/User 面按 `output-guard/adapters/claude/README.md` 合并模板；随后在真实会话内执行四类行为各一次。
- **启用前置三件**：conformance 通过 = 是；真实冒烟通过 = 否；降级验证通过 = 是（离线）。⇒ **启用状态：未启用（停在第 2 项）**。

## 3. codebuddy

```text
output-guard runtime=codebuddy coverage=full policy=v1
```

- **拒绝**：离线（adapters-contract）——`PreToolUse` ⇒ `permissionDecision=deny` + 替代写法。真实会话冒烟：未执行。
- **裁剪**：离线（adapters-contract）——`PostToolUse` ⇒ `updatedToolOutput` + `complete=false` trailer。真实会话冒烟：未执行。
- **逃生**：离线（adapters-contract）——逃生阀合法 ⇒ Pre 面无决策，Post 面无回填（正文逐字、无 trailer；向量 `dec-05`）；四条负向逐条断言。真实会话冒烟：未执行。
- **降级**：离线（adapters-contract）——policy 不可解析 ⇒ 无决策 + stderr 降级行。真实会话冒烟：未执行。
- **ENVIRONMENT_MISMATCH**：项目级 / 用户级配置面未安装（`<project-root>/.codebuddy/settings.json`、`.codebuddy/settings.local.json`、`~/.codebuddy/settings.json`），且 Windows 下 hook command 经 Git Bash 执行的可达性未在真实会话中实测。
- **所需建立动作**：owner 部署窗口内按 `output-guard/adapters/codebuddy/README.md` 把 hooks 段合并进目标配置（**daemon 不参与**：`dep-15` 对 codebuddy 只写记忆文件与 skills 发现目录），重启到新会话后在真实任务内执行四类行为各一次。
- **启用前置三件**：conformance 通过 = 是；真实冒烟通过 = 否；降级验证通过 = 是（离线）。⇒ **启用状态：未启用（停在第 2 项）**。

## 4. qoder

```text
output-guard runtime=qoder coverage=full policy=v1
```

- **拒绝**：离线（adapters-contract）——`PreToolUse` ⇒ `permissionDecision=deny` + 替代写法。真实会话冒烟：未执行。
- **裁剪**：离线（adapters-contract）——`PostToolUse` ⇒ `updatedToolOutput` + `complete=false` trailer。真实会话冒烟：未执行。
- **逃生**：离线（adapters-contract）——逃生阀合法 ⇒ Pre 面无决策，Post 面无回填（正文逐字、无 trailer；向量 `dec-05`）；四条负向逐条断言。真实会话冒烟：未执行。
- **降级**：离线（adapters-contract）——policy 不可解析 ⇒ 无决策 + stderr 降级行。真实会话冒烟：未执行。
- **ENVIRONMENT_MISMATCH**：三级配置面未安装；且本 Runtime **不产生会话启动记录**（`startRecord=none`），覆盖度只能由结果 trailer 与安装期检查读数派生。
- **所需建立动作**：owner 部署窗口内按 `output-guard/adapters/qoder/README.md` 合并 hooks 段并重启会话；真实会话内执行四类行为各一次。另需人工复核该 README 记录的**配置面路径差异**（已审批设计取 `.lingma/settings.json`；现行厂商文档为 `.qoder/settings.json` 并列出 `SessionStart`）——改判属 scope amendment，不在实施期内自行改写。
- **启用前置三件**：conformance 通过 = 是；真实冒烟通过 = 否；降级验证通过 = 是（离线）。⇒ **启用状态：未启用（停在第 2 项）**。

## 5. codex

```text
output-guard runtime=codex coverage=partial policy=v1
```

- **拒绝**：离线（adapters-contract）——`PreToolUse`（managed）⇒ `permissionDecision=deny` + 替代写法。真实会话冒烟：未执行。
- **裁剪**：离线（adapters-contract）——`PostToolUse` 走 block/feedback 路径（`{ decision: "block", reason: <裁剪后正文 + trailer> }`，非透明替换）。真实会话冒烟：未执行。
- **逃生**：离线（adapters-contract）——逃生阀合法 ⇒ Pre 面无决策，Post 面无回填（正文逐字、无 trailer；向量 `dec-05`）；四条负向逐条断言。真实会话冒烟：未执行。
- **降级**：离线（adapters-contract）——policy 不可解析 ⇒ 无决策 + stderr 降级行。真实会话冒烟：未执行。
- **未覆盖路径**（与 `capabilities.json#runtimes.codex.paths[].uncovered` 一一对应）：`hosted-WebSearch`、`codex-cloud-tasks` —— 不经本地 hook，本适配器**不生效**，不追求全覆盖。
- **ENVIRONMENT_MISMATCH**：`.codex/hooks.json` 未安装，`/hooks` 审查-信任（按哈希）未执行；非托管 hook 未信任即不运行。
- **所需建立动作**：owner 部署窗口内按 `output-guard/adapters/codex/README.md` 安装 hooks.json 模板并完成 `/hooks` 信任（脚本变更后需重新信任）；真实会话内执行四类行为各一次，并至少实测一条 uncovered 路径「不生效」。
- **启用前置三件**：conformance 通过 = 是（partial 向量）；真实冒烟通过 = 否；降级验证通过 = 是（离线）。⇒ **启用状态：未启用（停在第 2 项）**。

## 6. 启用顺序（AC-20）

- 顺序权威：`output-guard/capabilities.json#enableOrder` = `pi → claude → codebuddy → qoder → codex(partial)`。
- 每个 Runtime 的下一项前置 = 「conformance 通过 + 真实冒烟通过 + 降级验证通过」三件齐备；当前**五项都停在第 2 项**（真实冒烟未执行），故顺序面**整体未推进**——不得把任何 Runtime 记为已启用。
- **零治理结构新增**：本 CR 不新增 CR 状态、Pipeline 节点或门禁（AC-20②）；误伤检查由历史回放承担（`evidence/ac9-sampling.md`），**不建长期 shadow mode**（AC-20③）。
- **挂载面逐 provider 可区分**（AC-19④）：claude = daemon 单写入点合成 `{workDir}/.claude/settings.json`（TASK-09，目标文件已存在则不写不合并并告警）；codebuddy / qoder = 项目级或用户级配置文件**已安装且不被 daemon 触碰**（`dep-15` 对该二 Runtime 只写记忆文件与 skills 发现目录）；pi = 宿主级 `extensions[]`；codex = 宿主级 `.codex/hooks.json` + `/hooks` 信任。

## 7. 部署后 `after` 复测执行入口（FR-8 第 5 项）

- **谁执行**：`owners.development`（部署窗口内）。
- **命令**：`node skills/shared/metrics/scripts/cr-cost.mjs after --window 14d --out <产物路径> --baseline <本 CR 提交的 evidence/fr8-baseline.json>`。
- **产物落点**：`--out` 指向 KB `change-requests/CR-2026-069/evidence/` 下的复测 JSON（人读摘要只走 stdout，不写第二份产物）。
- **终态语义**：样本不足 ⇒ `status=insufficient-sample`（**不产出成本结论、不延长本 CR**）；样本充足 ⇒ 按「目标桶 tokens/CR 下降 ≥20% ∧ 三项护栏均不恶化」给出 `target-met` / `no-improvement`，四条判据逐条可见。
- **不回收声明**：该次执行的结论**不回收为本 CR 的门禁、状态或验收条件**（plan §2.1 / R-14）。

---

## 8. 更正记录（M4 取证期，只增不改）

| 日期 | 触发 | 更正内容 | 是否触动已审批对象 |
|---|---|---|---|
| 2026-09-17 | `review-code` 第 1 轮 blocker B-1（Post 面逃生阀无回填缺失）回修 | ① 逃生阀措辞口径：§0 补「回修前该措辞只被 Pre 面无决策证据支撑」的边界，§1～§5 每条逃生条目改为「Pre 面无决策 + Post 面无回填（正文逐字、无 trailer；向量 `dec-05`）」双侧表述；② 本回修的四条 blocker 修复与判据落点：B-1/B-2/B-3 = Post 面调用级回放（`callCommand` / `offset` / 命令族 `kind` 三个**纯追加可选输入**，实例契约由 `output-guard/core.mjs` 的 `ResultInput` JSDoc 承载——SDD §3.2 原话「类型…实施时以 JSDoc 承载」，且不改变该节已宣告字段的名字与语义；与既有的 `kind` 同一类扩展）、B-4 = 安装面 matcher 与声明路径双向一致（ac-09 + multica 同包 `TestOutputGuardClaudeMatcherCoversDeclaredFullPaths`）。**`sdd.md` 本回修零字节改动**（sha256(LF) = 技术评审 `subject-sha256`，受 `cmd-05` 的 KB `zero_diff` 面机械约束；B-1/B-2 的「同步改写 SDD §3.2」取向与本 CR 已批准的该约束不可同时成立 —— 差异已写入 Issue 回修记录，需 owner 裁定才能改走该取向） | **否**。本文件的 `evidence/**` 不在 dev-start 审批 `evidence-digest`（`review-annotations/dev-plan.yml` + `plan.md`）也不在 dev-plan 复合摘要（`plan.md` + `tasks/TASK-*.md`）内；本轮只增不改，未触动已审批对象（`crctl gate --for developing` 与 dev-plan digest 实测见 `test-report.md` 分析段） |

- **回修期的机械判据入口（不新增基础设施）**：B-2 的窗口锚点见 `dec-06`（`offset=500` ⇒ 首行 `500<TAB>file-line-500`、续读 `offset=638 limit=138`），B-3 见 `dec-07`（`cat` ⇒ `kind=read`），B-1 见 `dec-05`（`adapterExpect.patch=false`），B-4 见 `ac-09`；四者均在 `cmd-02` 执行面内。

- **未做的部分（留给 owner 裁定）**：Qoder 安装面改判（`.lingma/settings.json` → `.qoder/settings.json`）属 **scope amendment**，本更正**不含**：设计所钉的 `.lingma/settings.json` + `startRecord=none` 原样保留，代码与 `capabilities.json` 仍按**已审批设计**落，差异留痕在 `output-guard/adapters/qoder/README.md` §1 与本文件 §4。
- **取证口径**：本更正是**只增不改**的口径补正，不改变任何一条机器判据所断言的 token（`cmd-08` 的逐 Runtime 段扫描与 `ENVIRONMENT_MISMATCH`/`所需建立动作` 断言在更正后仍全绿，见 `test-report.md`）。
