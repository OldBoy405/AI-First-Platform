# Tools 防御性编程精简：交付就绪不把读错当未配置，回写正文与摘要同源，续办只认冻结候选

<!-- source_hash: ce0cbfcb43ff0ac8 -->
<!-- generated_at: 2026-11-18T15:23:04.004176 -->
<!-- canonical: canonical/proposals/2026-11-18-defensive-trim-tools.yaml -->

## Why

2026-11-18 对 Tools 二开代码的只读审查（逐条核实，行号见来源方案）发现三类防御性编程问题，均落在会影响“签出、放行、覆盖”的入口：
(1) 交付就绪：`readDeclaredComponents` 对 `dir-graph.yaml` 的读取错误一律返回 `[]`，`workspace.components` 不是列表时同样归为 `[]`，
    二者都被当作“未配置组件就绪要求”而放行；交付层又对 `ready` 做了一次与组件判定器重复的二次判定，且有测试只构造生产不可达的形状。
    （YAML 不可解析本身已硬失败，不属此问题。）
(2) 回写与恢复：PRD/SDD、traceability、任务索引、规格索引各自用两次以上独立读取取得正文和 `beforeSha256`，期间文件可变，
    可能把 A 的正文配上 B 的摘要；多处读取把一切错误记为“不存在”（`null`），已存在的空索引也被记为 `null`；
    已有 journal 续办时还会比较“当前”生成脚本 SHA，仅升级生成脚本就阻断在途事务。
(3) OutputGuard：Pre/Post 只认命令首行，但原因的换行检查在其输入已截首行、正则不跨行的前提下恒假，
    `escapeHatch.singleLine` 被读取却守卫一个恒假条件，是无效的配置与分支。


## What Changes

- 交付就绪的配置读取：对适用组件就绪要求的 CR，`dir-graph.yaml` 任何读取失败（含文件不存在）在文件边界报告原因，
已声明的 `workspace.components` 不是列表时报错；只有成功读取有效配置且 `workspace.components` 缺省或为 `[]` 才视为未启用。
宽松 YAML 解析不改，不扩到其他读取 `dir-graph.yaml` 的路径。

- 就绪结论只算一次：组件判定器负责条目与观测值是否匹配；交付层只合并判定器 findings，需要展示 `ready` 时由同一组 findings 推导，
删除交付层按 `ready` 的二次判定及只构造生产不可达形状的测试。保留旧合同适用范围与其他交付条件。

- 回写生成与应用的读取：PRD/SDD、traceability、任务索引、规格索引各用一次文件读取同时取得原始字节（算 `beforeSha256`）与归一换行后的正文（生成候选）；
只有文件不存在才记 `null`，空文件有自己的摘要，其他读取错误向上报错；已存在的空索引不再记为 `null`。
应用端仍独立读取目标并沿用既有 before/after 比对、路径限制和事务锁。

- 回写恢复：新事务仍使用固定生成器并校验版本；已有 journal 续办时不运行生成器，也不再比较当前生成脚本 SHA。
续办凭既有业务输入与 manifest 摘要绑定、blob 核对和目标冲突检查；manifest 中的生成器 SHA 继续记录生成来源。
“journal 续办不比较当前生成器 SHA”写入本 change 的项目级规格；不修订 `specs/ai-first-platform/SDD.md`，不为此开 CR。

- OutputGuard 逃生口：Pre/Post 只认命令首行，保留标记及原因长度检查；移除无效的原因换行检查与 `escapeHatch.singleLine` 配置项，不引入多行模式。


### New Capabilities

- **writeback-source-consistency**：回写候选的正文与 before 摘要同源于一次读取；读取错误不被当作文件不存在；中断事务只续办其冻结候选，不因生成脚本升级而阻断。
- **output-guard-escape-hatch**：OutputGuard 逃生标记只认命令首行，Pre/Post 判定一致；无多行模式和无效配置项。

### Modified Capabilities

- **evidence-delivery-contract**：交付就绪：确实未配置才能跳过组件就绪要求；配置读取失败或声明形状非法时硬失败并给出原因；就绪结论由组件判定器的 findings 单点产生。

## Success Criteria

- [ ] 对适用组件就绪要求的 CR：`dir-graph.yaml` 缺失或不可读时 evidence-check/gate 失败并报告文件与原因，不放行；`workspace.components` 不是列表时失败；缺省或 `[]` 时通过且不新增阻断。
- [ ] 声明与观测不符、组件错配时不能放行；原始原因进入交付报告，不被二次判定替换为统一文案。
- [ ] 交付层不再含对 `ready` 的二次判定；原来构造 `ready:true` 带 findings 等生产不可达形状的测试已删除，剩余用例均经同一采集器或真实 gate 入口。
- [ ] 含 CRLF 的底稿 A 生成候选后、应用前把目标改为 B，应用报告冲突且 B 原样保留。
- [ ] 不存在的目标 `beforeSha256` 为 `null`；空文件与已存在的空索引得到空内容摘要而非 `null`；非 ENOENT 的读取错误向上报错，不记为不存在。
- [ ] 中断的事务：仅升级生成脚本后仍可续办；冻结的 manifest 或 blob 改变后不能续办；新事务仍校验生成器版本。
- [ ] OutputGuard 首行标记有效、仅第二行有标记无效，Pre 与 Post 判定一致；原因长度检查仍生效；`policy.json` 与 `core.mjs` 不再含 `singleLine`。
- [ ] 项目级规格中明确写出“journal 续办不比较当前生成器 SHA”，并核实 SDD.md:476 的描述仍然成立，不需为此开 CR。
- [ ] 既有受影响测试（evidence-check、writeback、workspace-transactions、OutputGuard）按新语义更新后全部通过；被改写用例对应的保证各至少保留一个；未新增删除即无法解释的跳过。
