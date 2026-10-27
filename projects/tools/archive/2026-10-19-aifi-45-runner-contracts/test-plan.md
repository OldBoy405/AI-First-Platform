# AIFI-45 tools — 测试方案与案例（Phase 2 草案）

> Gate 2 待确认；下述案例均待实现/待验证。C7测试诊断/修复已获Gate1范围确认。
> 权威Spec：canonical/specs/code下六个capability；Human View由同源YAML渲染。

## 一、测试策略

### 1.1 测试金字塔

优先扩Node内置测试：registry/模板/提示词合同用确定性单元回归；crctl深原语用隔离Git/workspace夹具；实际Runner/DB/daemon执行在multica验证。不引入新测试框架、运行时门禁或报告平台。

### 1.2 测试原则

- 每Scenario对应下文唯一TC；Phase3先RED再GREEN。TC与Agent验证CP通过同一个SC-ID关联，命令见canonical/specs/agent。
- 记录实际子进程退出码和monotonic耗时；不以`test | tail`的末端exit代替测试exit。日志完整留临时目录并脱敏，不回显密钥/DB URL。
- 当前发现为35**文件**，case数从实际日志统计；新增回归纳入全量。timeout、无匹配case、意外skip均不计成功。旧15s/200s只是诊断预算，不是挂死证据。
- 不动真实CR/生产DB/Git全局配置，不禁hook换绿；只清理所属已核实的本次进程和夹具。
- 每条TC的AND完整约束仍以对应canonical Scenario为准，表内列本切片关键检查，不删减未重述断言。

### 1.3 既有资产

