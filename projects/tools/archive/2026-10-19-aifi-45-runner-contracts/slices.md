# AIFI-45 tools — Phase 3 切片执行计划

## Dependency Graph Summary

```text
T00a 全35文件基线/分类
  → T00b authority夹具与错误根因
  → T00c 完整复测/独立审查（检查点1）
  → T01 executor绑定
  → T02 四registry/digest/loop
  → T03a 输入与版本 ─┐
  → T03b drift/block ├→ multica生成/消费/执行恢复闭环
  → T03c workspace/archive ┤             ↓
  → T03d upstream/recovery ┘   T04a 去Agent接力
                               T04b 同源索引/交互
                               T04c approve边界
                                  → T05 整套验收 → 人类Gate3
```

T03子片概念上可独立审查，但修改共享模板/测试文件时必须串行。T04去接力与平台接管协同交付，不在中间节点安装启用。跨仓检查点报告不新建业务审批节点。

## Slice Execution Plan

| ID | P | 风险 | 规模 | 并行组 | TC覆盖 | 独立交付目标 | 依赖 |
|---|---|---|---|---|---|---|---|
| T00a | P0 | 中 | M | 无 | TC-T-TEST-001、TC-T-TEST-002 | 完整文件发现、真实exit/计时/分类，复现已知RED | 无 |
| T00b | P0 | 高 | M | 无 | TC-T-TEST-003、TC-T-TEST-005、TC-T-TEST-006 | 原断言下修夹具根、共享authority TxError分类、合法容忍/未知异常回归 | T00a |
| T00c | P0 | 高 | M | 无 | TC-T-TEST-004 | 全量自然结束、真实case计数、既有三校验和独立review | T00b |
| T01 | P0 | 高 | M | 无 | TC-T-BIND-001、TC-T-BIND-002、TC-T-BIND-003 | owner≠executor，nodeId唯一，独立reviewer，human不派Agent | T00c |
| T02 | P0 | 高 | M | 无 | TC-T-REG-001、TC-T-REG-002、TC-T-REG-003 | 四schema、完整inputs/digest、重复ref和多loop/无loop | T01 |
| T03a | P0 | 中 | M | 无 | TC-T-TPL-001 | authority版本继承/new-vs-legacy输入 | T02 |
| T03b | P0 | 高 | M | 无 | TC-T-TPL-002 | exit0 drift/block不误当业务成功、真实测试/评审证据 | T02 |
| T03c | P0 | 高 | M | 无 | TC-T-TPL-003 | camelCase operationalWorkspace与归档重入合同 | T02 |
| T03d | P0 | 高 | M | 无 | TC-T-TPL-004 | 上游先复评与原权限内结构化recovery | T02 |
| T04a | P0 | 高 | L | 无 | TC-T-PROMPT-001 | 五Agent和对应模板统一当前节点职责，禁止评论/跨阶段自启 | T03全部+平台接管闭环 |
| T04b | P1 | 中 | M | 无 | TC-T-PROMPT-002、TC-T-PROMPT-003 | 索引/权限同源、必要人类输入与失败回执 | T04a |
| T04c | P0 | 高 | M | 无 | TC-T-APP-001、TC-T-APP-002 | 保持四审批Skill已有正确边界、幂等与人工驳回 | T04a |
| T05 | P0 | 高 | M | 无 | 全21TC复验 | 全量质量、技术评审/diff/失败模式/test-report，不自动批准Gate3 | 全部 |

**规模口径**：S为1–2TC/单文件，M为3–5TC或2–3紧密相关文件，L为跨多个提示词/合同。T04a的五Agent职责必须一起被验证，不能为形式上的小切片留下相互矛盾的自动接力；实施时可分文件RED/GREEN，但只按整体合同验收。

## 五步分析与Rationale

1. **依赖**：先恢复可信测试基线，再改变Runner输入；否则新合同失败与旧夹具失败混杂，失去RED/GREEN解释性。
2. **风险**：authority/权限/digest/业务结果/审批均高风险；共享函数处修根因，不逐caller打补丁；签名、隔离和原安全断言不可删。
3. **估算**：表中为相对实现复杂度，不是测试timeout。已知crctl单文件需约6分钟，完整套件预算应更长；不把超过旧15s/200s当挂死。
4. **分组**：基线、根因、全量验收分别可被独立review拒绝；模板按输入/结果/workspace/回修拆开，避免四阶段改成一个不透明大任务。
5. **并行**：当前只并行独立的文档规划/事实核实；业务测试S0只有一名worker独占crctl.mjs及crctl.test.mjs。先不安排会竞争Git夹具、共享模板或测试源的写入。

## 每片执行与证据

- Read：对应canonical Scenario、Agent CP与现有caller/测试；跨行读取先规范CRLF。
- RED：运行真实目标测试，确认失败发生于目标分支；无匹配case不是RED或GREEN。
- GREEN：根因处最小修改；需要新增依赖/改环境/扩大权限或范围时停。
- REFACTOR：仅清理本切片必要重复，保持公共接口；不新建测试平台或通用编排引擎。
- VERIFY：目标+邻接回归、真实exit/耗时/case/skip与独立review；主会话核对后立即勾tasks。
- 连续三轮同一阻塞未收敛则停。最终测试发现不能保留name过滤/排除；不禁hook取得通过。
- S0证据留S0-build-report.md，后续按既有STDD切片记录保留；不把这些过程文档变成产品运行时账本。

## 文件边界

- T00：`skills/shared/crctl/scripts/crctl.mjs`、`skills/shared/crctl/scripts/test/*.test.mjs`中的已证实根因，保留`.gitignore`既有改动。
- T01/T02：`pipeline-templates/emit-registry.mjs`、对应test及原四模板的必要执行声明。
- T03：原四模板及既有merge/writeback/archive/test/version-set输出/测试合同；daemon执行由multica承担，不在tools实现第二套本机路径解析。
- T04：原五Agent、必要README/索引/矩阵及既有合同测试；四approve无真实矛盾就只加负向保护。
- 不注册CR、不改真实账本，不提交/push/部署；共享授权以execution-policy.md为准。
