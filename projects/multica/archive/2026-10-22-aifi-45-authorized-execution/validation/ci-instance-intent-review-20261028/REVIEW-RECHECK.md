## 限定结论

**新测试补充了多项有效负例，但不能据此关闭全部边界覆盖发现；UTF-8 fatal 归因问题仍未解决。** 本轮仅静态阅读，未运行测试、容器或 DB，未修改文件。原 BLOCK 保持，不允许接线。

### SHA-256 核验

自行计算 raw-byte SHA-256，均匹配：

- `../multica/scripts/aifi45-db/instance-intent-record.mjs`  
  `d69334f5a419f6725553cdacab1704f1dd947aec3eada63d5b65c6e0a0eaefbc`
- `../multica/scripts/aifi45-db/instance-intent-record.test.mjs`  
  `dbd8075846c0020d03b2fc21ca052322826455af3c8522475499873fa0d6614b`

以下行号均指该 `.test.mjs`。

### 1. 有效 payload 基础上的测试：哪些归因较强

| 测试 | 静态判断 |
|---|---|
| magic/version，L44 | 从有效编码结果等长替换版本，payload、长度及 checksum 保持有效；能针对 magic/version 拒绝。 |
| 长度前导零，L45 | payload 不变，数字值仍等于实际长度，header 增长也自然计入偏移；能针对非 canonical 长度语法。 |
| 错误结束标志，L48 | `END`→`FIN` 等长，其他边界有效；能针对结束标志检查。 |
| canonical 空白、字段顺序、转义，L66–68 | helper 重算正确长度和 digest；JSON 解析后仍是有效预期字段。能针对 canonical 比较，而非靠字段无效拒绝。 |
| payload 篡改但保留 digest，L26–30 | 修改后的 image 仍是有效 hex；能针对 checksum 比较。 |
| 重复键、额外字段，L85–92 | 最终字段值仍有效，长度和 digest 正确；能针对 canonical 拒绝。 |

因此，旧发现中“缺少这些场景”的部分已有源码层面的补充，不能继续一概称为完全未覆盖。

### 2. 仍可能由其他分支拒绝，不能证明指定防护有效

- **超限 payload，L55–57——主要剩余问题。**  
  `frame(' '.repeat(4097))` 的长度和 digest 正确，但 payload 是纯空白，**不是有效 JSON**。删除 `Number(length) > maxPayload` 检查后，仍会被 JSON 解析拒绝，测试可继续绿。  
  此 frame 总长为 **4188 bytes**，也没有触及 **4196 bytes** 的总长度上限，不能证明该上限有效。

- **非十进制长度，L46。**  
  使用有效 payload 是改进，但移除长度正则后，`Number('NaN')` 仍导致后续长度一致性检查失败。因此不能单独证明长度语法校验有效。

- **声明长度 +1、截断、尾随内容，L33–41、L47。**  
  都是有效记录基础上的真实负例；但会同时破坏总长度关系与 suffix 检查，不能分别证明这两个检查各自有效。拆成独立测试只分开了输入场景，没有隔离拒绝分支。

- **非 Buffer，L59–61。**  
  即使移除显式类型检查，字符串仍可能因缺少 Buffer 方法而抛错，满足裸 `assert.throws`。能证明该样例被拒绝，不能证明显式类型门禁或受控错误路径。

- **顶层数组/null，L64–65。**  
  即使删除顶层形状检查，后续公开字段验证仍会失败。不能单独归因于 object/array/null 检查。

- **高位 header 字节，L73–83。**  
  对防止 latin1 被改为会折叠高位字节的 ASCII 解码有价值；但不能分别证明长度正则或 digest 正则有效：其他数值/摘要比较仍可拒绝。

这些是**测试归因限制，不是已发现的 codec 接受漏洞**。

### 3. UTF-8 fatal：旧发现仍成立

L108–115 仍执行：

```js
payload[2] = 0xff;
```

它破坏的是 `"name"` 键中的 `n`。若取消 `fatal: true`，replacement 解码会产生错误键名，随后因缺失有效 `name` 而拒绝；测试仍可能通过。

因此：

- 正确重算 digest 排除了 checksum 作为拒绝原因；
- **没有排除字段验证作为拒绝原因，不能证明 fatal 解码有效。**
- 当前合法 canonical payload 的字符受限为 ASCII，简单换一个非法字节位置也未必能隔离 fatal；单凭最终 `throws` 不足以证明这一内部防护。
- BOM 测试与非法 UTF-8 测试是不同性质，不能用前者补足 fatal 归因。

### 4. 剩余覆盖范围

尚无独立证据证明 payload/总字节上限及其临界值；digest 长度/大小写、缺失 header 分隔符等语法矩阵也未完整覆盖。另 L94 的“creation window”只测了非法时间字符串，未测试倒置时间窗或超过 120 秒。

**最终仅认可：新增 header 和 canonical 场景的静态构造有实质改善；部分拒绝仍存在其他分支兜底，不能宣称目标检查均已验证，更不能宣称测试已通过或解除原 BLOCK。**