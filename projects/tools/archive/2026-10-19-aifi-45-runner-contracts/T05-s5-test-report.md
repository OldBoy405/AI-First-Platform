# T05 / S5 汇总验收与测试报告

**change**：`2026-10-19-aifi-45-runner-contracts`（tools 侧）
**切片**：S5（任务 5.1 完整测试与校验 + 5.2 设计调整汇总与 test-report）
**执行人**：Main（executor）
**日期**：2026-10-20

---

## 1. 验收范围

| 切片 | 任务 | 覆盖 TC |
|---|---|---|
| T04a | 五 Agent 删除评论委派/跨阶段自启，保留入口/异常/必要人类输入、status/next 查询 | TC-T-PROMPT-001 |
| T04b | 与 multica 编译/解析同源核对，记录检查点 | TC-T-PROMPT-002、TC-T-PROMPT-003 |
| T04c | 保持四 approve Skill 已有正确收尾，加禁止尾启动/幂等/人工驳回负向回归 | TC-T-APP-001、TC-T-APP-002 |
| T05 | 全量测试 + JSON/Agent/matrix/lint 校验 + 本报告 | 全部 |

---

## 2. 全量测试结果（native exit / monotonic 耗时 / 分层计数）

**命令**（前台顺序批，31 个测试文件全枚举，不挑不跳）：

```bash
cd "C:/Users/GOBAO/Downloads/AI/tools"
node --test --test-reporter=tap --test-concurrency=2 \
  skills/shared/crctl/scripts/test/*.test.mjs      # 31 文件
```

| 指标 | 值 |
|---|---|
| 测试文件 | 31 |
| tests | 848 |
| pass | 848 |
| fail | 0 |
| cancelled | 0 |
| skipped | 0 |
| todo | 0 |
| native exit | 0 |
| monotonic 耗时 | 1752.6s |

> 口径说明：这是 R1–R4 评审修复**之前**的全量基线。修复涉及 4 个 `agents/*.md` 与 1 个 `.test.mjs`，已单独复跑受影响面（见 §2.1），最终全量复跑见 §2.2。

### 2.1 评审修复后受影响面复跑

| 文件 | tests | pass | fail | exit |
|---|---|---|---|---|
| contract-scan / caller-contract / check-agents-contract / check-skill-matrix / lint-prompts / pipeline-structure | 147 | 147 | 0 | 0 |

### 2.2 最终全量复跑

见本报告末尾「§7 最终全量复跑记录」（R1–R4 修复 + R1 回归守卫补齐之后）。

---

## 3. 脚本级校验（S5.1 的 JSON / Agent / matrix / lint 四门）

| 校验 | 命令 | 结果 |
|---|---|---|
| 8 个 pipeline JSON 可解析 | `json.loads` 逐文件 | PASS（req 6 / arch 4 / code 11 / wb 5 / planning 8 / radar 5 / market 5 / resume 3 nodes） |
| 四阶段 registry 导出 + digest | `node pipeline-templates/emit-registry.mjs --pipeline <id>` | PASS ×4，digest 与 multica pin **逐字节一致** |
| prompt lint | `node skills/shared/crctl/scripts/lint-prompts.mjs` | PASS exit=0 |
| Agent 合同 | `node skills/shared/crctl/scripts/check-agents-contract.mjs` | PASS exit=0 |
| Skill 矩阵 | `node skills/shared/crctl/scripts/check-skill-matrix.mjs` | PASS exit=0 |

四阶段 digest 实测值（与 multica `*_registry_gen.go` 内嵌值相同）：

```text
requirement-authoring  f839d28c30ce2dc0eec709589f742abac1f45db96771d80a3ef3ef66a45ea32c
architecture-design    11970fe3aec6013ff88117eda212617fec4b395e45c52057d157fd8112f2aeb5
code-implementation    ee6461ff376646dba36f64d57dfd4482c1e6f6532e049ce6547350b1c7175a88
feature-writeback      6a63a222146eb018564cd0487e8b1ab5352f832fd3d972f6c065ff7010c01108
```

---

## 4. 新增/修改的 TC 与断言清单

### 4.1 新增 TC

