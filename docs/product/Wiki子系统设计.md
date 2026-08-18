# Wiki 子系统设计 — 代码 Wiki 维护 · 知识问答 · 知识晋升

> 决策状态：**conditional（条件触发）**。本文件是候选设计输入，不是当前实施授权；只有具备明确 owner、维护频率和稳定检索需求后，才按 `docs/product/缺口清单-最终版.md` 的准入规则注册 CR。正文中的阶段、工期和交付切分均为历史设计假设，注册时必须依据当前代码与权威合同重新核实。
> 权威边界：当前能力处置以 `docs/product/缺口清单-最终版.md` 为准；状态机、Pipeline、Skill 和 `crctl` 行为继续以 tools 权威文件为准。
> 承接：v1.1 知识层设计（PRD §2.1.7 三分工：事实生产 / 知识消费 / 知识晋升）、P0 §6.1 目录契约扩展、P2.5 runner 轻量档、P3 §2.3 知识晋升巡检。
> 借鉴来源：OpenWiki（langchain-ai/openwiki）的文档维护方法论与"确定性护栏包住生成式内核"的工程模式——**借模式与纪律，不引其依赖**（我们的执行体是 Claude Code CLI + Agent SDK，不是 LangChain/DeepAgents）。源码级调研结论见《对比分析》会话记录：prompt 方法论、docs-only-backend 写边界、okf-middleware 三段式校验、gitHead 增量机制均已逐一核对。
> 日期：2026-07-30。
> 修订：2026-07-30 —— §3.2 补 shell 路径与文件工具路径同等拦截的要求，§7 W3 验收标准加对抗性用例（重定向写/`..` 穿越/反斜杠路径），吸取 OpenWiki 的 shell 逃逸缺口教训。

---

## 0. 定位与边界（先钉死，再谈功能）

**Wiki 是衍生解释层，不是事实源。** "Git 负责让事实可信，Wiki 负责让知识好用"——Wiki 回答"代码是怎么回事"（架构解释、模块文档、代码问答）；"承诺了什么、谁批的、验证了什么"这类治理事实（CR 状态、traceability、审批记录）仍走 `cr` / `spec_trace` 投影表查询，**不经 Wiki 转述**。

三条边界条款（与 N8 记忆/图谱预留同构）：

1. **可整目录删除重建**：`wiki/` 是从事实源（代码 + specs + docs）生成的衍生物，删掉后可全量重建，永不作为状态权威。
2. **Wiki 任务只写 `wiki/**`**：写边界在 execenv 工具层硬实现（§3.2），不靠 prompt 自觉。
3. **Wiki 即图谱的种子**：页面 frontmatter 是节点属性、正文概念链接是关系边——将来接图谱 MCP 时解析器读 Wiki 即可重建全图，无需独立图数据库（这充实了 N8"图谱可删除、可重建"条款的实现路径）。

三块业务与承载位置：

| 业务 | 执行位置 | 阶段 |
|---|---|---|
| **维护**（生成 + 增量更新代码 Wiki） | daemon 本机（knowledge-agent + Claude Code CLI，开发者流量） | P2.5 起步，P3 完整 |
| **查询**（Wiki 问答，带出处） | runner 轻量档（Agent SDK，平台侧流量） | P2.5 |
| **晋升**（高频缺口回写事实源） | P3 巡检 Autopilot | P3 |

---

## 1. 目录与格式契约

### 1.1 `wiki/` 目录（进 dir-graph 声明）

在 P0 §6.1 已扩展的目录契约上加第三类：

| 目录 | 治理属性 |
|---|---|
| `wiki/` | **生成的衍生解释层**：不受 gate 保护（不是证据）；不入 protectedPaths 的 deny/ask（但 Wiki 任务的写白名单**只含**此目录）；git 版本化（diff 可审、可回滚）；可整目录删除重建 |

结构约定（借鉴 OpenWiki 的 required structure）：

