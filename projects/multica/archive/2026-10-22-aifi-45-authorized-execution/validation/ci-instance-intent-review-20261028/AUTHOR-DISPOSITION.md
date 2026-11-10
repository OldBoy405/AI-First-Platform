# 作者处置（不改变独立 verdict）

独立原报告见 `REVIEW-STRONG.md`，其 SHA、会话和原始源码快照见 `REVIEW-RECEIPTS.json`。该报告未运行测试；不因下列作者补充而改为 PASS。

- intent 编码器只投影 name、nonce、image 和创建时间窗，不序列化 target 或 expectedEnv。其 checksum 无认证语义；没有文件 I/O、可信目录、fsync、引擎适配或 runner 入口。
- 对独立审查指出的遗漏，补充互相独立的错误 magic、长度格式/长度不符、越界、末尾、非 Buffer、顶层类型、字段顺序/空白/转义测试。异常 UTF-8 测试可证明该样例被拒绝，但因字段校验亦会拒绝相同数据，**不能单独归因于 fatal 解码**；未宣称此分支经变异证明。
- 作者对前版小测试观察 RED→GREEN：高位 length/digest、BOM 分别为 RED，修正后 GREEN；将保持字段合法的 image 字节篡改（无重算 checksum）单独测试，移除 checksum 检查时 RED，恢复源码 SHA `d69334f5a419f6725553cdacab1704f1dd947aec3eada63d5b65c6e0a0eaefbc`；移除 canonical 比较时，独立空白测试 RED，恢复相同 SHA。
- 四文件组合：`node --test scripts/aifi45-db/run.test.mjs scripts/aifi45-db/instance-ownership.test.mjs scripts/aifi45-db/instance-lifecycle.test.mjs scripts/aifi45-db/instance-intent-record.test.mjs`，作者在复审快照 `dbd8075846c0020d03b2fc21ca052322826455af3c8522475499873fa0d6614b` 运行 135/135，fail 0，skip 0。复审 `REVIEW-RECHECK.md` 确认部分有效构造，同时指出长度上限、fatal UTF-8 及其他测试的分支归因限制；原报告及结论不变。
- 按复审补三个独立的防护控制测试：总长超限时不遍历，并有上限边界进入遍历的正向对照；payload 超限时不访问 payload；有效记录解码时检验真实 TextDecoder 实例的 fatal 配置。分别删除总长度上限、删除 payload 长度上限、改 fatal=false，三项单独变异均 RED，逐次恢复同一源码 SHA 后 GREEN。fatal 配置测试不替代非法 UTF-8 样本的端到端拒绝归因，也不证明外部文件安全读取。其余边界归因与未覆盖问题仍以原复审为准。
- **最新作者组合 138/138，fail 0，skip 0**；编码测试 SHA `7f2e5f40580d6126e5e1b5104f9b0dd4ee76bfc1ecea8d31d4e2bd35e3eb4787`，晚于复审快照，未被该报告复核。结果均为 Node 纯函数和 fake-I/O，不是任何真实 DB/容器或完整 CI 证据。

仍未实现：实际文件安全读取/权限、持久 journal、平台命名空间同步、固定引擎及镜像、进程树退出、丢回执恢复、正式 provisioner 和 CI 路由。本机 Windows 目录 fsync 的独立临时文件探针及其局限见 `../ci-instance-journal-design-20261028.md`；只读句柄返回 EPERM，但读写句柄的目录 fsync 返回成功，二者都不证明断电后的命名空间持久性。
