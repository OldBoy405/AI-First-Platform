---
id: CR-2026-009-plan
type: PLAN
cr-ref: CR-2026-009
sdd-ref: "change-requests/CR-2026-009/sdd.md"
target-version: "0.16"
status: draft
created: "2026-08-02T11:50:00+08:00"
updated: "2026-08-02T11:50:00+08:00"
---

# CR-2026-009 开发计划

## 1. 交付里程碑

后端两块 + 前端两块 + 端到端验收，共 5 任务，总估算 18h：

| 阶段 | 内容 | 估算 |
|---|---|---|
| T01 | 后端：migration 161 + 8 处排除谓词扩值（单值→NULL 安全容器清单）+ ensureContainerIssue 抽取 + `GET /api/projects/{id}/discussion` | 5h |
| T02 | 后端：触发豁免短路（computeCommentAgentTriggers）+ 负向单测 + 既有触发链回归单测 | 2h |
| T03 | 前端：DiscussionPane（timeline + CommentCard + ReplyInput/draftKey）+ ?mode= 深链 + 四语文案 | 5h |
| T04 | 前端：inbox 容器起源跳转条（project_chat 与 project_discussion 共用） | 2h |
| T05 | 端到端验收：AC-1~7 全场景 + 回归 | 4h |

## 2. 任务依赖图

```
T01 (migration + 谓词清单 + ensure/端点)
 ├─> T02 (触发豁免，单测需 discussion 容器可造)
 ├─> T03 (DiscussionPane，吃 T01 端点)
 └─> T04 (inbox 跳转条，判定 origin_type 清单)
        T05 (E2E 验收) <── T02/T03/T04 全部完成
```

T01 是唯一硬前置；T02/T03/T04 之后可并行；T05 收尾。

## 3. 资源与分工

单人（Ray）串行执行，按 T01→T02/T03/T04→T05。

## 4. 风险与回滚策略

| 风险 | 缓解 | 回滚 |
|---|---|---|
| 谓词替换（单值→清单）8 处漏改导致 discussion 容器泄漏 | T01 完成后 `grep -rn "project_chat'" server` 断言零残留单值谓词；T05 逐入口核对 | 缺项按独立小 patch 补 |
| 触发短路误伤非容器 Issue（本 CR 唯一动既有行为的点） | 等值判断 + Valid 检查；T02 负向单测（discussion 容器 @agent → triggers 空）+ 既有触发链单测全量回归；普通 Issue @agent 正常入队（T05 反向验证） | 删除短路 if 即退回旧行为，无数据影响 |
| **PSUG-001（SDD 评审 SUG-001）**：down 迁移在容器已挂大量 comment 时的级联行为未演练 | T01 确认 comment→issue 外键级联；down 脚本显式处理；本地库演练 down→up 往返一次 | down 脚本本身即回滚路径 |
| **PSUG-002（SDD 评审 SUG-002）**：ensureContainerIssue 抽取重构 CR-A 已上线的 EnsureProjectChatIssue | T01 保留其既有单测并补 discussion 同构用例，两条 ensure 路径除 title/origin_type 外逐字节等价 | 抽取是纯重构，revert 恢复两函数独立实现 |
| **PSUG-003（SDD 评审 SUG-003）**：?mode= 深链任意值写入持久化 store | T03 白名单校验（team_agent\|private_ask\|discussion 之外忽略） | 纯前端读参分支 |
| inbox 跳转条影响既有通知流 | 纯渲染分支，非容器 item 零路径变化；T05 回归 | 单组件 revert |
| 并发首开 Discussion tab 重复建容器 | 部分唯一索引 + ON CONFLICT DO NOTHING 后重查（照抄 CR-A 已验证模式） | 索引即安全网 |

## 5. 验收与发布策略

- 发布：随 CR 正常合并/回写流程进入 multica main；migration 161 随部署管道执行。
- 无 feature flag：新增均为增量路径（新容器类型/新端点/新前端面），唯一行为变更点（触发豁免）
  仅命中 `origin_type='project_discussion'` 的 Issue——上线前该类型零存量，天然灰度。
- 验收红线（cr.md）在 T05 显式覆盖：AC-3 DB 级零 `agent_task_queue` 增量、AC-4 容器全入口隐藏。
