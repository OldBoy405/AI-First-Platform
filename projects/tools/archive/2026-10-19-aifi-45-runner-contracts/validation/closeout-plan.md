# 交付收口清单（DELIVER 阶段，Gate 3 之后）

> 口径：Gate 3 已确认 BUILD。本文件不改写 `tasks.md`，只登记 BUILD 之后追加的验证与修复。

## 1. 三类残余项

| 类别 | 含义 | 处置 |
|---|---|---|
| V（只缺验证） | 代码已存在，缺「当前 HEAD 上跑绿」的证据 | 全量补跑，见 §3 |
| C（要改代码/测试） | 实质缺陷 | 本轮修复 8 处，见 §2 |
| N（不声称） | 只能声明边界 | 见 §4 |

## 2. C 类：本轮修复 8 处

产品代码 2 处、测试 6 处。逐条见 `delivery/summary.md` §7.2 表。关键一条是**产品缺陷**，不是测试问题：

`crctl.mjs` 的 `--json` 信封与原生输出走 `process.stdout.write(...)` 后立即 `process.exit()`。POSIX 管道只接收 65536 字节即被丢弃，Windows 管道可整块接收，因此大输出（>64KiB）在 Linux 上被静默截断——`--json` 信封不再是单个 JSON，64MiB `ENOBUFS` 信封同样被截断。改为循环 `fs.writeSync`（`writeAllSync`）后两侧一致。

另 3 条是 **M003（`de9bf75`）引入的回归**，已在 `projects/tools/archive/2026-10-27-trusted-verdict-channel/delivery/summary.md` 追加修订记录。

## 3. V 类：全量套件双平台

| 平台 | 运行时 | tests | pass | fail | skip | 证据 |
|---|---|---|---|---|---|---|
| Windows 11 / Node 24.15.0 | 1461s | 1291 | 1290 | 0 | 1 | `win-full-20261028T063000Z.tap` |
| WSL2 Linux 6.18（原生 ext4，root + 受限身份） | — | 1291 | 1290 | 0 | 1 | `linux-full-20261028T064500Z.tap` |

两轮均设置 `AIFI45_ISOLATION_PROFILE=995:994`、`AIFI45_ISOLATION_AGENT=994:993`，M003 的 isolation leaf 因此被真正声明并执行（故 1291 = 1280 + 11）。

两条 skip 互补：Windows 无符号链接原语（`EXEC-12`），Linux 无 junction 原语（`EXEC-15`）；各自在对侧平台执行通过。

## 4. N 类：不声称

- Node 20 未执行。
- 独立 Linux 主机未执行（Linux 列为 WSL2 内核 / 原生 ext4）。
- Linux 列以 root 运行（M003 的 isolation 测试在 WSL 内需要 root 才能 `runuser`）；因此 `source-not-readable` 分支在该轮不可证，已按 diagnostic 登记。

## 5. 证据索引

| 项 | 文件 |
|---|---|
| 修复前 Windows | `win-full-20261028T040000Z.tap` |
| 修复前 Linux（drvfs / 原生） | `linux-full-20261028T050500Z.tap`、`linux-native-20261028T052500Z.tap` |
| 修复后 Windows | `win-full-20261028T063000Z.tap` |
| 修复后 Linux | `linux-full-20261028T064500Z.tap` |
