# T01–T03 tools 候选交接（未提交、未部署）

## 最新候选 — M10 集成修订 ADJ-T-004

- producer 仍为未提交 working tree，BASE `a5ecb5783fd8f7b5fa1d0d3b328b704199bbe011`；**当前259文件 canonical-LF manifest `073c75924e21f13c973bfeaa7197a33c98959004d00bab8f47fceafa6e034daa`**。初次 eb99… 与 source 修订中间19034…均只作历史，不冒充当前来源或已提交 revision。
- 仅在 requirement writer 一个 prompt 叶值恢复 `{{inputs.source}}`：已记录恢复输入仅作与本次 cr.md source 原样核对的数据，不能覆盖 cr.md；原 Skill 参数仍取 cr.md，缺记录/漂移/读取失败停止，显式空与缺值不混同。原真实版本/version-set/title/summary/路径安全规则保留。新增合同回归，不改 schema/key/权限/签名/Go renderer/恢复/事务；详 ADJ-T-004 与 multica M10-source-repair-report.md。
- 四原生 export 与编译 raw 全字段同源、独立 Node 完整 body SHA 相同，节点6/4/11/5、非human权限23、loop1/1/3/0不变。**当前 body digest**：

```text
requirement-authoring sha256:f839d28c30ce2dc0eec709589f742abac1f45db96771d80a3ef3ef66a45ea32c
architecture-design  sha256:11970fe3aec6013ff88117eda212617fec4b395e45c52057d157fd8112f2aeb5
code-implementation  sha256:ee6461ff376646dba36f64d57dfd4482c1e6f6532e049ce6547350b1c7175a88
feature-writeback    sha256:6a63a222146eb018564cd0487e8b1ab5352f832fd3d972f6c065ff7010c01108
```

- 主会话当前八文件完整联合 **213/213 PASS、native0、7.095790200s、0 fail/skip/todo/cancelled**；不是最终35文件全量。当前 multica 整包 **native0、40.292777400s、195父PASS+108子PASS、1原有LiveGitHub SKIP、304RUN/304完结、无DB skip**，原 generator `--check`0/0.345544000s，后端build0/8.887457500s。运行前后259 tools和3594 server文件不漂移。
- 保留中间联合 RED：19034…候选213例/212P/1F，caller-09将新增静态正则字面误当缺workspace调用。只将该断言改为普通 `\s+` 并增强校验完整version-set/显式workspace，未改扫描器/白名单/排除；独立Reviewer验证删workspace时新断言失败、旧断言仍通过，且仅第878行变化，body/Go不变。随后重冻为073c…并重跑上述整包/联合。两路 source delta审查及该单行窄复核均无硬问题，未把模型审查当业务成功。
- 证据：`%TEMP%/aifi45-m10-repair-e4o5e8vm/source-producer-repair-evidence/` 保存四 export/原链/RED→GREEN；`main-final/` 保留中间联合RED及当时Go绿；`main-closeout/` 保存当前完整日志、native结果与source manifests。当前四Go常量身份见 multica M10-source-repair-report.md 的六SHA表；generator/runner_contract/code/writeback原SHA不变，gate86df…、requirementb473…。CI仍pin9d0a6a7…待未来授权提交对齐，无部署/真实CR/存量digest覆盖。
- M10a/M10b动作验收完成；M11parser及后续仍按依赖推进，CP005/007整体、四阶段Runner闭环、T04/T05/T-FINAL及Gate3未完成。当前临时33551 PG仅本次自建测试资源，继续已授权后续切片，由Main最终按run-id/确切容器卷清理。

## 以下为初次 T01–T03 交接历史快照

以下旧manifest/digest/212计数均对应初次候选，不代表上述当前修订。原始证据不覆盖。

### 初次结论

- T01绑定、T02四registry/digest、T03输入与真实业务结果合同均已实现；独立Standards/Spec审查通过。首轮两项P2已真实补RED、修复并由原审查者独立复现关闭。
- 这里只交接tools候选，不代表multica生成器/parser/Runner已实现或启用，也不是Gate3。T04去旧Agent/ack接力必须等平台执行闭环，不半套启用。
- S0的4个修复文件与既有`.gitignore`未被本轮覆盖；所有变更仍未提交，未push/部署/连接DB/操作真实CR。

## 源码身份（不以HEAD冒充完整候选）

- 实际tools HEAD：`a5ecb5783fd8f7b5fa1d0d3b328b704199bbe011`。
- **未提交候选**，259个tracked文件的canonical-LF manifest SHA-256：`eb99e18aad2292a614a133b35a9265b6505c852a0bf7897c519e4dbf973d6984`。
- 算法：每文件字节先CRLF→LF后SHA-256，再对路径→摘要映射按key排序、紧凑JSON（ensure_ascii=true）编码UTF-8并SHA-256。完整映射与4份原始导出保存在下面的handoff.json所在目录。
- 主会话联合测试前后259文件哈希相同；导出交接前再与同一映射核对，无source drift。此内容身份不是已提交Git revision，正式提交/CI pin对齐仍需人类后续授权。

