## 审查结论

**通过信封互操作复跑，但不能据此声称已覆盖前驱错误拒绝或完整入链。** 未修改文件。

- `interop_test.go` 动态导入 tools 仓真实 Node signer/verifier，并调用真实 Go `governance.VerifyControlEnvelope`；两帧使用运行时生成的 Ed25519 密钥，Go 比较了验签返回的原 payload 字节。
- 首帧签名翻转后，Node 和 Go 都要求返回明确的签名无效错误；缺少 Node 或协议文件会失败，不会跳过。正向结果并非仅由同一实现自我对照。
- **覆盖缺口：**第二帧前驱是测试自行构造的首帧 payload SHA，Go 独立重算并比较，但没有构造错误前驱并验证链写入器拒绝。底层信封验签器本身也不检查链连续性；不能把该测试当作前驱负例或完整入链证据。
- 源码路径上未发现 DB 调用：独立子包不运行父包 DB `TestMain`；密钥在 Node 内存生成，未加载真实密钥。复跑未访问 DB 或容器；该判断基于代码路径而非系统调用跟踪。

## 复跑

在 `multica/server` 清空 `DATABASE_URL`/`PG*`，禁用 Go 依赖网络下载后执行指定命令：

`go test -v -count=1 ./internal/governance/crosslang_test`

结果：**1 个顶层测试、4 个子测试全部 PASS**，包耗时 0.875s。Node 为 v24.15.0。

## SHA 与风险

- `server/internal/governance/crosslang_test/interop_test.go`：421 行、14,774 原字节；SHA-256  
  `bcec35e7f885ca209e03d3ccc0000cc73dae95d44e467be28e8a7aeb2317bed4`
- 按源码中的 JSON 字段及序列化规则独立重建，首帧 payload 为 276 字节，其原字节 SHA-256 为  
  `a83b6892cb2eb8c810dc05c1f7fa624d975ac19d67373d351594a088ee1d011c`  
  这是**源码重建值**，不是本次测试日志直接打印的运行时值；测试内部另有 Node/Go 重算比较。
- 421 行中临时脚本、跨进程序列化和错误诊断大体有理由；`node_verified`、重复 sequence 字段及部分重复断言可精简，但不是阻塞问题。
- 依赖 PATH 中的 Node、Go 模块依赖及独立 tools checkout；默认路径假定两个仓库为兄弟目录，`-trimpath` 可能破坏 `runtime.Caller` 回溯。可用 `AIFI45_TOOLS_ROOT` 显式指定；缺依赖会失败而非假绿。Windows 本机通过，其他平台未复跑。

## 归档补充限定

上述信封互操作测试不能证明错误前驱会被拒绝、真实 writer 的入链行为、DB 行为或可信 B 的建立与绑定。