| TC | 文件 | 断言要点 |
|---|---|---|
| TC-T-PROMPT-001 | `contract-scan.test.mjs` | 五 Agent 无评论委派/跨阶段自启（11 条禁止模式）；派发归 Runner；`crctl status/next` 保持事实查询；协调者三项保留职责（入口/异常接管/人类审批信号承接）显式落点 |
| TC-T-PROMPT-002 | `contract-scan.test.mjs` | 索引 ≡ 目录枚举（无孤儿 `.md`、五 Agent 全 `active`）；「唯一编辑源」「已合并 ≠ 已部署」「部署产物」三声明；作者类 Agent 不得 `owns` 任何 `review-*`，reviewer 独占四类 |
| TC-T-PROMPT-003 | `contract-scan.test.mjs` | 不转交有权限 CLI 给人类；显式禁止代签/自行审批；失败回执含 CR-ID、原始错误码、影响摘要；精简回执纪律（不贴回执全文）；协调者保留必要人类输入 |
| TC-T-APP-001 | `contract-scan.test.mjs` | 四 approve Skill 仅收尾：双模式授权不可绕过、禁代签、`APPROVAL_REQUIRES_HUMAN`、驳回 `APPROVAL_DECLINED_ROLLED_BACK`、`changed=false` 幂等、无 `crctl start/resume`、无 `mention://agent/`、无「直接委派」「直接交给下一位」 |
| TC-T-APP-002 | `crctl.test.mjs` | 四 stage 驳回结果不含 `rerunHint`/`nextSkill`/`continuation`/`retryTask`/`attempt` 等重试信号；不派发新 task；同一 grant 重投仅幂等回放（`changed=false`、回退目标不变、CR 仍停回退态） |

### 4.2 修前的两个 HEAD 既有失败（非本次改动引入）

**发现**：tools HEAD `1fa6059a` 提交态即带 2 个失败测试。

| 测试 | 断言 | 根因 |
|---|---|---|
| `CR-2026-029：merge-feature-branch 收敛为…` | `md.includes('operational_workspace')` | 断言的是模板 token 拼写；生产文件在 **AIFI-45 T01–T03 冻结 `2bfa3ad`** 中已改为真实机器字段名 `operationalWorkspace`（`summary-projectors.mjs` pick、`workspace-transactions.mjs` 读 `ms.operationalWorkspace`），断言未同步 |
| `CR-2026-029：feature-writeback pipeline 各节点…` | 同上 + `!/lease/` | ① 同一 token 拼写问题；② `lease` 无词边界，被 prompt 里 `phase=release-drift` 的 **release** 子串误命中 |

**结论**：是我们自己的冻结提交造成的回归，被带进了推送。修复方向是**修测试而非改生产**：
- `operational_workspace` → `operationalWorkspace`（机器字段名，语义意图不变）；
- `|lease|` → `|\blease\b|`（保留对独立 `lease` 的检出，只排除 `release` 子串）。

**验证规则未被打穿**：探针把 `PROBE: 先取 lease 再合并。` 注入 merge prompt 后，`\blease\b` **正确报红**（exit 非零）；还原后复绿。

> 过程中一次转义事故需记录：首版替换经 shell heredoc 传递后，`\b` 被折叠成退格符 `\x08`，使正则变为 `/\x08lease\x08/`——既不匹配 `release` 也不匹配 `lease`，规则被静默掏空且测试全部通过。靠「注入真实违规词后应报红」的探针才发现。改用 `chr(92)+'b'` 显式构造后修正。**教训与工程纪律第 1 条一致：跨层转义必须用可验证探针兜底，不能只看测试绿。**

---

## 5. 独立技术评审结论与处置

独立评审（独立 session，只读）结论：**有条件通过，无阻塞项**，提出 R1–R5。逐项处置：

