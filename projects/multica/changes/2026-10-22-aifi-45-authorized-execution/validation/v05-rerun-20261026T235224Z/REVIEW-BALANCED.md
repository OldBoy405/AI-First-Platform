方案裁决：**BLOCK** ／ 实现·动态验收：**未执行，不作通过裁决**

**范围与限制**：已读冻结 plan 470 行全文、tc-coverage 增量 25–32、B17 源码 `T/lib/change-scope.mjs`(180行) 与 `T/test/change-scope.test.mjs`(299行)、`b17-green.tap`+4 份 `b17-red-*.tap`、`tools-full-suite-after-b17.tap`、`M/scripts/aifi45-db/run.mjs:40–80`、`workspace-transactions.mjs:1986–2010,2021–2027`、`approval.go:425`、`execution_authorization.go:195`、`approval_record` DDL。未读：proposed 源码（不存在）、Go 643–648 实体、其他 lane 输出。**输入漂移：无**（plan raw=`6f98229a…f92a06` 沿用入口轮核验）。actual 无后端回执，记 **unknown**。

## Findings

**BAL-01 · blocker · ③权威来源无落点，17 条 merge leaf 无法构造**
plan:126/466 规定改动集合权威源为"M 侧持久 code 批准记录中冻结的 source sha，`approval.yml` 仅投影"。实测 `public.approval_record`（`todo-a/b1-cross-task-red.schema.sql:1489–1503`）字段仅 `stage,decision,approver_user_id,evidence_digest,key_id,signature,reject_reason,grant_json`，**无 per-repo source sha 列**；`grant_json` 按 `execution_authorization.go:195` 专供 execution grant，夹具中 code 行实为 `digest='dummy'`、`grant_json={}`；schema 亦无 release/subject 表。plan §4 的 13 表（plan:139–152，计数已核：8+5=13）无承载对象，§6 无读取接口。→ plan:307 leaf 无可比较的另一侧，其 mutation 不可判别。**这是上轮三路第 1 条的换名而非闭环。**修：把该记录落入 §4（列或 `control_fact.kind=code-source-freeze` + allowlist/unique）并在 §6 定接口与"缺失即 `AUTH_SCOPE_UNVERIFIABLE`"。归属 M003。

**BAL-02 · blocker · 必达 leaf 少算 7 条，"一一对应"为假**
plan:303 称"一一对应"，plan:354 称"**十条**"，plan:442 称"6:5→**10:10**"。逐条点数 plan:304–314 实为 **17 个 leaf**（304 六个 + 306/307/308/309/310 各一 + 311 二 + 312 一 + 313 二 + 314 一）、mutation 16 个，且 plan:305 另要求为 `越界零写入` **追加**第二个 mutation（该 leaf 独占 2）、plan:313 又让 **2 leaf 共用 1 mutation**。按 plan:347–354，`channel-test-expectations.json` 须逐个要求真实 PASS leaf，"任一 leaf 缺失…判未验证"——按"十条"落名单会静默漏 7 条，含 plan:308（覆盖发布集合，正是上轮"区间过窄"守门项）与 plan:312。修：plan:354 内联 17 条全名，删"十条/10:10"，plan:313 拆两个 mutation，plan:305 并入 plan:306。归属 M003。

**BAL-03 · major · 越界零写入要求不存在的注入缝**
plan:306 要求"注入 publish 端口并断言零调用"。实测 `mergeCr(ctx,input)`（`:1986`）只消费 `ctx.{graphDigest,installRoot,knowledgeBaseRepoId,repositories}`，**无 publish/网络端口**，锁在 `:1997 acquireLock` 内直连执行，push 为内部 git 调用；plan:305 自己又退到"观测 journal/锁/outbox/Git 写命令"，两处冲突。修：二选一并写死——给 `mergeCr` 增 `ports/hooks`，或删"注入端口"，改为 `PATH` 前置 git wrapper 记录 argv，断言零 `git push`、`.crctl` 零新 journal、状态仍 `code-approved`。归属 M003+tools。

**BAL-04 · major · 失败码闭集与复用函数产出不一致**
plan:132 定 5 条闭集，但"复用 `AUTH_SCOPE_*`"(plan:133) 复用的是 `change-scope.mjs` 另一组：`INPUT_INVALID`(:36)、`REPOSITORY_UNKNOWN`(:44)、`PATH_ESCAPE`(:48)、`PATH_NOT_ALLOWED`(:54)、`REPOSITORY_IDENTITY_MISMATCH`(:166)。矛盾点：plan:304 要 `空集合不可放行` 产出 `AUTH_SCOPE_UNVERIFIABLE`，而复用函数对非数组返回 `INPUT_INVALID`、对 `[]` 返回 `allowed:true`，**都不可能产出 `UNVERIFIABLE`**；plan 未定义映射。修：在 plan:132 补 finder→对外码映射表。归属 M003。

**BAL-05 · major · B17 第 4 条 RED 是 TypeError 红**
`b17-red-empty-changeset-allowed.tap`：`error:'changes is not iterable'`、`name:'TypeError'`、`code:'ERR_TEST_FAILURE'`，栈 `change-scope.mjs:40:24`。按 plan:348–350 自身口径（"marker 位于该 leaf 的条件失败断言输出"、"编译/setup/连接错均不是预期 RED"），该 RED 不合规：失败由语言抛异常产生，非 test:293 的 `assert.equal(verdict.allowed,false)`；它只证"删守卫会崩"，未证被记录的旧形态（返回 `allowed:true`）。其余 3 条达标：`+[] -['src/中文 名称.txt']`、`+[] -['src/new-name.txt','src/old-name.txt']`、`false !== null`。修：mutation 改为"保留可迭代、非数组先替换为 `[]`"。归属 AIFI-45（B17 证据）。

