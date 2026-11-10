# 最终版本变异配方

基于 `source-sticky-green/supervisor-collector.mjs` raw SHA `fa9d4013bf5220ef63ffdc972b636c9aa096ec631eb2fabe4d37325305f122c7`，对 UTF-8/LF 字节各做唯一一次文本替换，隔离目录以 wx 创建，不改 live 工作树。`MUTATION-FINAL.json` 用的是旧测试 `source-sticky-green/supervisor-erase.test.mjs`（raw SHA `55fdfa64ddc5ada392e3c5c7a003a96fba7139b906d2457c44350b25e1ab9b75`）；`MUTATION-FINAL-TESTS.json` 以最终测试 `source-final-rechecked/supervisor-erase.test.mjs`（raw SHA `023725bb6893d3f54018528c4893ce1ccd6e3be16ca4a90f92344fc9f8bbc9fe`）重新运行两项，源码/测试 hash 前后不变。两份结果记录变异体 raw SHA、目标断言命中和清理；变异体文件没有另存。

- `late_wipe`：删第二 EOF 的 `finally { erase(); }` 中 `erase();`，并在 `result()` 的 `if (!decoded) return fail('INVALID_INPUT');` 前调用 `erase();`。模拟推迟至 result 才擦；四个早擦除断言失败，额外故障注入也失败。
- `late_failure`：将 `if (!failure) failure = Object.freeze(...); erase();` 改为 `if (!failure) { erase(); failure = Object.freeze(...); }`。模拟擦除成功后才记录错误；故障注入的首错保留和重试断言失败。

两项仅验证测试可检测对应局部回退；并不能检测全部字节复制、同 realm 篡改或 GC 后明文残留。