```
wiki/
├── quickstart.md          # 唯一入口：高层综述 + 链接到每个主要章节 + ## Backlog 节
├── open-questions.md      # Active / Answered / Stale 三节（知识晋升信号源之二）
├── .last-update.json      # {timestamp, gitHead}——增量更新锚点，机器可读
├── architecture/          # 章节目录按需：architecture/ workflows/ domain/
├── data-models/           #   api/ data-models/ operations/ integrations/ testing/
└── …                      # 每目录多个实质页面；index.md 由确定性代码生成，模型禁写
```

### 1.2 页面格式：结构化 frontmatter + 链接即边

每个非保留页（`index.md`、`.last-update.json` 除外）以 YAML frontmatter 开头（对齐 OKF v0.1 的精神，字段从简）：

```yaml
---
type: <概念类型>            # 必填，自描述短语（"API Endpoint" / "状态机" / "Runbook"）
title: <显示名>             # 推荐
description: <一两句摘要>    # 推荐——为检索优化编写，这是问答层的召回锚点
tags: [<横切标签>]           # 可选，英文保持跨语言稳定
---
```

**链接即边**（图谱种子的关键纪律）：

- 概念间的 markdown 链接是**有语义的关系边**——链接必须放在解释该关系的那句话里（"X **dispatches to** [Y]"、"A **is secured by** [B]"），周围文字说明边的含义；
- 禁止为凑图密度加链接、禁止机械互链；只有当反向链接帮助解释目标概念且有证据支撑时才加；
- **孤儿审计**：每个实质概念页应连接 ≥2 个其他实质概念；孤立页要么补上有证据的关系、要么并入更宽的页、要么明确说明它确实独立（quickstart/index 的导航链接不算语义边）；
- 每个概念只有一个 **canonical 页**，其他页面提及时只留链接不复述。

### 1.3 反薄页纪律

- 不为单个短页建目录；stub 页并入 quickstart 或更宽的章节页；
- 小仓库（主源文件 ≤10 个量级）：quickstart + 至多 1–2 个辅助页；
- 运行收尾前审一遍目录树：合并/移除低价值单文件目录——**Wiki 要窄到维护得动**。

---

## 2. `wiki-maintain` Skill（维护）

新增 Skill，**owner = knowledge-agent**（tools 九 Agent 现成的位置），init / update 双模式。以下纪律直接吸收 OpenWiki 打磨过的成品方法论：

### 2.1 通用纪律（两模式共享）

- **双读者定位**：Wiki 要同时对人类和未来 Agent 优秀——目标是"未来 Agent 用文档回答问题和做修改时，减少原始源码探索"。每个主要区域包含**面向变更的指引**：从哪开始、注意什么、改动时跑哪些测试。Wiki 本质上是仓库的**预压缩上下文缓存**。
- **解释 why 不止 what**：git log / blame / show 定向用在高信号文件上，解释重要代码为何存在、关键工作流如何演化；不过度考古，聚焦近期与高信号历史；持久化的 commit 哈希列表不进文档（除非某个历史决策对未来工作重要）。
- **禁止发明**：不虚构文件、模块、API、业务规则；每个重要论断锚定在检查过的源文件、既有文档或 git 证据上。
- **既有文档是一等素材**：README / docs/ / Runbook / SKILL.md 优先作为素材，有用就总结+链接而非整段复制；与源码冲突时指出疑似过时并以当前源码为准。
- **子代理只读、主代理唯一写者**：并行调研的子代理只许 inspect+summarize（返回精炼发现 + 源路径 + 未解问题），一切写入由主代理完成——单一写者语义与我们 Team Agent 一致。
- **诊断图纪律**：运行时流程 / 生命周期 / 数据模型 / 复杂控制流用 mermaid（sequenceDiagram / stateDiagram-v2 / erDiagram / flowchart），图必须锚定检查过的源码；过时的图是过时的论断，随正文一起修。
- **秘密纪律**：不读 `.env` 与密钥文件；凭据只按环境变量名引用；涉密配置只记"存在此配置、应在何处描述非敏感设置"。

### 2.2 init 模式（初始生成）

