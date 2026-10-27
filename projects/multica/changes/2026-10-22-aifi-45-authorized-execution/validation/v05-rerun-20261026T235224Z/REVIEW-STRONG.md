方案裁决：BLOCK

实现/动态验收：未执行，不作通过裁决。

## 审查身份、输入与边界

- cwd：`C:/Users/GOBAO/Downloads/AI/AI First Platform`。
- strong requested：`OpenAIPersonal/gpt-6.1-sol:high`；actual：**unknown**，无后端回执。
- 独立只读；未编辑文件、未运行测试或 DB、未委派、未读取本轮其他 lane 输出。
- 已完整读取 brief、manifest、冻结方案、旧 v0.5 汇总及 disposition；读取两仓行为约束、`change-scope.mjs` 及其测试全文，并定位真实 merge 链关键源码。
- 已用只读 SHA256 核验 manifest 中全部输入，均匹配；三个 HEAD 均匹配。方案 raw SHA256 为 `6f98229a53e05dcffec20ad39b4ee1190b0444dcfce6e4a5505e9c2639f92a06`，tools HEAD 为 `7168198978e71a292d85f5bf8f538c3ee90d87bd`。本次核验未发现输入漂移，但不构成覆盖整个评审时段的持续监测。
- **覆盖限制**：merge 大文件仅完成关键符号/行段定位，未逐段完整读取 lock/recovery 全部实现；未读取 B17 TAP 正文。因此不认证“18/18、1121/1120/0fail/1skip”或四份 RED 的失败原因，不将其当通过依据。未遇读取 root 拒绝，未绕过限制。

以下 `P` 为冻结 `inputs/trusted-verdict-channel-implementation-plan-20261026.md`；`W` 为 tools 的 `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`；`S` 为同目录 `change-scope.mjs`。

## 阻断项

### STR-01 — blocker：发布对象仍有未选择语义，追加条目未形成唯一契约

**证据**：P:113 明写 Strict 下 `(a)/(b)` 二选一、“必须在实现前定死”，目前仍未选；但 P:127 已无条件规定 `trunk...HEAD` 为核对集合，P:126 又称改动集合权威来源为 M 持久批准记录中的 source SHA。

这不是纯编辑问题：选择 (b) 会禁止 KB 审批后提交及 tree-equal 放行，选择 (a) 则需要为批准后实际 source HEAD 建立独立冻结绑定，不能把批准记录下界等同发布源。两者影响批准、预检、恢复与测试正例。

真实链还有 source diff 之外的写集：W:2194–2227 的 finalize 修改并提交 `cr.md`、`merge-commits.yml`、`merge-verification.md`；W:2240–2264 可重建并发布 finalize。仅写“全部纳入”尚未给出这些生成路径在首次预检时如何枚举、冻结、授权及重验。

**最小修订**：明确选择一种语义；分别定义批准 source、实际 source、base、候选 merge/finalize 写集，列出生成路径及重建规则。不得给 KB 隐藏豁免。

**归属**：M003 方案；若选择改变既有批准语义，须相应授权确认。

### STR-02 — blocker：可信 merge caller、只读端点和冻结凭据未定义

**证据**：P:124–125 正确要求 workspace/CR 由 M 解析，并依赖 §6 的只读端点；但 §6（P:186–198）列出的 commands/verdict/checkpoint API，没有该 merge facts 接口，也没有 merge caller 的认证及授权合同。

**反例**：agent 控制 CLI 的 workspace、graph、请求参数；若端点仅按所报 workspace/CR 返回一份有效 grant，CLI 仍可能把另一套本地仓与 source 集合作为发布对象。typed facts 有正确名字，不等于已经绑定当前调用和实际发布集合。

**最小修订**：规定 endpoint、认证主体及禁止的 fallback；服务端如何解析 scope；请求/响应闭集；selection、head revision、repo identity/current binding、source/base、批准记录之间的绑定；冻结凭据的保存及恢复验证。不得依赖 agent 可写 `.crctl` 自证可信。

**归属**：M003 方案／外部身份授权。

### STR-03 — blocker：撤销与实际 Git 发布之间仍缺明确线性化合同

**证据**：P:117 要求 publish 前“锁内重验”，并规定部分发布后撤销停止后续发布；但未定义该锁与 M 撤销事务的共同互斥关系。真实发布链是逐仓进行，W:2146–2180 涉及 publish/rebuild，最终 KB 发布另在 W:2230–2267。

