# runner 赋值遮蔽的 AST 补测

强审 recheck 指出只检查构造右侧而不检查 `=` 与左侧，错误的 `:=` 可能遮蔽外层 runner。原测试快照 `source-recheck/router_admission_test.go` SHA `7c817e9cffed262e215c9afba94db908e39fa8e5cd80d51c5d2f8a8d2b884e91` 保留。

仅修改测试：要求构造语句赋值给 `architectureRunner, runnerErr` 且 token 为 `=`。在独占临时副本将 `=` 替换为 `:=`，原 AST 测试 PASS、新测试在 `runner constructor must assign the outer runner and error directly after guard` 断言处 FAIL；变异只进行 AST 解析，不声称运行了 server。逐一删除副本并核空删除目录。

当前测试 SHA `897b8192b6eb47704822cc2ed23775e8356a33f878f32dc91adf81aa46da8026`；其他 4 文件 SHA 不变，作者 no-DB 两包重跑 4 顶层/16 leaf PASS、0 skip。生产源码未变，AST 依然不检查其他文件、间接构造或上游改写，也不执行 startup。另在强审进行期间已单独补充 CLI help，见 `AUTHOR-CLI-HELP.md`。
