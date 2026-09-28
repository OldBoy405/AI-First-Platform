---
id: CR-2026-071-sdd
type: SDD
cr-ref: CR-2026-071
title: CR Agent 委派回执判定统一与需求 PRD 前 checkpoint 恢复 技术设计
target-version: 0.44
status: draft
created: 2026-09-27T15:10:00+08:00
updated: 2026-09-28T13:55:00+08:00
---

# CR-2026-071 技术设计（SDD）

## 1. 架构概览

本 CR 含两个正交工作流，分属两个代码仓，无共享代码依赖，仅在 CR 计划里程碑上协同：

```text
multica 仓（FR-1/FR-2/FR-3：判定规则修复 + 单一合同 + 回归）
  cr-prompts-revised/delegation-contract.md   ← 新增：唯一规范合同源
  cr-prompts-revised/{requirement-writer,dev-agent,
    quality-reviewer-agent,cr-coordinator-agent}.md  ← 内联合同全文，删 enqueued
  cr-prompts-revised/bak/                      ← 审计后修正仍可部署的副本
  cr-prompts-revised/test/delegation-contract.test.mjs ← 新增回归（node --test，零依赖）
  线上四个 Agent instructions                   ← 同源全文同步，ID/绑定不变

tools 仓（FR-4：node-2 后评审前 checkpoint 恢复）
  pipeline-templates/requirement-authoring.pipeline.json ← 恢复节点 ...0003（ref=push-progress）
  pipeline-templates/_index.yml                          ← nodes 5 → 6 + brief 同步
  skills/shared/crctl/scripts/test/pipeline-structure.test.mjs ← 结构断言同步更新
```

模块边界：判定规则只进 multica 仓提示词与合同；Pipeline 编排只动 tools 仓 JSON。
依赖方向：四份提示词与线上指令单向消费合同源；回归脚本只读三方（合同源、提示词/副本、平台枚举源），不写任何账本与状态。
关键流程：修复提示词 → 合同回归全绿 → 同步线上指令并逐个 `agent get` 核验 →
恢复 checkpoint 节点 → 结构测试全绿 → 评审 PASS 发布 → 人工审批（分属各自阶段门禁）。

ARCHITECTURE.md：multica 仓与 tools 仓均已存在，直接引用；本次未起草任何 ARCHITECTURE.md。

术语映射（PRD canonical term → 代码别名）：`queued` → `DispatchQueued`、`coalesced` →
`DispatchCoalesced`、`deferred` → `DispatchDeferred`、`blocked` → `DispatchBlocked`
（见 dep-1）；`target_unavailable` → `ReasonTargetUnavailable`，是 `ReasonCode` 而非 status
（见 dep-2）。同一术语全文单一批判，无语义冲突需澄清，不停顿。

## 2. 数据模型

N/A（本 CR 无既有实现依赖之外的新增实体）。变更对象是提示词文本、单个 JSON 合同源、
Pipeline JSON 节点与测试脚本，不涉及数据库、存储 schema 或持久化字段。

## 3. 接口契约

N/A。本 CR 不新增或修改任何 HTTP API、IPC 或事件接口（收窄基线未触发）：
判定逻辑是提示词自然语言规则 + 离线回归脚本；checkpoint 复用 `push-progress` Skill
既有深原语（`crctl checkpoint`），不新增 crctl 子命令、不改调用签名。
线上指令同步经既有 `multica agent update/get` 通道，无新接口。

## 4. 关键算法与流程

### 4.1 规范判定规则（合同正文，四处内联全文，逐字一致）

```text
只检查本次实际 mention 的 agent/squad 目标各自对应的 trigger_outcomes：
status=queued|coalesced|deferred 视为该目标投递成功；
status=blocked（记录 reason_code）或该目标缺失 outcome 视为 DELEGATION_FAILED。
status 与 reason_code 分属不同字段；target_unavailable 是 reason_code，
不得当作 status；未知 status 不得判为成功。
若评论只 mention 人类成员、无 agent/squad 目标，评论发布成功即无委派失败可报；
若评论发布本身失败，报告发布错误，不得伪称成功。
一个目标的成功不掩盖另一被 mention 目标的失败；不得因误判重复 mention 或上报。
```

落点（逐文件替换现状，现状见 dep-3/dep-4）：

- `requirement-writer.md:43`、`dev-agent.md:39`：把 `enqueued/coalesced/deferred 为成功，
  其余为 DELEGATION_FAILED` 替换为上文全文。
