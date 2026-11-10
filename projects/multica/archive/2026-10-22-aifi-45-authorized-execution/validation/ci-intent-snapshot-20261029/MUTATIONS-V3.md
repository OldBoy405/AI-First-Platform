# intent snapshot V3 定向变异（作者）

基于 `source-final-v3/`，以与旧 `MUTATIONS.md` 同样的唯一文本替换分别构造十一个变异；每项 `node --test --test-reporter=tap` 两个测试文件，exit 1，36 tests、0 skip，目标 `not ok` 均命中。仅在内存提取固定计数/测试名；不保存原输出。临时实验目录独占创建，仅删除过路径及 raw SHA 已核的本次文件，逐一确认目录为空后移除。

| 变异 | 相对 V3 规则 | mutant raw SHA-256 |
|---|---|---|
| shared | 移除 shared 拒绝但保留 resizable 拒绝 | `69938eed292bef5ea4cfbb2bcab4d36c984edd4fc30eb0cd47c9ca0e156e9f56` |
| resizable | 删除 resizable 拒绝 | `96df4c2e5efbc63f3baa1158ef9412ea4f5224b373824aaa1070ea84920ef020` |
| kind | 删除 `types.isUint8Array` 判定 | `3136b68a923a04f2b694873dace55dd95ff32a3c6ffa68c6fa1714aca6e18af7` |
| total | 删除实际 view 总长度限制 | `8da82efca77a45b333432650f8921b25feceba74d074b619a934b7f946287e9e` |
| payload | 删除 payload 长度限制 | `1c518bce654a4d68020dd212d31c0ccd16f073a6c6fa01ea6d385158287eb524` |
| offset | 复制时使用 offset 0 | `49bc92ec6ea3ad6f8c0fd8c794616fe41eb9dac7b45735f5b02a0a54e82e8b7e` |
| own_length | 读取 `input.length` 代替内建 getter | `f5ebe1991d419ea7d534be9f468789a741063592332d52ff15e9e565e5b5458c` |
| wipe | 删除 finally 清零 | `519cc0ffcf34f3e5759acc27ed1bd139ac10424febb4ee0fc1e6a326aaee1812` |
| wipe_error | 捕获并吞掉擦除异常 | `f44b5d8895a68b305569f468e5db5f54dfd942fdd60b70e9f56284c43a422cc5` |
| late_decoder | 把捕获的 decode 恢复为运行期 `.decode(payload)` | `5a1e8d0f48944eb4bae2cb01caf3642a4cfcc587c9c728156f3d94f791a6632c` |
| fatal | 把 `fatal: true` 改为 `fatal: false` | `25bbf44292d458fecd8ba571d2d300e2a17b8f376ae1e4273b2aca49220da8ee` |

payload 长度测试确认有界复制后拒绝超限解析，并有 4096 字节正控进入解析；不是「超限 payload 从未复制」。以上仅检测所列代码变异，不证明来源认证、真实并发、生产接线或 Gate3。
