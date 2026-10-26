# AIFI-45 multica 切片计划

## Dependency Graph Summary

```text
隔离DB核验 ──────────────┐
T S1/S2授权 → M-S1认证/签名/传输 → M-S2真实队列/四阶段恢复
T S3准入/assessment ──────────┘
T S4/S5门禁版本 → M-S2联合身份/旧合同 → M-S3通知/幂等消费 → M-S4全量三路径审查
```

## Slice Execution Plan

| # | 优先级 | 风险 | 预估 | 并行组 | TC覆盖 | 目标 | 依赖 |
|---|---|---|---|---|---|---|---|
| M-S0 | P0 | 高 | S | T S1只读环境 | 环境前置 | 新建仅本change隔离实例并验证DB，秘密不入日志 | 无 |
| M-S1 | P0 | 高 | L | 合同冻结后 | RUN-001～003/010、T AUTH-010 | 真实认证签名来源和送达/消费分离 | T S1/S2、M-S0 |
| M-S2 | P0 | 高 | L | 同文件单writer | RUN-004～009 | 永久根键、实际wake/扫描、adoption、版本与证据 | T S3/S5、M-S1 |
| M-S3 | P0/P1 | 高 | L | 独立消费者可并行 | NTF-001～007 | 三类通知、责任人分流、Inbox事务恢复与消费者幂等 | M-S2 |
| M-S4 | P0/P1 | 高 | L | 独立评审并行 | 全部17TC与跨仓三路径 | 真实TaskService/隔离DB/前端、全量回归与Gate3 | 全部 |

## Rationale

依赖先T可信准入、再M实际执行；风险集中在认证和持久化身份，不能用fake walker证明。工作量按现有边界S/L估算，不承诺固定工时。每个TC先RED→GREEN，不能横向先写全部实现。只有环境调查可无依赖并行；schema/query/model和共享Runner单writer。使用实际下一迁移号，无FK/cascade，每个CONCURRENTLY索引独立文件。

普通模式在重大设计偏离、阻断或迭代上限停下。M-S0未验证隔离身份时禁止迁移和governance测试；零选中、整包skip和共享DB结果不算本轮证据。每片完整覆盖及回归后才登记完成。
