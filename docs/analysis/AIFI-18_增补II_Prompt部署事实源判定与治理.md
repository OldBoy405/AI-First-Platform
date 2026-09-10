《AIFI-18 原位修订清单》增补 II（**第 2 版，按最新决定修订**）。

**本版依据的决定**：
1. `cr-coordinator-agent` 是 **multica 平台专用** Agent，tools 包本身不需要。
2. 其余 Agent prompt **以 multica 中的为事实源**，按前述方案修订冲突，**并同步到 tools 工具包**。
3. `agent-skill-matrix.yml` **也以 multica 为准**。

相对第 1 版的修订位置：§三（7.1 改写）、§四（由「不同步」改为「同步」，新增 7.2）、§五（R3 / R4 关闭，R1 降级）、§六（总表 13→14）、§七（批次改为跨仓三段 + 下游校验）。§一 / §二 事实与冲突陈述不变。

---

## 一、Prompt 现状：三方分叉（本轮逐文件实读，未变）

| 处 | 内容 | CI 守卫 | 与运行时行为是否吻合 |
|---|---|---|---|
| **A. `tools/agents/`** | 9 个 agent md + `_index.yml`（`product-planning` / `requirement-writer` / `dev` / `spec` / `delivery` / `quality-reviewer` / `knowledge` / `competitive-analyst` / `customer-support`）。**无 `cr-coordinator-agent`** | ✅ `check-agents-contract.mjs`（root=`tools/`）、`lint-prompts.mjs`、`contract-scan.test.mjs`、`crctl-ci.yml` 监听 `agents/**` | ❌ 不吻合 |
| **B. `multica/cr-prompts-revised/`** | `agent-skill-matrix.yml` + 5 个 CR 小组 agent md（`cr-coordinator` / `requirement-writer` / `dev` / `quality-reviewer` / `delivery`） | ❌ 零静态守卫 | ✅ **吻合** |
| **C. Multica DB（运行时）** | 平台 agent 实体（本次执行者：coordinator `87ca2271`、dev `ff6fcbb6`、reviewer `2ed1a9de`、requirement-writer `6317495b`） | ❌ 无漂移检测（`aifirst/agent-import.mjs` 为一次性导入工具） | — 即运行时本体 |

### B 吻合运行时的三条硬证据

1. **`_context.md` 规则只存在于 B**：`multica/cr-prompts-revised/dev-agent.md:47` 有「通过正常 `push-progress`/checkpoint 随 CR 一起提交，不创建单独的上下文提交」；`tools/agents/dev-agent.md` 全文无该规则。
2. **`cr-coordinator-agent` 只存在于 B**：`tools/agents/_index.yml` 的 9 个 id 中没有它，目录下也无该 md；而驱动本 issue 全程的正是 coordinator（`87ca2271`）。
3. **两代文本差异量级**：`dev-agent.md` 两份差 **70 行**、`quality-reviewer-agent.md` 差 **66 行** —— 是 CR-2026-060 后的整代重写。

**判定：B 为 Prompt 事实源，与运行时证据一致。**

---

## 二、与既有登记的冲突（未变，必须原位反转）

`multica/CUSTOM.md:385`（登记项 #75）明文规定了相反方向：

> …本目录是修订结果的**对照快照**…｜合并注意：fork 新增无冲突；**与 tools 仓实际生效 prompt 分叉时以 tools 仓为准并人工对齐**

同表 #74 记录部署路径：

> `aifirst/agent-import.mjs`…把 tools 仓 **9 个** Agent 注册进 Multica：`POST /api/agents`…CR-2026-001 TASK-03/FR-2 的**一次性**导入工具

登记在册的设计是「tools 为源 → 一次性导入 DB → cr-prompts-revised 只是快照」；实际运行时跑的是 B。这层事实源分叉正是本次 `_context.md` 口径冲突未被发现的上游原因——coordinator 08:55 诊断时引用 crctl 白名单与 CR-2026-057~061 先例、未引 AGENTS.md 明文，与「读到的是 A」一致。

---

## 三、7.1（改写）：`multica/CUSTOM.md` 第 385 行 —— 原位反转权威方向并登记新分工

原文（表格第 385 行，逐字）：

```
| 75 | `cr-prompts-revised/`（`agent-skill-matrix.yml` + 5 个 Agent prompt md） | CR-2026-060 修订后的平台 Agent 提示词包仓库侧快照（chore 提交 `7e50590b4`；后续 `18eb6e35d`/`be6426a7c` 把 `quality-reviewer-agent.md` 恢复为 CR-2026-060 后基线） | CR-2026-060 交付物在 tools/KB 仓，本目录是修订结果的对照快照，rebase 前可逐条核对 | 2026-09-03 | fork 新增无冲突；与 tools 仓实际生效 prompt 分叉时以 tools 仓为准并人工对齐 |
```

