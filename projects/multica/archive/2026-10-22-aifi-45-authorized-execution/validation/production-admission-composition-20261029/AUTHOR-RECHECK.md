# 生产组合 guard 强审后的补充

强审识别了 AST 结构测试可能假绿、`runner.go` 旧注释与新组合行为冲突，以及 router 在 guard 前已进行其他初始化。先保全原强审 4 个源码/测试快照与 `runner.go` 到 `source-first-green/`，保留原审阅与原作者记录，不覆盖。

## 假绿复现与补测

在 `mkdtemp` 独占目录创建最小 Go AST 测试副本，在副本的 router 逐次变异，不碰工作区真实源码。初版测试对：构造器传 nil、guard 后覆写 opts.Decider、Exit 前提前 return 三种变异均错误 PASS。随后只修改 AST 测试，要求 guard 的 log 与 exit 形状、紧接其后只能声明未初始化的 runnerErr、构造器接收被验证的同一 opts.AdmissionDecider，拒绝当前文件中旧 constructor 及 governance 别名/dot import。

最终 AST 测试对以上三种变异均在对应明确断言处 FAIL；另将 import 改为别名的静态解析变异也在别名断言处 FAIL。副本只解析 router AST、不编译整个变异 server，因此这些是**结构变异**而非运行时证明；改名别名时副本没有同步改所有引用，更不作编译结论。临时文件逐一删除、目录核空删除。别的文件、间接调用、类型检查、实际进程行为仍不在此测试覆盖范围。

`runner.go` 与 `execution_admission.go` 另外只改注释：描述 direct constructor legacy 风险、decider 仅覆盖部分路径、现有 CR-level component 不可直接生产接线、request ID 与 task ID 相等是未验证假设、manifest/scope 来源与恢复仍未证明。`router.go` 行为未变。注意 guard 在当前 router 中段，虽然位于 runner 构造/连接之前，但其他初始化可能已发生；未宣称整个进程零副作用。

## 最终作者复跑

no-DB 测试：`go test -count=1 -json ./internal/governance/admissionguard_test ./internal/governance/runnerquery_test`，分别 1 顶层/13 leaf 与 3 顶层/3 leaf，0 fail、0 skip；`go build -o <独占临时目录>/server.exe ./cmd/server` exit 0，未运行 server，二进制与自有目录已清除。测试前后 SHA 未变：

- `execution_admission.go` `23cac3ae674b5aa7e93676bc3c2f04c691e5dde27a695ad0e347a0b266c5a92e`
- `runner.go` `d8898444d260d2f674d84b2709ac3f4c622b00d502013a2cd0626c0ad4552811`
- `router.go` `0ee5c8cfeafd688a851c8604d2382354f2fb2171d7facbe18a5185eee7b18f87`
- `admissionguard_test/decider_test.go` `60b99f2518400449ba7e22942b41a189249e6d9d1aae3073a2244c0e22bd0028`
- `runnerquery_test/router_admission_test.go` `7c817e9cffed262e215c9afba94db908e39fa8e5cd80d51c5d2f8a8d2b884e91`

最终版本尚待独立复核。非 nil/typed-nil 形状检查不认证 decider；main 未注入，启用开关会终止整个 server，不能视作生产集成完成。未运行 DB、容器、真实 CR，不改变 RUN/Gate3。
