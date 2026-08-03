---
id: CR-2026-012-plan
type: PLAN
cr-ref: CR-2026-012
sdd-ref: "change-requests/CR-2026-012/sdd.md"
target-version: "0.19"
status: draft
created: "2026-08-03T18:45:31+08:00"
updated: "2026-08-03T18:45:31+08:00"
---

# CR-2026-012 开发计划

## 1. 交付里程碑

三条独立工作流（DC 后端 / 合并转发 / ChatInput 解耦）+ 端到端验收，共 8 任务，总估算 48h
（对照规划量级：CR-G 4–5 人日 + ChatInput 债 2–2.5 人日 ≈ 52–60h，收敛在下限内，零 migration 省下迁移工位）：

| 阶段 | 内容 | 估算 |
|---|---|---|
| T01 | 后端：DC 基座——agenttmpl 模板 + settings 读取函数 + AskOnly claim 规则 + trivial 抑制豁免 | 6h |
| T02 | 后端：触发过滤改造（discussion 分支两类并集 + exemption 测试 6 分支扩展） | 4h |
| T03 | 后端：DC 路由 re-target + originator 显式解析 + 满队 system comment | 6h |
| T04 | 后端：merge-forward 端点（校验/组装/Send 内核复用/register_cr 指令块）+ 薄发送端点扩 attachment_ids | 6h |
| T05 | 前端：ChatInputCore 拆分 + 默认包装 + "不触碰 useChatStore" 双重锁定单测 | 6h |
| T06 | 前端：project-chat-store 附件槽 + mentionItemTypes 过滤 + Team Agent / Private Ask 两面回填 | 8h |
| T07 | 前端：DiscussionPane 多选态 + 合并预览 Dialog + DC 设置项 + 四语文案 | 6h |
| T08 | 端到端验收：AC-1~8 全场景（含 DC 只读审计与升级 CR 实跑） | 6h |

## 2. 任务依赖图

```
T01 (DC 基座) ──> T02 (触发过滤) ──> T03 (路由 re-target)
T04 (merge-forward 端点 + attachment_ids)          [独立]
T05 (ChatInputCore 拆分)                           [独立]
 ├──────────────┐
T04 ────────────┴─> T06 (两面回填，依赖 T04 的 attachment_ids + T05 的 Core)
T04 ──> T07 (多选/预览前端，消费 merge-forward 端点；locale 收口)
T08 (E2E 验收，依赖 T03/T06/T07 全部完成)
```

三条工作流可并行开工：T01→T02→T03（DC 链）、T04（端点）、T05（解耦）互不依赖；
T06 汇合 T04+T05；T07 消费 T04；T08 收尾。

## 3. 资源与分工

单人（Ray）执行，建议顺序：T01 → T05 与 T04 穿插 → T02 → T03 → T06 → T07 → T08
（把纯前端 T05 提前穿插，避免后端链路阻塞时空转）。

## 4. 风险与回滚策略

| 风险 | 缓解 | 回滚 |
|---|---|---|
| 触发过滤改造误伤普通 Issue 评论触发链 | 改动限定在 `project_discussion` 分支内（未配置 DC 逐字节等价现状）；T02 保留 CR-D exemption 测试全量 + 新增 6 分支 | 分支内 revert 即回到 CR-D 全拒语义 |
| **TSUG-001**：originator 穿透能力未证实，路由 enqueue 可能落 a2a 直通绕过容量守卫 | T03 任务期核实 `resolveOriginatorForIssueTask`；不足则 re-target 处显式解析 parent 链透传；解析失败路径记日志 + 写进 AC-3 验收口径 | re-target 是新增分支，关闭即 DC 失去路由（协调输出不受影响） |
| **TSUG-002**：trivial 抑制吞 DC 输出 | T01 一行容器豁免（机制级）+ DC 模板 instructions 要求实质输出；T08 边界用例 | 豁免条件单点 revert |
| re-target 补偿语义（路由 comment 落了、enqueue 失败） | T03 沿 SendProjectChatMessage 补偿删除模式（project_chat.go:236）+ DD-6 system comment | 同上，分支可独立关闭 |
| ChatInput 拆分回归 /chat 页与浮窗 | T05 保持既名导出与 props 不变，draftKey/editorKey 派生逻辑原样搬入默认 adapter；既有 chat-input.test.tsx 全量回归 | 拆分是等价重构，git revert 单 commit 可回 |
| project-chat-store persist 兼容（旧数据无 draftAttachments） | T06 新字段可缺省（空 map 回落）+ rehydration 分支测试 | 字段新增向后兼容，无需数据迁移 |
| mentionItemTypes 过滤漏 server-search 分支 | T06 在 buildSyncItems 与 MentionList 异步搜索两处都过滤 + 单测断言 agent/squad/issue 不出现 | 新 prop 不传即回落现状 |
| 合并转发长内容 prompt 爆量 | T04 `comment_ids ≤ 50` 硬上限 + trigger_summary 既有截断；`ponytail:` 注释标注摘要压缩升级路径 | 上限常量收紧即可 |
| **TSUG-003**：approvalSvc 未配置环境 gates 缺失 | T07 默认勾选态容错（404/错误 → 默认不勾）；T08 未配置环境冒烟 | 前端探测分支，无后端耦合 |
| parity 漏键 | T07 四语同 commit（CR-D 惯例），parity.test.ts 门禁 | — |

## 5. 验收与发布策略

- 发布：随 CR 正常合并/回写进 multica main；**零 migration**，无部署管道特殊步骤。
- 天然开关两层：DC 未绑定（`discussion_coordinator_agent_id` 未配置）→ 触发行为与 CR-D
  交付态逐字节一致；merge-forward 是新端点、ChatInputCore 未被旧消费方引用——三块都可
  独立灰度/回退。
- 验收顺序：T02 后先跑触发豁免回归（AC-1 前半）→ T03 路由/满队单测 → T04 端点单测
  （校验/守卫/补偿/register_cr 组装）→ T05 双重锁定单测 + 既有回归 → T06/T07 联调 →
  T08 端到端（依 PRD 顺序：静默边界 → 激活审计 → 路由 → 合并转发 → 升级 CR → 解耦锁定 →
  回填隔离 → 双端/locale 回归）。
