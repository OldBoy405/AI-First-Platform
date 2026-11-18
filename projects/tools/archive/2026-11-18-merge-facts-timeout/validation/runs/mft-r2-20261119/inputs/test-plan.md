# merge-facts 超时 — 测试方案

> 2026-11-18；对应 `canonical/specs/code/merge-facts-timeout.yaml`。

## 一、测试策略

在 `skills/shared/crctl/scripts/test/merge-facts.test.mjs` 中，把原有挂起断言移到一个直接启动 Node 的新用例；完整文件为 14 项。原响应分类断言及用例名保持不变。不访问现网，不给子进程加保活夹具。保留已实测的 Linux Node 20 原用例对照（基线 8 通过、5 取消；修复后 13 通过、0 取消）。对新用例单独证明 RED → GREEN：在隔离快照用同一份新测试驱动未修 `merge-facts.mjs`（子进程因未决顶层 await 退出 13）和已修源码（退出 0，输出确切的超时结果）。不回改独立实现副本来制造 RED。

## 二、详细测试案例

### 功能 1：既有超时与响应分类

#### 客户端传输合同（SC-MFT-001、SC-MFT-002）

| 字段 | 内容 |
|---|---|
| **ID** | TC-MFT-001 |
| **对应 Spec** | REQ-MFT-001 / SC-MFT-001、SC-MFT-002 |
| **优先级** | P0 |
| **预置与执行** | 直接启动一个不经 test runner 的 Node 子进程，使用不兑现的 `fetchImpl`，等待 `timeoutMs: 20` 的结果；在原用例中保留正常和错误响应测试。 |
| **预期结果** | 子进程自然退出 0，返回 `MERGE_FACTS_UNAVAILABLE` 且原因为 `timeout after 20ms`；可分类响应的结果保持；14 通过、0 失败、0 取消、0 跳过。 |

## 三、测试执行矩阵

| 层面 | 执行 |
|---|---|
| 模块／同次证据 | `node --test --test-reporter=tap skills/shared/crctl/scripts/test/merge-facts.test.mjs` |
| 配置的质量检查 | 运行独立实现副本的 `quality.test`；复用输入未变的 lint、Agent 合同和 Skill 矩阵结果 |
| Linux 全量回归 | 在 `AIFI-ISO` 用真实受限身份和已有 Node v20.20.2，基于含此修复、新测试与原精简补丁的临时快照，运行一次 `suite-gate`，保存退出码、耗时、通过/失败/取消/跳过；writeback 输入不变，复用已通过的 24/24 |
| E2E | 项目未启用，不执行 |

## 四、回归风险矩阵

| 风险 | 级别 | 保护 |
|---|---|---|
| 定时器生命周期改变响应退出行为 | 低 | 用裸进程验证超时；原响应分类和 `finally` 清理保持 |
| 临时组合快照的全量失败 | 中 | 不跳过、不登记例外；全量结果和模块同次证据分别记录 |

## 五、执行顺序

P0：先验新用例 RED/GREEN 及完整模块同次证据，再完成配置的质量检查和最终 Linux 组合 `suite-gate`。本修不改 writeback 跨秒行为。无 P1/P2。

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
