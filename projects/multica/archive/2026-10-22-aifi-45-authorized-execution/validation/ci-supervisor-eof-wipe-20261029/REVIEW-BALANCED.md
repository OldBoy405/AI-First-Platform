# AIFI-45 supervisor collector 独立复跑（最终测试快照）

## 结果

- 实际 live 目录：C:/Users/GOBAO/Downloads/AI/multica/scripts/aifi45-db/。
- Node v24.15.0；按请求执行四文件 TAP 单元测试。仅继承 SystemRoot、WINDIR；子进程输出在内存中捕获，只提取固定计数。
- 实测：tests 66、pass 66、fail 0、skip 0、cancelled 0、todo 0；退出码 0。
- 运行前后六文件 raw SHA 一致，且与 source-final-rechecked/ 及指定值一致；测试后再次核对仍一致。

| 文件 | 运行前 raw SHA-256 | 运行后 raw SHA-256 |
|---|---|---|
| supervisor-collector.mjs | fa9d4013bf5220ef63ffdc972b636c9aa096ec631eb2fabe4d37325305f122c7 | fa9d4013bf5220ef63ffdc972b636c9aa096ec631eb2fabe4d37325305f122c7 |
| supervisor-erase.test.mjs | 023725bb6893d3f54018528c4893ce1ccd6e3be16ca4a90f92344fc9f8bbc9fe | 023725bb6893d3f54018528c4893ce1ccd6e3be16ca4a90f92344fc9f8bbc9fe |
| supervisor-collector.test.mjs | 59425758881ffdb4d3a1850d8891a0419f647d089ff602490fe4035b2ba3fd7f | 59425758881ffdb4d3a1850d8891a0419f647d089ff602490fe4035b2ba3fd7f |
| supervisor-protocol.mjs | 92329bb48d9eed2b97eabd26b1b883dfb2b1684278ce91f593ecf3d95e3ea5c8 | 92329bb48d9eed2b97eabd26b1b883dfb2b1684278ce91f593ecf3d95e3ea5c8 |
| supervisor-protocol.test.mjs | b7d4dd793cb6cf69d6cdd93c293cee3363d4c1d3deed44cda41af7c2b9c77705 | b7d4dd793cb6cf69d6cdd93c293cee3363d4c1d3deed44cda41af7c2b9c77705 |
| supervisor-buffer-brand.test.mjs | abaa1f9ffe6cce3dab655054ba21763d642e722999402e186a54cc75caf55448 | abaa1f9ffe6cce3dab655054ba21763d642e722999402e186a54cc75caf55448 |

## 历史复跑不是最终测试证据

- 本复核者先前 55/55：collector 9c4d561f26780a49bbf8dc09b7e35fee682732182785fcded8d38e0846c34fc3；erase 测试 9133b4e95bff56d152704a465af6aae4d4c7c57e7a376264a8e60ee188ee0b13；collector 测试 fb6d2f412799bd7b88d6b7ee7c3874973efe8e942b9e830c81966009dfea9437。
- 本复核者先前 59/59：collector 已为最终源码 SHA；erase 测试仍为 55fdfa64ddc5ada392e3c5c7a003a96fba7139b906d2457c44350b25e1ab9b75；collector 测试仍为 fb6d2f412799bd7b88d6b7ee7c3874973efe8e942b9e830c81966009dfea9437。两次均不能代表本次最终测试快照。

## 风险与范围

- 先前针对相同最终 collector 源码的内存故障注入：擦除连续两次抛错时原始异常可逸出；当时私有缓冲仍含明文，需后续事件重试才能清零。注入情况下后续重试成功且清零后重复事件不再擦除；不证明真实故障一定发生或调用方一定继续重试。调用方记录逸出异常时可能泄漏异常内容。
- 此前源码检查时脱敏错误，测试夹具标记曾被误回显；经核其来自硬编码测试夹具，未发现真实凭据来源。不能仅据此排除与真实凭据偶然相同。本文不重复该值。
- 未运行 DB、容器、外网或真实 CR；未执行真实进程树实验。未验证操作系统级沙箱或网络隔离。测试不能背书真实资源、来源认证、进程退出、清理授权或端到端行为。backend receipt：unknown。
- 本次未复跑变异实验；历史记录不替代本次独立实测。
