# Supervisor 解析副本清零：作者记录

## 问题与修复

首轮强审在旧 decoder `bed82664f2f17918b47302a94255e3061cbce9f516f578a074a997671b75452c` 下实测：`Buffer.from` 产生的池化副本可在调用结束后从同进程 Buffer 池读出 canary；collector 清零只覆盖自己的缓冲，不覆盖 decoder 副本。原审阅及所用四个旧源码/测试快照保存在同目录 `REVIEW-STRONG-INITIAL.md` 与 `source-review/`。

新 decoder 使用有界、非池化的私有副本，并在 `finally` 对成功、解析拒绝和解析异常的私有副本清零。调用者持有的输入不被修改；输入本身、上层管道、运行时其他副本及可篡改同 realm 内建对象的恶意代码不在证明范围。此修复仍不提供进程退出、树清空或清理授权。

## RED / GREEN / 变异

- 新 `supervisor-erase.test.mjs` 在旧 decoder 上先因未发生私有非池化分配失败，collector 清零测试通过；这不是原池泄漏复现（原强审另有实测）。
- 修复初版后，既有 protocol 的“限额前不复制”测试因监测旧 `Buffer.from` API 而失败；更新该测试为监测捕获的私有 allocator，仍要求超限零分配、合法帧一次分配。三个直接相关测试文件 **42/42，0 skip**。
- 仅在独占复制树中分别删除 decoder 清零、collector 失败清零、collector 成功清零；每个变异均使清零测试失败。真实源码 SHA 不变，副本目录按单文件清理并核空删除。
- 七个 fake I/O 测试文件联合 **204/204，0 fail、0 skip**，Node v26.3.0，13 个输入文件前后原始 SHA 不变；独占 TMPDIR 核空后删除。
- 本轮原始测试快照 raw SHA（后续增强另见 `AUTHOR-ERASURE-RECHECK.md`）：decoder `8c83e4f1e6d4b0f248a58ee505d542b404e18cf5aee3c70f6a7dc3fb942caa30`，decoder test `b7d4dd793cb6cf69d6cdd93c293cee3363d4c1d3deed44cda41af7c2b9c77705`，collector `340403a916e68b4eef6be4f17831414de100220c4bd422a76d55fda0eca2ca7a`，collector test `5350526362ffd81069a291a2272e54532b77e7528b489b654c07a74b810f0e33`，擦除测试 `faa42abf0135a9ef7fd8098416b418b6a779d07da509c5dc7dec4a623c48718f`。

此文件为作者记录，未保存完整原始测试输出。新快照的独立复核在本记录撰写时尚未完成；旧快照独立通过不能代证新快照。