- `quality-reviewer-agent.md:93`（及 PASS/BLOCK 委派段 `:69` 按需对齐措辞，不改路由语义）：
  同上替换；`其余报告 DELEGATION_FAILED` 的"其余"必须按全文展开为 blocked/缺失 outcome/
  未知 status，且 human-only 路径豁免。
- `cr-coordinator-agent.md:50`：把 `enqueued / coalesced / deferred 为成功，
  blocked / target_unavailable / 无触发结果报告为 DELEGATION_FAILED` 替换为全文
  （核心修正：`target_unavailable` 从 status 列移除，归入 reason_code 记录；"无触发结果"
  收窄为"被 mention 的 agent/squad 目标缺失 outcome"，human-only 不算失败）。
- `bak/`：先审计目录用途（dep-5 现状：`bak/cr-coordinator-agent.md:45` 与
  `bak/quality-reviewer-agent.md:67` 含同一漂移；其余 bak 文件无委派子句）。
  仍可作为部署来源的副本按上文同等修正；确认不再部署的副本在该目录留一行排除理由
  （不删文件以保历史可追溯），回归检查只覆盖"需维护"集合。

### 4.2 线上指令同步流程（FR-2）

1. 以合同源全文为唯一输入，经 `multica agent update <id>` 更新四个线上 Agent
   instructions，仅替换委派判定段落，其余职责、绑定、skill 列表原样保留，不更换 ID。
2. 逐个 `multica agent get <id> --output json` 核验成品含规范三元组且无 `enqueued` 成功语义、
   无 `target_unavailable` status 语义；任一不符即失败，不得以"文件已改"代替线上交付。
3. AIFI-35 评审结果与账本只读，不触发其 reviewer（zero_diff 兜底）。

### 4.3 回归检查流程（FR-3）

新增 `multica/cr-prompts-revised/test/delegation-contract.test.mjs`（`node --test`，
零第三方依赖，与两仓测试惯例一致），三组断言：

1. **枚举对齐**：从 `server/internal/handler/admission.go` 解析 `DispatchStatus` 字面量
   （dep-1），断言合同源成功集合 == `{queued,coalesced,deferred}` 且失败集合含 `blocked`；
   平台新增 status 字面量而合同未同步时失败（防再漂移）。
2. **无漂移**：四份提示词 + "需维护" bak 副本逐文件含规范三元组与按目标/缺失 outcome/
   human-only 豁免子句，且不含 `enqueued` 成功语义；任一漂移失败。
3. **场景向量**（AC-1/AC-2，7 例）：`queued` 成功（含 AIFI-35 `status=queued,
   reason_code=queued` 只读重放）、`coalesced` 成功、`deferred` 成功、
   `blocked + reason_code=target_unavailable` 失败、`blocked` + 其他 reason 失败、
   被 mention 目标缺失 outcome 失败、仅 mention 人类成员且评论成功不失败；
   另加未知 status 不成功、评论写入失败不报成功。判定函数实现即合同伪代码化，
   与 §4.1 逐字对应。

### 4.4 checkpoint 节点恢复流程（FR-4）

在 `requirement-authoring.pipeline.json` 的 node-2（`write-requirement-prd`，
`...0002`）之后、`review-requirement`（`...0004`）之前恢复独立节点，
复用被 CR-2026-066 删除的 id `00000000-0000-0000-0011-000000000003`：

```json
{
  "id": "00000000-0000-0000-0011-000000000003",
  "kind": "skill",
  "label": "提交 PRD 草稿（评审前 checkpoint）",
  "ref": "push-progress",
  "prompt": "读取 node-1.md 的 execution_context。调用 push-progress：\n- cr_id: {execution_context.cr_id}\n- message: PRD 草稿评审前发布\n\n消费 batchId 与三仓 confirmed；phase 非 complete 按 Skill 错误语义中止，不进入评审。在 node-3.md 输出 checkpoint 结果并继续传递 execution_context。",
  "onFail": "abort",
  "timeoutMinutes": 10
}
```

语义：`ref=push-progress`（= 调用 `crctl checkpoint` 深原语，PRD 指定口径）；
失败/`changed` 未 complete 不得进入评审；`reviewLoop` 的 repair 仍指回 node-2，
回修后正向流再次经过本节点重新发布再复评；评审 PASS 发布与审批后节点保持
CR-2026-066 既有机制不变。`_index.yml` 同步 `nodes: 5 → 6`（SDD-CLOSE-03 要求见 §10），
`pipeline-structure.test.mjs` 对应断言同步更新（见 §6）。

