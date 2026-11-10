# 迟换 decoder 方法 RED

独立 balanced 复核 `REVIEW-BALANCED.md` 静态指出：可在同 realm 晚替换 `TextDecoder.prototype.decode`，令 checksum 后的私有 payload view 被改成另一合法 intent；旧报告保留，actual backend unknown。

作者增加定向测试，旧源码与新增测试保存在 `source-late-decoder-red/`。no-DB 运行两个指定文件：exit 1，36 tests、35 pass、1 fail、0 skip；唯一失败为新增「模块初始化后替换 decoder 不得改写已验证 payload」，目标断言命中。原 stdout/stderr 仅驻内存，不保存、不输出。

- 源码 raw SHA `f32e0e7e6f11870d1f53c654b5798441ebde7db9620f03a29857677f9918b906`
- 新测试 raw SHA `885bc1462d68d7e79051ca35894cee158595ea25ceb389ff00935b7468f0aea3`

这是受控的同 realm 插桩，不是对全部同 realm 篡改的威胁模型保证。修复在可信模块初始化时捕获 decoder 方法；其他内建、加载前篡改、输入和运行时副本仍属未覆盖边界。新版测试在 `GREEN-V3.md`，strong 独立复核未完成。
