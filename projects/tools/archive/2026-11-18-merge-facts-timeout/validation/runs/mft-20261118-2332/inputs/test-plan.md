# merge-facts 超时 — 测试方案

> 2026-11-18；对应 `canonical/specs/code/merge-facts-timeout.yaml`。

## 一、测试策略

复用 `skills/shared/crctl/scripts/test/merge-facts.test.mjs` 的 13 条测试：挂起请求断言 `MERGE_FACTS_UNAVAILABLE` 和超时原因，其余验证正常和错误路径。不访问现网、不加入保活夹具。基线 RED 使用已记录的干净 HEAD Linux Node 20 同文件运行：8 通过，首条取消是挂起请求，其后 4 条取消。修复后在同一 Linux 环境验证 GREEN。

## 二、详细测试案例

### 功能 1：既有超时与响应分类

#### 客户端传输合同（SC-MFT-001、SC-MFT-002）

| 字段 | 内容 |
|---|---|
| **ID** | TC-MFT-001 |
| **对应 Spec** | REQ-MFT-001 / SC-MFT-001、SC-MFT-002 |
| **优先级** | P0 |
| **预置与执行** | 原测试文件分别用不兑现的 Promise、正常或错误响应驱动现有客户端。 |
| **预期结果** | 挂起时得到 `MERGE_FACTS_UNAVAILABLE` 和超时原因；可分类响应的结果保持；13 通过、0 失败、0 取消、0 跳过。 |

## 三、测试执行矩阵

| 层面 | 执行 |
|---|---|
| 模块／同次证据 | `node --test --test-reporter=tap skills/shared/crctl/scripts/test/merge-facts.test.mjs` |
| Linux 全量回归 | 在 `AIFI-ISO` 用真实受限身份和已有 Node v20.20.2，基于含此修复与原精简补丁的临时快照，运行 `suite-gate` 和 writeback 原套件；保存退出码、耗时、通过/失败/取消/跳过 |
| E2E | 项目未启用，不执行 |

## 四、回归风险矩阵

| 风险 | 级别 | 保护 |
|---|---|---|
| 定时器生命周期改变响应退出行为 | 低 | 现有文件走完整超时和响应分类路径；保留 `finally` 清理 |
| 临时组合快照的全量失败 | 中 | 不改既有断言，保留全量真实结果；不同于模块同次证据 |

## 五、执行顺序

P0：先验模块行为及同次证据，再跑 Linux 组合回归。本修不改 writeback 跨秒行为。无 P1/P2。

## 六、同次执行证据计划

```stdd-evidence-plan-v1
{
  "task": "merge-facts-timeout",
  "inputs": [
    {"root": "project", "path": "skills/shared/crctl/scripts/lib/merge-facts.mjs"},
    {"root": "project", "path": "skills/shared/crctl/scripts/lib/cr-id.mjs"},
    {"root": "project", "path": "skills/shared/crctl/scripts/test/merge-facts.test.mjs"}
  ],
  "coverage": {"applicability": "not_applicable", "reason": "Node 栈，仓库覆盖率检查只支持 pytest-cov"},
  "checks": [
    {"tc": "TC-MFT-001", "case_id": "merge-facts transport contract", "requirement": "REQ-MFT-001", "scenarios": ["SC-MFT-001", "SC-MFT-002"], "cp": "CP-MFT-001", "kind": "command", "applicability": "required"}
  ]
}
```
