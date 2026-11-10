# intent snapshot 定向变异（作者）

基于 `source-final-v2/` 的四个 raw 字节快照；对源码在独占目录内做唯一文本替换，每项运行 `node --test --test-reporter=tap instance-intent-record.test.mjs instance-intent-snapshot.test.mjs`，原 stdout/stderr 只在内存用于派生计数，未存储或输出。每个变异 exit 1、35 测试、0 skip，且目标测试项 `not ok`；每个仅清理了验证过路径和 hash 的本次文件，目录均确认空后移除。变异体文件未保存，以下原始字节 SHA 可复核重建结果。

| 变异 | 替换规则摘要 | mutant SHA-256 | 目标失败 |
|---|---|---|---|
| shared | 将 shared-or-resizable 拒绝改为仅非 shared 的 resizable 拒绝 | `478c3a4691cc0b64f9bbcbbbff16743dbae729849dd33ee7d7623a3db296573d` | shared backing |
| resizable | shared-or-resizable 拒绝改为只拒绝 shared | `9aa63c511b4e22835f0b3de1c038d5674a0af32b32d4786e260ebca5056aaa28` | resizable |
| kind | 去掉 `!types.isUint8Array(input)` | `65a4ebbf3e40bec2155972af60eeafaab18924b7ec68a783b7295bb293662994` | 有效记录的非 byte 伪装 |
| total | 删除实际总长度上限 | `66d909e5c18ff675ac93c37a390a7b7fc990a5bf0814e0ff68ab9da7ca1a7edd` | 超限不得分配，边界须分配 |
| payload | 删除 `Number(length) > maxPayload` 分支 | `3ea7667c04630263ce48db64ff5d750ebea88069f7d85a85ac77044df723b275` | 超限不可进入 payload 解析 |
| offset | view 构造时以 0 替代实际 offset | `41cfe838130199b75ee580a7e1f0dd9631971c224cd7de01b786e833d1e05a4d` | 非零 offset 合法记录 |
| own_length | 以 `input.length` 代替内建 getter | `d3b636ec78993ba5b053d283cc4e070c87f136e5e401b3c76e3c5f74804b7894` | 输入 own 属性不可信 |
| wipe | finally 不清零 | `6be6e8a1953c6f304be20f37e5f2f47cac81ef69c2e97d928cf6084d3f78d813` | 私有快照清零 |
| wipe_error | 捕获并吞掉清零异常 | `09463fbf02e53183e5f9980d3823f7cc8270865675152fa2d3cfc2f6c20152e9` | 擦除失败不能发布成功 |

这些只证明测试能检测列出的局部变异；不是强档独立审查、并发真实攻击、来源认证、真实 DB/容器或 Gate3 证据。source/test 四文件 hash 在作者绿色测试前后不变，见 `GREEN.md`。
