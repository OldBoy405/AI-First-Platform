# M10 独立审查记录

## 1. 原六文件冻结候选（source 合同修复前）

来源：M10-build-report.md 的六文件 SHA 表；tools BASE `a5ecb5783fd8f7b5fa1d0d3b328b704199bbe011` + 259 文件 canonical-LF manifest `eb99e18aad2292a614a133b35a9265b6505c852a0bf7897c519e4dbf973d6984`。明确未提交，不把 BASE 当完整工作树身份。主会话整包 native exit1、192 父 PASS/3 FAIL/1 外部 SKIP、108 子 PASS 是该候选真实结果。

用户恢复子代理能力后，实际启动下列两个作者之外的 reviewer。首次运行各因 turn limit 未完成；该轮没有 PASS，随后沿同一会话只补未完成项，得到以下最终结论。两位 reviewer 全程只读、未运行 Go/DB/生成器测试或修改权限。

### Standards — 01a1547d-2ffc-75ce-a57c-1ba7f2461afe

最终已核对：

- 六文件 canonical-LF SHA 6/6 与冻结报告相同；gen 的原 UTF-8 BOM/CRLF 保留，Go 文件 LF 规范化送原生 gofmt 零差异。
- 独立核 tools HEAD、259 tracked 文件与 compact/ensure_ascii 路径→LF-SHA manifest，相等；不丢 BOM。
- runner_contract_test.go 的 HEAD 原三个测试函数逐字节保持，不因新增 imports 声称整个文件原样 prefix；无原断言/skip/exclude 弱化。
- 新增两个测试和四个 helper 覆盖四合同、12 个字段 digest 变异、13 类 fail-closed、四 header 篡改及 LF/CRLF；未引入依赖/CLI/engine/新权限表。
- 四 JSON schema/id/node 数、header/const/envelope digest 互相一致；code/writeback 常量仅生成/测试引用，没有新 runtime 接通。保留原投影 selector。

**结论：已检查范围无确认硬问题。** 不把静态/派生检查称作 reviewer 跑过整包或逐字节证明无手填；CI pin `9d0a6a7…` 等未来获准提交对齐属于已披露发布阻塞。

### Spec — 01a1547d-300a-75ce-a57c-1ba821d13445

最终已核对：

- 原生 Node 解码四 Go quoted JSON，分别与 TREG 四原始 export 的 raw 文本/值完全相同；pipeline.inputs/nodes 与 tools 模板值和数组顺序相同。
- 节点 6/4/11/5、权限 5/3/10/5 合计23、loop 1/1/3/0；permission 恰五字段，nodeId/ref/executor 顺序绑定，owner/auth 完整。
- 独立 Node 重算完整既定 body 的四 SHA，相等于 export、Go 常量和来源头；来源是 working-tree BASE + 实际 body digest，check 比较包含 header。
- schema/pipeline/inputs 同源 keys/重复拒绝、节点/kind/prompt/approvalPrompt、五字段权限覆盖、digest/行尾/顺序的 fail-closed 与相应新增正负测试；原三个测试无删除或新增 skip。
- 批准 wire pipeline 形状为 id/name/inputs/nodes，description/triggerCommand/scope/isDefault 原本不在 wire/export；不以泛词“完整”擅自扩大 schema。
- 未发现生成器改坏 source；旧整包三项 source 问题交独立根因任务，不将 M11 或后续未实施功能列为 M10 代码缺陷。

**结论：此生成合同范围无硬 P。** 未跑任何 Go/DB/生成器测试；未单独核 pipelineOwner 变异用例、producer 全矩阵负例或旧 run DB 迁移，后者不是本轮操作。CP005/007、carrier/runtime、四阶段平台验收仍不能由这份审查或局部测试代替。

## 2. source 集成回归及受控修订（ADJ-T-004，进行中）

根因报告 M10-source-repair-report.md 证实：source 正确持久化，但 producer writer 删除原 `{{inputs.source}}`，唯一 renderer 不再消费恢复输入；不是原生成链数据丢失。新33551隔离库精确三条真实 RED：native exit1、2.681725s、3 父 FAIL、0 SKIP。

Main 选择 minor 修订：只在 writer prompt 恢复既有 inputs.source 机器绑定，作为与刚读取的 cr.md source 原样核对的数据；原 Skill source 参数仍来自 cr.md，不以数据库值覆盖，漂移/读取失败停止、显式空值与缺失保持区别。不动 Go renderer/恢复/事务/权限，不造新输入 key/模板语法/运行时通道。

单 writer 01a15431-f3c3-75ce-a57c-1b9d5c663298 独占该 tools prompt 叶值、现 contract-scan 新回归以及原链派生四 Go 产物；原 generator 源码/runner_contract_test.go/其它 producer 文件冻结。旧候选身份保留历史，修后需四次真实导出、新259 manifest、原链生成/check、原三条与 source 邻接 GREEN，交回后 Main 整包与两路独立差异复审。

## 3. 修复后独立 delta 与 Main 最终收口（已闭合）

- 原两 reviewer 实际独立完成 source 修订 delta：Standards 证明相对初版只有 tools 两路径/server两派生产物，prompt只一个叶；旧测试完整raw前缀、source fixture及S0保护、BOM/CRLF/gofmt不变；Spec原生执行四export到内存并解Go quotedJSON，raw逐字一致、独立Node四SHA与header一致，source是非权威核对/缺值与显式空保持区别。均无硬问题，未跑Main整套。
- Main中间19034…候选Go完整native0/37.334530300s，195父PASS+108子PASS/1原LiveGitHubSKIP、304RUN/完结；但tools8联合native1/6.426670900s，213cases/212PASS/1FAIL：caller-09将新静态正则中的字面命令误当无workspace执行。该RED保存于OS Temp main-final，不能以两审查静态无P或Go绿掩盖。
- Main只增强contract-scan第878行：普通`\s+`分隔、核验完整version-set/显式非空workspace。没有改caller扫描器/allowlist、没有删断言或skip；source prompt、四Go/data/body SHA不变。Standards独立窄复核证明相对19034只有这一行、旧/新manifest都可复算；原实际prompt匹配，删workspace后新断言false、旧断言仍true，故是更强断言而非扫描豁免。CRLF/BOM不变，无硬P。
- **最终M10冻结tools259 manifest：073c75924e21f13c973bfeaa7197a33c98959004d00bab8f47fceafa6e034daa**；req body f839d28c…，其余三body不变。旧eb99/19034与原8d836f…只作历史。source/Go源前后259/3594文件不漂移。
- Main最终无filter/exclude治理整包：native0、**40.292777400s、195父PASS/0FAIL/1SKIP+108子PASS、304RUN/304完结、无DB skip**，唯一外部skip仍TestReconcileLiveGitHub。完整tools8文件native0、**7.095790200s、213/213、0fail/skip/cancelled/todo**；原generator默认check0/0.345544000s；后端go build -mod=readonly ./... 0/8.887457500s。
- 持久证据：`%TEMP%/aifi45-m10-repair-e4o5e8vm/main-closeout/` 内原生stdout/stderr/result JSON、259/3594 manifests；source authorRED/GREEN/四export见source-producer-repair-evidence；中间失败main-final保留，不覆盖。

**M10a/M10b动作验收完成，ADJ-T-004 minor/resolved，四个任务即时勾选。** M11已明确交给新单writer，尚未完成；SC003/CP005/007完整runtime义务、T04/T05/T-FINAL仍未完成。当前专属33551资源仅继续已授权后续测试，Main负责最终确切清理；不声称已删本批资源。无提交/push/部署/真实CR/Gate3。
