---
spec-id: ai-first-platform
version: "0.42"
id: CR-2026-069-TASK-10
type: TASK
cr-ref: CR-2026-069
plan-ref: "change-requests/CR-2026-069/plan.md"
sdd-ref: "change-requests/CR-2026-069/sdd.md"
target-version: 0.42
title: "冒烟与启用顺序取证 + after 复测能力（14 天窗口与 insufficient-sample 判定）+ AC-9 抽检记录"
slug: smoke-enable-order-evidence
status: pending
estimate: 12h
depends-on: [CR-2026-069-TASK-01, CR-2026-069-TASK-09]
created: 2026-09-17T17:34:00+08:00
---

# CR-2026-069-TASK-10 冒烟与启用顺序取证（G10，AC-14 / AC-20 / AC-9 / AC-18）

## 1. 任务描述

**目标**：把 AC-14（每个已启用 Runtime 至少一次真实冒烟，覆盖拒绝 / 裁剪 / 逃生 / 损坏降级四类行为）、AC-20（启用顺序前置链）、AC-9（历史回放与合法调用抽检）、FR-8 第 5 项（`insufficient-sample` 与 14 天窗口判定为可测纯函数）四件事落到可核对的交付证据上，并明确「部署后那一次真实 `after` 执行」由 owner 在部署窗口执行、**不回收为本 CR 的门禁或状态**。

**背景（完成边界的硬约束）**：`dep-1` FR-8 第 1/5 项把 FR-8 的执行次数钉为「改造前一次 + 部署后（14 天窗口）一次」。若把「部署后的真实 `after` 执行完成」写成本 TASK 的完成前置，则该 TASK 只能在 merge 与部署之后才可能 `done`，而 `crctl task done` 仅允许 `status=developing` ⇒ `deliveryIndexComplete` 归档门禁永久不可达（正是 CR-2026-057 FR-10 要阻断的形态）。因此本 TASK 的完成边界限定为 deployment 前可登记的事件（plan §2.1 的 5 项）。

**输入条件**：TASK-01（FR-8 脚本与基线）与 TASK-09（claude 的 Managed 挂载）已完成；TASK-03~TASK-07 的 Adapter 与安装说明已就位；owner 的部署窗口可用（宿主级/项目级 Runtime 配置面显式安装一次）。

**范围边界（零越界）**：新增 KB `change-requests/CR-2026-069/evidence/ac14-smoke.md`；必要时补 `evidence/ac10-selection.json`（`verify-selection` 输出副本）与 `evidence/ac9-sampling.md`（TASK-01 已产出，本 TASK 复核与补充判定）。**不改**任何代码文件、不改 `sdd.md` / `prd.md`、不新增 Pipeline 节点 / 状态 / 门禁 / 账本字段 / 仪表盘 / sidecar。

## 2. 涉及文件 / 模块

| 文件 | 动作 | SDD 落点 |
|---|---|---|
| `change-requests/CR-2026-069/evidence/ac14-smoke.md` | 新增（五 Runtime 的真实冒烟记录 + 每个 Runtime 一行 `check-install.mjs` 读数；未启用/前提缺失的 Runtime 按 `ENVIRONMENT_MISMATCH` 显式登记所需建立动作） | §6.2 AC-14 可达性、`fix` S6 |
| `change-requests/CR-2026-069/evidence/ac10-selection.json` | 复核（TASK-08 的 `verify-selection` 输出副本；本 TASK 只取证不改写） | §3.6、AC-10 |
| `change-requests/CR-2026-069/evidence/ac9-sampling.md` | 复核并补判定（抽检清单 + 逐条判定 + 零误伤结论） | §6.2 AC-9 |
| KB 的 `after` 复测执行入口说明（落 `ac14-smoke.md` 末段或同目录附录） | 新增（谁在部署窗口执行、产物落哪、失败如何处置） | §1.4.4、FR-8 第 5 项 |

## 3. 实现要点

