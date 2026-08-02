---
id: CR-2026-011-TASK-03
type: TASK
cr-ref: CR-2026-011
plan-ref: "change-requests/CR-2026-011/plan.md"
sdd-ref: "change-requests/CR-2026-011/sdd.md"
title: review 事件通道（daemon 扫描正则 + yml payload + 服务端放行）
slug: review-event-channel
status: pending
estimate: 4h
depends-on: [CR-2026-011-TASK-02]
assignee: ""
created: "2026-08-02T12:40:00+08:00"
---

## 任务描述
落地 SDD §4.2 + DD-3：blocked/passed 评审对平台可见。daemon commit 扫描新增第 5 类正则，
命中后读取该 commit 的 review-annotations yml 作事件 payload（event_kind=`review`）；
服务端放行并交投影器写 review 节点行（blocked + attempt + detail）。**tools/crctl 零改动。**

## 涉及文件
- `server/internal/daemon/crevents.go`：第 5 类正则
  `^\[cr\] review-(requirement|tech-design|code) (CR-\S+): verdict=(\S+)`（只锚前缀段，
  后缀自由文本忽略）；命中后 `git show <sha>:change-requests/{cr}/review-annotations/{stage}.yml`
  解析 {verdict, blockers[], current-attempt, reviewer, reviewed-at} 为 payload
- `server/internal/governance/crsync.go`：`HandleCREvents` kind 白名单放行 `review`；
  新增 `applyReview` 分支 → 投影器 review 节点 upsert（blocked/passed + attempt + detail JSONB）
  → publish `cr:updated`

## 实现要点
- yml 解析用 Go 侧既有 yaml 依赖；解析失败 → 该事件 BAD_EVENT 进 dead（不阻塞批次）。
- 幂等键 `(cr_id, commit_sha, event_kind)` 照旧；同一 commit 的 status 与 review 事件是
  两个 kind，互不冲突。
- stage → pipeline/node 映射复用 T02 的映射表与 `ResolveNodeID`。
- payload 内容脱敏边界：blockers 的 issue/suggestion 是评审正文（本就入 git 的治理数据），
  可全文上报；不携带证据文件内容。
- 单测：正则命中/不命中用例（含措辞后缀变体、planning-report 不在三 stage 内不命中）；
  yml 缺字段容错；事件重放幂等；端到端（daemon 侧构造 commit → 扫描 → 上报 → 投影行断言）。
