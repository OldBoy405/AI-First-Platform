# 上游同步提案：{{sync_id}}

> 模板版本：v2（2026-10-20）
> 适用：`task_type: upstream-sync` 的 Phase 1 / Gate 1
> 变更：在 v1 基础上前置《§0 台账新鲜度检查》，把“先补台账、再合并”变成 Gate 1 硬前置。
> CUSTOM.md 仍是唯一事实源；本模板只定义 Gate 1 需要确认的范围、基线与准入条件。

## 0. 台账新鲜度检查（硬前置，不新增 Gate）

### 0.1 四维检查

| 维度 | 检查方法 | 判定 | 证据 |
|---|---|---|---|
| 条目新鲜 | 上次 CUSTOM 更新..HEAD 的代码改动，逐文件对照《代码改动明细》 | FRESH / STALE-ENTRIES / UNKNOWN | |
| 基线新鲜 | 现场四数 vs 最后一条基线行；差异逐项归因 | FRESH / EXPLAINABLE / UNEXPLAINED | |
| 状态新鲜 | 《当前状态》日期、迁移水位、CR 索引 vs git/PR 实际 | FRESH / STALE-STATUS | |
| 格式可解析 | 表头列数与行语义一致；基线行是否在《核对基线》表 | FRESH / UNPARSEABLE | |

判定值说明：

- **FRESH**：该维度无待处理项。
- **STALE-ENTRIES**：存在未登记到《代码改动明细》的代码改动。
- **EXPLAINABLE / UNEXPLAINED**：基线差异能否逐项归因到已登记改动。
- **STALE-STATUS**：状态字段与 git/PR/实际迁移水位不符。
- **UNPARSEABLE**：表格结构或列语义不一致，按章节读取会出错。
- **UNKNOWN**：证据不足，无法判断。

### 0.2 判定规则

- 任一 **STALE-ENTRIES / UNEXPLAINED / UNKNOWN** → **BLOCK**：不进 Gate 1，先补台账或补齐证据。
- 仅 **STALE-STATUS / UNPARSEABLE** → **PASS-WITH-FIX**：先做事实性修正，独立提交，再进 Gate 1。
- 全部 FRESH / EXPLAINABLE → **PASS**。

禁止把“CUSTOM.md 最近改过”当作 FRESH 的证据；必须看内容。

### 0.3 检查命令

```bash
git log -1 --format='%h %ad %s' --date=short -- CUSTOM.md
CUSTOM_SHA=$(git log -1 --format=%H -- CUSTOM.md)
git log --oneline "$CUSTOM_SHA"..HEAD -- server packages apps
git rev-list --count "$CUSTOM_SHA"..HEAD -- server packages apps

# 四数按 CUSTOM《核对基线》同一口径现场重取；不要混用 2026-09-08 之前的命中数口径
git grep -cE "AIFIRST|CR-2026-[0-9]{3}" \
  -- 'server/**/*.go' 'server/**/*.sql' 'server/**/*.mjs' \
     'packages/**/*.ts' 'packages/**/*.tsx' 'packages/**/*.mjs' \
  | awk -F: '{n++; s+=$NF} END {print n" 文件 / "s" 行"}'

# 迁移水位
ls server/migrations | sort | tail -20
```

说明：最后一条 CUSTOM 提交 = HEAD 只证明时间上同步，不证明该提交里的每处代码改动都已登记。条目维度必须逐文件对照。

### 0.4 修正记录

| 项 | 内容 |
|---|---|
| 是否存在修正 | 是 / 否 |
| 修正提交 | `{{sha}}` |
| 修正文件 | `CUSTOM.md` / 其他 |
| 修正类型 | 补登条目 / 状态刷新 / 格式修正 |
| 复核人 | |
| 复核时间 | |
| 复核结论 | PASS / BLOCK |

### 0.5 Gate 1 准入结论

`PASS` / `PASS-WITH-FIX` / `BLOCK`

> BLOCK 时不得继续填写 §1–§8；先处理台账欠债。

## 1. 窗口与策略

| 项 | 值 |
|---|---|
| 仓库 | {{repo}} |
| fork 分支 | main @ {{fork_sha}} |
| 上游分支 | upstream/main @ {{upstream_sha}} |
| 上次同步点 | {{last_sync_sha}}（CUSTOM《合并官方记录》{{日期}} 行） |
| 本次窗口 | {{last_sync_sha}}..{{upstream_sha}} |
| 提交数 | {{N}}（非浅克隆下 `git rev-list --count`） |
| 触发原因 | 双周例行 / 上游修复 / 迁移撞号 / release |
| 合并策略 | merge（默认）/ rebase（理由：{{...}}） |
| 同步分支 | sync/upstream-{{date}}-{{short_sha}} |
| 执行模式 | lightweight / standard / thorough |
| 模式理由 | 按窗口大小 + 风险面定档，不用冲突文件数直接套 complexity score |
| 上游 tip 冻结 | 以 Gate 1 确认的 {{upstream_sha}} 为准，窗口外新提交不纳入本次 |

## 2. 前置检查

- [ ] §0 判定为 PASS 或 PASS-WITH-FIX，修正已独立提交
- [ ] `git status` 干净，无未提交/未跟踪改动
- [ ] `git rev-parse --is-shallow-repository` = false；若 true，已 `git fetch upstream --unshallow` 或 `--deepen`
- [ ] `git fetch upstream --tags` 完成，确认 upstream/main SHA
- [ ] 已创建同步分支，main 未动
- [ ] 已打基线标签：`pre-sync/{{date}}`
- [ ] 停写窗口确认：其他 agent/PR 不再向 main 合入
- [ ] 本次不 push、不部署、不改生产库
- [ ] 库账本如需修复，只记录命令和影响面，不在合并中代跑