1. **冒烟矩阵（逐 Runtime 四类行为）**：对已在 `capabilities.json#enableOrder` 中**已启用**的每个 Runtime，记录：拒绝（无界搜索/递归列举/全文读取被拒绝或收窄）、裁剪（超阈值结果带 `action=truncate complete=false` trailer）、逃生（首行逃生阀得到完整结果）、损坏降级（移走/损坏 `policy.json` 或 bundle ⇒ 原调用继续、结果不改、`OUTPUT_GUARD_UNAVAILABLE runtime=<r> reason=<四值>`）；每类给出可复现的调用与观测结果。
2. **逐 Runtime 一行 `check-install` 读数**：`output-guard runtime=<rt> coverage=<full|partial|unavailable> policy=v1` 原样粘入证据文件（这是 §5.0 的 readiness 证据，也是 plan `cmd-09` 的运行时对应面）。
3. **挂载面逐 provider 可区分（AC-19④）**：证据必须写明每个 Runtime 的安装面与其管理归属——claude：daemon 自动写入 `{workDir}/.claude/settings.json`（TASK-09）；codebuddy / qoder：项目级或用户级配置文件**已安装且不被 daemon 触碰**；pi / codex：宿主级配置面。`check-install` 读数 + 四类行为观测共同判定「手工安装是否真的生效」，**不由部署过程自证**。
4. **启用前置链（AC-20①）**：逐 Runtime 记录「该 Runtime conformance 通过 + 真实冒烟通过 + 降级验证通过」三条证据入口；前一项未过则后一项**不得启用**（顺序即 `capabilities.enableOrder`）。不新增 CR 状态或 Pipeline 节点（AC-20②）；不建长期 shadow mode（AC-20③，误伤检查由历史回放承担）。
5. **前提不可建立时的处置（R-12）**：某 Runtime 的宿主/项目配置面无法安装、或 Multica 每任务 env 不可用时，**按既有 `ENVIRONMENT_MISMATCH` 标签中止并写清「所需建立动作」**，并把该 Runtime 记为**未启用**（顺序停在其前一项）；**不得**用"宿主级单进程冒烟"冒充 Multica 真实任务冒烟，也不得静默记 N/A 或跳过。
6. **AC-9 抽检复核**：确认 `baseline` 含可复现筛选规则与实际样本数；离线回放完成；抽检清单与逐条判定齐备且结论为「合法调用零误伤」；抽检以"需要完整证据的真实调用"为样本来源，不伪造样本。
7. **`after` 复测能力交接（FR-8 第 5 项）**：确认 `cr-cost.mjs after --window 14d` 与 `insufficient-sample` 终态已由 TASK-01 的实现与测试覆盖；在证据文件内写明 owner 在部署窗口执行的方式（哪一个命令、产物落哪一个 `--out` 路径与 KB `evidence/` 副本、样本不足时的终态语义），并**显式声明**该次执行的结论不回收为本 CR 的门禁或状态（plan §2.1 / R-14）。
8. **不改代码**：本 TASK 若发现实现缺陷，**不得**就地修改交付代码或证据以掩盖——按 `implement-code` 的回修口径处理（重开对应 TASK 或走既有回修路径）。

## 4. 验收条件

1. `change-requests/CR-2026-069/evidence/ac14-smoke.md` 存在（LF 长度 ≥ 500），且对 `pi` / `claude` / `codebuddy` / `qoder` / `codex` 每个 Runtime：含 `runtime=<rt>` 的 `check-install` 读数行，且该 Runtime 段落内四类行为观测齐备（拒绝 / 裁剪 / 逃生 / 降级）；前提缺失者以 `ENVIRONMENT_MISMATCH` + 「所需建立动作」显式登记。
2. 每个**已启用** Runtime 的启用前置三件（conformance / 冒烟 / 降级验证）在证据文件内逐条可指到证据入口；未启用者写明停在哪一项及原因。
3. `evidence/ac10-selection.json` 的 `minimalSet` ≡ `registryKeys` ≡ `verify-selection` 的实测输出，且 `baselineSha256` 与同批提交的 `evidence/fr8-baseline.json` 的 sha256(LF) 相等（由 plan `cmd-08` 机械核对）。
4. `evidence/ac9-sampling.md` 含抽检清单、逐条判定与「合法调用零误伤」结论；`evidence/fr8-baseline.json` 的 `sampleCRs` / `observedAt` / `rule` 齐备。
5. `after` 复测能力：`node --test --test-reporter=dot skills/shared/metrics/test/cr-cost.test.mjs` 覆盖 14 天窗口判定与 `insufficient-sample` 终态（exit 0）；证据文件内写明部署窗口执行入口与「结论不回收为本 CR 门禁」的声明。

## 5. 完成标志

- `evidence/ac14-smoke.md` 落盘并提交；`ac10-selection.json` / `ac9-sampling.md` 复核通过；验收条件 1~5 逐条实测或逐行可核。
- 明确登记「部署后 14 天窗口的真实 `after` 执行」不在本 TASK 完成前置内（引 plan §2.1 与 R-14），并给出其执行入口与产物落点。
- `tasks/_index.yml` 本 TASK 标 `done`。
- **不**包含：任何代码改动、任何状态推进、任何账本编辑、任何共享服务启停、把部署后结论回填为门禁。

## 6. 接口契约

**产出（供人工 `approve-dev-start` / `review-code` / `approve-code` 消费）**

```text
change-requests/CR-2026-069/evidence/ac14-smoke.md
  结构（逐 Runtime 一节，五节）：
    output-guard runtime=<rt> coverage=<full|partial|unavailable> policy=v1     ← check-install 读数原样
    拒绝 / 裁剪 / 逃生 / 损坏降级 四类行为的可复现调用与观测结果
    启用前置三件（conformance 通过 / 真实冒烟通过 / 降级验证通过）的证据入口
    未启用时的 ENVIRONMENT_MISMATCH 段（缺失前提 + 所需建立动作）
  末段：after 复测执行入口（命令 / --out 落点 / insufficient-sample 语义 / 结论不回收声明）
```

**消费（本 TASK 依赖的上游）**

- TASK-01：`cr-cost.mjs` 四子命令、`evidence/fr8-baseline.json`、`evidence/ac9-sampling.md`。
- TASK-02~TASK-07：`capabilities.json#enableOrder` 与各 Adapter 的安装说明、conformance 向量结果。
- TASK-09：claude 的 daemon 单写入点挂载事实（不 clobber 判据与"未完成由安装期检查报告"的语义）。
- `dep-1` FR-8 第 5 项 / FR-1 第 10~12 项：执行次数、三级 scope、启用顺序与回滚粒度。
