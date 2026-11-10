# SC-NTF-003：既有命令名后接 TAB 的局部守卫切片

## 范围与状态

原 AIFI-45 Gate2 的 SC-NTF-003/TC-NTF-003 要求不让业务方搬运终端命令；先前行分隔符切片未声明覆盖 TAB。本切片仅拟使既有五个命令名 `sudo`、`psql`、`kubectl`、`podman`、`docker` 后接 ASCII TAB 的检查，与其后接 ASCII 空格的既有检查一致；行尾的空白会被既有 `TrimSpace` 去除，所以命令名后只有空白时仍不在此模式覆盖内。不是新增命令黑名单、完整 shell 解析器或新签名/线协议。

源码 `multica/server/internal/governance/execution_notice.go` 在 `BuildNotice` 的 Action 和逐项 TriedPaths 上调用同一守卫；`DeliverNotice` 在事务和广播前调用 `BuildNotice`，静默事件先返回。旧版五个既有模式只含空格，带 TAB 的同类字符串未命中；现已在原位增加五种 TAB 模式，并新增 `TestNoticeRejectsTabbedExistingCommands`、登记 `multica/CUSTOM.md` #285。函数快照已 RED→GREEN；旧版公开 API RED、新版 GREEN 和同包回归也已执行，但独立审查指出目标 token 和继承句柄等隔离缺口，不能作为合规验收。见 `notice-tab-isolation-20261031/ISOLATION-REVIEW.md`；本切片仍未完成。

## 执行顺序调整：先做函数级切片

完整的公开 API 旧版 RED、修复后 GREEN 和同包回归要求**保留**，不以函数测试替代。由于 `noticeguard_test` 的第三方初始化隔离仍未证明，先从当前生产文件唯一锚点原样提取该函数，在全新独占临时目录、显式无凭据环境和仅 Go 标准库的构建图中执行局部 RED→GREEN；提取片段与生产文件分别记录 LF 哈希。这是调整局部修复的验证顺序，不变更 SC 或降低最终验收。它不是 OS 沙箱，也不能证明 Build/Deliver 行为。已有旧版公开 API 测试二进制保留在编译预检的本轮独占目录中，隔离就绪后须先运行该旧版真实 RED，再编译当前源码跑 GREEN 和同包回归；二进制、源码和完整依赖身份均须重新核验。

函数快照 RED 已执行：19 个父/子测试事件、5 个 TAB 子例和父测试按预期失败，5 个空格对照与其余 8 个父/子回归事件通过，0 skip；旧行为缺陷已在函数快照中重现。该结果不是公开 API RED，也不是 TC-NTF-003 通过。证据和边界见 [预检报告](notice-tab-preflight-20261031/REPORT.md)。

## 测试与实现计划

1. 在独立子包 `server/internal/governance/noticeguard_test/` 的公开 API 测试里先登记五个命令的空格/TAB 对照，覆盖两类受众的 Action、TriedPaths 非首项及 Build/无 DB 的 Deliver 拒绝；保留普通 TAB 文本、静默事件、错误优先级和原有模式正控。2026-10-31 的测试准备增量拆分 Build/Deliver 子例，补双受众超长 TriedPaths、字面 `\\t` 与行尾只有 TAB 的既有接受边界；这些增量已独立静态复核，公开 API 动态观察及隔离不足见 `notice-tab-isolation-20261031/ISOLATION-REVIEW.md`。
2. 先证明旧代码下 TAB 断言因行为缺口失败、空格正控通过；编译失败、缺依赖、零选中、跳过或 panic 均不计 RED。当前 TAB 矩阵不再捕获 nil pool：Deliver 使用 nil broadcaster，使旧代码漏过命令检查时先返回既有 `notice broadcast is required`，不会进入 pool；反例要求更早的 `NOTICE_ACTION_MUST_BE_HUMAN` 和零返回。另有普通输入对照要求该 nil-broadcast 错误。该方式只验证公开投递入口的校验顺序，不证明事务或广播。
3. 函数快照 RED 后可先在原检查增加这五种 TAB 模式，不重新分割或规范化输入；保留所有旧检查。修复不视为完成：仍须按上面的顺序运行旧版公开 API RED、修复后相同断言 GREEN、独立子包完整回归，并由非作者审核。新增拒绝对历史调用/重试的兼容风险应记录；维护者的超长 TriedPaths 含该 TAB 模式时，原 VERBATIM 错误会变为更先执行的命令错误；授权者的超长 TriedPaths 虽不渲染，也会从接受变为拒绝。该双受众场景现已补断言，但尚未执行。合法 JSON 字符串中的 TAB 只能转义为两个字符，不是此处匹配的原始 TAB；不宣称识别所有命令。
4. 真实源码改动须按当前结构登记 `multica/CUSTOM.md`。最终只可计组件子断言，真实 producer/recipient/恢复/广播、完整 TC 和 Gate3 均仍待验证。

## 执行安全

- 独立子包测试文件本身静态无 DB fixture，但它导入 governance 的完整依赖图。独立 strong 审阅无法证明全部第三方 init 无副作用，因此业务测试暂时 BLOCK；绝不运行父包 TestMain、`./...`、真实 CR 或 DB。
- 已在无凭据最小环境中以 `GOPROXY=off`、`GOTOOLCHAIN=local` 等约束仅执行 `go list -deps -test`，exit 0；获取 491 个包、其中 251 个非标准库包，未运行测试或包 init。依赖列表不等于隔离或安全证明。输出与独占 Go cache 位于本轮自建临时目录，未删除既有资源。
- 执行真实测试前须对依赖初始化风险取得足够的独立安全证据或可证明的 OS 隔离，且保留 exact selector、非零匹配、实际失败断言和 exit；离线依赖缺失不联网补齐。用户已新授权建立全新独占离线隔离环境及 disposable PG，但授权不等于环境已建立或隔离已证明；本执行者未创建或访问任何 DB/容器。
- 2026-10-31 只做不执行产物的离线编译准备：`notice-tab-guard-preflight.mjs` 在不继承宿主凭据的显式环境、全新独占 HOME/TEMP/GOCACHE/GOPATH 中，以本机 Go 1.27.1 和已有 module cache 运行 `go list -deps -test -json`、`go test -c -vet=off -o <新目录>/noticeguard.test.exe ./internal/governance/noticeguard_test`，均 exit 0。目标源码与生产源码编译前后 SHA 相等；父 governance 没有测试变体，未运行其 TestMain 或任何依赖 init。
- 证据：[本轮预检交接](notice-tab-preflight-20261031/REPORT.md)。实际依赖图仍为 491 包 / 251 非标准库包；选中文件清单及 39 个显式 init 候选文件已保存。候选扫描不包含所有包变量初始化及调用副作用，**不构成独立安全证明或测试运行许可**；编译 exit 0 不计 RED、GREEN、用例选中或同包回归。
