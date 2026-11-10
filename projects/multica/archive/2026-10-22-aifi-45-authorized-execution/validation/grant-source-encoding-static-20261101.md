# 执行授权源字符边界调查（2026-11-01，静态）

**INCOMPLETE / 尚未实现或动态验证。** 两名只读分析者先后调查；requested `GBClaude/claude-opus-5-5:high`，actual unknown。首位分析者误执行 `ls`（只列当前工作区根），已披露；第二名仅只读。结论以二次交叉检查为准，不能将推断计作签发／消费完整 TC。

## BOM 判空的不一致

Go `server/internal/governance/execution_authorization.go` 的 `executionNonEmptyString` / `executionStringArray` 使用 `strings.TrimSpace`，不视 U+FEFF 为白；T `tools/.../lib/execution-authorization.mjs` 的 `text()` 使用 ECMAScript `trim()`，将其视为空白。静态路径显示初始请求的 goal、target_version、delivery_targets / acceptance / prohibitions 元素、敏感动作部分字段可能因此在 M 签发后被 T 拒绝。allowed_paths 在规范化路径校验上还有不同约束，须按各字段生产调用具体证明，不能一概而论。实际 HTTP 到 head 的完整链、历史 CR 恢复、签名与跨语言消费尚未运行验证。

**不能直接修改共享 parser。** `parseExecutionScopeBody` 不仅用于初始签发，还用于 `execution_authorization_read.go` 历史冻结来源回读和后续链校验；改其共享 helper 会让历史签过但尚未处理的来源不能再回读。若要收紧，应审议仅限新初始签发的单独校验，明确是否／如何处置已有记录并做回放与真实入口测试；不得伪称这会修复已经签发的 CR。撤销 reason 的判空属于另一合同，不能顺手更改。Go 的 U+0085 限制比 JS 更严，不是允许放宽的理由。

## JSON escaped surrogate 另一个未决边界

Go `encoding/json` 与 JS `JSON.parse` 对字符串内的孤立 `\\ud800` 类转义可能产生不同值；Go 反序列化后的 scope 与 T 对原始冻结源的解析和 binding 可能因此不一致。必须逐字段和签发/回放链验证，包括转义合法 pair、孤立 high/low surrogate 与拒绝或兼容策略，不可把这一问题当成 BOM 修复已覆盖。

## 安全测试限制

`internal/governance` 父包的测试入口涉及 DB；完整包或原 HTTP fixture 未经额外隔离预检禁止运行。源码函数快照可以验证有限局部逻辑，但不能当作真实签发链或生产运行证据。若引入独立可测试 helper，要先评价是否仅为测试增加架构、其调用是否只覆盖新签发、初始化和所有临时/缓存文件的生命周期；不能随意读取 HOME、用户配置或旧 DB。仍需 B4/兼容性决定时按 STDD 正式处理。