**BAL-06 · major · `symlinkEscapes` 真逃逸判定 0 覆盖**
`change-scope.mjs:114–125`：非仓→null(:116)、无条目→null(:118)、非 120000→false(:119)、realpath 失败→null(:121–123)、**前缀比较→true(:124)**。测试仅覆盖前四支：test:281 走"非仓"；`checkChangeScope` 各 wiring 用例路径全为普通文件，在 :119 即返回，**永不抵达 :120–124**。故"保留 mode 检查、把 :124 改 `return false`"可让 18/18 全绿——正是 B17 第 3 项守的面。平台事实加剧：全量唯一 skip 为 `after-b17.tap:4271 EXEC-12 受控文件自身为 symlink：拒绝写入 # SKIP …EPERM`，Windows 无法造真实 symlink，**当前无任何正例**。修：加 leaf `指向仓外⇒true / 仓内⇒false`（用 `git update-index --cacheinfo 120000,<blob>,link` 构造 index 侧符号链接），mutation `:124` 恒 false 必须 RED。

**BAL-07 · minor · `trim()` 专属损伤面未测 + 死参数**
test:217 `scopeRepo(t,{utf8=true}={})` 的 `utf8` 从未被使用；test:233 只覆盖"非 ASCII+内嵌空格"。b17 增量的修复点是"不用换行拆分+`trim()`"，能专打 `trim()` 的是**首/尾空格路径**（git 不转义普通空格，`trim()` 会剥掉）。修：补该用例，或删死参数并注明仅覆盖引号变形面。
余项（原 BAL-08/09，minor）：plan:118 仍称"非数组当空数组返回 allowed"，已被 B17 `:35–39` 推翻，真正残留只剩 `[]`（`:56`）且被 test:296–298 固化为期望；plan:429 命令模板有逐字重复残句与游离反引号。

## 已核正面项（不作通过依据）
B17 计数为真：`b17-green.tap` 18/18/0skip；`tools-full-suite-after-b17.tap` 1121/1120 pass/0 fail/1 skip，skip 即 EXEC-12，**未被挪作 DB 豁免**。rename 两端闭合（`:87–101`，`i+=3` 收源+目标；test:250–275 断言只授权目标仍报 `PATH_NOT_ALLOWED src/old-name.txt`）。`-z` 无损且采集失败≠空集（`:59–67,92,104,179`）。命令模板可运行：`run.mjs:68` 白名单逐含 `'./internal/governance'`，`-migration=` 正则(:52/57) 接受 643–648，`:46` 强制零 skip；模板读取的 `meta.json` 字段（`original_unchanged/owned_resources_cleaned/original_release.sessions|locks/test.counts.*/test.exit/test.leaf_pass`）在真实 meta 全部存在。X7 字段语义（plan:134）、核对区间=发布区间（:127）、修订记录措辞（:442）文本层已修。

## 旧问题状态
| 旧问题 | 状态 | 依据 |
|---|---|---|
| ③源为 agent 可写 | **open** | BAL-01 换名未落点 |
| 区间<发布区间 | **closed** | plan:127/308 |
| leaf:mutation 非一一对应 | **open** | BAL-02 17:16，"十条"错 |
| X7 前缀属 `allowed_paths[repo]` | **closed** | plan:134；与 `:26–31,51–53` 一致 |
| 修订记录不一致 | **closed** | plan:442 |
| 核对对象≠发布对象 | **partial** | plan:113 (a)/(b) 仍未选（有意留决，但阻断可实现性） |
| 空集合 fail-open | **partial** | 非数组已闭；`[]` 仍放行并被测试固化 |
| 零写入外延 | **closed** | plan:127/284 |
| B17 四缺陷 | **partial** | rename/编码基本闭；symlink 正例缺；空集只闭非数组 |
| 旧评审 session 误写 `01a17797-` | **open（本冻结副本仍错）** | `inputs/trusted-verdict-channel-v05-review-20261026.md:8–10`；正确 `01a1796a-`。economy 主责 |

## 最小闭合集合
1. ③落到 §4 具体对象 + §6 接口 + 缺失即 UNVERIFIABLE（BAL-01）。
2. plan:354 换 17 条全名、删"10:10"、拆 plan:313、并 plan:305（BAL-02）。
3. 为 `越界零写入` 定可执行的零 publish 观测法或加注入缝（BAL-03）。
4. 补 finder→对外失败码映射，使 UNVERIFIABLE 可被真实产出（BAL-04）。
5. B17 第 4 条 mutation 改为"非数组→空集"，产出断言红（BAL-05）。
6. 补 symlink 真逃逸正/负 leaf 及其 mutation，补首尾空格路径用例（BAL-06/07）。
7. 选定 (a)/(b)（plan:113）——所有 merge leaf 夹具形态取决于它。

1–7 未闭前 B11 增量不可实施、不可验收，故判 BLOCK（非"实现未完成"）。AIFI-45 覆盖 41/49、Gate NO-GO、M001/M002/M003 unresolved、原库 HOLD 均不变；本结论不授予注册、Gate、commit/push、部署授权。