**授权偏离注（Ray 2026-09-28 在 AIFI-36 评论 `01a0e687-ef04-71fd-899d-086a432847e2`
裁定「包 1」）**：FR-4 实施时文件集为 4 个——第 4 个
`skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs` 仅为机械必需件（其 T05 断言
显式枚举 requirement-authoring 的 `push-progress` 节点集合为空集，恢复 `...0003` 后必然
红，见 dep-7），非新增范围；口径为「已声明 3 文件 + 1 授权件」。

## 5. 技术选型与替代方案

- **合同源位置（SDD-CLOSE-01 结论）**：选 `multica/cr-prompts-revised/delegation-contract.md`。
  备选 `tools/skills/shared/controlled-shell/rules.json` 否决：它是受控 shell 白名单的
  事实源，主题与部署仓均不对（判定规则消费方是 multica 仓提示词与线上 Agent），
  跨仓引用徒增耦合；且 tools 不变量要求 Skill 通用、约束归仓，判定规则是 multica
  平台契约，应住在 multica 仓。
- **引用方式**：四份提示词内联合同全文（非路径引用）。备选"只写路径引用"否决：
  PRD 明确线上 Agent 运行时无法解析本地路径引用，发布/导入必须注入完整规则；
  内联 + 回归"无漂移"断言是满足"同源生成、可核验"的最小机制，不引入模板生成器。
- **回归 runner**：`node --test` 单文件脚本。备选 Go test 否决：被测对象是 Markdown
  提示词语料，无需编译进 server 二进制；备选接入 tools 侧 `lint-prompts` 否决：
  跨仓测试依赖违反"约束归仓"，multica 仓自持回归。
- **checkpoint 节点 ref**：`push-progress` Skill（PRD 指定口径）。备选节点直调
  `crctl checkpoint` 否决：Pipeline 节点统一经 Skill 契约消费深原语，不在 JSON 里
  内联 CLI 调用。

## 6. FR 到技术实现映射

- **FR-1**：§4.1 全文替换四份提示词对应行（dep-3 现状行号）；可观测：回归场景向量 7/7 通过；
  可达性：规则按"被 mention 目标"逐项求值，多目标互不掩盖，human-only 有显式豁免分支。
- **FR-2**：§4.2；`bak/` 审计结论落盘（保留/排除理由）；线上 `agent get` 四份成品核验；
  可达性：更新范围限定判定段落原文替换，不触碰绑定/skill 列表，故 ID 与协作职责不变。
- **FR-3**：§4.1 合同源 + §4.3 回归；可观测：`node --test` 全绿且平台枚举字面量变更时变红；
  可达性：枚举对齐测试直读 admission.go 源字面量（dep-1），不经转述。
- **FR-4**：§4.4 JSON 节点 + `_index.yml` nodes 6 + `pipeline-structure.test.mjs` 断言更新为
  `requirement-authoring` 6 节点、恰 1 个评审前 `push-progress` 节点（含 id `...0003`
  在位）、审批后 `push-progress` 仍 0（dep-6/dep-7 现状基线）+ `checkpoint-tx.test.mjs`
  T05 集合同步（授权偏离件，见 §4.4 授权偏离注）；可达性：`onFail=abort`
  保证未发布不可达评审，repair 回 node-2 后正向必经 checkpoint。

### AC 逐项设计与验收映射

- **AC-1 → FR-1**：设计落点 §4.1 + §4.3 向量前 3 例；可观测：AIFI-35 回执重放判成功，
  零 `DELEGATION_FAILED`、零重复委派；可达性：`queued` 在成功集合字面量内，无前置过滤。
- **AC-2 → FR-1**：设计落点 §4.1 blocked/缺失 outcome/human-only/未知 status 四分支 +
  §4.3 向量后 4 例 + 2 例否定；可观测：失败诊断同时输出 `status` 与 `reason_code`；
  可达性：human-only 豁免先于失败判定求值，不会被"无 outcome"分支误吞。
- **AC-3 → FR-2/FR-3**：设计落点 §4.2 + bak 审计；可观测：四份 `agent get` 成品与合同逐字一致，
  交付记录列 P0/P1/测试/核验/边界；可达性：核验读线上成品原文，不以源文件已改代替。
- **AC-4 → FR-3**：设计落点 §4.3 三组断言；可观测：任一源/发布物漂移测试变红；
  可达性：无漂移断言覆盖全部四份 + 需维护 bak 集合，无死角文件。
- **AC-5 → FR-4**：设计落点 §4.4；可观测：Pipeline 顺序 node-2 → `...0003` → review，
  结构测试通过；可达性：BLOCK 回修路由 repair→node-2，正向必经 checkpoint 再复评。
