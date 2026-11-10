# 独立 balanced 初审：BLOCK

**结论：BLOCK。** 两个指定测试和静态 SHA 核对通过，但本次审查启动时误运行过一次 `node --version`；它不是两个指定测试文件的 Node 进程，违反执行白名单，不能声称本次操作完全合规。其输出仅为版本号，无测试数据；应由授权方决定是否允许重新做合规复核。本文是 balanced 初审，**不是 strong 复审，也不能替代不可用的 strong**；backend actual **unknown**。

## 范围和证据

只读比较当前 `../multica/scripts/aifi45-db/instance-intent-record.mjs`、两个指定测试与 `source-before/`、`source-final-v2/`；另读了本地 `instance-ownership.mjs`、计划和作者 RED 摘要。当前三个文件逐原始字节匹配 v2，源文件匹配指定 SHA。测试前后以下 11 个源码、测试与依赖文件的 raw SHA 全部匹配各自预期且逐项不变（11/11）：

| 文件 | raw SHA-256 | 位置 |
|---|---|---|
| instance-intent-record.mjs | f32e0e7e6f11870d1f53c654b5798441ebde7db9620f03a29857677f9918b906 | 当前、v2 |
| instance-intent-record.test.mjs | 66206118e5f036baab5d34c0e0ee907dd3de4458428c1ad4d1083fbba8ad0cc9 | 当前、v2 |
| instance-intent-snapshot.test.mjs | dbea8a4bfda44292ae6122aa2437fec8a09ba541363f074a2330f931c114f484 | 当前、v2 |
| instance-ownership.mjs | 5c4785ae4a03a951a00a72248528ba97b11163caf5675c8304e6a8c656e05288 | 当前、before、v2 |
| instance-intent-record.mjs | d69334f5a419f6725553cdacab1704f1dd947aec3eada63d5b65c6e0a0eaefbc | before |
| instance-intent-record.test.mjs | 7f2e5f40580d6126e5e1b5104f9b0dd4ee76bfc1ecea8d31d4e2bd35e3eb4787 | before |

没有 before 的 snapshot 测试；作者 RED 是历史证据，不是本次复跑。

## 测试

使用两个独立 `node --test --test-reporter=tap` 调用，仅指定各自文件；白名单仅系统变量 SYSTEMROOT/WINDIR/COMSPEC/PATHEXT/TEMP/TMP 与收窄 PATH，stdin 禁用，stdout/stderr 完整内存捕获，只提取汇总计数与是否含两个测试 fixture 标记，未保存或输出原始流。没有 OS 级网络隔离证明。节点版本为 v24.15.0，版本获取有上述违规。

| 文件 | exit | tests / pass / fail / cancelled / skipped / todo | stdout / stderr bytes | 标记命中 |
|---|---:|---|---|---|
| instance-intent-record.test.mjs | 0 | 26 / 26 / 0 / 0 / 0 / 0 | 4314 / 0 | 否 |
| instance-intent-snapshot.test.mjs | 0 | 9 / 9 / 0 / 0 / 0 / 0 | 2065 / 0 | 否 |

测试与 hash 子项 PASS 不覆盖执行白名单违规，不是总 PASS。无 DB、容器、真实 CR 操作；未写删固定 /tmp 文件。审查报告是唯一有意创建的文件。

## 代码审查

- 旧版直接使用调用方 Buffer，校验和与解析可能读到不同内容；新版先验证真实 Uint8Array 内部类型及 Buffer 形状，内建 getter 获取实际 backing、offset、byteLength，拒绝 shared/resizable，限制实际长度后分配独立非池快照。detached 在构造 view 时失败并固定化；非零 offset、池 view 不因输入自有 length/buffer/method 造假而改变复制范围。测试含伪 prototype、Uint16Array、代理、跨 realm 真字节 view 和 offset 正例；Buffer 形状不是来源认证。
- 复制后帧分隔、长度、摘要、payload、UTF-8 和 JSON 均从该同一快照或其子视图读取；不可共享、不可调整的正常 backing 在单线程同步复制中不受外部 worker 并发写入。约束仍依赖标准内建函数与非敌对同 realm，见下。
- 实际总长 >4196 在分配前拒绝；边界 4196 允许分配。声明 payload >4096 在有界复制后、payload 子视图访问前拒绝。新测试分别观察分配次数和 payload 子视图访问，并有 4196/4096 正控；删除对应 guard 会改变可观察计数，非只靠后续坏 JSON 恰好失败。此为静态断言分析，未执行变异测试。fatal UTF-8 另有 decoder 配置观察正控与坏编码拒绝，保留旧 wire/canonical 校验；兼容性限于这些测试覆盖，非全平台证明。
- 分配成功后 copy、解析和返回均在 finally 内，捕获的 fill 尝试擦除完整私有分配；擦除抛错会覆盖成功返回并经外层 catch 固定为拒绝。测试观察嵌套调用分别擦除、失败输入擦除、擦除抛错不发布，并确认调用方输入不清零。分配前/分配失败没有可引用快照；不能保证调用方内存、JS 字符串、运行时或 native 副本擦除，也无法证明机器级物理擦除。

## 红旗与剩余风险

1. **可从代码推导的同 realm 完整性绕过（未执行 exploit）**：摘要之后调用可修改的 `TextDecoder.prototype.decode` 并向其传入快照的 payload 子视图；若同 realm 恶意代码先替换该方法，可在原 decode 前修改该子视图为另一合法 canonical 内容，随后解析和返回的内容不再是已摘要内容。当前测试本身也通过修改该原型演示可插桩。相似地，动态 Buffer 原型方法和其他内建对象可被替换、窥视或篡改；预捕获的 fill 若在导入前被替换也不能保证擦除。此风险要求同 realm 代码/内建函数已被攻击者控制，不是仅凭正常字节 Buffer 可在隔离 realm 中实现的竞态；若需求把同 realm 对抗包括在内，这是阻断性漏洞，否则必须明确把它排除并控制运行环境。未运行额外 Node PoC，不能声称已动态验证。
2. `Buffer.isBuffer` 在内部类型判定之前；其基于原型链的检查对恶意 Proxy/原型可能触发用户代码。异常被固定化不等于无副作用，也不构成 JS 沙箱。测试仅验证简单代理被拒绝，未验证所有副作用。
3. 摘要是无密钥完整性校验，不认证来源、不赋予清理权限；当前 codec 是草案，不能把单元测试当成生产 journal 已接入或资源可安全删除的证据。测试中的共享变更是模拟而非真实并发或误删证明。
4. 测试范围没有独立 strong 审查、变异实跑、其他 Node/平台兼容矩阵、生产集成或部署/全验收；backend actual unknown。对以上同 realm 风险和测试白名单违规需授权裁决及后续复核，不能报告全验收通过。
