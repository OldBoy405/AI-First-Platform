# v0.5 B17 后三路复核：BLOCK

## 结果与效力

| 轴 | 独立会话 | 最终裁决 | 原文报告 |
|---|---|---|---|
| strong：安全/实施合同 | `01a17aa2-015a-77b9-a3c5-0f8663641eb4` | **BLOCK** | [REVIEW-STRONG.md](REVIEW-STRONG.md) |
| balanced：测试/配置 | `01a17aa2-0142-77b9-a3c5-0f85af3e8583` | **BLOCK** | [REVIEW-BALANCED.md](REVIEW-BALANCED.md) |
| economy：文档/Skill | `01a17aa2-016b-77b9-a3c5-0f88b1b04e55` | **BLOCK** | [REVIEW-ECONOMY.md](REVIEW-ECONOMY.md) |

- 三路均为新鲜非作者上下文，按双仓有效 STDD 模型配置启动；requested model/effort 及续接记录见 [REVIEW-RUNS.json](REVIEW-RUNS.json)，actual 均无回执，保持 unknown。
- balanced 初次仅完成元数据准备，未被当作完成；在同一会话续完正文/源码/TAP审查，再因宿主截断重排输出。economy 在同一会话补读 Skill/API 并纠正码层级与 B2 归属。未将其他 lane 的输出传入任何 reviewer。
- 仅静态计划复核；没有新跑测试、DB、迁移、真实 CR、部署或 git 写操作。TAP 核验是读取已有证据，不是本轮独立复跑。
- **M003 仍 proposed/搁置，用户自行注册；AIFI-45 41/49、Gate NO-GO、M001/M002/M003 unresolved、原库 HOLD 不变。** 三路 BLOCK 不等于引入了三个新 change，也不授权跨 Gate。

## 冻结与覆盖

- 被审方案为 `inputs/trusted-verdict-channel-implementation-plan-20261026.md`，原始 SHA256：`6f98229a53e05dcffec20ad39b4ee1190b0444dcfce6e4a5505e9c2639f92a06`。
- 文档副本、22 项输入哈希及三仓 HEAD 见 [source-manifest.json](source-manifest.json)；B17 六份 TAP 哈希另见 [evidence-manifest.json](evidence-manifest.json)。结束时再次核对，结果见 `integrity-check.json`。
- 原始字节哈希与 LF canonical 哈希分别比较，不混用。评审期不修被审方案、不重写历史 TAP，以保持同一审查对象。
- strong 完整读方案/范围采集器与测试，merge 大文件只定位关键链，未完整审核所有 recovery 段，也未读 TAP 正文。balanced 补读全文方案和 B17 TAP，未读 Go 643–648 全部实体。economy 完成 Skill/API 补读，未独立复核整份锁图。各限制保留，不能声称完整动态验收。

## 合并后的实质阻断（非简单票数）

| ID | 事实与影响 | 来源 | 归属 / 最小闭环 |
|---|---|---|---|
| R1 | 方案 P:113 仍保留 (a)实际候选写集 / (b)批准SHA 二选一；P:126/127 对权威 source 与 `trunk...HEAD` 的表述未统一，finalize 的 KB 生成写集未具体列明。 | STR-01；E02；BAL最后一项 | M003方案：定死一种语义，区分批准源/实际源/base/finalize生成路径及恢复规则，不暗设KB豁免。 |
| R2 | P:124–126 依赖 M 的可信 merge facts 与持久 code source freeze；§4/§6 未定义相应承载及认证读取合同。不能仅把 YAML 权威改名成“平台记录”。 | STR-02；BAL-01；E07 | M003方案：明确存储落点、endpoint/caller/认证、请求响应闭集、selection/head/repo/source/base绑定、缺失时失败及恢复凭据。现库没有该字段本身不是缺陷，**未规划新增落点**才是。 |
| R3 | “publish前锁内重验”没有定义本地锁和 M 撤销的共同排序；重验成功→实际push之间的撤销、部分发布与响应丢失、base变化后的rebuild仍无唯一语义。 | STR-03 | M003方案：逐effect的线性化点、in-flight/revoke顺序与恢复/转人工边界；不跨网络持DB事务，不用后续授权追认历史。 |
| R4 | 方案仍写“十条/10:10”，S5 枚举已增到17个必达leaf，mutation映射不一一对应；观测零publish的实现缝未选定。 | BAL-02/03；E01 | M003方案：统一唯一leaf清单和mutation矩阵，定可执行的零副作用观测法；不得只改数字。 |
| R5 | B17 用index mode推断工作树类型：普通文件替换为出仓symlink会跳过realpath；无index的普通untracked、已提交删除/rename旧端又会作为未知误拒。 | STR-04 | AIFI-45本地：按被核状态取事实，补真实`checkChangeScope`/CLI接线正反例；未来tree适配仍归M003。 |
| R6 | B17第四份变异TAP失败为`TypeError: changes is not iterable`，并非预期旧行为`allowed:true`的断言红；真symlink出仓比较分支也无有效守门证据。 | BAL-05/06 | AIFI-45本地：正确恢复旧“非数组→空数组”语义做断言RED；补仓内/仓外symlink正反及恒false变异。不能只造index mode就声称已执行realpath分支。 |
| R7 | G5 root竞态在缺口台账归AIFI-45，disposition仍整体归M003；S1/S6又未声明G5/G1等未修前置。 | E09′ | 对齐归属与前置；B2已落地，真正残余为G1/G5等，不能退回“B2未合入”的错误口径。 |

