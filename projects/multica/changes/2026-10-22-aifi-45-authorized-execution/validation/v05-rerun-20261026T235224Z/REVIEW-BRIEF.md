# v0.5 B17 后三路独立复核（第二次启动）

## 对象与冻结
- 用户请求：重跑一轮 v0.5 三路复核。
- cwd：`C:/Users/GOBAO/Downloads/AI/AI First Platform`。
- 被审方案：本目录 `inputs/trusted-verdict-channel-implementation-plan-20261026.md`，原始字节 SHA256 `6f98229a53e05dcffec20ad39b4ee1190b0444dcfce6e4a5505e9c2639f92a06`。
- 全部冻结输入及 HEAD：`source-manifest.json`；文档按 `inputs/` 副本读，源码按 manifest 的绝对路径读，主会话在评审期间不改这些输入。评审结束再次核 SHA。
- tools HEAD `7168198978e71a292d85f5bf8f538c3ee90d87bd`（B17）；multica HEAD `5c395581f21eb0669e13aa455c0850f263c2e464`；工作区 HEAD `3f5addf87dbaff309b711d8c2e91e64b48be2274`，尚有 B17 记录未提交。
- 有效模型配置：`model-config.json`，双仓均 `kind=configured`。三路 requested：strong `OpenAIPersonal/gpt-6.1-sol:high`；balanced `Gobao/deepseek-flash:max`；economy `GB-JP/deepseek-flash:high`。actual 仅接受后端回执，无回执记 unknown。

## 共同行为与边界
1. 全新非作者、独立上下文；不看其他本轮 reviewer 的输出，不委派下一层。
2. 仅只读静态计划复核：不得编辑任何仓库文件，不跑 DB/迁移/部署，不操作真实 CR，不 commit/push。回复完整 Markdown，由主会话逐字落盘。
3. 读工作区 `AGENTS.md`、`dir-graph.yaml`，再读 sibling `tools/AGENTS.md`、`agent-skill-matrix.yml`、`README.md` 的相关约束；若查看 multica 源码先读其 `AGENTS.md` 与 `CLAUDE.md`。遵守可用读取工具的 root 限制；不得绕过。如果读取被拒，报具体路径与影响，不猜测其不存在。
4. 本轮只判断当前冻结 v0.5 是否足够明确、可实施、可验证。M003 仍 proposed/搁置，注册由用户，不因方案通过变成实现通过。AIFI-45 权威覆盖 41/49、Gate NO-GO、M001/M002/M003 unresolved、原库 HOLD 均不变。
5. 历史三路都未通过，修订主要通过追加条目完成，不能自动将“按意见修改”当成闭环。读取旧评审仅为定位旧问题，结论必须由本轮独立验证。
6. B17 是新变化：`change-scope.mjs` + 测试四项加固，当前记录称 18/18、全量1121/1120/0fail/1skip（既有 Windows EXEC-12），证据见 `../todo-a-20261026/`。这些计数是待核事实，不是通过依据；尤其区分夹具/ReferenceError/TypeError 红与行为断言红。不要沿用“中文路径一定放行”等未证因果。
7. 自检采集和未来 committed/tree 适配有不同输入来源；不得把调用者 `--grant`、本地扫描、agent 可写 YAML/`.crctl` 当可信 selection/head/store。不得复制 tools 唯一业务判定到 Go。
8. X7：KB 不隐藏豁免；repo id / allowed_paths 前缀 / 冻结绑定三者分别提供，漏列 fail-closed；X8：不改 inputDigest，旧摘要被交付 gate 拒绝不等于自动执行了重测。

## 三路分工
### strong — 安全与实施可行性
- 对照真实 `cmdMerge` → gates → `mergeCr` → lock/journal/recover/prepare/publish/rebuild/finalize 链核插入点、零写入承诺和恢复范围。
- 权威批准来源、可信 merge caller/认证/端点/typed facts、repo 集合/base/source/selection/head revision 的冻结与锁内重验、撤销线性化/部分发布、Strict/legacy 降级、实际发布及 finalize 写集是否定义完备。
- 核 (a)/(b) 是否仍未选、追加条目是否互相冲突；不代规范选语义。
- 核 B17 是否真的清掉通用采集前置：rename 两端、lossless 路径、缺失/失败、symlink 的来源与未知处理、untracked/deleted 的合法行为。指出影响方案的残余，不直接改源码。

### balanced — 测试与配置
- 核 TC/CP/leaf/mutation 矩阵逐条映射、命令可运行性、确定性同步点、状态/副作用断言，以及审批后写入、journal/rebuild/resume、撤销交错、legacy/unknown、异常零写入的覆盖。
- 方案中的“六条/十条/10:10”等与后追加条目能否同时成立；不得凭文本关键字重算权威41/49。
- B17 读取真实用例与 TAP，识别测试设计、假 RED、变异失效模式、未测适配器行为。静态分析即可，不跑测试与 DB。
- DB 证据计划须经 `multica/scripts/aifi45-db/run.mjs`、643–647/拟648、隔离与零skip约束；tools既有symlink skip不能移作DB豁免。

### economy — 文档与 Skill 一致性
- 全读冻结方案与 disposition，核版本、proposed/搁置、归属、依赖、X7/X8、计数、前后文及历史记录指针。
- 对照真实 implement-code Skill 与 change-scope 公开 API，核复用边界不是缺少已有纯函数，也不是强行复用不适用采集器。
- 核原评审 session 身份：旧文档将 `01a1796a-...` 误写成 `01a17797-...`。正确历史值：strong `01a1796a-23b8-77b9-a3c5-0f7bb49a78dc`；balanced `01a1796a-6197-77b9-a3c5-0f7c0aa2351c`；economy `01a1796a-91f3-77b9-a3c5-0f7f2e805ad0`。请指出，但不要为了修记录改被审输入。
- 方案可实施性中未定义接口、未定语义与纯编辑问题分开。

## 返回格式
- 首行：`方案裁决：PASS | BLOCK | INCOMPLETE`；另列 `实现/动态验收：未执行，不作通过裁决`。
- 列已读文件/符号与未读限制、静态/动态界限、是否输入漂移。
- 每条 finding 用稳定本路ID，标 severity（blocker/major/minor）、精确文件行号/符号、可复现反例或矛盾、最小修订建议、归属（AIFI-45本地/M003方案/外部授权）。
- 明确旧关键问题本轮 closed / partial / open；新问题单列。
- 最后列阻断通过的最小集合。不要求为凑数提建议；证据不足用 INCOMPLETE，不将“未实现”本身错误地当成 proposed 方案缺陷。
