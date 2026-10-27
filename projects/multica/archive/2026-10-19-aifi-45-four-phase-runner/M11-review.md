# M11 独立审查与收口记录

## 最新收口：M11 动作已验收，全部审查 P 闭合

- 第二轮先读真实emitter predicate/shape规则，不照建议猜policy枚举：独立review确startsWith(review-)必有loop，显式loop/replay/policy/repairID的presence不得按零值混同。非空policy可独立出现、不枚举policy值，普通无loop合法；不把write-test-report当独立review、不加replay目标唯一限制。
- 真实REV004 RED68 RUN/58P10F，覆盖缺/null loop、显式[]/null replay、空policy/ID及原Go错拒合法单policy；修后补同分支2个null变体，**70/70 PASS**、原130邻接全PASS/0skip；旧58/50cases及427raw前缀不变。作者review-fixes-round2与旧证据分开保存。
- 原Standards与Spec分别完成最终delta：**REV001/002/003/004均闭合，无新hard P**。只读复核，没跑suite，不把意见算业务成功；Raw/presence同源/typed完整、重复ref局部guard与四schema/无loop原义保留。
- 最终M11 LF：runner `3c7e58d12a6e956bab41bc4c1f16be5a9d0c9533a96b71f2d9e242a8c117ac8f`；req-registry `27fa7d145e0d8241b2902910ca7ec28788fbdcefd658858d832362594aa5e112`；contract `5817850ffbcd54961874621d37e74c88f931f679109b4bd262d6d23e192df7a9`。tools073c…、四compiled/generator/renderer/state未变。
- Main最终独立完整 `go test -mod=readonly -count=1 -v -json -timeout 1500s ./internal/governance/`：**native0/36.797773400s、196父PASS+177子PASS/1既有LiveGitHubSKIP、374RUN/374完结、0FAIL/DBskip**；gencheck0/0.345719300s、vet0/0.474851800s、build0/3.433185000s，3594server/259tools源前后稳定。证据`%TEMP%/aifi45-m11-main-final-r2/`，旧354/362/RED全部保留未覆盖。
- M11两动作即时勾选，CUSTOM#140登记；这只闭合parser/声明消费动作，不是SC003完整walker/CP003/005/007/最终四阶段验收，旧architecture位置型walker仍M20边界。M12已交新单writer01a154e9-42d6-75ce-a57c-1bb8277722e4，角色绑定/来源/handler/实际执行未因此提前完成。
- 当前33551专属测试PG继续已授权M12，由Main最终核runid/容器/卷精确清理，不能宣称本批已删；BUILD仍normal/in_progress，无提交/push/部署/真实CR/Gate3。

## 以下为首次审查与中间修复历史

### 旧停点：首轮三 P 已闭合，新 loop 完整性 P2 第二轮修复中

M11 未勾完成、M12 未开始。首版三文件整包通过后 Spec 发现三个缺口；作者真实反例修复、Main新候选完整362 RUN通过、两位独立reviewer已复核关闭原三P。但Spec又找到review节点可无loop/显式空replay与absence混同的同类P2，现第二轮三文件内补齐既有emitter的loop shape规则。不以整包绿或旧三P关闭掩盖新增缺口，没有新需求/审批/引擎/任意body认证入口。下表保留首次报告当时状态，最新结论见后节。

## 首版冻结与真实验证

- tools259 canonical-LF manifest仍 `073c75924e21f13c973bfeaa7197a33c98959004d00bab8f47fceafa6e034daa`，四compiled/generator/producer未改。
- 首版三LF SHA：runner.go=`2524e7192fc6fd30d3225602959b63279c26716237084249622773f77b01191f`；req-registry=`16cc22604f497923bcaeb3b8b33f7b43b6876979bee1a7ed2a19f2f1548cc313`；contract-test=`18bc44535b9199762553de11fc8835aedde2131ee0b68d91e908454b3d6cce8f`。后续修复会改变三文件，不能把此表当修复后身份。
- 作者真实行为RED为11 RUN/6 PASS/5 FAIL；最初用现共享parser拒其他三个pipeline形成错误，而非未定义符号编译失败。首版GREEN扩全原TestMDispatch003为50 RUN/50 PASS，原427行完整raw前缀不动。作者另外执行的完整Go包/vet/build是作者证据，不代替Main。
- Main唯一DB执行者独立完整 `go test -mod=readonly -count=1 -v -json -timeout 1500s ./internal/governance/`：native0、**37.527436800s、196父PASS+157子PASS、1原有LiveGitHubSKIP、354RUN/354完结、0FAIL/DBskip**；gen default check0/0.295725900s，vet0/0.482892400s，build0/3.671315300s。3594server与259tools前后一致。
- Main证据 `%TEMP%/aifi45-m11-main/` 保存原生logs/results及全source manifest；作者 `%TEMP%/aifi45-m11-evidence/` 独立保留。没有工具/系统环境改动、外部KB/真实DB/真实CR/Gate3/提交/部署。

