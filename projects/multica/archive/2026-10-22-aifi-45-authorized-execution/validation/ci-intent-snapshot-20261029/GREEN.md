# CI intent snapshot GREEN（作者）

作者在 `source-final-v2/` 明确选择 `instance-intent-record.test.mjs` 与 `instance-intent-snapshot.test.mjs` 运行 Node 纯内存测试：exit 0，**35 tests / 35 pass / 0 fail / 0 skipped / 0 cancelled**。选择的两个文件均真实执行，结果不含其它组件或旧快照。输入和输出只用于派生计数，未保存或打印原 stdout/stderr；环境按系统必要变量白名单，未证明 OS 级网络隔离。

以下四文件测试前后 raw SHA-256 一致；测试期间仅验证此受控快照。源码根的对应四文件在快照时按原始字节复制，未做换行归一化：

| 文件 | SHA-256 |
|---|---|
| `instance-intent-record.mjs` | `f32e0e7e6f11870d1f53c654b5798441ebde7db9620f03a29857677f9918b906` |
| `instance-intent-record.test.mjs` | `66206118e5f036baab5d34c0e0ee907dd3de4458428c1ad4d1083fbba8ad0cc9` |
| `instance-intent-snapshot.test.mjs` | `dbea8a4bfda44292ae6122aa2437fec8a09ba541363f074a2330f931c114f484` |
| `instance-ownership.mjs` | `5c4785ae4a03a951a00a72248528ba97b11163caf5675c8304e6a8c656e05288` |

`RED.md` 为旧源码及测试的独立保存快照；`MUTATIONS.md` 为同一最终测试版本上的九种作者变异。`source-final/` 与 `source-final-review/` 是扩展测试期间保存的旧快照，不是本次最终测试输入，保留不覆盖。共享输入时序是插桩模拟，非真实并发实证。拒绝 shared/resizable backing、校验 byte view，并在真实长度上限后复制指定 view；解析和 SHA 读同一快照。成功与失败时尝试清零私有快照，擦除失败不发布成功。不能保证清除输入、JS string、原生库复制或异常终止的内存，也不防任意同 realm 内建函数篡改。

与旧测试不同，新实现允许在总长内复制整个记录，然后拒绝超过 payload 上限的声明；它只保证超限 payload 不进入解析，不保证没有复制。checksum 不认证来源、身份、新鲜性或清理权限。未接线生产 journal/引擎，不证明数据库/容器生命周期或 Gate3；strong 独立复核因提供商额度不足仍待完成。