1. 先建**仓库清单**：既有文档、入口、package/config、主要领域目录、测试、数据/schema 文件、运维脚本；不逐文件穷举读，定向发现（按目录与扩展名，排除 .git/node_modules/dist 与既有 wiki 输出）。
2. 写**临时计划** `wiki/_plan.md`：列出计划页面、每页的源码证据、概念间关系（`源概念 → 关系含义 → 目标概念`，先设计边再写页）、未解问题；**运行结束前必须删除**——临时计划不留在 Wiki 里污染事实。
3. `quickstart.md` 先行，然后章节页；**初始 ≤8 页预算**（仓库明显巨大除外）。
4. **Backlog 兜底**：识别到但没写的领域必须进 quickstart 的 `## Backlog`——领域名 + 源码锚点 + 一行原因。"没写"和"没发现"必须可区分，覆盖率因此可审计。
5. 收尾自检：每个识别区域已文档化或已入 Backlog；概念链接可解析；无孤儿页；`_plan.md` 已删。

### 2.3 update 模式（增量维护——外科手术纪律）

1. **差量证据**：读 `.last-update.json` 的 `gitHead`，用 `{lastHead}..HEAD` 的提交与变更文件作为本次证据（含未提交的本地变更 git status/diff）。
2. **docs impact plan 先行**：编辑前建 `源码变更 → 受影响文档 → 需要的编辑 → 为什么` 的映射；对不上任何变更的页面**不许碰**。
3. **软 diff 预算**：<5 个源文件变更 → 最多改 1–2 个 Wiki 页；除非顶层行为/导航变了否则不碰 quickstart；认为要改 >3 页时先深想为什么。
4. **禁 formatting-only 编辑**：不重排表格、不规整空行、不为润色而改；"宁可替换一句过时的话，不新增一段"。
5. **Backlog 消化**：近期变更触到某 Backlog 区域、或本次有富余预算时，把该条目升级为正式文档并从 Backlog 移除；Backlog 不许静默增长。
6. **no-op 合法**：无相关变更且 Wiki 已准确 → 不改任何文件，如实说"已是最新"。
7. 成功收尾时写回 `.last-update.json`（timestamp + 当前 gitHead）。

### 2.4 探索型知识的置信度纪律

Wiki 消费 `docs/research|notes|minutes`（P0 §6.1 探索型目录）时：

- 结论标注置信度：`confirmed`（权威/多源证实）/ `source-backed`（单一可信来源）/ `contested`（可信来源冲突未决）/ `watchlist`（弱信号待观察）；
- **冲突保留**：可信来源互相矛盾且无定论时，双方 claim 连来源与日期一起保留在 `## Contested` 节；**不许按时间新旧独断**——只有新证据settle冲突或证明某来源过时才解决，并留一行解决记录；
- 答不上的缺口进 `open-questions.md`（Active 节），运行中被新证据回答的移入 Answered 并链接证据。

---

## 3. 执行与护栏（确定性外壳）

### 3.1 触发与 no-op 门槛

- **触发**：Autopilot 定时（建议每日或每周，挂 sys_cron）+ 聊天内手动（`/更新wiki` 可加入 P2 §6.1 斜杠命令族）。
- **no-op 门槛在 daemon 侧、任务派发之前**：比较目标仓库 HEAD 与 `wiki/.last-update.json#gitHead`，无新 commit **不派任务、零 token**。这是从 OpenWiki 照抄的最划算的一条。

### 3.2 写白名单（边界在工具层，不在 prompt）

借鉴 docs-only-backend 的实现要点，落在我们已有机制上：

- `rules.json` 增加 **allowlist 段**：`"taskWriteAllowlist": { "wiki-maintain": ["wiki/**"] }`——execenv 对挂此 Skill 的任务，Write/Edit 工具只放行白名单路径；
- 路径判定先做 **normalize 折叠 `../`**（OpenWiki 明确防了 `/openwiki/../AGENTS.md` 式逃逸，照抄）；
- **shell 路径必须与文件工具路径同等拦截，这是 OpenWiki 的真实教训**：其 docs-only backend 只覆写了 Write/Edit 工具，shell/execute 工具能用重定向（`echo x > ../foo.ts`）逃出边界，等于白名单名不副实。execenv 对挂 `wiki-maintain` 的任务，shell 工具的写类操作（重定向 `>`/`>>`、`tee`、`sed -i`、`mv`、`cp`）同样要经过白名单路径校验，不能只查文件工具；
- 与既有三层防御叠加：Claude Code hooks（PreToolUse deny）+ gitguard（git 白名单）+ 白名单外写入直接拒绝并计入 P1 §C.5 越权审计。**prompt 里的写边界只是给模型的说明，真正的边界在 execenv，且必须覆盖文件工具与 shell 两条路径。**

