---
id: CR-2026-002-TASK-03
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: evidence-digest 统一（canonical 唯一实现）+ crctl approve --grant 验签
status: done
estimate: 12h
depends-on: []
assignee: ""
created: "2026-07-31T09:30:00+08:00"
spec-id: ai-first-platform
version: "0.11"
---

## 任务描述
FR-7 tools 侧 + FR-4 crctl 侧：canonical digest 唯一函数（SDD §4.1，含 normalizeEol）；TTY 审批改写 `evidence-digest` 字段；gate/validate 两轨重算比对；`approve --grant` Ed25519 验签放行。仓库：tools。

## 涉及文件
- 修改 `skills/shared/crctl/scripts/crctl.mjs`：`canonicalEvidenceDigest()`（唯一实现，替换/收编 evidenceSha16 的使用点）、cmdApprove TTY 分支与 --grant 分支、runGateChecks、cmdValidate
- 新增共享测试向量 `skills/shared/crctl/scripts/test/fixtures/digest-vectors/`（输入文件集 + 期望 digest hex，供 T08 Go 侧引用）
- 测试追加用例

## 实现要点
- digest = sha256(concat(sorted paths 的逐文件 sha256(normalizeEol(content)) hex))，对 `gates.json#approvalStages[stage].evidence` 全部文件。
- 旧 `evidence-sha256-16` 读到视为"无摘要"，不报错（NFR-3）。
- --grant：验签（crypto.verify ed25519，公钥 `.crctl/keys/{key_id}.pub`）+ 重算 digest 比对 + cr_id/stage 匹配检查；任一不符给结构化错误（EVIDENCE_DRIFT / SIGNATURE_INVALID / GRANT_MISMATCH）。
- AC-7⑤：TTY 写入、--grant 验证、gate/validate 重算三处调**同一函数**（代码评审核查项）。

## 验收条件
1. 测试：TTY 审批后 approval.yml 出现 `evidence-digest`，无旧字段（AC-7①）。
2. 测试：批后篡改证据文件 → gate 与 validate 均报 EVIDENCE_DRIFT（AC-7③④检测半边）。
3. 测试：--grant 验签通过/签名伪造/digest 不符三用例（AC-4⑥）。
4. 测试：历史 approval.yml 含 `evidence-sha256-16` → 不报错按无摘要处理（AC-7②）。
5. digest-vectors fixture 落盘且自测通过。

## 完成标志
tools 测试全绿（含新增 ≥6 用例）+ 完成记录回填。

## 完成记录（2026-07-31）

- **提交**：tools@63f5f0c（custom/main，已推 origin）。测试 19/19（新增 5 个 test 块，覆盖 ≥8 个断言场景）。
- **`canonicalEvidenceDigest()`**：唯一实现（AC-7⑤），TTY 写入 / --grant 验证 / gate 复核 / validate 复核四处调同一函数；含 normalizeEol（继承 M0 行尾坑）；任一证据缺失返回 null（无法计算 ≠ 漂移）。
- **TTY approve**：改写统一字段 `evidence-digest`（canonical 覆盖 stage 全部证据文件），不再写 `evidence-sha256-16`。
- **`approve --grant`**：非 TTY 放行链 = schema 校验 → decision 校验（reject 拒收并指路回退转移）→ cr/stage 匹配（GRANT_MISMATCH）→ 状态/passCondition/requireFiles（grant 不豁免 blocker）→ 本地重算 digest 比对（EVIDENCE_DRIFT）→ Ed25519 验签（SIGNATURE_INVALID/KEY_NOT_FOUND，公钥 `.crctl/keys/{key_id}.pub`）→ 写 server-approve 段（含 key-id/signature/grant-approved-at 存档以供 gate 重验签）→ 级联 advance + outbox 证据事件。
- **gate/validate 两轨统一**：via 承认 crctl-approve 与 server-approve；`evidence-digest` 存在即重算比对（两轨都测）；server-approve 额外从存档字段重建 canonical 重验签（摘要漂移与签名有效性分开判断）；CI cr-guard 模板经 validate 自动获得远端复核能力。
- **兼容性决策（偏离源方案一处，记录在案）**：源方案 §B.3 说旧字段"视为无摘要"；实现改为**保留旧字段的兼容复核**（单文件短哈希继续检测漂移）——M0 与本 CR 已有的 4 次审批不因此失去保护，"不报错不阻塞"的 AC-7② 语义不变。代码评审时可复核该取舍。
- **共享测试向量**：`test/fixtures/digest-vectors/`（两文件 + expected.json，digest c28c5b93…）；tools 侧 conformance 测试证明 crctl 实现与向量一致，TASK-08 的 Go 实现必须过同一组向量。
- **待 live 验证**：TTY 路径写 evidence-digest（AC-7①）在下一次真实审批（tech-design 之后的 code 阶段审批）自然发生。