| 资产（tools根） | 文件数/入口 | 范围与基线 |
|---|---:|---|
| skills/shared/crctl/scripts/test/*.test.mjs | 31文件 | 旧15s逐文件19完成、12未完成不代表case数；crctl整文件实测另见下节 |
| output-guard/test/*.test.mjs | 3文件 | 旧摘要无完整自然退出计数，Gate3须重跑 |
| pipeline-templates/*.test.mjs | 1文件 | 扩四schema/绑定/loop/digest，保留原回归 |
| lint-prompts.mjs | 1入口 | 曾exit0但有OUTDATED告警，改动后重跑、不隐藏告警 |
| check-agents-contract.mjs、check-skill-matrix.mjs | 2入口 | 曾exit0，改后必须重跑，不能复用旧证据 |

## 二、详细测试案例

### 2.1 Owner与Executor

#### 共享Skill合法绑定
| 字段 | 内容 |
|---|---|
| **ID** | TC-T-BIND-001 |
| 关联Spec | SC-T-BIND-001 |
| 优先级/状态 | P0；待实现/待验证 |
| GIVEN | 共享Skill由system维护，阶段Agent具有matrix授权。 |
| WHEN | emitter导出该节点执行绑定。 |
| THEN | SHALL 保留owner=system，executor为真实阶段Agent，每nodeId有唯一合法绑定。 |
| AND | 不建system执行Agent，不把owner当派发Agent。 |
| 测试文件 | pipeline-templates/emit-registry.test.mjs |

#### 独立Reviewer与拒绝
| 字段 | 内容 |
|---|---|
| **ID** | TC-T-BIND-002 |
| 关联Spec | SC-T-BIND-002 |
| 优先级/状态 | P0；待实现/待验证 |
| GIVEN | 作者can-call review，另有独立review节点及forbidden变体。 |
| WHEN | 导出合法/自审/无授权配置。 |
| THEN | SHALL 绑定独立reviewer；自审/无授权/system执行者失败关闭。 |
| AND | 不临时回退到调用者或空闲Agent，不扩作者权限。 |
| 测试文件 | pipeline-templates/emit-registry.test.mjs |

#### 重复Ref不是重复节点
| 字段 | 内容 |
|---|---|
| **ID** | TC-T-BIND-003 |
| 关联Spec | SC-T-BIND-003 |
| 优先级/状态 | P0；待实现/待验证 |
| GIVEN | 同ref不同nodeId合法夹具、重复nodeId和缺绑定反例。 |
| WHEN | 导出后由平台解析registry。 |
| THEN | SHALL 保留全部合法重复ref节点，拒绝重复nodeId/缺绑定。 |
| AND | human节点不派Agent；跨仓消费有独立回归，不只比较JSON。 |
| 测试文件 | emit-registry.test.mjs；multica parser对应回归 |

### 2.2 四阶段Registry

#### 全四份执行合同
| 字段 | 内容 |
|---|---|
| **ID** | TC-T-REG-001 |
| 关联Spec | SC-T-REG-001 |
| 优先级/状态 | P0；待实现/待验证 |
| GIVEN | 四active模板、matrix和既有节点ID。 |
| WHEN | emit四pipeline并交由multica生成器编译。 |
| THEN | SHALL 按原6/4/11/5稳定节点原序导出四份执行registry。 |
| AND | 不仅新增PipelineIDs枚举，不新增业务节点，不丢重复ref。 |
| 测试文件 | emit-registry.test.mjs；multica生成器--check |

#### Digest与非法输入
| 字段 | 内容 |
|---|---|
| **ID** | TC-T-REG-002 |
| 关联Spec | SC-T-REG-002 |
| 优先级/状态 | P0；待实现/待验证 |
| GIVEN | CRLF/LF和binding/input/loop/prompt变体、非法声明。 |
| WHEN | 导出并比较digest或检查失败返回。 |
| THEN | SHALL 同义换行同digest，执行声明变化使digest变化，非法输入非零退出。 |
| AND | 完整pipeline.inputs进body；不产出空registry或第二份输入事实源。 |
| 测试文件 | pipeline-templates/emit-registry.test.mjs |

#### 三Loop与零Loop
| 字段 | 内容 |
|---|---|
| **ID** | TC-T-REG-003 |
| 关联Spec | SC-T-REG-003 |
| 优先级/状态 | P0；待实现/待验证 |
| GIVEN | coding三reviewLoop及code_generation，writeback没有loop。 |
| WHEN | 导出并由平台解析。 |
| THEN | SHALL 原样保留loop、onFail、approvalPrompt和timeout等声明。 |
| AND | 不统一不同loop预算，不给writeback硬造loop，不按ref唯一去重。 |
| 测试文件 | emit-registry.test.mjs、pipeline-structure.test.mjs；multica parser |

### 2.3 输入与业务结果

#### 版本Authority
| 字段 | 内容 |
|---|---|
| **ID** | TC-T-TPL-001 |
| 关联Spec | SC-T-TPL-001 |
| 优先级/状态 | P0；待实现/待验证 |
| GIVEN | unassigned或真实version，new与legacy夹具。 |
| WHEN | 评审前负责人确认后由Agent用version-set更新，再进coding/writeback。 |
| THEN | SHALL 后续继承authority，不猜tbd、不重复询问元数据，缺真实版本明确失败。 |
| AND | new不传milestone，legacy按旧合同；不新增CLI flag或审批节点。 |
| 测试文件 | version-set.test.mjs、writeback-tx.test.mjs |

#### Exit0仍可能业务阻塞
| 字段 | 内容 |
|---|---|
| **ID** | TC-T-TPL-002 |
| 关联Spec | SC-T-TPL-002 |
| 优先级/状态 | P0；待实现/待验证 |
| GIVEN | merge exit0/phase=release-drift与test exit0/status=block。 |
| WHEN | 消费机器业务结果。 |
| THEN | SHALL 分别回开发回修/测试回修，不当merge成功或测试通过。 |
| AND | 不沿旧grant继续，不技术retry merge；保留真实test证据，code用release-subjects。 |
| 测试文件 | merge-tx.test.mjs、test-cr.test.mjs；平台carrier验证 |

#### Merge后新任务与归档
| 字段 | 内容 |
|---|---|
| **ID** | TC-T-TPL-003 |
| 关联Spec | SC-T-TPL-003 |
| 优先级/状态 | P0；待实现/待验证 |
| GIVEN | merge返回operationalWorkspace，archive会清理事务worktree。 |
| WHEN | merge结束后新task绑定writeback/archive并执行清理/重入。 |
| THEN | SHALL 消费camelCase同源字段，从安装根归档，cleanup-pending为业务成功。 |
| AND | 不改运行中env跨目录；已删除txws不作为重入前置；server不猜本机路径。 |
| 测试文件 | writeback-tx.test.mjs、archive-tx.test.mjs；daemon新task验证 |

#### 上游复评与结构化Recovery
| 字段 | 内容 |
|---|---|
| **ID** | TC-T-TPL-004 |
| 关联Spec | SC-T-TPL-004 |
| 优先级/状态 | P0；待实现/待验证 |
| GIVEN | upstream-design-blocker/repair-target，或crctl结构化recovery。 |
| WHEN | 按权威节点合同执行回修/恢复。 |
| THEN | SHALL 先进入既有设计复评再必要修订/重审/审批；恢复不超出原授权。 |
| AND | 不直退tech-designing、不沿旧PASS、不重置轮次；人工驳回/权限签名冲突不盲retry；保留机器recovery字段。 |
| 测试文件 | contract-scan.test.mjs；multica carrier/交接验证 |

### 2.4 Agent与审批职责

#### 只执行当前节点
| 字段 | 内容 |
|---|---|
| **ID** | TC-T-PROMPT-001 |
| 关联Spec | SC-T-PROMPT-001 |
| 优先级/状态 | P0；待实现/待验证 |
| GIVEN | 五Agent与模板旧职责含评论委派/阶段自启。 |
| WHEN | 修订并运行既有合同检查。 |
| THEN | SHALL 无评论委派、审批转述和跨阶段自启，只返回当前节点归因结果。 |
| AND | 协调者保留入口/异常/必要人类输入；status/next只是查询；不增Agent/Skill/运行时lint。 |
| 测试文件 | contract-scan.test.mjs、skill-scope.test.mjs |

#### 同源索引和权限
| 字段 | 内容 |
|---|---|
| **ID** | TC-T-PROMPT-002 |
| 关联Spec | SC-T-PROMPT-002 |
| 优先级/状态 | P1；待实现/待验证 |
| GIVEN | 同一tools版本的源提示词、README、active索引和matrix。 |
| WHEN | 跑既有合同/矩阵/lint校验并核对发布交接。 |
| THEN | SHALL 权限和引用一致，源文件与待部署instructions同源。 |
| AND | 不扩作者自审；不称checkout更新等于线上已生效；STDD过程只写集中根。 |
| 测试文件 | contract-scan.test.mjs；check-agents-contract/check-skill-matrix/lint-prompts入口 |

#### 必要业务输入与失败回执
| 字段 | 内容 |
|---|---|
| **ID** | TC-T-PROMPT-003 |
| 关联Spec | SC-T-PROMPT-003 |
| 优先级/状态 | P1；待实现/待验证 |
| GIVEN | 缺真实版本需确认，或失败带registration key及recovery。 |
| WHEN | 请求必要输入或返回异常摘要。 |
| THEN | SHALL 只求人类业务确认、由授权Agent执行现有CLI；回执有CR-ID或key及错误影响摘要。 |
| AND | key不替代恢复参数，原始机器结果留既有run；不代签、不转交有权限CLI给人复制。 |
| 测试文件 | skills/shared/crctl/scripts/test/contract-scan.test.mjs |

#### 保持审批Skill正确边界
| 字段 | 内容 |
|---|---|
| **ID** | TC-T-APP-001 |
| 关联Spec | SC-T-APP-001 |
| 优先级/状态 | P0；待实现/待验证 |
| GIVEN | 四approve Skill目前已没有start/resume尾启动。 |
| WHEN | 合同负向回归并修改其他提示词。 |
| THEN | SHALL 保持仅当前审批收尾，不为制造diff无故改写正确Skill。 |
| AND | 不恢复默认dev-start；保留授权/TTY/grant/签名/隔离；Runner接续下一阶段。 |
| 测试文件 | contract-scan.test.mjs、caller-contract.test.mjs |

#### 幂等与人工驳回
| 字段 | 内容 |
|---|---|
| **ID** | TC-T-APP-002 |
| 关联Spec | SC-T-APP-002 |
| 优先级/状态 | P0；待实现/待验证 |
| GIVEN | 审批幂等重入或APPROVAL_DECLINED_ROLLED_BACK。 |
| WHEN | 消费当前节点权威结果。 |
| THEN | SHALL 保留真实审批与业务回退，停止正向，不沿旧grant或技术retry。 |
| AND | 不一律自动重写；STDD确认不是业务CR审批授权。 |
| 测试文件 | crctl.test.mjs；平台审批/交接回归 |

### 2.5 测试执行可靠性

#### 全范围与真实计数
| 字段 | 内容 |
|---|---|
| **ID** | TC-T-TEST-001 |
| 关联Spec | SC-T-TEST-001 |
| 优先级/状态 | P0；待实现/待验证 |
| GIVEN | 35文件清单与新回归，旧短预算结果未分类。 |
| WHEN | 定义并运行完整发现范围。 |
| THEN | SHALL 保留全部文件，分开记录文件数与case数、自然exit与监督器超时、monotonic耗时与skip。 |
| AND | 不exclude或skip超时文件，不以未匹配case/管道末端exit当通过。 |
| 测试文件 | 现有全量入口及其实际执行证据 |

#### 最小反馈环分类
| 字段 | 内容 |
|---|---|
| **ID** | TC-T-TEST-002 |
| 关联Spec | SC-T-TEST-002 |
| 优先级/状态 | P0；待实现/待验证 |
| GIVEN | 未完成文件与可完成对照、最小真实name-pattern case。 |
| WHEN | 单变量比较进程完成、输出、环境和Git hook证据。 |
| THEN | SHALL 用可复现命令区分正常慢、缓冲/输出延迟、环境与真实阻塞，不假设同根因。 |
| AND | 仅清理本次所属进程，原始日志可审计，正式验证不禁hook。 |
| 测试文件 | 现有harness/最小caller；design末节列精确命令 |

#### 根因修复而非放宽断言
| 字段 | 内容 |
|---|---|
| **ID** | TC-T-TEST-003 |
| 关联Spec | SC-T-TEST-003 |
| 优先级/状态 | P0；待实现/待验证 |
| GIVEN | 已证实根因，或证据只支持正常慢套件。 |
| WHEN | 最小原回归RED后修根因并GREEN。 |
| THEN | SHALL 在根因处最小修复并保留原失败断言；仅慢则改合理执行预算/报告而不虚构业务补丁。 |
| AND | 不删断言/跳过/全局禁hook；不新建扫描、重试或通用测试平台。 |
| 测试文件 | crctl.test.mjs现有fixture与最小边界回归 |

#### 完整验收报告
| 字段 | 内容 |
|---|---|
| **ID** | TC-T-TEST-004 |
| 关联Spec | SC-T-TEST-004 |
| 优先级/状态 | P0；待实现/待验证 |
| GIVEN | 修复后的完整原始运行日志。 |
| WHEN | 汇总PR/Issue和test-report。 |
| THEN | SHALL 报真实命令/版本/exit/耗时/case/pass/fail/skip/todo/cancelled，未完成不得验收。 |
| AND | 明列基线与新增回归，意外skip阻塞；不把部分Windows/Node24结果当跨平台已通过。 |
| 测试文件 | 全35文件及新增回归的全量入口 |

#### Payload夹具Authority
| 字段 | 内容 |
|---|---|
| **ID** | TC-T-TEST-005 |
| 关联Spec | SC-T-TEST-005 |
| 优先级/状态 | P0；待实现/待验证 |
| GIVEN | 五个原测试把payload写主checkout，但cmdReviewRecord读CR权威副本，实际PAYLOAD_NOT_FOUND。 |
| WHEN | 在真实authority布置夹具或按目标显式绝对from，重跑原五个失败。 |
| THEN | SHALL 到达原forged/回修/证据漂移目标分支，原安全与零写入断言保持。 |
| AND | 不改生产authority放宽权限；目标为payload缺失的反例仍缺失；最小原测试先exit1后exit0。 |
| 测试文件 | crctl.test.mjs约2588/3146/6058/6436/8259，实际按test标题定位 |

#### 共享Authority错误分类
| 字段 | 内容 |
|---|---|
| **ID** | TC-T-TEST-006 |
| 关联Spec | SC-T-TEST-006 |
| 优先级/状态 | P0；待实现/待验证 |
| GIVEN | authorityWorkspace已知TxError经task done等漏格式化caller变INTERNAL_ERROR。 |
| WHEN | 在共享解析出口现有容忍判定后格式化已知TxError，回归同源caller/合法容忍/未知异常。 |
| THEN | SHALL 保留原CR_WORKTREE_STATUS_MISSING、非零exit、零业务写入；未知仍走INTERNAL_ERROR。 |
| AND | 不只补单caller；显式override/无绑定容忍不变；不全局透传任意e.code。 |
| 测试文件 | crctl.test.mjs原AIFI-69 B1/R1及新增最小参数化边界回归 |

### 2.6 Phase2已执行诊断（不是修复完成证明）

- checkpoint同两个case：15s预算→15.15s监督器124；45s预算→18.12s自然exit0、2pass，直接证伪短预算就算挂死。
- crctl单TTY case内含24组合：26.53s自然exit0、1pass；整文件358.14s自然exit1，294case=288pass+6fail，0skip/cancelled。
- 整文件200s时5551次子进程已完成但stdout长期仅TAP头，证明输出延迟/慢套件而非无进展。
- 原forged-payload与AIFI-69 R1最小case约1.03s/1.11s、均exit1，实际分别PAYLOAD_NOT_FOUND/INTERNAL_ERROR；精确命令见design末节。
- Git LFS hooks环境开销只做进程级对照，正式验证不禁hook；诊断所属进程清理后0PID。
- 其余此前超时文件仍待分类，不称全部通过或同根因；当前只有Windows/Node24证据。

## 三、执行矩阵与命令

| 模块 | 单元/合同 | 集成/跨仓 | 状态 |
|---|---|---|---|
| registry+binding | 四schema/权限/重复ref/digest | 生成器--check与parser | 待验证 |
| 多loop/零loop | 完整执行声明 | Runner回修/authority/DB真实执行 | 待验证 |
| 输入/深原语 | version/new-vs-legacy | release-drift/test-block/archive-reentry/daemon绑定 | 待验证 |
| Agent/approve | 正负向职责合同 | matrix/索引同源；线上instructions仅另授权后核实 | 待验证 |
| 测试执行 | 最小诊断/RED→GREEN | 全35文件及新增回归、真实计数 | 待验证 |

Gate2后从tools根执行，Node24支持quoted glob，实际发现数须核实：

```text
node --test "skills/shared/crctl/scripts/test/*.test.mjs" "output-guard/test/*.test.mjs" "pipeline-templates/*.test.mjs"
node skills/shared/crctl/scripts/check-agents-contract.mjs
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node skills/shared/crctl/scripts/lint-prompts.mjs
node -e "const fs=require('fs'); for(const f of fs.readdirSync('pipeline-templates').filter(f=>f.endsWith('.json'))) JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8')); console.log('json ok')"
```

最小切片用canonical Agent spec所列TC name-pattern或design里的原失败完整标题。必须实际匹配；最终全量不得带name过滤/文件排除。平台从multica/server跑`node internal/governance/gen/generate-gate-nodes.mjs --tools <tools checkout> --check`，不能以Source SHA注释代替内容检查。治理测试另需隔离、迁移后的测试DB及真实case执行证据，不得拿TestMain提前exit0当通过。

## 四、回归风险

| 区域 | 风险/保护 | 等级 |
|---|---|---|
| digest与权限 | 完整body/CRLF/UUID正负例/独立reviewer | 高 |
| 多评审 | 不共享loop预算、不将重试当业务轮次 | 高 |
| 业务结果 | drift/block/cleanup-pending与exit0分离 | 高 |
| authority修复 | 原安全断言、同源caller、override/容忍及未知错误边界 | 高 |
| 测试执行 | 足够预算、真实exit/case/skip、进程归属、无排除 | 高 |
| 提示词索引 | 既有三校验、不新增运行时lint | 中 |

## 五、执行顺序

1. P0：分类剩余未完成文件；先RED再修payload夹具根与共享authority出口错误分类；不排除文件凑绿。
2. P0：绑定/四registry→模板业务结果→独立Agent/审批禁止接力，与multica消费共同回归，不半套启用。
3. P1：同源索引和必要输入回执本次交付前完成，不延后到部署。
4. P0：全量自然完成与真实计数；未完成/意外skip明确阻塞。生产部署、停服、存量恢复另授权。

## 六、文档校验说明

当前STDD的AND警告按整份spec.md累计，并非按Scenario；canonical已逐Scenario检查不超过5。TC采用含项目/能力前缀的唯一ID，STDD旧TC正则未识别该扩展前缀，另以明确的SC→TC/CP映射和唯一性检查核实21条，不为消警改STDD或删断言。
