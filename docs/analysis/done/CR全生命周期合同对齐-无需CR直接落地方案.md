# CR 全生命周期合同对齐：无需 CR 直接落地方案

> 状态：可直接执行的非语义勘误清单  
> 日期：2026-09-01  
> 边界：只修正已被当前代码、Pipeline 或测试明确证明的文字错误；不改变输入、输出、门禁、状态、路由、评审标准或文件 schema

## 1. 结论

全面复核后，原方案绝大多数内容都会改变运行时合同，必须走 CR。无需 CR 的范围应严格收缩为四类事实性勘误：

1. 删除重复步骤或错误编号；
2. 删除易漂移的 Pipeline 节点序号；
3. 把 Skill 文字改成当前实现和测试已经支持的真实输入格式；
4. 修正工作区说明中与当前实现相反的事实。

不开 CR 不等于可以顺手调整行为。若修改涉及 `.mjs`、Pipeline 的 inputs/node/ref/reviewLoop、gates、Agent 职责、review 判定、repair-target、writeback 语义或产物字段，立即停止并转入《CR 全生命周期合同对齐：需 CR 实施方案》。

## 2. 直接修改清单

### D-1 `requirement-register` 版本输入说明勘误

文件：

```text
../tools/skills/requirement/requirement-register/SKILL.md
```

当前文字写“真实版本不含 v 前缀”，但 `normalizeTargetVersion` 和现有 register 测试已接受 `v/V` 并 canonical 为无前缀版本。只改说明：

```text
输入允许可选 v/V 前缀；canonical 落盘值不含前缀。
```

不得同时改变版本值域、`unassigned`、`version-set` 或 writeback 行为。

### D-2 删除审批 Skill 的重复步骤

文件：

```text
../tools/skills/develop/approve-dev-start/SKILL.md
../tools/skills/develop/approve-code/SKILL.md
```

修改：

- `approve-dev-start` 删除第二条重复的“3. 输出审批记录路径……”；
- `approve-code` 删除第二条重复输出步骤；保留 suggestions 可选承接规则，只修正连续编号；
- 不改变 approve/reject、签名、状态推进、suggestions 是否阻塞等语义。

### D-3 删除 `review-code` 易漂移节点序号

文件：

```text
../tools/skills/develop/review-code/SKILL.md
```

将“code-implementation pipeline 第 8 节点”改为“code-implementation pipeline 的 review-code 节点”。当前 Pipeline 已不是稳定的第 8 节点；只删序号，不改评审维度、输出或状态操作。

### D-4 修正工作区对 register 入口的事实表述

文件：

```text
AGENTS.md  # AI First Platform 根目录
```

将“创建新 CR 不是 crctl 的子命令”修正为：

```text
面向用户的入口是 requirement-authoring Pipeline；其 requirement-register 节点内部唯一调用 crctl register 深原语。
```

不把 `crctl register` 暴露成绕过 Pipeline 的常规用户流程，也不改变注册权限。

## 3. 明确不直接修改

以下全部需要 CR，本方案不得触碰：

- requirement-authoring 输入、required/default、node prompt 或 execution_context；
- `registration-key`、`target-spec-id`、owner timestamp、YAML serializer 或 register 返回 JSON；
- `version-set` 允许状态和版本冻结边界；
- PRD/SDD/PLAN/TASK/Coding/reviewer 的责任或 blocker 标准；
- dev-plan/code repair-target 和 replayNodes；
- test-report 机器字段、source revision、日志 hash；
- feature-writeback 输入、generator、幂等、TASK 状态、traceability 或 archive；
- `review-alignment` 定位和 quality-reviewer-agent 职责。

## 4. 验证

在 `../tools/` 运行现有轻量检查：

```bash
node skills/shared/crctl/scripts/lint-prompts.mjs
node --test skills/shared/crctl/scripts/test/lint-prompts.test.mjs
node --test skills/shared/crctl/scripts/test/contract-scan.test.mjs
node -e "const fs=require('fs'); for (const f of fs.readdirSync('pipeline-templates').filter(f=>f.endsWith('.json'))) JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8')); console.log('json ok')"
```

并人工确认：

- diff 只包含上述四项文字勘误；
- 没有 `.mjs`、gates、Pipeline inputs/ref/reviewLoop、schema 或索引变化；
- 没有新增或删除 Agent、Skill、Pipeline 节点、CR 状态或 ledger；
- `git diff` 中没有任何评审阈值、状态转换和写入范围变化。

## 5. 完成标准

- 四项勘误均与当前实现和现有测试一致；
- 所有检查通过；
- diff 中不存在行为变化；
- 若执行中发现需要行为变化，停止直接落地并把该项移入需 CR 方案，不扩大本清单。