## 主会话裁决：不能原样照单接收的地方

1. **空集合**：已证明完整且确实零改动的 `[]` 是合法输入；纯判定器允许它不是自动等于 fail-open。需要拒的是“采集失败/集合不完整/丢失输入被伪装成空集合”。BAL关于此项的建议只按适配器完整性合同采纳，不要求无条件拒绝所有空数组。
2. **码层级**：现有 CLI 已把 findings 折叠为 `AUTH_SCOPE_VIOLATION`，problems为 `AUTH_SCOPE_UNVERIFIABLE`（`crctl.mjs:1880–1884`）。不采纳“现自检完全没有映射”的笼统说法；M003新增适配器仍须明确其mapping和完整性失败路径。economy已撤回原E08并改为措辞项。
3. **零写入**：balanced将外延记为closed，但P:115/116与P:123仍有“首次拒绝零新增写入”对“前置audit不算”的相反口径；按strong判partial，须合并正文，不以追加一句取代旧句。
4. **区间等于发布集**：`trunk...HEAD`修正了“只查批准SHA”的方向，但不等于finalize/rebuild/恢复输入已闭合；按STR-01/03判partial，不继承BAL的完全closed。
5. **路径因果**：上一轮“中文路径一定放行/中文名即可绕过”未经证明，予以撤回。已有证据证明路径变形和rename源遗漏，不足以推导所有中文文件都会被放行。
6. **B17取证**：18/18、1121 tests/1120 pass/0fail/1skip是已有TAP的真实计数，唯一skip为EXEC-12；但“四个变异均为有效行为RED”和“通用前置已全部清掉”不成立，予以撤回。初版夹具/ReferenceError不补算有效RED。
7. **跨平台symlink测试**：仅用`git update-index --cacheinfo`只证明index事实，不能自动覆盖真实filesystem/realpath逃逸分支；修复时须用可执行的真实链接环境或明确适配器测试缝，不能再次以setup失败/skip冒充。

## 记录类修订（不冒充产品安全阻断）

- disposition重复编号、“strong仍在跑”等旧状态、方案“未经复核”应改成“修订稿待复核”的精确表述；旧数字、命令模板残句同步清理。
- 历史v0.5首轮session的正确值如下；冻结的旧汇总误写`01a17797-...`，本轮在此做errata，不改冻结输入：
  - strong `01a1796a-23b8-77b9-a3c5-0f7bb49a78dc`
  - balanced `01a1796a-6197-77b9-a3c5-0f7c0aa2351c`
  - economy `01a1796a-91f3-77b9-a3c5-0f7f2e805ad0`
- X7字段语义与不豁免原则在计划层已修正；X8“不改inputDigest、gate拒绝不等于已重测”保持原决策，不增设专用触发器。

## 后续顺序（本轮未执行）

1. AIFI-45先闭R5/R6并更正B17证据记录；不拿现有四份RED直接宣称完成。
2. M003方案把R1/R2/R3一次收敛为唯一实施合同（推荐保持(a)覆盖真实候选写集，但本轮未把推荐写成用户已确认），同步R4/R7与记录类修订。
3. 对修订后的新hash再次独立复核；旧BLOCK不自动继承为PASS。G1/G5等本地DB修复仍须按既定隔离runner与RED/GREEN取证，不等M003另开change才处理。

本轮仅新增复核产物；未修源码/方案、未提交、未push，未动其他change脏改与multica生成物churn。
