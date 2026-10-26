# AIFI-45 当前 task/project claim 读面（BUILD进行中）

## 当前结论

主会话已实现 wire §3.4：既有task status GET显式claim query、MDT认证/只读同快照/冻结queue project与live issue/project核对；新SDK严格解析及运输边界；daemon新合同在根准备/授权安装前实际回读。SDK读取失败不再沿prepare-error发送task-ID-only终态回调。**这不是完整终态代次CAS、execution-binding签名、凭据隔离、activation或消费；完整0/49、5major未关闭。**

用户原文“继续，非必要不停下来”“继续”。不为常规阶段结束重新等批准；下一必要片是终态callback完整代次fence/重放，再继续每repo本机事实与受保护控制域。Gate3/commit/push/部署未授权。

## 真实分工与模型

产品主会话；balanced `01a1712c-a7d9-77b9-a3c5-0ee2ce56920b` 实写公开MDT HTTP矩阵及真实SDK贯通，`01a1712d-2ee1-77b9-a3c5-0ee4fc221846` 实查生产项目来源并写SDK矩阵，`01a17158-a034-77b9-a3c5-0eed780e9d5f` 独立终态fence事实调查后接独立新库回归；strong `01a17158-a01c-77b9-a3c5-0eea6fbcaf49` 独立server/SDK/caller分段审核。非作者独立三组已完成并明确释放DB权；server/SDK/caller限定静态均完成，无剩余确证新finding，不替代全局C1或其它终态fence。

每次必要派发前从M源码根原生config models重读schema_version=1/kind=configured；最终冻结前M/T两根再次保存 `final-review-*-models.json`。requested/configured：balanced Gobao/deepseek-flash/max、strong OpenAIPersonal/gpt-6.1-sol/high；无后端actual回执，actual unknown。

## 行为和边界

- `agent_task_queue.project_id` 是冻结入队列，原claim `project_id`是live来源投影，二者不能混用。新mode只支持issue-backed；NULL/异项目/跨workspace/错误daemon/代次/终态拒绝，其他来源fail closed，legacy status不变。
- shared `protocol.ParseExecutionClaimTime` 在time.Parse有损截断前限制最多6位小数、拒comma；SDK request/response和server新mode共用。原StartTask旧解析不在本片变更内。
- opaque daemon非UUID但不能空/C0/C1；workspace只取认证，伪header不影响scope。同一个RR/read-only事务的已有sqlc查询，无新表/迁移/FK/sqlc生成物/端点/任意nonce签发。
- exact8字段metadata无缓存/redirect降级，1MiB/严格完整JSON；SDK非200 body不读不echo；时间UTC回显和精确代次比较。
- snapshot不是持续freshness/本机进程或根/CR归属证明；现有同UID daemon profile可读问题未解除。当前资源descriptor与此claim是分别的读面，不自动组成可消费proof。

## 作者真实运行（每条独占新库）

| 标签 | RUN/PASS/FAIL/SKIP | PASS leaf | 含义 |
|---|---|---:|---|
| http-red1 | 1/0/1/0 | 0 | 原公开status只回1字段，缺新schema，业务RED |
| http-green1 | 1/1/0/0 | 1 | 首个MDT正例 |
| sdk-red1 | 1/0/1/0 | 0 | 可编译stub对合法八字段响应报unavailable，业务RED |
| sdk-green1 | 0/0/0/0 | 0 | 漏c. receiver造成编译错；原始证据保留，不算业务RED/验证 |
| sdk-green2 | 1/1/0/0 | 1 | 修正receiver后公开SDK正例 |
| http-red2 | 21/17/4/0 | 16 | 三个失败leaf：Go截掉第10位小数秒、C0/C1 daemon；一个失败父 |
| daemon-red2 | 39/36/3/0 | 36 | 小数秒SDK input一失败leaf/父、旧根优先一失败leaf |
| http-green2 | 21/21/0/0 | 19 | 精度及daemon控制字符根修 |
| daemon-green3 | 39/39/0/0 | 38 | SDK矩阵/根前回读 |
| callback-red1 | 1/0/1/0 | 0 | handleTask真实stale-read后发1次不带代次terminal callback |
| author-governance | 851/851/0/0 | 770 | 含真实SDK→MDT→公开HTTP→DB正反贯通 |
| author-daemon | 113/112/0/1 | 106 | 含callback=0修复；唯一Windows symlink权限SKIP不计PASS |

