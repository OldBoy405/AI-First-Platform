---
id: CR-2026-002-TASK-03
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: evidence-digest 统一（canonical 唯一实现）+ crctl approve --grant 验签
status: pending
estimate: 12h
depends-on: []
assignee: ""
created: "2026-07-31T09:30:00+08:00"
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
