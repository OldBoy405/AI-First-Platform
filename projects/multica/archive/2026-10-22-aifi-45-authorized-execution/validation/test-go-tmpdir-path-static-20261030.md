# test-go guard 的 TMPDIR/PATH 风险：静态发现，复现 BLOCK

只读会话 `01a187a2-63ca-7020-aecc-d38d8dbb86b5` 发现 `scripts/go-test-with-agent-cli-guard.sh` 将 `$TMPDIR` 下的 sentinel 目录直接放入以 `:` 分隔的 PATH；`scripts/test-go.test.sh` 对假 go 目录同样如此。若 Bash 路径的 TMPDIR 含 `:`，路径被拆分，可能找不到 sentinel 或测试 fake-go；后备 PATH 中的程序可能被调用，marker 不一定产生。`test-go.sh` 在 guard 之前运行 `go list`。这些是静态推导，未证明真实环境下发生，亦未实测 RED。

独立安全评审 `01a187a7-2ce8-7020-aecc-d3952c18410e` 确认风险，并将执行复现方案标记 **BLOCK**：两个现有脚本包含 `rm -rf` trap，mktemp 目录及父目录在创建后可能被替换；PATH 和所运行工具亦非可信。环境白名单不是 OS 隔离。实际 backend unknown。

候选收紧：三个入口在执行 Go 或创建临时目录之前，对 PATH 中使用的临时根拒绝非 POSIX 绝对路径和包含 `:` 的路径。Git Bash `/tmp`、`/c/...` 是候选兼容形式，Windows `C:/...` / `C:\\...` 须先转换；显式空 TMPDIR 目前按 `${TMPDIR:-/tmp}` 回退，是否改变这一行为需要兼容决策。字符串校验不能解决 symlink 竞态、恶意 PATH 工具、绝对路径调用 CLI 或自行改写 PATH。

后续复现须用经独立确认的 OS 级私有隔离、只含 fake Go/CLI 的工具链、受控 mktemp/rm 替身和完整所有权清单；已登记对象逐个清理，出现未知对象或路径变化即停止并保全，不运行真实 Go、agent CLI、DB、网络或容器。隔离与安全清理尚未证明，当前**不运行拟议测试、不修改这些脚本**。