### 最终非作者回归

| 标签 | RUN/PASS/FAIL/SKIP | PASS leaf |
|---|---|---:|
| independent-governance | 851/851/0/0 | 770 |
| independent-handler | 13/13/0/0 | 10 |
| independent-daemon | 113/112/0/1 | 106 |

均exit0/error null，唯一 `TestExecutionTrustRefusesLinkedRootInsideWorkspace` 因Windows symlink权限SKIP，未计PASS。每条执行前由非作者wx存19项实际raw/LF source pin、与冻结一致，后再次核无漂移；宿主复核三份均19/19。[实际报告](claim-project-20261025T052646Z-independent-report.md) SHA256 `c266985a6d67dfa9d8c902d815c511eabddd47805c39fb5b3e4c8871f6b33378`。

重复选择/父子事件不累计完整TC。HTTP/SDK正反、输入精度、alias/重复键/尾JSON/旧status降级/范围/代次/终态/运输边界均见实际测试，loopback假平台SDK测试不冒充真实认证。

## 源码和DB证据

12条命令分别执行前wx保存source manifest，执行后核无漂移。SDK单包运行时排除同时由其他writer修改且不编译进该包的governance _test文件，manifest scope明确；不拿后来冻结倒签。author GREEN后、独立执行前保存19项 `source-manifest.json`/`source-archive/` raw原字节+raw/LF hash，供独立每条另行预pin；此冻结不是全仓源码完整性签名。

每条版本化run.mjs单schema-only新库/受限role，原库before/after均与旧冻结137表/6228行、82审批ID/hash共同相同，session0/锁0、精确新库/role清理且末catalog不存在。原库HOLD/missing41/extra40保留，82不是83恢复；未访问共享库测试、未补造原历史。非作者独占DB期间主会话未并DB；收到明确释放后主会话接回，只加一次RR/read-only事务最终核验：本片15条before/after、当前137表/6228行与82审批ID/整行hash共同相同，0其它session/锁；本片15对及前段22对共37对精确已知临时库/role均在catalog不存在。见 `final-readonly.json`。不拿资源声明代替实际catalog。

## 审核与剩余

- [server初审](claim-project-20261025T052646Z-server-strong.md)：确证P2 Go截掉第10位以后的小数秒，已以真实RED复现；不声称跨完整微秒/越权。
- [server+SDK复核](claim-project-20261025T052646Z-server-sdk-strong.md)：P2关闭，限定产品代码静态完成、无新增确证finding；动态并发快照race未验证，不代签caller或C1。
- [终态事实](claim-project-20261025T052646Z-terminal-fence-facts.md)：原complete/fail、outbox只有taskID，reclaim复用行换代，确有代次隔离缺口。本片只抑制**新claim读失败**后的旧callback；runtime-offline/其他早退、成功/失败/补偿及outbox持久重放仍需全链fence，不能因抑制一条路径宣布关闭。
- [caller限定strong](claim-project-20261025T052646Z-caller-strong.md)：根准备前真实claim/配置daemon核对、unavailable错误链拒发旧callback、legacy兼容静态完成，无新增确证运行时finding，19/19冻结匹配。非阻塞建议：旧“path preparation first”注释过时，后续实际相关修改时一并校正；不因注释变更倒改本片冻结源码。
- 三组独立结果/宿主readonly+catalog已核；四包 `go vet` exit0，原始stdout/stderr/argv另存。最终源码/保护文件/分支/文档核对见final-static。旧claim锁序仍INCOMPLETE，resume2具体未尽独立保存，绝不默认PASS。
- CUSTOM #169/M11=22；新读面/证据流程Skill已更新（包含Go时间截断与stale callback警示）；无receipt/activation/预算变化，T源码/签名字节不改，原policy与quality/binding保持。
