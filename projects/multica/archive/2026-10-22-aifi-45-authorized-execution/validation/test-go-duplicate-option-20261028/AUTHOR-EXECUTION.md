# test-go 重复选项与路由测试：作者记录

## 范围

`scripts/test-go.sh` 在第二次 `--only` 出现时即打印 usage 并退出 2，不让后一个选项覆盖前一个。重复且相同、重复且冲突均拒绝；单次 `--only`、`--race` 与默认两套件不变。

新增 fake-Go 断言覆盖四种重复顺序、默认两套件和两种单选套件、两种 race 参数顺序、regular 的一次 `go list` 和 agent 不查询包集。fake `go test` 检查由 guard 传递的 marker 变量；这是受控测试桩中的路径断言，不是防恶意伪造的安全认证。此前的空包集和 `go list` 失败回归保留。

## 版本、红绿与变异

- 修改前源码 `6ea063a5b5eed74897468a35a404919a80f4a83b494208359f726a5e8f2b90c8` 和测试 `67d51ae935eae61980a91bb7e40da35f2fc33cd1d131f4d26d970de16a285214` 已逐字节保全于 `source-before/`；旧报告未变。
- 新增重复用例、尚未修源码时，测试 SHA `891dcc83dae2da1a4dc75541dbe213d38b7508a3bb75efb4c21e432471a7dd73`：实测退出 1，命中 `conflicting --only regular then agent returned status 0, want 2`；测试在首个失败后停止，不能说其余三例均实测 RED。
- 源码修复、增加默认测试后，首次 GREEN 并独立审阅的版本保全于 `source-review/`；测试 SHA `8a2229d9eed881de3407d085b8c8b5f6867d4ec126fd0da405aefeda66612d29`。此后只扩充测试，不改产品源码。
- 针对独立审阅指出的路由盲点，最终测试 SHA `47ad3429a9850c379419d7c9f09c0b8e883ac26f3647bc2d32e5719c24a2b67e`；源码 SHA `b009954bc50ac182de9137782195766db46950cca5dfadf20fae17af77c4f543`。作者运行 `bash scripts/test-go.test.sh` 退出 0，输出 PASS；前后源码及测试 SHA 一致。
- 在隔离自有临时复制树中分别仅移除 regular 或 agent 的 guard 调用，每次均退出 1 并命中 `go test was not routed through the agent CLI guard`。没有改动真实源码；变异后重新核实时源码和测试 SHA 不变，最终测试再次退出 0。隔离复制树只含已列出的四个脚本/名称文件和空 server 目录，逐项删除；测试临时目录均确认空后删除。

只运行 fake Go，未运行真实 Go 套件、DB、容器或真实 CR。未保存逐次完整 stdout/stderr，以上为作者记录而非原始日志。测试未注入 fake `go test` 失败，不能证明每条失败传播；也不覆盖受信实例 supervisor、TestMain 环境或完整 CI。

## 口径更正

此前 `continuation-boundaries-20261028.md` 与会话中称“业务 TC 44/49”不够准确：`validation/tc-coverage-20261025T153000Z.md` 的 44/49 是按命名 CP 执行与断言的台账口径，不能推论 44 项完整生产能力或端到端业务验收。未在本轮复跑全部 CP；仍有 RUN-001/003/006/007 和 EVD-008 待补，Gate3 NO-GO。以上更正不改写既有已引用报告。
