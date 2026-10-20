# T03 构建报告（已完成，文件释放；不是整体验收）

## 范围与所有权

- 第一阶段获准修改：tools `AGENTS.md`（仅 Pipeline §9）、`skills/writeback/merge-feature-branch/SKILL.md`（仅 camelCase）、`skills/develop/review-dev-plan/SKILL.md`（仅 upstream 顺序）、`skills/shared/crctl/SKILL.md`（绑定 exit0 范围与 recovery 不授予权限）、既有 `skills/shared/crctl/scripts/test/contract-scan.test.mjs`。
- 四份 JSON 在首次 RED 和文档修复期间仍归 T01 writer；收到主会话明确交接后才接管。交接快照在临时证据目录 `templates-handoff.json`，固定原节点 ID/order/kind/ref/reviewLoop/executor/onFail/timeout/approvalPrompt；不改 emitter 或其测试。
- `pipeline-structure.test.mjs` 由主会话修正 obsolete unsupported-coding 反例，本 worker 不编辑。
- S0 `crctl.mjs`、`crctl.test.mjs`、`caller-contract.test.mjs`、`writeback-tx.test.mjs` 及矩阵、索引、四 approve Skill 不编辑；字节摘要已记录在 `protected-before.json`。
- 已读 writing-for-agents、SKILL-MECHANICS、system-prompts；沿用原中文文档风格，不做提示词整体重写。原文件 UTF-8 无 BOM、CRLF，使用精确 edit，保持编码和行尾。
- Node v24.15.0 / Git 2.54.0.windows.1；未注册真实 CR、未操作 DB/网络、未改依赖/环境/设置，未 commit/push。

## 持久证据位置

`C:/Users/GOBAO/AppData/Local/Temp/aifi45-t03-stage1-lNFodd/`

每次运行独立保存 `<label>-command.json`、`<label>-result.json`、`<label>-stdout.log`、`<label>-stderr.log`；计时为 monotonic wall，退出码为直接 spawnSync 捕获的 Node native status，不取管道末端状态。

## 第一阶段：真实 RED → 文档部分 GREEN

在既有 contract-scan 末尾追加四组 `TC-T-TPL-001..004`，各含文档与实际模板两例，共 **8 例**；旧测试和旧断言逐字保留，无 skip/todo。它们验证声明消费合同，不冒充 Runner/daemon 运行。

| label / name-pattern（文件均为 contract-scan.test.mjs） | tests/pass/fail/skip | native exit | wall 秒 |
|---|---|---|---|
| red / `TC-T-TPL-00[1-4]` | 8/0/8/0 | 1 | 0.1474495 |
| partial / `TC-T-TPL-00[1-4]`（仅文档已修，JSON 未动） | 8/4/4/0 | 1 | 0.1486450 |
| docs-green / `TC-T-TPL-00[1-4] 文档` | 4/4/0/0 | 0 | 0.1453548 |

三次均 cancelled=todo=0；定向命令形态：`node --test --test-reporter=tap --test-name-pattern=<pattern> skills/shared/crctl/scripts/test/contract-scan.test.mjs`。

真实首个失败分别为：AGENTS §9 缺 authority/new/legacy；需求 writer 缺评审前确认/version-set；共享绑定合同无条件 exit0 继续；merge prompt 缺 phase 分流；merge Skill 错写 snake_case；merge prompt 错写 snake_case；upstream Skill 先人工修订而非设计复评；upstream prompt 缺 pending/Runner 复评交接。均是 assertion 失败，不是语法/找不到文件/无匹配用例。

文档 GREEN：§9 保留非空要求并区分 new 继承/legacy 显式；merge 只改四处实际输出名；upstream 保留既有 advance/expect、改为 Runner 先设计复评且不沿旧 PASS/重置轮次；共享 Skill 收窄绑定 exit0 并保留 recovery 五字段、TTY/输入入口与原权限边界。

## 模板实现与最终 GREEN

收到独占交接后，仅修改 inputs 的 description/required 和必要 prompt，具体为：

- **TC-T-TPL-001**：注册仍可为负责人确认的 unassigned；需求评审前须有负责人确认的真实版本，writer 在写脏 PRD 前调用既有 `version-set`。后续 title/summary/source/version 继承 cr.md authority；coding 不再用空表单或 tbd 覆盖版本。writeback 两字段不再全模式表单必填：new 由 strict authority 继承，legacy 显式必填；new 不传 milestone_file，legacy 原合同保留。
- **TC-T-TPL-002**：merge 只有 `phase=complete` 接回写；exit0 + `phase=release-drift` 原样携 advanced/to=developing 停止正向，不沿旧 code grant 或技术 retry。测试节点消费 Skill 内真实 testCr 的 status/commandDigest/attempt/reviewLoop/commands/report，exit0 + block 仍回 implement-code；保留原 passCondition。代码评审消费机器 release-subjects，不扩造单一摘要。
- **TC-T-TPL-003**：merge 实际输出名为 operationalWorkspace；旧 Task 出证据后结束，由 Runner 新 Task 重新解析并绑定该根，不改 env、不猜路径。archive 从稳定 knowledge-base 主 checkout/安装根调用；complete 和 cleanup-pending 均保持业务成功，保留清理摘要；重入按既有 Skill/recovery，不重做首跑前置或要求已删除 txws/CR worktree。
- **TC-T-TPL-004**：upstream 停止当前 replay，交 Runner 先派既有 review-tech-design 复评；架构评审节点承接上游反馈，再按结果必要修订、重审与人工审批，不沿旧 PASS/直接退 writer/重置轮次。merge 只引用共享 recovery 合同，保留机器错误码；结构合法不授予额外权限。