## 独立 Standards — 01a1547d-2ffc-75ce-a57c-1ba7f2461afe

只读最终结论无硬P：三SHA/raw与报告一致、仅三源文件变化，contract原427行SHA=`5430fb7c…0202b73`保持；四生成物/源码/权限/API/deps未越界，无Go伪canonicalizer/近似SHA/legacyfallback；三文件全CRLF无BOM、gofmt一致、注释英语；req共享validator、四schema/ID/expectedpair、typed与Raw/ID权限/repair解析符合已检查范围。未运行Go/DB/任意suite，不把模型意见算运行证明。并明确旧architecture位置型walker仍在、req ref helper仍在，当前固定compiled实际形状由原测试守护；不是本轮已实现四阶段walker。

## 独立 Spec — 01a1547d-300a-75ce-a57c-1ba821d13445

只读静态反例；尚需由作者真实RED确认，不直接冒称已运行：

| ID | 级别 | 位置/触发 | 影响/最小处理 | 状态 |
|---|---|---|---|---|
| M11-REV-001 | P1 | req-registry nodeByRef/approvalNodeOf：合法新nodeId+permission的重复语义ref前插时取首个 | generic数据允许重复ref，但没有nodeId选择权的旧req语义桥接不得find-first；对应必需语义节点歧义时fail closed，不把ref全局唯一限制加回，不提前改walker。这里是受控fixture/未来合法声明的consumer问题，不声称当前有外部raw入口远程利用 | 修复中 |
| M11-REV-002 | P2 | loop保repairNodeId、删repairRef被接受 | 与emitter要求非空ref且与显式ID一致对齐；不能空ref进入后续repair视图 | 修复中 |
| M11-REV-003 | P2 | loop.passCondition={}或[]（甚至scalar）只检查有效JSON/非null | 与emitter对齐为非空object，保完整Raw/未知keys；不造条件DSL/eval/GoSHA | 修复中 |

如 writer 发现某触发先被其它guard拒绝，必须记录真实原因并构造满足其它前置、能命中所述缺口的反例，不能仅复制review verdict。duplicate write-PRD 若先触发repair-ref歧义，则用无loop引用的push-progress或明确原repair ID，避免假RED路径。

Spec同时记录architecture仍固定Nodes[0..3]的后续walker边界，但按M11已披露范围不列本轮硬P；M12/M14/M15/M20未实施不能拿来扩本轮实现。

## 首轮三 P 闭合与新 M11-REV-004（P2）

- 原Spec实际复核：M11-REV-001/002/003全部闭合，Standards delta无硬P。作者先真实RED58RUN/50P8F，命中duplicate push-progress/human、repairRef缺失、空/array/scalar passCondition；修后同58P，原50cases与427raw前缀完整，原邻接118P/0skip。
- 首轮修后LF：runner4abdefff807f4b92d4157cc0746885160ab13b385ba7d6e020ec335088a25c1e；req-reg27fa7d145e0d8241b2902910ca7ec28788fbdcefd658858d832362594aa5e112；contract9916eb5ec3f022f30c002653abc5873b95722164bd1ad5e9c57f5482055c0f14。后续第二轮会再变，此表只历史。
- Main独立修后完整native0/**37.726270800s、196父PASS+165子PASS/1既有LiveGitHubSKIP、362RUN/362完结、0FAIL/DBskip**；gencheck0/0.320639000s、vet0/0.446120500s、build0/3.890475200s；3594server/259tools前后稳定。证据`%TEMP%/aifi45-m11-main-final/`，旧aifi45-m11-main首版354与作者review-fixes分开保留。
- 新 **M11-REV-004/P2** 静态触发：删code review-dev-plan.reviewLoop，Go仅对非nil loop校验；或显式replayNodes=[]并删/清replayPolicy，Go以len0当未声明。与原emitter:123/134已存在的独立review必有loop、显式replay非空且policy配套不一致。不是原三P再次失败，也不默认声明任意远程raw攻击入口。
- 第2轮作者同三写域/soleDB：先真实RED核定具体predicate，再一次对齐本validateReviewLoop的已批准required/type/presence/policy规则，保Raw/unknownkeys、code三loop与wb no-loop/普通无loop，不把所有有loop节点当独立review，不造DSL/SHA/表/engine。保首58case与427原前缀；证据review-fixes-round2，完整包仍留Main。若第三轮同一阻塞仍不收敛按原授权暂停，不无限补丁迭代。

## 修复所有权与验收前置

唯一writer/DB测试者仍 `01a154b3-3adf-75ce-a57c-1bb640cddd9b`，只原三文件+M11-build-report；Main不同时Go。先新增真实counterexample RED→GREEN、全TestMDispatch003和原合同/req/attempt/source邻接，保护原断言/BOM/CRLF/四compiled/source；本轮完整包留Main。完成后新三SHA冻结交回，Main全量+两路delta独立闭合后才勾M11，未知/不收敛按既定授权暂停而非绕过。33551本批专属PG仍用于授权测试，Main最终精确清理。