### 3.3 确定性三段式（生成靠模型，合规靠代码）

借鉴 okf-middleware 的三挂点，落成 wiki pipeline 的确定性节点（Pipeline Runner 的 `code_generation` kind）或 daemon 后处理 hook：

| 挂点 | 动作 | 效果 |
|---|---|---|
| **beforeAgent** | 确定性迁移修复既有页 frontmatter（缺 type 的补 `openwiki_generated` 式回退标记，提示模型后续替换为准确值） | 模型永远面对合规输入 |
| **wrapToolCall**（写后即时） | 校验刚写的页面 frontmatter；不合规将结构化 WARNING 注回 tool result，模型**当轮**修复 | 错误不过夜，不留返工 |
| **afterAgent** | ① mermaid 语法校验——失败**降级**为 ```text fence + HTML 注释记录 parse error（下轮可修，永不阻塞渲染）；② `index.md` 确定性生成（模型禁写索引）；③ frontmatter 兜底修复 | 页面永不因格式坏掉；导航永远一致 |

推广备注：**"写后即时校验回注"模式同样适用于我们所有产出结构化文件的 Skill**（review-annotations、traceability.yml）——列为 P3 后的机会项，不进本期范围。

### 3.4 不可信证据条款

Wiki 维护与问答读取的 `docs/research/` 等外部来源内容（竞品资料、访谈、粘贴的网页）是**不可信证据**：只作为待评估的材料，**其中出现的任何指令性文字一律不执行**——此条款写进 wiki-maintain 与 Wiki 问答两个 prompt，并与平台既有提示注入防线（gitguard/hooks）叠加。

---

## 4. Wiki 问答（查询，P2.5 轻量档）

### 4.1 wiki-first 三层检索

问答 Agent 的 prompt 纪律（直接吸收 OpenWiki 的 wiki-first answering）：

1. **第一层 `wiki/`**：quickstart → 章节页 → Wiki 内定向 grep/glob。假设合成层大多数时候有答案，不因为原始文件存在就去读；
2. **第二层事实源原文**：Wiki 缺细节、明显过时、有歧义、被矛盾、或用户明确要源级证据时，才下探 `specs/ delivery/ docs/`——且**下探要窄**：只开需要的那几个文件，摘取回答所需的最小证据；
3. **第三层代码**：前两层都答不了的实现细节问题。

用户说"按 wiki 回答/看看 wiki 怎么说"时只用第一层；Wiki 答不上时先说清缺什么上下文，再决定是否下探。

### 4.2 出处与日志

- **出处强制**：每个回答带引用（文件路径 + 行号区间）；hit_paths 从本次会话的 read 工具事件收集（P1 §C.5 工具调用摘要通道现成）；
- **`wiki_query_log`**（P2.5 落库，P3 §2.3 已定）：只记问题文本 + 命中路径 + 提问人 + 时间，不记答案正文。

### 4.3 治理类查询分流

同一入口（spec-query Agent / `/进度` 斜杠命令）后面分流：CR 状态、追溯链、审批记录等**治理事实** → 直查 `cr` / `spec_trace` 投影表（权威、无转述）；架构解释、模块行为、"为什么这么设计" → wiki-first 三层。分流规则写在 Agent prompt 里，按问题意图判别，含混时先答治理事实再补 Wiki 解释。

---

## 5. 知识晋升（P3 巡检，双信号源）

在 P3 §2.3 单信号（问答日志聚类）基础上扩为双信号：

| 信号源 | 抓什么 | 来源 |
|---|---|---|
| **信号一：问答日志聚类** | 被反复问的（≥3 次同类问题且命中文件分散） | `wiki_query_log` |
| **信号二：open-questions.md 的 Active 条目** | Wiki 生成/更新时发现答不上的（缺口在生产侧就被记录，不用等有人来问） | wiki-maintain 运行产物 |

两路汇进同一晋升流：周巡检（knowledge-agent 只读）→ 自动开「建议将〈主题〉回写事实源」Issue，附问题样本/open-question 条目 + 建议落点（specs/ 或 docs/）→ 回写走人审的正常流程。**只开 Issue 不动文件**。被回写解决的 open-question 移入 Answered 节并链接落点。

---

## 6. 数据面：零新表

| 数据 | 位置 | 说明 |
|---|---|---|
| Wiki 内容 | git `wiki/**` | 衍生层，版本化，可重建 |
| 增量锚点 | `wiki/.last-update.json` | 文件即权威，daemon 读 |
| 问答日志 | `wiki_query_log`（P2.5 已定） | 本设计不新增 |
| 写白名单 | `rules.json#taskWriteAllowlist` | P1 单一事实源文件加一段 |
| 晋升信号二 | `wiki/open-questions.md` | 文件即信号，巡检读取 |

无新 PG 表、无新权威域、无新事件类型——完全符合"P3 不引入新采集"与"治理层做成新增文件"两条既有纪律。

---

## 7. 交付切分与验收

| 序 | 交付物 | 阶段 | 验收 |
|---|---|---|---|
| W1 | 目录与格式契约：`wiki/` 进 dir-graph + frontmatter/链接/反薄页规范成文 | P0 文档补齐（随 §6.1） | dir-graph 声明齐备；规范文档评审通过 |
| W2 | `wiki-maintain` Skill（init/update 双模式全纪律）+ Autopilot 挂载 + daemon no-op 门槛 | P2.5–P3 | ① 对一个真实仓库 init 产出 ≤8 页 + Backlog ② 无新 commit 时 Autopilot 触发零任务派发 ③ 改 3 个源文件后 update 只动 ≤2 页且 diff 无 formatting-only 噪声 |
| W3 | 护栏：写白名单（**文件工具 + shell 两条路径同时拦截**，含 `../` 折叠）+ 确定性三段式收尾 | P2.5–P3（复用 P1 机制） | ① wiki 任务写 `specs/x.md` 被工具层拒绝且计入越权审计 ② 人为写坏 frontmatter → 当轮收到 WARNING 且最终文件合规 ③ 人为写坏 mermaid → 降级 text fence 不阻塞，注释含 parse error ④ **对抗性用例（借鉴 OpenWiki 的 shell 逃逸缺口）：** shell 重定向写 `echo x > ../../specs/leak.md` 被拒绝且计入越权审计；`wiki/../../AGENTS.md` 这类 `..` 穿越路径无论走 Write 工具还是 shell 都被拒绝；反斜杠路径（`wiki\..\..\specs\leak.md`，Windows 风格分隔符）经 normalize 后同样命中白名单校验并被拒绝，不能因为分隔符不同而绕过 |
| W4 | Wiki 问答 prompt（wiki-first 三层 + 出处 + 分流 + 不可信证据）+ 晋升双信号 | P2.5（问答）/ P3（晋升） | ① 问答回答带路径+行号出处 ② 治理类问题直查投影表不经 Wiki ③ open-questions 的 Active 条目出现在周巡检产出的晋升 Issue 里 |

排期归属：W1 是文档工作（随 P0 文档修订）；W2/W3 主体在 P2.5–P3 之间（约 +2 周，daemon 侧与 runner 侧可并行）；W4 并入既有 P2.5 问答与 P3 §2.3 巡检条目，不单列。

## 8. 明确不做（防蔓延）

- **不做 connectors / personal mode**：Gmail/Slack/Notion 聚合超出平台范围，触个人隐私边界；
- **不引 LangChain / DeepAgents 依赖**：借纪律与模式，执行体仍是 Claude Code CLI + Agent SDK；
- **不做 Wiki 实时性**：更新跟 Autopilot 周期（日/周级），代码刚改完 Wiki 短暂滞后是接受的代价（问答层第二层下探兜底）；
- **不做独立图数据库**：图谱=Wiki 的链接结构，接图谱 MCP 时从 Wiki 解析重建（N8 条款不变）；
- **不做多语言 Wiki**：单语言起步（团队工作语言），OpenWiki 的确定性翻译层设计留作将来参考。