没有新增节点、CLI、参数、错误码、门禁、恢复引擎或 merge spec/version 元数据输出。human_approval、approve、TTY/nonce/签名/人工驳回均未变。

| label | 范围 | tests/pass/fail/skip | native exit | wall 秒 |
|---|---|---|---|---|
| templates-green | 四 TC 的文档+模板全部选中 | 8/8/0/0 | 0 | 0.1338898 |
| contracts-full | 完整 contract-scan + pipeline-structure | 74/74/0/0 | 0 | 1.0269856 |
| contracts-full-final | EOF 空白修正后的同两份完整文件（含四 TC） | 74/74/0/0 | 0 | 0.9246704 |
| emitter-full | emit-registry.test.mjs 完整原测试 | 64/64/0/0 | 0 | 5.9578982 |
| prompt-neighbors-full | skill-scope / check-agents-contract / check-skill-matrix / lint-prompts 四份完整测试 | 53/53/0/0 | 0 | 2.7631871 |
| version-test-full | version-set / test-cr 两份完整测试 | 42/42/0/0 | 0 | 81.8623794 |
| merge-writeback-archive-focused | merge-tx / writeback-tx / archive-tx 定向 11 例（不是三份全量） | 11/11/0/0 | 0 | 73.7638089 |
| agents-check-final | check-agents-contract.mjs | 非测试入口 | 0 | 0.0508550 |
| matrix-check-final | check-skill-matrix.mjs | 非测试入口 | 0 | 0.0615403 |
| lint-check-final | lint-prompts.mjs（非 strict） | 非测试入口 | 0 | 0.1061646 |
| integrity-final | 下述所有权/编码/旧断言/diff-check 校验 | 非测试入口 | 0 | 0.1234150 |

以上 emitter-full 64/64 及 contracts-full-final 是收到 A 再接管 emitter 做两项 malformed-metadata RED→GREEN 修复消息之前的实际结果，不覆盖 A 的新增回归。收到消息后不再运行 emitter 或 pipeline 测试，待 A 再冻结后由主会话联合复验；没有运行 pipeline/*.test glob。

所有测试 cancelled=todo=0，无 skip；定向范围由 command.json 原样记录，不把未选中的邻接测试算通过。两个完整深原语邻接文件与 11 个定向例只用本地隔离 fixture；没有真实 CR/生产 Git/DB 操作。未重复约 35 分钟的 crctl 全套，S0 既有 875/875 不能扩称本次整体验收。

11 个深邻接例覆盖 merge complete/camelCase、exit0 drift、publication-lag 分类；new baseline/authority 缺失/traceability 无 milestone、legacy traceability、缺失/未排期版本失败关闭；archive new 首跑/缺 txws 失败关闭/发布后 txws 已删重入（包含稳定安装根）。实际所选测试名与 stdout 均在对应日志。

质量入口实际结果：AGENTS 通过（10 agents，不变式 1–3 + 附加检查 5；不变式 4 是运行时行为约束）、矩阵通过（56 active skills / 8 actors，owns 唯一、external 引用点齐全）；lint exit0，但保留 **1 条已有 OUTDATED**：`skills/sync/handover-cr/SKILL.md:59` 的 R5 `attempts[]`。该文件不在本任务写集，不将非 strict 通过描述成零告警。

## 边界与字节校验

`verify-integrity.mjs` / `t03-final-integrity.json` 是临时证据，不是新增仓库命令：

- 与 `templates-handoff.json` 做逐叶语义 diff：四份 JSON 仅 **17 个 inputs/prompt 叶值**变化，其余字段全部相等；26 个节点 ID/顺序/kind/ref/reviewLoop/executor/onFail/timeout/approvalPrompt 等未变。
- 四个独立 reviewer executor 逐字保留。write-test-report 没有被加 reviewer executor，仍按既有 dev 绑定；64/64 emitter 回归通过。
- 四份最终 JSON SHA256：requirement `3abc0009afcd9f4c699e176c4eddb695b40d68374c068b84f67ea4b0fd1c5c8e`；architecture `9208a3f739216fccf227267666b5d84f6bb91e1bc0dd0312cfc7adc53943d776`；coding `304ec236eaae1c78cac3486ed106b46a15f146313a15687e832956cfe95b201f`；writeback `11fc7f0e81a9c412df797e37229e2311553c3084ae6f34cfe282171e488714fd`。
- 12 个受保护文件与第一阶段摘要完全相等（S0 四件、矩阵、三索引、四 approve Skill）。
- 九个所属源码文件均 UTF-8 无 BOM、仅 CRLF；contract-scan 旧文件是当前文件的完整前缀，旧测试/断言没有变。
- 首次 `git diff --check` native exit2，仅追加测试 EOF 多一空行；已精确移除，保留 `diff-check-before-eof-fix-*` 证据，最终 exit0，随后重跑完整 74/74。没有用空白问题解释或掩盖 TC 的真实 RED。

## 交还检查点与剩余责任

**现在释放全部九个所属源码文件及本报告，不再继续写入。** 未编辑 emitter/其测试、主会话的 pipeline-structure 反例、S0、矩阵/索引、approve Skill、任务/phase/spec/ADJ 账本或其他文件。

本报告交付 T03 静态消费合同及本地深原语邻接回归证据；**未声称 Runner/daemon 真实跨 Task 换根、平台多载体集成或整项 AIFI-45 已验收**。后续独立 review/任务勾选由主会话负责，multica 真绑定另有责任边界；T04 如需退役既有旧交接文字，可在释放后按其独占写集继续，不重置本次已保留的结构合同。