改为：

```
| 75 | `cr-prompts-revised/`（`agent-skill-matrix.yml` + 5 个 Agent prompt md） | CR-2026-060 修订后的平台 Agent 提示词包，**Agent prompt 与 `agent-skill-matrix.yml` 的唯一事实源**（chore 提交 `7e50590b4`；后续 `18eb6e35d`/`be6426a7c` 把 `quality-reviewer-agent.md` 恢复为 CR-2026-060 后基线；AIFI-18 原位修订 `dev-agent.md` 与 `cr-coordinator-agent.md` 的委派合同否定面） | 事实源判据：`cr-coordinator-agent` 仅本目录存在、`dev-agent.md` 的 `_context.md` 口径仅本目录存在，与运行时行为一致。分工：① `cr-coordinator-agent` 是 **multica 平台专用** Agent，**不进 tools 包**（tools 无该职责，且 `check-agents-contract` 不变式 1 要求 `agents/*.md` 必须在 `_index.yml` 登记，拷入未登记会硬失败）；② 其余 4 个 Agent（`requirement-writer` / `dev` / `quality-reviewer` / `delivery`）prompt 先改本目录，再**全量同步**到 `tools/agents/` 同名文件，tools 侧为下游镜像、不独立演进；③ `agent-skill-matrix.yml` 以本目录为准，与 `tools/agent-skill-matrix.yml` 当前**逐行内容完全一致**（291 行，顺序敏感比对无差异），仅行尾不同（tools=CRLF、本目录=LF；7207−6916=291=291 个 `\r`），故无内容需同步 | 2026-09-03（事实源判定 2026-09-09，AIFI-18） | fork 新增无冲突；**与 `tools/agents/` 同名文件分叉时以本目录为准**（反转原口径）；本目录不在 tools 的 `check-agents-contract` / `lint-prompts` / `contract-scan` 守卫面内，改动后须按 §七 同步至 tools 并重跑两个校验脚本以获得事后守卫 |
```

- 原位性：同一表格行内改写「改动」「原因/追溯」「合并注意」三个单元格，不新增登记行、不改表头、不动 #74 及其它行。
- 归属：CUSTOM.md 是 fork 分叉登记表（人读 + rebase 对照），登记「哪份是事实源、如何分工」正属其职责；不承载可执行细节。

---

## 四、7.2（新增）：tools 侧下游同步

### 4.1 同步范围

| 文件 | 动作 | 依据 |
|---|---|---|
| `tools/agents/dev-agent.md` | **以 `multica/cr-prompts-revised/dev-agent.md` 全量覆盖** | 事实源判定；且 6.1 的补丁随之自动传播，无需 tools 侧单独改 |
| `tools/agents/quality-reviewer-agent.md` | 同上全量覆盖 | 两份差 66 行，属不同代文本 |
| `tools/agents/requirement-writer.md` | 同上全量覆盖 | 同 |
| `tools/agents/delivery-agent.md` | 同上全量覆盖 | 同 |
| `tools/agents/cr-coordinator-agent.md` | **不创建** | coordinator 为 multica 平台专用；创建但不登记会触发 `check-agents-contract` 不变式 1「未登记」硬失败 |
| `tools/agents/_index.yml` | **不动**（保持 9 个 agent 登记） | 不新增 coordinator；`brief`/`version` 与新正文的措辞一致性属软问题，非守卫项，本次不动 |
| `tools/agent-skill-matrix.yml` | **零改动** | 与 multica 侧逐行完全一致（见 §三 ③），仅 CRLF/LF 差异；改行尾只产生噪音 diff，无收益 |

### 4.2 形态说明（诚实标注）

7.2 是**同步动作（4 个文件全量覆盖）**，不是原位补丁。这里全量覆盖是正确且最小的动作：

- 两份是不同代文本（合计差 136 行），逐行原位对齐等于重写，反而更大更易错；
- 事实源已判定为 B，tools 侧不独立演进，因此「镜像」是唯一自洽语义；
- 6.1（`dev-agent.md:31` 委派合同否定面）随覆盖自动落到 tools 侧，避免出现第三种表述。

### 4.3 同步安全性（本轮实测，非推断）

| 校验 | 是否读 agent md 正文 | 基线实跑结果 | 同步影响 |
|---|---|---|---|
| `check-agents-contract.mjs` | ❌ 否——只读 `agents/_index.yml`（path/status/references）+ 文件存在性 + `agent-skill-matrix.yml` 的 owns/can-call/external（代码第 87-116 行） | `agents.contract 校验通过：9 个 agent（不变式 1-3 覆盖）` | **不受影响**（正文变更不进入判据） |
| `lint-prompts.mjs` | ✅ 是——`rel.startsWith('agents/') && name.endsWith('.md')` | `lint-prompts report: 0 findings（prompt 与 crctl 无漂移）` | **必须同步后重跑** |
| frontmatter 兼容性 | — | 两份结构一致（`name` / `description` / `mode: primary` / `permission.bash: deny`），仅 `description` 文案不同 | 覆盖后形态兼容 |

### 4.4 同步方向的常态化口径

```
prompt 改动 → multica/cr-prompts-revised/（事实源，先改）
            → 平台侧更新 Multica DB（运行时生效）
            → 全量同步 tools/agents/ 同名 4 文件（下游镜像）
            → 在 tools 重跑 check-agents-contract + lint-prompts（事后守卫）
```

`cr-coordinator-agent` 只走前两步，不进第三步。

---

## 五、残留风险（修订：R3 / R4 关闭，R1 降级，R2 保留）

| # | 状态 | 说明 |
|---|---|---|
| **R1** | ⬇️ **降级：零守卫 → 延迟守卫** | `check-agents-contract` / `lint-prompts` / `contract-scan` / `crctl-ci` 的 root 与触发器仍只覆盖 `tools/`，multica 侧改动当场无 CI。但按 7.2 同步到 tools 并重跑两脚本后，**tools 的 CI 成为 multica prompt 的事后守卫**——这是本决定带来的实际收益。残留：守卫是事后的，multica 侧单独改动而未同步时仍无检测。后续候选：让 `lint-prompts.mjs` 支持 `--root` 与自定义 agent 目录名，在 multica CI 直接调用（新增能力，独立 CR） |
| **R2** | ⚠️ **保留** | `aifirst/agent-import.mjs` 是 CR-2026-001 的一次性导入工具；prompt 改动如何进 DB、DB 是否已漂移无任何校验。后续候选：加 `--check` 模式比对 `GET /api/agents` 与事实源目录，复用 commitprefix 生成器的 `--check` 范式（CUSTOM.md #67 有先例） |
| **R3** | ✅ **关闭** | 原风险为「`cr-coordinator-agent` 未登记进任何契约」。按新决定，它是 multica 平台专用、tools 不需要，因此 `tools/agents/_index.yml` 保持 9 个登记即为**正确终态**，不是缺口。反向约束已写入 7.1/7.2：**禁止**把 `cr-coordinator-agent.md` 拷入 `tools/agents/`（会触发不变式 1 硬失败） |
| **R4** | ✅ **关闭** | 原风险为「两份 `agent-skill-matrix.yml` 不一致」。本轮顺序敏感比对（`Compare-Object -SyncWindow 0`）结果：**291 行 vs 291 行，完全一致**；字节差 291 = tools 侧 291 个 `\r`（CRLF vs LF）。事实源登记为 multica 即可，**无内容需同步、无字节需改** |

---

## 六、修订后总表（14 处）

| # | 层 | 仓 | 文件 | 位置 | 形态 |
|---|---|---|---|---|---|
| 1.1 | crctl | tools | `lib/workspace-transactions.mjs` | 661 | 语句内改参数数组 |
| 2.1 | crctl | tools | `crctl.mjs` | 960 | `fail()` 内改消息串 |
| 2.2 | crctl | tools | `crctl.mjs` | 1821 / 1844 | 签名加 `async` + 替换 1 条写语句 |
| 3.1 | rules | tools | `controlled-shell/rules.json` | 11 | `shapes` 数组内插 1 个正则 |
| 4.1 | Skill | tools | `review-tech-design/SKILL.md` | 40 | 既有段句首插入 + 既有句改述 |
| 4.2 | Skill | tools | `review-tech-design/SKILL.md` | 79 | 既有句链内插 2 个分句 |
| 5.1 | Skill | tools | `write-tech-design/SKILL.md` | 105-109 | 既有 code block 内加 2 行 |
| 5.2 | Skill | tools | `write-tech-design/SKILL.md` | 111 | 既有反查句内插 4 个分句 |
| 5.3 | Skill | tools | `write-tech-design/SKILL.md` | 129 | 既有句尾分号续接 |
| 5.4 | Skill | tools | `write-tech-design/SKILL.md` | 135-136 | 既有段内加 1 行（增补 I 已改写） |
| **6.1** | Agent（事实源） | multica | `cr-prompts-revised/dev-agent.md` | 31 | 既有句链内插 1 个分句 |
| **6.2** | Agent（事实源） | multica | `cr-prompts-revised/cr-coordinator-agent.md` | 42 | 既有 bullet 句尾续接 |
| **7.1** | 登记 | multica | `CUSTOM.md` | 385（#75 行） | 同一表格行内改写 3 个单元格 |
| **7.2** | Agent（镜像） | tools | `agents/` 下 4 个 md | 全文 | **同步动作**：以 multica 同名文件全量覆盖 |

合计 **14 处**，跨 2 仓（multica 3 / tools 11）。其中 13 处为原位修订，7.2 为同步动作（已在 §4.2 标注理由）。

零新增章节、零新增 Step 编号、零新增机制/状态/门禁/审批节点。不动 `architecture-design.pipeline.json`、README、`gates.json`、`tools/agents/_index.yml`、`tools/agent-skill-matrix.yml`、`quality-reviewer-agent.md` 正文（其内容随 7.2 从 multica 镜像而来，不在 multica 侧单独修订）。

### 分层合规性复核

| 层 | 本次改动 | 是否越界 |
|---|---|---|
| Agent | 6.1 / 6.2 委派合同否定面；7.2 下游镜像 | ✅ 方向是**减少** Agent 承载的 Skill 内容，与「Agent 不应拥有状态机」「Pipeline 不应复制 Skill 完整算法」同向 |
| Skill | 4.x / 5.x 前置语义、写手 bar、产物归属 | ✅ 业务判断与失败语义 = Skill 应有 |
| crctl | 1.1 / 2.1 / 2.2 dirty 口径、错误可操作性、受控账本原子提交 | ✅ 状态/门禁/账本/审计/原子提交 = crctl 应有 |
| 登记文档 | 7.1 记录事实源与分工 | ✅ 人读分叉登记 = 其应有职责，不承载可执行细节 |

---

## 七、批次与验证（跨仓三段）

| 批次 | 仓 | 内容 | 顺序约束与验证 |
|---|---|---|---|
| **1** | multica | **7.1 → 6.1 → 6.2**（严格此序） | 先落事实源判定再改 prompt；否则改动落在仍被 CUSTOM.md 宣告「以 tools 为准」的目录，下次 rebase 可能被反向对齐掉。本批无 CI 覆盖（R1），人工核对三项：① 6.1/6.2 插入后原句首尾逐字未变；② 两处否定面表述一致；③「给人类的交互式命令不受此限」例外在两处均在场 |
| **1'** | tools | 4.1、4.2、5.1、5.2、5.3（纯 SKILL 原文修订） | 可与批次 1 并行。验证：`node skills/shared/crctl/scripts/lint-prompts.mjs`、`node --test` 跑 `check-skill-matrix.test.mjs` / `contract-scan.test.mjs`。6.1/6.2 与 4.1 成对（委派侧防 + reviewer 侧防） |
| **2** | multica→平台 | 平台侧更新 Multica DB 使 6.1/6.2 生效 | R2 无自动校验，需人工确认运行时 prompt 已含新否定面 |
| **3** | tools | **7.2**（4 文件全量覆盖） | 必须在批次 1 完成后执行，否则镜像的是未修订版本。验证：`node skills/shared/crctl/scripts/check-agents-contract.mjs`（期望仍「9 个 agent 校验通过」）+ `node skills/shared/crctl/scripts/lint-prompts.mjs`（期望仍 0 findings）。**两条基线本轮已实跑确认**，同步后须复现同结果 |
| **4** | tools | **1.1 + 5.4**（必须同批）、2.1、3.1 | 1.1 解阻塞、5.4 定归属，缺一则出现「已按 AGENTS.md 保持未跟踪、但 inspect 仍判 dirty」的中间态 = 本次中断 #1 原样复现。验证：`node --test` 跑 `workspace-freshness` / `workspace-resolver` / `crctl` / `contract-scan`；新增 untracked-not-dirty 与 tracked-still-dirty 两例 |
| **5** | tools | 2.2（reset 原子提交） | 触及事务提交路径，单独一次改动。验证：`node --test` 全量 + reset 后工作区干净单测 |

### 附带影响（记录，自愈）

`tools/openwiki/` 与 `tools/AGENT-SKILL-MATRIX.md` 中对 agent 职责的描述性文字在 7.2 后可能措辞陈旧。openwiki 由每日定时 workflow 经 `openwiki code --update` 以 PR 回写（CUSTOM.md #73），会自愈；`AGENT-SKILL-MATRIX.md` 是矩阵的人读说明、不含逐 agent 正文，无需同步。