- **AC-6 → FR-1～FR-4**：设计落点批准范围 zero_diff（§9）；可观测：AIFI-35 无新 reviewer run、
  其 CR 状态/账本零 diff；FR-4 变更仅影响新 CR 未来流程；可达性：实现文件清单不含
  AIFI-35 路径与审批后 checkpoint 节点。

### 既有实现依赖与事实

```text
dep-1
  repo: multica
  relative path: server/internal/handler/admission.go
  stable symbol/对象: DispatchQueued/DispatchCoalesced/DispatchDeferred/DispatchBlocked status 字面量（L32-41）
  commit SHA: a0d0d369b9fbbe545876830350279c1d6e5b85ad
  依赖结论: 平台公开 status 枚举确为 queued|coalesced|deferred|blocked，无 enqueued
dep-2
  repo: multica
  relative path: server/internal/handler/admission.go
  stable symbol/对象: ReasonTargetUnavailable 系 DispatchReasonCode（L50-64，L118 mapped as reason）
  commit SHA: a0d0d369b9fbbe545876830350279c1d6e5b85ad
  依赖结论: target_unavailable 是 reason_code，不得当作 status
dep-3
  repo: multica
  relative path: cr-prompts-revised/cr-coordinator-agent.md:50, dev-agent.md:39, quality-reviewer-agent.md:93, requirement-writer.md:43
  stable symbol/对象: 四份提示词委派判定子句（含 enqueued 成功语义与 target_unavailable status 语义）
  commit SHA: a0d0d369b9fbbe545876830350279c1d6e5b85ad
  依赖结论: 现状确与 dep-1/dep-2 冲突，是 §4.1 替换的精确靶点
dep-4
  repo: multica
  relative path: cr-prompts-revised/bak/cr-coordinator-agent.md:45, cr-prompts-revised/bak/quality-reviewer-agent.md:67
  stable symbol/对象: bak 副本委派判定子句（同类漂移）
  commit SHA: a0d0d369b9fbbe545876830350279c1d6e5b85ad
  依赖结论: bak 至少两份为可部署副本候选，须审计定保留/排除（其余 bak 文件无委派子句）
dep-5
  repo: tools
  relative path: pipeline-templates/requirement-authoring.pipeline.json（nodes: node-2 …0002 直连 review …0004，无 …0003）
  stable symbol/对象: requirement-authoring 节点序列与 reviewLoop.repairNodeId=…0002
  commit SHA: c0e66ccbb84af6b730329a7db3fb3ac78e7e3e04
  依赖结论: node-2 后评审前确无 checkpoint 节点，是 §4.4 恢复的精确缺口
dep-6
  repo: tools
  relative path: pipeline-templates/_index.yml（requirement-authoring-v1 nodes: 5，CR-2026-066 注记）
  stable symbol/对象: _index.yml 节点数台账
  commit SHA: c0e66ccbb84af6b730329a7db3fb3ac78e7e3e04
  依赖结论: 恢复后须同步为 6，否则结构测试（dep-7）按现状 5 断言失败
dep-7
  repo: tools
  relative path: skills/shared/crctl/scripts/test/pipeline-structure.test.mjs（AC-1: 5/4/12 节点数、push-progress 节点数 0、已删 id 含 …0003）
  stable symbol/对象: Pipeline 结构回归断言
  commit SHA: c0e66ccbb84af6b730329a7db3fb3ac78e7e3e04
  依赖结论: FR-4 实施必须同步更新该测试的目标断言，否则实施即红
  补充（2026-09-28 授权偏离，AIFI-36 评论 01a0e687-ef04-71fd-899d-086a432847e2）: 同目录
    checkpoint-tx.test.mjs 的 T05 亦枚举 requirement-authoring 的 push-progress 节点集合为
    空集，故 FR-4 的最小正确文件集 = pipeline-structure.test.mjs + checkpoint-tx.test.mjs；
    实际落盘 4 文件（见 §4.4 授权偏离注、§6 FR-4）
```

线上指令现状另经本轮 `multica agent get` 取证（dev-agent `ff6fcbb6…` 与
cr-coordinator-agent `87ca2271…` instructions 均含 `enqueued…为成功` 语义，与 dep-1
冲突），实施期以同命令复核成品为准；其余两 Agent（requirement-writer
`6317495b…`、quality-reviewer `2ed1a9de…`）的线上行文以实施期 `agent get` 为准，
源文件行文见 dep-3。

待核实依赖：无（正文全部事实已绑定 dep-1～dep-7 或本轮 CLI 取证）。

## 7. 安全与性能考量