| # | 发现 | 性质 | 处置 |
|---|---|---|---|
| R1 | `cr-coordinator-agent.md:56` 仍写「四类评审由**产出 Agent** 通过独立 task/run 启动」，只豁免需求期——其余三阶段仍是作者自启 | **真实残留**（我最初的现状地图误标为"已迁移"） | 改为「四类评审均由平台 Runner 依各 Pipeline 派发…」。**并补测试守卫**：新增 `/由产出 Agent 通过独立[^。]*启动/` 禁止模式；探针验证基线绿→回灌红→还原绿 |
| R2 | 三处「跨人工 gate 的发布动作在同一 run 内执行」**缺主语**（原主语是"第一份委派"，删除委派后主语丢失），未闭合的 `push-progress`/checkpoint 可能无人承接 | 真实语义削弱 | 三处补回主体：「跨人工 gate 的首个节点由 Runner 派发时，显式携带上一阶段尚未闭合的发布动作并在同一 run 内执行、只回报结果」 |
| R3 | `quality-reviewer-agent.md:56` 无条件放弃 `trigger_outcomes`，导致本 Agent 自己的异常上报评论投递失败被静默吞掉 | 真实语义削弱 | 限定范围：仅「评审/回修派发」不解读；**本 Agent 自己发布的异常上报评论仍须确认发布成功并检查 mention 目标**，`status=blocked` 或缺失 outcome 不得当作已上报，须改报工作区所有者 |
| R4 | TC-T-PROMPT-003 ② 有一段 `for (const forbidden of [...]) { void forbidden; }` 空循环 | **死代码式恒真断言**（虚假覆盖率） | 删除空循环，保留后面真实生效的 `assert.match` |
| R5 | 未做字节级编码核对；`quality-reviewer-agent.md` 末行无换行 | 需核实 | 已核：五 Agent 与两测试文件**全部无 BOM、纯 CRLF**；`quality-reviewer-agent.md` 缺末行换行**为 HEAD 既有**（`git show HEAD:` 同样 `末换行=False`），非本次引入，保留不动以免制造无意义 diff |

评审同时确认无需改动项：`crctl.test.mjs` 两处断言修改、`contract-scan.test.mjs` 的 `CRCTL` 常量规避，均**正当且不失真**。

---

## 6. 设计调整汇总（S5.2）

### 6.1 与设计文档一致、无需调整

- 五 Agent 统一为「只执行当前节点，结果由平台 Runner 消费与推进」；未新增 Agent/Skill/运行时检查/路由表副本（符合 SC-T-PROMPT-001 `and` 约束）。
- 四 approve Skill **零改动**——任务 4.2 明确「不为制造 diff 改写正确 Skill」，实测四个 Skill 已具备正确的双模式授权、禁代签、驳回权威回退与幂等重放语义，因此只新增负向回归断言。
- `crctl status/next` 语义保持「唯一状态事实源/下一步以 next 为准」，未被写成派发授权。

### 6.2 实施期发现并已在本次收敛的偏离

| 偏离 | 处置 |
|---|---|
| T04a 最初误判 `cr-coordinator-agent.md:56` 为"已迁移"，实际仅需求期已迁移 | 已修 + 补回归守卫（R1） |
| 删除"第一份委派"时连带丢失发布动作的执行主体 | 三处补回主体（R2） |
| 简化 `trigger_outcomes` 时过度扩大豁免范围，吞掉异常上报失败 | 限定豁免范围（R3） |
| 测试断言中写字面量 `crctl status` 被 caller-contract 扫描器判为未登记调用点 | 改用 `const CRCTL = 'crctl'` 拆开字面量（扫描器对引号内命中直接跳过），断言语义不变 |
| TC-T-PROMPT-003 遗留 `void forbidden` 空循环 | 删除（R4） |

### 6.3 跟进项（2026-10-20 更正）

