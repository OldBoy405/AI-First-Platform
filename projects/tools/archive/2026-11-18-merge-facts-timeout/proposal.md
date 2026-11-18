# 让 merge-facts 等待到已有超时结果

<!-- source_hash: fca824e9c92c4fc0 -->
<!-- generated_at: 2026-11-18T23:06:10.688567 -->
<!-- canonical: canonical/proposals/2026-11-18-merge-facts-timeout.yaml -->

## Why

Linux Node 20 的全量回归中，merge-facts 的挂起请求用例因事件循环提前退出被取消，随后同文件另外四个用例也被取消；干净 HEAD 同环境复现。

## What Changes

- merge-facts 等待挂起请求时，即使没有其他活跃任务，也返回既有超时结果；正常响应行为不变。

### Modified Capabilities

- **merge-facts-timeout**：现有客户端的挂起请求按既有时间阈值返回 MERGE_FACTS_UNAVAILABLE。

## Success Criteria

- [ ] 当请求未完成且超时是唯一待处理任务时，现有客户端返回带超时原因的 MERGE_FACTS_UNAVAILABLE，不提前退出。
- [ ] 现有 merge-facts 正常响应及错误分类测试全部通过，取消数为 0。
- [ ] 在隔离工作副本验证现有 Linux Node 20 suite-gate；不跳过、不豁免失败。
