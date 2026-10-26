# AIFI-45：保留事故现场，以逐命令可丢弃库恢复测试

## 授权与结论

用户明确授权：“保留现库与事故证据不动，另建一个可丢弃的隔离测试库继续。”

仅恢复新隔离库中的 BUILD 测试；原库 `stdd_aifi45_20261022` 仍禁止测试/写入，原临时入口的 `AIFI45_DB_HOLD` 不解除，原事故记录与原始证据不改写。事故后82条审批记录的保留不是原83条历史恢复：missing41/extra40/changed0 的既有事实不变，未补造旧ID、签名或删除新增行。

本轮新 runner 限定静态复核通过，最终独立三组回归完成；旧 claim 锁序审核的 INCOMPLETE 不被此结果替代。完整业务 TC 仍0/49、5 major未关闭、消费关闭，BUILD/in_progress；未Gate3、commit/push、部署或真实CR试点。

## 最小变更

- `multica/scripts/aifi45-db/{run.mjs,run.test.mjs,README.md}`：Node标准库，无新依赖。每条Go命令新建nonce库/独立role，用 `template0` + `pg_dump --schema-only --no-owner --no-privileges`，以受限role导入，不搬旧业务行。
- 固定已批准容器完整ID、change label、running、loopback55432、原DB/user；不改变端口、容器、卷、rootless/WSL配置。管理操作仅在该容器的维护库创建/删除本轮资源；原库仅SELECT/pg_dump。
- 新role无superuser/CREATEDB/CREATEROLE/INHERIT/REPLICATION/BYPASSRLS，实际核新库/workspace与审批空表、实际角色，并实际验证它不能读取原审批表。密码仅内存/stdin/子进程环境，不写URL/密码证据。
- 测试只获新DSN，清继承DB设置及已知GitHub/knowledge/OpenAI/Anthropic凭据，禁止真实agent smoke。此为可信测试代码的数据库权限分离，不是恶意同UID代码/网络/daemon控制域隔离。
- 每条前保存原库137表内容摘要、82审批ID/整行hash、审批表原行SQL备份与schema；每条后（包括失败）比对并直接核原库其它session/所有advisory lock为0。漂移或未释放时停止，不继续清理/后续测试。
- 只按nonce+OID+owner+marker清新库/role，无FORCE/前缀扫删/REASSIGN/DROP OWNED；创建先记intent，最后catalog确认两对象实际不存在。回执不确定不得凭本地flag宣称清理完成。证据wx、事件append-only。
- `execution_start_claim_test.go` 不再借旧owner残留，改用既有Fixture创建并精确清理自己的user/member；产品StartTask与锁逻辑本轮未再改。
- CUSTOM #167、M11=20行；#166事故时记录保留。

## 失败、修复与独立审核

1. 首个新库 canary 实际跑到测试，因原fixture查询旧owner报 `no rows in result set` 失败；不是业务越权RED。修为自拥有user/member后 `claim-canary2` 为3/3（父1+子2），两次均原库未变、临时资源清理。
2. strong首轮发现两项MEDIUM，不予静态PASS：全叶SKIP仍可能成功；CREATE ROLE已提交而回执丢失时本地flag可能虚报清理完成。
3. 纯Node守卫真实RED：6项4PASS/2FAIL；修后6/6。丢ACK是对进程调用边界的mock故障注入，不是实际制造数据库回执丢失，也不计业务TC。原RED/首次不通过不覆盖。
4. strong同会话复核F1/F2均关闭，后续释放检查增量允许维持限定runner静态PASS；不替旧claim审核或生产准入。当前固定COUNT查询未见异常字段生成路径，truthiness的异常返回健壮性提示保留，不冒充已证明的漏洞。
5. `balanced` 早批次、`balanced2` 为有效中间源码回归，均保留；`balanced3` 才是加入逐命令释放直接证据后的最终快照，不能把旧执行追认为最终源码。
6. economy对本恢复包文档/Skill作partial核对，无硬矛盾；指出历史STOP标题仍标“最新”的P3措辞残留，主会话已改为“事故时快照”，不改原事故记录/原始证据。partial不升级完整验收；源码与DB结果未因措辞修订重写。

## 最终非作者回归（balanced3）

| 选择 | RUN | PASS | FAIL | SKIP | PASS leaf | exit |
|---|---:|---:|---:|---:|---:|---:|
| governance `^Test`，排除LiveGitHub | 817 | 817 | 0 | 0 | 739 | 0 |
| handler `^TestStartClaim` | 13 | 13 | 0 | 0 | 10 | 0 |
| daemon `Test.*Execution` | 48 | 47 | 0 | 1 | 44 | 0 |

唯一SKIP：`TestExecutionTrustRefusesLinkedRootInsideWorkspace`，Windows缺符号链接权限（`A required privilege is not held by the client`）；未计PASS。父子事件、重复选择不相加成业务TC，LiveGitHub没有运行。

三个最终nonce分别 `e31515b4dd2f6c71`、`b442ae178ea98084`、`6734151f137ea2d5`。每条：原137表COUNT合计6228行摘要与82审批ID/hash不变，`original_release={sessions:0,locks:0}`，新库/role末catalog均不存在，error=null。执行者交还DB权后，主会话作为唯一执行者仅追加最终只读事务：9次测试的全部before/after及当前现场都与首个全表快照一致，全部9对已知临时库/role实际不存在；`transaction_read_only=on`、锁0/其它session0。之后不再DB测试/SQL写入；非DB的vet与旧入口拒跑检查另存。

## 可核入口

同目录前缀 `disposable-db-20261024T162608Z-`：

- `preflight.json`：原审批82条与事故只读现场逐行一致；`{tools,multica}-models.json`：真实原生配置读取，schema1/configured。
- `claim-canary{,2}.*`：真实空库失败/修复、拒读原表、清理/保留证明。
- `review-{red,green}.stdout.tap`、`final-unit.stdout.tap`：纯Node失败与6/6通过。
- `balanced3-{governance,handler,daemon}.{events.jsonl,stdout.jsonl,stderr.log,meta.json,original-before.json,original-after.json,original-approval-record.sql,schema.sql}`：逐命令原始证据。
- `balanced3-report.md`、`balanced3-source-manifest.json`：非作者结果与6文件raw SHA256；后者的“including LF as stored”不是独立的LF规范化hash。主会话在 `final-static.json` 单列raw/LF与独立raw比对。
- `final-readonly.json`：主会话最终只读复核的全137表/82审批摘要、9批before/after共同比对与9对临时对象实际不存在、只读事务/锁会话0；不恢复旧缺失。
- `vet.*`、`old-runner-negative.json`：go vet三包exit0；旧入口仍在任何DB访问前无条件拒跑。
- `final-static.json`：源码/质量/binding/HEAD/index/CUSTOM与链接核查，文档P3措辞修订前快照；原证据不覆盖。`economy-report.md` 留存局部文档/Skill结论，`post-review-doc-static.json` 为修订后最新文档hash/链接与代码hash不变的无SQL补核，不追认其它DB命令。

模型：按两业务根有效配置请求，普通实现归主会话；strong=`OpenAIPersonal/gpt-6.1-sol/high`，balanced=`Gobao/deepseek-flash/max`。所有actual无后端回执，unknown；economy请求 `GB-JP/deepseek-flash/high`，局部文档/Skill核对结果另留，不升级为整体验收。

下一实现接缝仍为每repo当前descriptor、完整可信claim/project、隔离控制域、activation、legacy防降级和消费/永久派发恢复；本报告只恢复安全测试条件，不自动关闭这些major。