- 边界条件：评论发布失败 vs 投递失败二分（§4.1 末两句），防止把 infra 故障伪装成成功；
  未知 status 默认失败侧（fail-closed），平台未来新增状态不会被静默判成功。
- 性能目标：回归脚本离线、秒级、无网络；`agent get` 核验 4 次只读调用。
- 安全控制点：提示词与合同不泄露不可见目标信息；失败诊断仅记录当前可见目标的
  status/reason_code；线上更新不改 permission_mode、owner 与绑定；multica 仓英文代码注释
  规则（其 CLAUDE.md）约束回归脚本注释用英文，本 SDD/提示词中文不变。
- 不新增状态、账本字段、审批旁路；状态机口径（15 具名 + `(new)`，28 声明/展开 50 条）
  与 tools 不变量 1/2/7 保持 intact（对照 tools ARCHITECTURE.md §4/§5/§6 判定通过）。

## 8. Prompt 采纳影响

N/A——本 CR 不触及 `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支，
不增改 `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny`
（无新增 crctl 子命令、无 guard 变更），故无 skill 需采纳新调用。本节省略。

## 9. 批准范围

- `scope_in`：FR-1 四份提示词判定子句修正；FR-2 bak 审计修正 + 四个线上 Agent
  instructions 同源同步（含 `agent get` 核验）；FR-3 合同源 + 回归脚本；
  FR-4 `...0003` 节点恢复 + `_index.yml` + 结构测试同步（含授权偏离件
  `checkpoint-tx.test.mjs`，见 §4.4 授权偏离注）。仅此而已。
- `scope_out`：不改平台 admission 返回值；不碰 AIFI-35/CR-2026-001 状态、账本与评审；
  不动其他 Pipeline、其他被 CR-2026-066 删除的 checkpoint（含全部审批后 checkpoint）；
  不修 reviewer `crctl git` 写禁令与 Skill 的提交顺序矛盾（待 Ray 拍板并入或另开，
  见 follow_up）；不代签任何人工审批。
- `zero_diff`：`admission.go` 枚举与 reason 码定义；CR 状态机与门禁声明；
  四个线上 Agent 的 ID、绑定、非判定职责；AIFI-35 全部文件；
  `requirement-authoring` 审批后节点与 review PASS 发布语义。
- `follow_up`：reviewer 提交禁令二选一（窄放行 `files[]` vs 提交移出 reviewer）待决策；
  平台未来新增 status 时合同回归变红后的跟进 CR；`bak/` 排除副本若日后重新启用须先补回归覆盖。
  四字段自洽：scope_in 无一触碰 zero_diff 对象；scope_out 未隐藏任何交付必需修改；
  follow_up 均为非 AC 必要条件。

## 10. SDD-CLOSE 关闭项（PRD 延后事项）

- **SDD-CLOSE-01**：合同源位置与生成方式 → 结论：`multica/cr-prompts-revised/`
  新建 `delegation-contract.md` 为唯一规范源；四份提示词与线上指令内联全文
  （同源注入 + 回归核验），不使用运行时路径引用。已关闭（§4.1/§5）。
- **SDD-CLOSE-02**：回归检查落点与 runner → 结论：multica 仓
  `cr-prompts-revised/test/delegation-contract.test.mjs`，`node --test` 零依赖，
  三组断言覆盖 AC-1/AC-2/枚举对齐/无漂移。已关闭（§4.3）。
- **SDD-CLOSE-03**：checkpoint 节点 ref 与 id → 结论：`ref=push-progress`
 （PRD 口径），复用被删 id `...0003`，`_index.yml` 同步 6。已关闭（§4.4）。

---

术语预检（首次推进前已完成）：风险术语均有 dep 绑定且单一批判，无待澄清项，可推进评审。

---

# 修订记录

| 版本 | 时间 | 作者 | 说明 |
|---|---|---|---|
| 0.1 | 2026-09-27 | dev-agent | 初稿：§4.1 合同正文、§4.2 线上同步、§4.3 回归、§4.4 checkpoint 恢复；dep-1～dep-7 与 AC-1～AC-6 映射。 |
| 0.2 | 2026-09-28 | dev-agent | 授权偏离订正（Ray 在 AIFI-36 评论 `01a0e687-ef04-71fd-899d-086a432847e2` 裁定「包 1」）：FR-4 文件集订正为「已声明 3 文件 + 1 授权件 `checkpoint-tx.test.mjs`」——§4.4 增授权偏离注，dep-7 补记最小正确文件集，§6 FR-4 与 §9 `scope_in` 同步。结论不受影响：节点恢复与结构测试语义未变，仅补齐 FR-4 的机械必需件。 |
