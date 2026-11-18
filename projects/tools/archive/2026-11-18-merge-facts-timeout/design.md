# merge-facts 超时 — 技术设计

## Context

`skills/shared/crctl/scripts/lib/merge-facts.mjs` 的 `fetchMergeFacts` 让请求和超时 Promise 竞争，再把失败映射为既有传输结果。超时是唯一活跃任务时，现有 `unref()` 允许 Node 在超时触发前退出。Linux Node v20.20.2 的最终补丁与干净 HEAD 均取消同样五条测试；只读实验中，原函数退出 13，去掉 `unref()` 后返回 `MERGE_FACTS_UNAVAILABLE` 和超时原因。

## Decisions

只移除 `fetchMergeFacts` 对该定时器的 `unref()`；保留 `setTimeout`、阈值、`Promise.race`、原有错误分类和 `finally` 的 `clearTimeout`。这样未完成请求不会失去超时，已完成请求仍会清理定时器。不给测试加保活任务：那会遮住被测函数在独立进程中的提前退出。不加第二个定时器、重试或新依赖。

生产 diff 仍只落在 `skills/shared/crctl/scripts/lib/merge-facts.mjs`。把 `skills/shared/crctl/scripts/test/merge-facts.test.mjs` 的挂起请求断言移入一个新用例：用 `process.execPath` 直接启动 Node，子进程顶层等待挂起请求并输出结果，不使用 `node --test`、额外保活任务或显式退出。父测试要求自然退出码为 0，并检查结果是 `MERGE_FACTS_UNAVAILABLE`、原因为 `timeout after 20ms`。原用例名称和正常响应、错误分类断言不变，不保留重复的挂起断言。先在独立快照验证新用例对修复前后有区分力，再用临时快照与原精简补丁组合验证；不合并两个变更的源码、证据或 Git 授权。

## Architecture

`fetchMergeFacts` → 原请求与超时竞争 → 正常响应原样分类，超时仍返回 `MERGE_FACTS_UNAVAILABLE` 和原因 → 清理定时器。请求构造、授权判据、状态写入边界、门禁阈值和 writeback `updated` / `noop` 均不变。

## Risks / Trade-offs

| 风险 | 缓解措施 |
|---|---|
| 正常响应结束后仍保活 | 保留 `finally` 清理；完整运行 14 项测试，验证裸进程的超时以及原有响应分类。 |
| 组合回归碰到旧 writeback 跨秒波动 | 记录真实退出与用例；不更改断言、登记例外或将它算作本修复通过。 |

采用 `lightweight`，仅一个 capability、预计 1 个生产文件、少于 50 行。经验库中有关异步异常未回主链的经验与本问题机制不同，不新增兜底。设计由主会话直接起草，无额外 planner。
