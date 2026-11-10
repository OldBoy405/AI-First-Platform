## 结论

**原 BLOCK 保持，不允许接线。** 本次仅完成静态只读审查；未修改文件，未运行测试、DB、容器或被审源码。编码器不能作为可信身份、操作授权或 journal 持久化完成的证明。

### 1. Raw-byte SHA-256

两份文件均与给定值完全一致，计算时未做换行规范化：

| 文件 | SHA-256 |
|---|---|
| `../multica/scripts/aifi45-db/instance-intent-record.mjs` | `d69334f5a419f6725553cdacab1704f1dd947aec3eada63d5b65c6e0a0eaefbc` |
| `../multica/scripts/aifi45-db/instance-intent-record.test.mjs` | `fc1e195d6370452b4a171bded116470ba69e97b690bdcc61e703fcaa0f844faa` |

已完整阅读 `instance-ownership.mjs`，以及 workspace 中：
`projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/ci-instance-journal-design-20261028.md`。

### 2. 源码边界检查

- **公开投影正确**：`instance-intent-record.mjs:11–16` 只构造 `name / nonce / image / createdAfter / createdBefore`。在普通可信数据对象前提下，没有把整个 target、`expectedEnv` 或额外 secret 字段交给 JSON 序列化。
- **长度与字节边界**：长度取 UTF-8 Buffer 字节数；decode 限定 Buffer、总长度、十进制长度格式、4096-byte payload 上限，并要求 payload 后恰好是 `\nEND\n` 和 EOF。未发现静态可见的截断、尾随内容或长度越界接受路径。
- **UTF-8 与 canonical**：fatal UTF-8 解码；`ignoreBOM: true` 保留 BOM，使其不能被静默剥除后接受。重新投影并要求 `JSON.stringify(intent) === text`，可拒绝额外字段、重复键、不同字段顺序、空白及非 canonical 转义。
- **checksum**：覆盖原始 payload，而非重新序列化结果；header 使用 latin1 后严格匹配，未发现高位字节被 ASCII 折叠的路径。

以上是静态判断，不是测试通过或完整安全证明。

### 3. 发现：测试证据不足，可能出现局部“假绿”

**中：缺少独立协议边界矩阵。**  
现有测试未分别锁定错误 magic/version、前导零或非法长度、声明长度偏差、payload 上限、错误终止标志、非 Buffer、JSON 顶层类型，以及字段顺序/空白/转义等 canonical 分支。源码目前存在相应防护，但不能把已有测试绿灯扩展解释为这些边界均经过验证。

**低：invalid UTF-8 测试不能单独证明 fatal 解码有效。**  
`instance-intent-record.test.mjs:74–80` 把 payload 的第 2 字节，即 `"name"` 键中的 `n`，改成 `0xff`。即使解码器退化为 replacement 模式，键名也会改变，后续必填字段校验仍会拒绝。因此该负例可能在 fatal 防护失效时继续通过。**这是防护归因不足，不是已证明存在非法 UTF-8 接受漏洞。**

正面观察：篡改 image 的测试仍保留有效字段格式，能够针对 checksum；重复键测试保留最终有效 nonce，能够针对 canonical，而非仅靠字段无效拒绝。

### 4. secret 与读取风险

- 未发现该模块直接输出、写盘或记录 secret；decode 对解析/字段校验异常统一报错。
- 但这**不证明完整 secret 防护**：encode 会读取调用方属性并执行校验；getter/Proxy 可抛出任意异常，encode 没有统一异常净化。未来调用层不得持久化任意异常消息或 stack。
- 模块仅依赖 Node crypto/util 和纯校验模块，没有文件、网络、数据库或进程操作。**它接收的是已读取的 Buffer，不负责安全读文件**；可信 root、祖先目录、链接、ACL、排他性及 TOCTOU 均未解决。上游也不能先无限量读文件，再依赖这里的长度上限。

### 5. 伪造与持久化边界：仍为阻塞项

任何人都能构造符合字段格式的 payload 并重算 SHA-256；`assertInstanceIntent` 只验证 image 是 64 位小写 hex，**不证明它属于批准镜像**，也不证明 nonce 来源、记录新鲜性或容器归属。decode 使用固定占位 `validationEnv` 只用于公共字段校验，**没有恢复或证明真实 expectedEnv**。

本模块没有排他创建、完整写入、fsync、close/no-replace 发布、目录持久化、writer 永久失败或恢复协调。设计文档记录的 Windows 目录 fsync 阻塞仍然存在，读回成功或 checksum 正确均不能替代持久化证明。

**最终裁定：保持未接线；lifecycle BLOCK、CI BLOCK、TC-RUN-003 与 Gate3 NO-GO 均不变。**