预检命令：

```bash
git status --short
git rev-parse --is-shallow-repository
git fetch upstream --tags
git rev-parse upstream/main
git switch -c sync/upstream-{{date}}-{{short_sha}} main
git tag pre-sync/{{date}} main
```

## 3. 基线快照（现场重取，不抄 CUSTOM《当前状态》）

### 3.1 挂钩四数

按 CUSTOM《核对基线》同一口径执行，记录执行时间与 HEAD：

```bash
git grep -cE "AIFIRST|CR-2026-[0-9]{3}" \
  -- 'server/**/*.go' 'server/**/*.sql' 'server/**/*.mjs' \
     'packages/**/*.ts' 'packages/**/*.tsx' 'packages/**/*.mjs' \
  | awk -F: '{n++; s+=$NF} END {print n" 文件 / "s" 行"}'
```

| 指标 | 本次基线 | 上次基线（CUSTOM 行/日期） | 差异 |
|---|---|---|---|
| 文件数 | | | |
| 命中行 | | | |
| AIFIRST | | | |
| packages/ | | | |

注意：不要混用 2026-09-08 之前的“命中数”口径。

### 3.2 迁移水位

| 项 | 值 |
|---|---|
| 上游最大迁移号 | |
| fork 占用区间 | |
| 是否重叠 | 是 / 否 |
| 重叠处理 | 顺延 +N / 无需处理 |
| 需同步引用 | cleanup map / migrate 测试 / 号引用测试 |

### 3.3 测试基线

| 检查 | 合并前结果 | 已知失败/备注 |
|---|---|---|
| `go build ./...` | | |
| `go vet ./...` | | |
| `pnpm typecheck` | | |
| `pnpm test` | | |
| 定向测试（按模块） | | |
| 空库 `migrate up` | | |

另存一份合并前树 A/B 快照：`pre-sync/{{date}}`。

### 3.4 路径与生成物基线

| 项 | 值 |
|---|---|
| git 跟踪文件数 | |
| apps/* 路径数 | |
| 关键生成物 | transitions_gen.go / gate_nodes_gen.go / pkg/db/generated/*.go |
| 前端无标记定制 | packages/ 清单是否完整 |

## 4. 预测冲突面

### 4.1 上游提交概览

```bash
git log --oneline {{last_sync_sha}}..{{upstream_sha}}
git diff --stat {{last_sync_sha}}..{{upstream_sha}}
```

| 提交 | 主题 | 影响模块 | 触及 fork 冲突面 |
|---|---|---|---|
| | | | 是 / 否 |

### 4.2 按 CUSTOM 模块索引预测

| 模块 | 台账行号 | 上游冲突面 | 预测冲突文件 | 风险 |
|---|---|---|---|---|
| M1 | #1–#2、#102、#108、#111 | | | 高 |
| M2 | #3–#5、#7–#11、#16、#26–#27、#72、#101、#135–#136、#152 | | | |
| M3 | #12–#13、#15、#23、#86、#132、#151 | | | |
| M4 | #28–#37、#52、#93、#115–#117、#125、#134、#137、#139–#148 | | | |
| M5 | #39–#47、#89 | | | |
| M6 | #48–#51、#67 | | | |
| M7 | #54、#96、#99、#109、#110、#119 | | | |
| M8 | #17–#20、#22、#24–#25、#59–#66、#104–#105、#112 | | | |
| M9 | #21、#68–#71、#77–#85 | | | |
| M10 | #6、#14、#58、#88、#94–#95、#100、#114、#121–#128、#133、#149 | | | |
| M11 | #53、#55–#57、#118、#150 | | | |
| M12 | #75、#90–#92、#97、#138 | | | |
| M13 | #38、#73–#74、#76、#87、#98、#103、#106–#107、#113、#120 | | | |

没有涉及的模块写“无”，不要留空。

### 4.3 高风险清单

- [ ] 迁移号是否再次压进 fork 区间
- [ ] 生成物是否冲突
- [ ] 认证 / daemon / 路径守卫是否被上游重写
- [ ] packages/ 无标记定制是否被上游覆盖
- [ ] CUSTOM 三条口径盲区是否被触及
- [ ] 《第 N 次同步要防的坑》是否逐条核对

## 5. 在途状态

| 项 | 状态 | 处理 |
|---|---|---|
| 未合并 CR / AIFI | | |
| 活跃 STDD change | | |
| 未收口部署项 | | |
| 库账本是否需要先修 | | 只提命令，不代跑 |

## 6. 范围外

- 不处理与本次窗口无关的 fork 技术债
- 不修改 CUSTOM.md 的历史记录
- 不在 Gate 3 前 push 到 origin/main
- 不自动部署、不自动重启服务

## 7. 风险与回滚

| 项 | 内容 |
|---|---|
| 主要风险 | |
| 回滚方式 | `git merge --abort` / 删除同步分支 / 回到 `pre-sync/{{date}}` |
| 升级复核条件 | 出现台账未登记改动 / 迁移号无法顺延 / 关键行为测试无法解释 |

## 8. Gate 1 确认项

请确认：

0. §0 台账新鲜度结论：PASS / PASS-WITH-FIX / BLOCK；若 PASS-WITH-FIX，修正提交为 `{{sha}}`
1. 窗口、fork SHA、upstream SHA、合并策略
2. 挂钩四数、迁移水位、测试基线
3. 预测冲突面与执行模式
4. 是否授权进入 Phase 2 编裁决矩阵

| 项 | 值 |
|---|---|
| 确认人 | |
| 确认时间 | |
| 方式 | dialog / file_token / cli |
| 确认原文 | |