**反例**：重验当前 head 成功后、实际 push 前，撤销提交。仅有本地 merge 锁不能据此证明撤销与平台 head 更新串行化。方案也未说明该 push 算撤销前已获授权的 effect，还是撤销后禁止发生的 effect。

另 P:114 说冻结输入变化即拒，而 W:2167–2179 会保留 source、更换 base；P:117 又把 base 列入冻结集合。合法 rebuild 是拒绝、重新求值还是生成新绑定，仍不确定。

**最小修订**：明定每次发布的授权线性化点、撤销排序及 in-flight 语义；覆盖各仓 push、finalize push、远端已成功但响应丢失、base 漂移及部分发布恢复。明确何时只能保留 journal 转人工，禁止新授权洗白历史发布。

**归属**：M003 方案；不可由实现者自行选语义。

### STR-04 — major：B17 部分修复成立，但采集前置尚未全部清除

**已能静态确认**：S:35–39 拒绝缺失/非数组；S:62–66 使用 NUL 分隔；S:87–101 收集 rename 两端；S:116–118 对部分未知情况返回 null，判定器 S:47–49 拒绝 null。因此旧“中文路径一定放行”因果不成立；现有 UTF-8 解码也不足以证明任意 Git 路径字节均无损。

**残余反例**：

1. S:115–121 用 **index mode** 决定是否读取工作树 realpath：索引仍是普通文件、工作树替换为出仓 symlink 时，S:119 直接返回 false，未检查当前对象。
2. untracked 文件没有 index entry，S:118 返回 null；`checkChangeScope` 对每条路径调用该函数，故授权内普通 untracked 文件也被拒。已提交删除、rename 旧端同样可能因当前索引无项而被拒。拒绝未知是安全方向，但不能据此宣称合法行为完整。
3. 当前 symlink 结果不绑定选定提交树，不能复用为 committed/tree 的可信判断。

**最小修订**：保留纯判定器复用；自检按状态区分 regular/symlink/untracked/deleted，使用与被检查状态一致的事实来源；committed 适配器按选定 tree/blob 取 mode/目标。补真实接线正反例，未知仍 fail-closed。

**归属**：通用自检缺陷归 AIFI-45 本地；committed/tree 适配归 M003。

## 旧问题闭环状态

| 旧关键问题 | 本轮状态 |
|---|---|
| `approval.yml` 单独充当权威 | **partial**：P:126 已禁止，但可信接口与绑定未闭合 |
| 核对对象与实际发布对象一致 | **open**：STR-01、03 |
| 首次拒绝零写入 | **partial**：P:115–116 前移到 gates 前是正确方向；`crctl.mjs:915,924` 确有 drift audit。P:123 仍保留旧式 audit 排除口径，应统一 |
| rename、路径编码、缺失集合 | **partial**：B17 有实质修复；不等于采集完整性已证明 |
| Strict/Unknown 不降级 | **closed（计划层）**：P:70–73、120、132 要求可信 legacy 证明，缺失拒绝 |
| X7 | **partial**：repo id、路径前缀、冻结绑定分别要求且无豁免；finalize 写集仍未闭合 |
| X8 | **边界正确**：不改 inputDigest；交付 gate 拒绝旧摘要不能记作已执行重测 |

历史身份记录还存在纯文档错误：冻结旧汇总的 session 前缀写成 `01a17797-...`，brief 给出的正确历史前缀为 `01a1796a-...`。此项不替代上述实施阻断。

## 最小通过集合

1. 解决 STR-01：选择发布语义，冻结完整 source/base/生成写集。
2. 解决 STR-02：补可信 merge caller、认证端点及可恢复绑定合同。
3. 解决 STR-03：定义撤销与每次实际发布的线性化、rebuild 和部分发布恢复。
4. 解决 STR-04：修正自检状态来源和合法删除/untracked 行为，并补独立 tree 适配契约。
5. 完成未覆盖的 lock/journal/recover 全链及 B17 TAP 静态复核，确认 RED 是行为断言失败，而非夹具、ReferenceError 或 TypeError。

本裁决不改变 **M003 proposed／搁置、用户自行注册、41/49、Gate NO-GO、M001/M002/M003 unresolved、原库 HOLD**。未实现本身不是本次 BLOCK 的理由；阻断来自当前冻结方案仍有未选语义及安全合同缺口。