1. **历史事实保留**：CI pin `9d0a6a7` 无法复现已提交的 registry（四阶段 raw pipeline fields 已随 `2bfa3ad` 漂移，exit=2）；四个 `*_gen.go` 的 BASE 记录为 `2bfa3ad`，与 pin 不一致。该内容漂移已由 `5a913605b` 前移 pin 至 `9e41ad7` 并再生生成物修复。
2. ~~`generate-gate-nodes.mjs` 默认 `toolsDir` 解析到 multica 仓内的**空壳 `tools/`**，不显式传 `--tools` 时会读到空目录；建议后续对空壳做 fail-fast。~~ → **撤销（原结论有误）**：默认路径上跳 5 层正确指向 sibling `AI/tools`，显式 `--tools` 仍可用，不额外改路径逻辑、不加 fail-fast；文件缺失时既有读取会失败。详见 T04b §3.1 更正。
3. ~~`--check` 把 provenance SHA 纳入比对，导致每次 tools 任何提交都必须 bump pin；建议另立 CR 解耦内容一致性与 provenance。~~ → **撤销/已更正**：CI 使用固定 tools pin，不因 tools 新提交自动变红，仅在合同升级时前移；真实误报仅发生在「内容相同、Git HEAD 不同」的本地 checkout，仅 BASE SHA 不同造成失败。已由 Main 做最小修补：`--check` 前归一化 CRLF/LF，仅忽略来源注释 BASE 的 40 位 SHA/`unavailable`，保留 pipeline digest 与全部生成正文比较，生成时仍记录真实 BASE；不新增 flag/config/模块，不另开 CR/STDD。详见 T04b §6.1、§7。

---

## 7. 最终全量复跑记录（R1–R4 修复 + R1 回归守卫补齐之后）

**命令**（同 §2，31 个测试文件全枚举）：

```bash
cd "C:/Users/GOBAO/Downloads/AI/tools"
node --test --test-reporter=tap --test-concurrency=2 \
  skills/shared/crctl/scripts/test/*.test.mjs
```

| 指标 | 值 |
|---|---|
| 测试文件 | 31 |
| tests | 848 |
| pass | 848 |
| fail | 0 |
| cancelled | 0 |
| skipped | 0 |
| todo | 0 |
| duration_ms（node 自报） | 1695900.5734（1695.9s） |
| native exit | **0**（前台实测） |
| 持久日志 | `full-foreground.tap`（177930 B） |

**native exit 取得过程（如实记录，不掩饰）**：

1. 首次分离进程跑完 TAP 汇总为 `848/848、fail 0`（`full-final.tap`），但分离运行**无法拿 exit 码**。
2. 为补 native exit 另起 `cmd` 包装运行→`native-exit.txt` 记 `0`，但同次 `full-exit.tap` 为 **0 字节**。按纪律「空跑 exit0 不算绿」**不采信本次**；包装器机制经最小探针验证正确（`node -e "process.exit(3)"` → exit `3`），故该次为空跑/无效。
3. 最终以**前台阻塞运行**取得唯一可采信结果：`native exit 0`、`848/848`、`fail 0`、`0 cancelled/skipped/todo`、`1695.9s`、日志 177930 B。

三次运行的一致结论：`848 tests / 848 pass / 0 fail`；唯一可采信的 native exit 为 **0**。

---

## 8. S5 结论

| 任务 | 状态 |
|---|---|
| 5.1 完整测试与 JSON/Agent/matrix/lint 校验；真实证据、独立技术评审、diff 审查、失败模式检查 | ✅ 完成 |
| 5.2 汇总设计调整及 test-report，未完成/意外 skip 明确阻塞 | ✅ 完成（跟进项见 §6.3，含 2026-10-20 更正，均不阻塞本切片） |

**失败模式检查**（S5.1 要求）覆盖：

| 失败模式 | 是否发生 | 说明 |
|---|---|---|
| 测试通过但规则被掏空 | **发生过并被捕获** | `\b` 经 heredoc 折叠成 `\x08`，正则失效但全绿；靠注入真实违规词的探针发现 |
| 恒真断言/虚假覆盖率 | **发生过并被评审捕获** | `for (const forbidden of [...]) { void forbidden; }` 空循环，已删 |
| 断言比生产宽松 | 未发生 | `\blease\b` 探针验证对独立 `lease` 仍报红 |
| 把 skip/exclude 当绿 | 未发生 | 全量 0 skip / 0 cancelled / 0 todo |
| 把 checkout 更新当线上生效 | 未发生 | TC-T-PROMPT-002 固化「已合并 ≠ 已部署」；部署仍为用户职责 |
| 半套启用 | 未发生 | 双侧对侧改动均已落码（见 T04b 检查点 §5） |
| TestMain 空跑 exit0 当绿 | 不适用 | tools 侧为 node --test，TAP 汇总直接可验 |
