# AIFI-45 tools — Gate 2 后上下文

## 最新覆盖历史停点 — TREG/M11 已闭合，M12 绑定实施中

- M11原3P及REV004均真RED→GREEN、原双轴最终逐项关闭无hardP，70parser/130邻接真P；Main最终完整native0/36.797773400s、196父+177子PASS/1既有LiveGitHubSKIP、374RUN/完结/无DBskip，gen/vet/build0，3594/259源稳定；旧354/362/RED不覆盖。M11两动作已勾、CUSTOM#140同步，仍不宣称完整walker/CP003/005/007或四阶段实际执行。
- M12新单writer01a154e9-42d6-75ce-a57c-1bb8277722e4接原actor派发/reqresolver与两integration测试域，Main不并行GoDB；M11 typedRaw/guard/四生成物与tools073c…/reqf839…均冻结，source归因/handler/walker后续不提前动。33551独立测试PG继续授权切片，Main最终精确cleanup、当前未删。无提交/部署/真实CR/Gate3，T04/最终35/C1–C7继续等待平台闭环。

### 上一轮历史停点

- M11首版Main完整196父+157子PASS/1旧外部skip、354RUN/完结/无DBskip、gencheck/vet/build0；但Spec指出req ref helper首匹配/P1、漏repairRef/P2、passCondition空或非object/P2，Standards无P不替代此缺口。同一writer原三文件内真实RED→最小failclosed修复中，tools/四生成物仍冻结073c…/f839…，M11仍未勾、M12未开始。详multica M11-review.md；CUSTOM#140登记在途、M4总20行。

- ADJ-T-004已minor/resolved：requirement writer恢复inputs.source仅作与本次cr.md核对的非权威数据；原Skill cr.md参数、版本确认、漂移/读取失败停、路径安全原规则不变。真实source三条与邻接绿、独立双轴/delta无硬P；中间caller-09静态正则提及误报保留RED，只增强完整workspace断言，不改scanner/白名单，独立窄复核+重跑关闭。
- 当前tools259 manifest **073c75924e21f13c973bfeaa7197a33c98959004d00bab8f47fceafa6e034daa**；reqdigest f839d28c30ce2dc0eec709589f742abac1f45db96771d80a3ef3ef66a45ea32c，其余三body不变。eb99/19034与8d836f…仅历史，正式BASEa5仍未提交、CIpin9d0仍待未来授权对齐。
- Main M10收口tools8完整213/213 native0/7.095790200s（非最终35）；multica完整native0/40.292777400s、195父+108子PASS/1原LiveGitHubSKIP、304RUN/完结/无DBskip，gencheck/build均0。证据新aifi45-m10-repair-e4o5e8vm/main-closeout，source真实RED/exports另存source-producer-repair-evidence，中间RED main-final保留。M10a/b四动作已完成，CP005/007整体及SC003walker尚未整体验收。
- multica已交单writer01a154b3-3adf-75ce-a57c-1bb640cddd9b做M11 parser三共享文件，tools/原generator/四compiled冻结，M12未实施。33551本次自建测试PG继续已授权切片，Main最终精确清理；不能说本批已清理。T04/T05/T-FINAL仍未开始、无新审批/提交/push/deploy/真实CR，BUILD normal不变。

## 较早授权与停点（历史）

