# 2026-10-29-trusted-verdict-outcome-binding — 切片执行计划

## Dependency Graph Summary

```
S1 (T: v2 签发 + 向量)  ──►  S2 (M: 单一验签点 + 准入拒绝)
                              │
                              └─(引用同一向量)→ TC-VM-014

S3 (AIFI-45: M005 单写入者) ──► S4 (AIFI-45: 隔离 PG 端到端)
```

**并行化说明**：无并行组。S1 必须先于 S2：M 的验收向量由 T 的 v2 代码产出。S3/S4 不属本 change。

## Slice Execution Plan

| # | 优先级 | 风险 | 预估工时 | 并行组 | TC 覆盖 | 实现目标 | 依赖 |
|---|--------|------|---------|--------|---------|---------|------|
| S1 | P0 | 🟡 中 | M（2 文件改 + 1 向量改 + 测试） | — | TC-VT-004、TC-VT-007、TC-VM-014 | `OPERATIONS.verdict` → v2、verdict 闭集校验、`verdictPayloadV2`、v2 向量 | 无 |
| S2 | P0 | 🟡 中 | M（3 文件改/增 + 测试） | — | TC-VM-003/004/005、TC-VM-018 | `VerifyTrustedVerdictEffect` + `DecideAdmission` 接线 | S1 |
| S3 | P1 | — | — | — | TC-VM-006/008/010/012 | M005 单写入者接线 | 归 AIFI-45 |
| S4 | P1 | — | — | — | C4 | 隔离 PostgreSQL 端到端 | 归 AIFI-45 |

## Rationale

### Slice S1：v2 签发与向量（P0，先行）
- **依赖关系**：M 侧验收读同一份向量，T 不先定字节，M 就没有可对照的事实。
- **风险分析**：经验库无匹配条目（本项目经验库为空）；风险来自既有 5 个 operation 共用一套 preimage 与 vector 文件——只改 verdict 一例，避免连带改动其他域。
- **工作量依据**：单文件协议表 + 一处闭集校验 + 一个构造函数 + 一个向量用例，符合 M 粒度。

### Slice S2：单一验签点与准入拒绝（P0，依赖 S1）
- **依赖关系**：需要 v2 的 schema 字符串与字段名先冻结。
- **风险分析**：`DecideAdmission` 是生产准入唯一判定点，改错会把「拒绝」变成「放行」；因此只在已成立的 trusted 分支后追加校验，失败一律回落到既有的 `WAIT_TRUSTED_T_COMMIT`，不新增放行路径。
- **工作量依据**：一个纯函数 + 一处 SQL 结果后的接线 + 表驱动测试，符合 M 粒度。

### 不在本 change
- **S3**：M005 生产接线（单写入者、`request_id = task_id`、游标与帧同事务）由 AIFI-45 的实施范围承担；本 change 只定义合同（[design](design.md) §范围）。
- **S4**：真实入口与隔离数据库证据按已确认 proposal 由各自变更独立提供。
