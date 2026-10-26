# STOP — 隔离库历史漂移，未恢复、不得验收

## 状态与责任

本次扩大到旧 governance 全包前，主会话错误地把签名组件 exact-owned fixture 的保证外推给了整包，只保存历史 ID/整行 hash，未取得可还原原行的备份。扩大选择是主会话的执行决策，不把责任转嫁给独立执行者。发现漂移后停止所有后续 DB 测试/SQL 写入与主线接线，仅做只读取证、保存现场；不手工补写旧 ID、删除新增历史或重新解释为“无数据丢失”。

**未取得可直接恢复缺失41条原始行的备份。需要人工指定恢复源，或授权另建可丢弃测试库；在此之前不继续写原批准库。**

## 核实事实

- 批准对象仍为专用容器 `666bfec52ac3c3d13b43389891f50c4105833198eab7e4167b76f014a774e823` / DB `stdd_aifi45_20261022`。未访问共享库。
- 批前 83 条；批后及主会话独立只读复核 **82 条：missing41 / extra40 / changed0**。完整 ID 集及当前 extra 的 workspace/CR/stage/hash 已落 `-incident-diff.json`，不以净少1掩饰41条缺失。
- 原 `20261024T122543Z-aifi45-review3-baseline42-before.json` 列出的 **42个受保护ID全部仍在**，其全行 md5 与本轮开始83行快照逐个相同；缺失41属于另外的历史。不能因此声称83全部保留。
- 缺失41已在六份旧元数据中映射到 CR，来自 `CR-9002-*`、`CR-9006-*`、`CR-9008-*` 测试 fixture。映射证据 `-incident-missing-evidence-search.json`；不是生产/真实CR数据，但仍违反本轮完整83行保留约束。
- 作者与独立复跑的 **5份源码 raw SHA256 完全一致**。balanced 首报与 T before-manifest 比较的是实施前快照，差异属预期；该比较不构成作者证据失效。补正已在 `-balanced-forensics.md` 及 `-incident-backup-search.json` 留证。
- 批后及只读取证时 advisory locks=0、其它 client sessions=0；独立执行者已交还，无并行 DB writer。
- 本轮临时测试入口 `aifi45-gotest.cjs` 已在任何容器/DB访问之前无旁路拒跑 `AIFI45_DB_HOLD`；实际负向检查通过。这不是更改数据库权限，也不代表其它入口被技术性禁写。
- `final-static.json`：作者5文件raw快照不变、四quality/binding不变、两仓main/原HEAD/staged0、gofmt/scoped diff-check通过；CUSTOM #166和M11实际19行、最新跨仓链接存在。没有用静态成功抵消DB事故。

## 根因及未证明部分

- 源码直接显示 `governance/crsync_test.go` 的 `resetCR` 按 `cr_id` 删除 `approval_record`，`gate_projection_test.go` 的 `resetGateProjection` 同样直接删除，再调用 resetCR。TestMain cleanup 不清该表，因此旧全包测试遗留的历史会在后续同CR测试中被替换。
- 本次 full `^Test`（排除 LiveGitHub）把这些旧 approval/crsync fixtures 纳入执行；41条缺失CR均在该测试命名族，和上述删除机制一致。**没有逐条 SQL 审计日志，尚未把每一条 DELETE 唯一归因到某次具体测试调用**，不反推未有的因果证据。
- 这不是新 claim 分支的业务断言失败：但测试安全不变量失败，因此全绿批次仍整体 STOP，不能验收，也不能继续对同库重跑来“证明”根因。

## 已保存证据

统一前缀 `claim-build-20261024T153817Z-`：

- T validation `db-before.json`：原83条 ID/全行md5；`db-before-independent.json`：批前83/83、locks0/session0。
- M validation `balanced-{governance,handler,daemon}.{stdout.jsonl,stderr.log,meta.json}`：原始三条命令与返回码；`balanced-report.md` 原报告保留、`balanced-forensics.md` 为补充，不覆盖原证据。
- `incident-current-readonly.json`、`incident-diff.json`：主会话只读复核、全missing/extra/changed集合与原42保护集比对。
- `incident-backup-search.json`：176份有界JSON证据结构检查，未定位可恢复缺失41条完整原行的备份；命中的历史记录以 ID/CR/hash 元数据为主，不等于穷尽用户其它备份位置。
- `incident-missing-evidence-search.json`：246次旧元数据命中，覆盖全部41个缺失ID及CR映射；只用于归因，不是原行备份。
- `incident-current-approval-record.sql` + `.meta.json`：**事后**只读导出当前 `public.approval_record`，保存剩余原行/签名字节及新增现场。不是事前备份，未执行恢复，不含其它表或凭据导出。

## 独立结果口径

- 治理 full选择：817/817、0skip、exit0；handler claim：13/13、0skip、exit0；daemon Execution：48事件=47PASS/1 Windows symlink权限SKIP/0FAIL、exit0。父子/重叠均不计完整TC。
- strong 两轮仍 **INCOMPLETE**：已核所见 runtime→task 与 claim 锁链，未穷尽改runtime的路径/FK/teardown，不能写完整静态PASS。
- economy 完成主报告计数/内部边界核对，CUSTOM正文/相对链接未完成，不算整体验收。
- 本片作者 RED→GREEN 与 `go vet` exit0证据保留，**不抵消历史安全失败**。没有完成业务TC/slice、没有关闭5个major、没有开消费或推进Gate3；没有commit/push/部署。

## 人工决策点

1. 如果有事前原始DB/表备份：请指定路径，由后续恢复方案明确哪些行/关系可还原；不直接覆盖当前库。
2. 如果没有：需明确授权保留原库/事故现场，另建全新可丢弃隔离测试库继续；不得将82条自动认作原83恢复成功。旧危险 fixture 必须先隔离或加保护，再扩大测试。