- Gate 1 已按用户“在这次修订中一起 确认”登记；测试超时诊断与根因修复为 C7，不另开 change。
- 用户审阅 Phase2 后回复“确认”，Gate2已通过CLI登记；随后回复“按推荐混合模式”。原生执行模式记录为normal（enabled=false），已通过CLI推进BUILD；不新增hybrid枚举。共享授权边界见execution-policy.md；Gate3、提交/push、真实审批和部署仍未授权。
- 记录根复用 AI First Platform Git；业务仓是 sibling tools/multica，STDD 不取代被开发系统内部的业务审批语义。
- 六个 capability，21 个 Scenario/TC/CP；权威 source 在 canonical/specs/code 与 canonical/specs/agent。Gate 2 CLI 已重渲染 Human View；不手改 MD。
- 关键设计：nodeId/executor与完整输入纳入现有registry digest；重复ref合法，多loop/no-loop原样保留；独立reviewer不由作者代替；authority/业务结果不等于CLI exit0。
- 核查更正：四个approve Skill没有跨阶段尾启动命令；保持当前正确边界，实际清理对象在Agent与模板。
- 测试诊断：crctl整文件358.14s自然exit1，294case=288pass+6fail，0skip/cancelled；两checkpoint case 18.12s可完成，短预算不能证明挂死。五个payload fixture根错位、一个已知TxError被包装INTERNAL_ERROR；保留最小RED反馈环和安全/未知异常边界。
- 前期其余超时文件当时尚未分类；现已由S0完整基线与5批复测收齐结果（875/875），不再沿用“尚待分类”的旧判断。全35文件及新增回归始终保留，不skip/exclude、不禁hook。
- 临时原始证据目录名 aifi45-node-diag-uubvw97i；完整命令和结果在其crctl-file-native目录（不把敏感环境复制进仓）。
- Phase3顺序：完整基线与真实失败根因→四阶段合同→multica生成/消费/执行恢复→去旧接力→完整回归，不半套启用。每slice先RED→GREEN。tasks.md/slices.md承载计划，只有真实验证后勾选。
- S0新完整基线已自然完成：35文件/869case，862pass/7fail/0skip，2116.4877s。第7项caller-09为非执行提及扫描误报，窄锚定并加真实调用负向回归；其余原五fixture及authority分类已修。
- S0b定向13/13；独立审查发现的事务exit绕finally问题已修复（私有来源标记后重抛，安全边界格式化），真实journal恢复先RED后GREEN，两轴复审0硬问题。主会话独立cleanup/trust2例为2/2、11.522s；持久证据aifi45-s0-main-cj2lod0q。详S0-build-report.md、S0-review.md和ADJ-T-001。
- S0c首轮后台单次复测异常结束，非通过：209.5738s、native/supervisor均3221225786（0xC000013A）、timed_out=false、无TAP最终统计。用户已确认非主动停止；终止发起方仍未证明，仅可断定该后台承载方式不可靠，不作为证据。证据aifi45-s0-final-run1/。
- S0c改用5个前台顺序批次（同35文件、concurrency2、无name过滤/排除）已跑完全绿：合计875 case/875 pass/0 fail/skip/todo/cancelled，各批exit0；较基线869新增6项回归，断言只增不减。合同/矩阵/lint入口exit0，保留既有handover-cr OUTDATED告警。证据aifi45-s0-run2/b{1..5}.log，详S0-final-report.md。
- S0切片已完成，任务0.1–0.8已勾；4个修复文件仍uncommitted，.gitignore既有改动保留。用户最新明确授权“直接进入T01四阶段合同改造，能并行的并行，需要我参与时才停下来”，解除此前仅跑完复测就停的要求；仍不提交/push/部署/真实CR/Gate3。
- T01–T03已完成tools侧实现及两轴独立复审，任务1.1–3.4已按真实证据勾选。T01/T02作者移交JSON后T03接管；T03独立Skills/合同测试与emitter工作并行，未并发写共享模板。首轮Spec两项P2（缺loop漏自审、歧义repairRef取首项）均真实RED、修复轮1关闭；emitter最终69/69，Spec另独立复现原反例/对照6/6，Standards无新增硬问题。
- 源冻结后主会话8个完整目标/邻接文件212/212，native exit0、6.858714s、0fail/skip/todo/cancelled，259tracked LF哈希前后相同；T03另8/8、真实10CP逐条正数case通过。不是全部35新版最终套件，也不是平台验证。详T01-T03-review.md、TREG-handoff.md，源码writer/审查worker均已完成并交回。
- 最终四registry实际导出节点6/4/11/5，23绑定，code三个loop/writeback无loop，原字段完整且Node重算SHA一致。未提交候选LF manifest eb99e18aad2292a614a133b35a9265b6505c852a0bf7897c519e4dbf973d6984；HEAD仍a5ecb578，不能以HEAD冒充完整候选或覆盖旧run digest。质量入口全exit0，既有OUTDATED告警保留。
- ADJ-T-003仅校准TPL三项CP文件定位和S0 CP003实际测试名，保留全部SC/TC/CP及深回归。nativevalidate exit0/既有5 AND告警；canon generate的spec参数实际被忽略而仅生成proposal，不声称Agent HumanView已更新、不手改索引、不扩scope修STDD。
- multica M00/B-DB 已解除：用户授权专属临时 Podman PG 迁移/测试/清理并回复“按建议继续，需要我参与时再停下来”。首轮失败为既有 code 公钥 fixture 写错根，已真实 RED→GREEN 最小 test-only 修复，独立 Standards/Spec 无硬问题并登记 CUSTOM #26；主会话 governance 整包 native exit0、20.688404s、193 父+75 子 PASS、0 FAIL、1 原有实时 GitHub SKIP，269 RUN/269 完结、无 DB 空跑。tools259文件 manifest 未漂移；不把该基线当四阶段 CP 完成。首轮资源已清理，续作新建带唯一标签的专属容器/named volume（仅回环动态端口、651迁移），用毕只清自建资源。multica M10a/M10b 原生成器六文件已冻结，定向 10 父+46 子 PASS、生成/check 通过，但 Main 新候选整包 native exit1：192 父 PASS/3 FAIL/1 原有 GitHub SKIP、108 子 PASS；三个 requirement recorded-source 渲染/采纳/恢复回归未关闭，不能拿 M00 或定向绿代替。两次独立审查 Agent 调用均返回 `Pi Web built-in sub-agents are disabled`，未启动、未绕过权限/未自审代替；此原权限阻塞现已由用户“子代理已经恢复，继续”解除，Main 已实际启动 source 根因 writer 及独立 Standards/Spec 两个 reviewer；先修复/复测三条 source 回归并完成审查，再进 M11，不绕过或自审替代。自建 PG 容器/具名卷经标签校验精确删除、端口复核关闭、私密连接文件已删；上一批 writer/planner 已交回且旧资源已清；续作另建带标签临时 PG（回环33551、651迁移），source writer 唯一目标 DB 测试，两 reviewer 只读六个冻结 M10 文件，Main 负责用毕精确清自建资源。CUSTOM #26/#139 已登记，M10 仍未标完成。两路旧M10完整独立审查随后均无硬问题；source根因已证为writer删去既有 inputs.source token，恢复记录本身已保存、原生成器同源无丢字段。Main 以 minor ADJ-T-004（暂 unresolved）重开 producer 一个 writer prompt 叶值和现 contract-scan 新回归，恢复 inputs.source 仅作非权威恢复核对；保留 cr.md Skill参数/漂移即停/读失败不降空及真实版本确认。单 writer 负责原链四 Go 产物重生；其它producer/generator/Go helper不动，先真实 RED→GREEN/新源身份冻结/整包/独立差异复审。原eb99 manifest及8d836f…requirement digest保留历史，不假装是修后候选。详 sibling change 的 M00-db-baseline.md/M10-build-report.md/tasks.md。T04 去接力仍等平台闭环，B-SWEEP 待隔离实测；CI producer pin 对齐、T05/Gate3/提交/push/部署仍未完成或未授权。
- 实际生产部署/停服/存量接管另需授权，不能由STDD Gate或代码审批暗推。
- STDD extract-proposal未识别capability，已核对canonical权威源；不扩scope修改STDD产品。无匹配项目经验。
- new产生的TODO种子不计真实capability、不渲染；由现有Gate2 renderer跳过，未修改其初始化索引。
