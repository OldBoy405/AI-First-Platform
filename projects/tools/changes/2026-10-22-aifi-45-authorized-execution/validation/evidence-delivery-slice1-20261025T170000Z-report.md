# EVD 切片 1（SC-EVD-003 / 006 / 010）— 交付报告

## 交付

| 文件 | 变更 |
|---|---|
| `skills/shared/crctl/scripts/lib/evidence-delivery.mjs` | 新增纯判定 `evaluateEvidenceDelivery(facts)` |
| `skills/shared/crctl/scripts/crctl.mjs` | 新增只读动词 `evidence-check <CR>`（+ 帮助行 + import） |
| `skills/shared/crctl/scripts/test/delivery-contract.test.mjs` | 新增 `TC-EVD-003` / `TC-EVD-006` / `TC-EVD-010` |

事实采集留在 `crctl.mjs`，因为它必须复用**唯一**的“被评审对象是什么”实现 `subjectMatchesAnnotation`
（requirement→`prd.md`、tech-design→`sdd.md`、dev-plan→复合摘要、code→`release-subjects` 重核）。
判定规则是纯函数，因此可以脱离工作区单测，且不会出现第二套 subject 口径。

## 三条规则的实际语义

| TC | 规则 | 判据 |
|---|---|---|
| EVD-003 | 只有作者本人评审不算评审 | `review-loop.yml#attempts[].by` 至少有一个身份 ≠ `cr.md owners.development`（旧写法 `owners.implementer`）；`unknown` 不算独立；缺 owner 时对**新合同** CR fail-closed（`EVIDENCE_AUTHOR_UNRESOLVED`） |
| EVD-006 | 在途 legacy CR 不追溯阻断 | `cr.md` 无 `execution-contract` ⇒ 直接 `deliver` + `legacy: true`，不新增必需字段、不新授予额度（输出里不含任何 budget 字段） |
| EVD-010 | scope 未变但对象已变 ⇒ 旧证据失效 | `subjectMatchesAnnotation` 复算当前对象摘要；`replaced` ⇒ `EVIDENCE_STALE_SUBJECT`；**无法复算**（对象缺失/形状非法）⇒ `EVIDENCE_SUBJECT_UNVERIFIABLE`，绝不当作“当前”放行 |

三条 finding 刻意**不合并**：自评与旧证据是两种不同的缺陷，合并会掩盖其中一种。

## 证据（先 RED 后 GREEN）

RED（同时改坏三处：独立性判定恒真、stale 分支短路、legacy 分支短路）：

```
not ok 1 - TC-EVD-003
not ok 2 - TC-EVD-010
not ok 3 - TC-EVD-006
# fail 3
```

GREEN：三条 CP 命令的四条断言全部满足（exit 0 / `ok 1 - <TC>` / `# fail 0` / `# skipped 0` / `# todo 0`）；
tools 全量 **1064 / 1063 pass / 0 fail / 1 skip**。

## 过程中被工具链抓到的一处真问题

新增 fixture 里原本照抄了真实 `review-loop.yml` 的表头 `# 由 crctl attempt 维护…`，
被 `caller-contract.test.mjs` 的 caller-09（“每处 CR 数据命令调用都要带非空 `--workspace`”）判为缺根调用 —— **扫描器是对的**：
那行在测试夹具里确实是“看起来像调用”的文本。改为中性表头，未放宽扫描规则、未加白名单。

## 未做（切片 2 起）

EVD-001/002（内容与缺口判定）、004/005（机械例外）、007（组件版本，依赖 D3）、008（迁移）、009（发布事务恢复）。