## 实际四份导出

命令仍为既有`node pipeline-templates/emit-registry.mjs --pipeline <id>`，不新增CLI命令/flag。4次均自然native exit0。schema命名空间均为`ai-first.pipeline-registry/`。

| pipeline | schema尾段 | nodes | nodePermissions | reviewLoop数 |
|---|---|---:|---:|---:|
| requirement-authoring | requirement-core-v1 | 6 | 5 | 1 |
| architecture-design | architecture-core-v1 | 4 | 3 | 1 |
| code-implementation | code-core-v1 | 11 | 10 | 3 |
| feature-writeback | writeback-core-v1 | 5 | 5 | 0 |

最终body digest（不是作者报告中的preT03历史值）：

```text
requirement-authoring sha256:8d836fc71f1274f035852a7fcf4cf1e28783a5f3584ca68d4acf77370772882d
architecture-design  sha256:11970fe3aec6013ff88117eda212617fec4b395e45c52057d157fd8112f2aeb5
code-implementation  sha256:ee6461ff376646dba36f64d57dfd4482c1e6f6532e049ce6547350b1c7175a88
feature-writeback    sha256:6a63a222146eb018564cd0487e8b1ab5352f832fd3d972f6c065ff7010c01108
```

主会话独立检查：完整pipeline.inputs与所有原节点字段等于真实声明；顶层inputs同源派生；Node重算完整body SHA一致；23项权限按nodeId精确覆盖非human节点、owner来自唯一owns、executor为有权限且非forbidden的matrix agent key。没有把这些key当成已验证的workspace Agent UUID。

## 验证与证据

- 作者emitter修复后69/69；原Spec审查者独立69/69，并额外复用原反例/对照6项全部符合预期，两项P2 CLOSED。
- **主会话冻结后联合8个完整目标/邻接文件：212/212，native exit0，单调6.858714s，0fail/skip/todo/cancelled，259文件哈希未变。** 无name过滤；不是全35文件套件。
- 主会话T03新合同定向8/8，源码9文件哈希未变；作者另有version-set/testCr42/42及merge/writeback/archive定向11/11，保留原深回归，不只凭新静态关键词。
- 10项T01–T03 Canonical CP逐条真实执行，全部正数case、exit0及原stdout断言达成；校准后的S0 CP003另4/4。命令落点修正见ADJ-T-003，未改SC/TC数量或业务语义。
- Agent/matrix/lint入口均exit0、8份模板JSON可解析、16个变更source文件diff检查通过（不含既有.gitignore）。既有`handover-cr/SKILL.md:59 [OUTDATED] attempts[]`保留。
- Canonical仍11 Requirements / 21 SC / 21 CP，无重复或悬空；native STDD validate exit0，保留既有5个按整篇spec.md累计AND的告警，不扩范围修STDD产品。

持久原始证据：

```text
C:/Users/GOBAO/AppData/Local/Temp/aifi45-treg-joint-2apx79y2/{result.json,stdout.log,stderr.log}
C:/Users/GOBAO/AppData/Local/Temp/aifi45-treg-final-6gl_4tqr/{handoff.json,quality.json,<pipeline>.json,*-stdout.log,*-stderr.log}
C:/Users/GOBAO/AppData/Local/Temp/aifi45-treg-cp-g00_wsuj/{result.json,S0-CP003-result.json,*-stdout.log,*-stderr.log}
C:/Users/GOBAO/AppData/Local/Temp/aifi45-t03-main-jk49rjxn/{result.json,stdout.log,stderr.log}
C:/Users/GOBAO/AppData/Local/Temp/aifi45-t03-stage1-lNFodd/  # 作者T03 RED/GREEN与深邻接
```

## multica接收条件与剩余阻塞

- 生成链/parser缝隙已只读核实，见multica `implementation-notes.md` I5；尚未运行生成/check、编译或DB测试。multica业务工作树仍clean。
- 按已批准依赖，M00治理基线需要**明确获准、已迁移、可销毁隔离DB**。当前没有授权目标；TestMain可能DB不可达时exit0且零case，禁止默认.env/DATABASE_URL或默认localhost“碰一下”。
- 本机仅确认Docker CLI文件存在，未访问Docker服务、未创建容器或连接DB。下一步需人类授权新建专用临时PostgreSQL及运行仓库迁移，或指定已迁移隔离库的安全配置位置。
- 最终候选全部35测试文件及新增回归仍须T05整套运行；S0旧候选875/875与本轮212/212都不能替代最终全套或跨仓技术评审。Gate3、提交/push/部署、真实CR/存量接管继续未授权。
