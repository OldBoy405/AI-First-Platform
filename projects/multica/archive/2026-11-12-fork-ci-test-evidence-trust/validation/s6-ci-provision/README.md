# Slice 6 证据 — ci-provision（TC-CBE-001，R1 口令边界）

> change：`2026-11-12-fork-ci-test-evidence-trust`｜执行时间：2026-11-12 本地｜Node v24.15.0｜npm 11.12.1｜Windows
> **本切片未运行任何数据库**：全部用例用注入的假连接（`connect` 由测试提供），不新建 podman 实例、
> 不连接 localhost:5432、不操作 `multica-postgres`。唯一一次真实网络尝试是 CLI 用例连 `127.0.0.1:1`
> （连接被拒，用于证明 `--env-file` 被接受后走的是连接失败而不是 usage 失败）。
> 切片结束后核对 `podman ps -a`：仍只有 `multica-postgres`、`multica-backend` 两个容器且均 Exited，无新增。
> 未读取或打印任何真实凭据值（用例中的口令是测试自造的 fixture）；未提交、未推送。

## 产出物

| 文件 | 性质 |
|---|---|
| `scripts/aifi45-disposable/ci-provision.mjs` | 新增（fork 独有），`ciProvisionUp`/`ciProvisionDown` + `up\|down` CLI，复用 `provision.mjs` 的建库/删库函数 |
| `scripts/aifi45-disposable/ci-provision.test.mjs` | 新增，26 项测试 |
| `scripts/aifi45-disposable/provision.mjs` | **未改**（只被调用；身份规则仍只有一份） |

CUSTOM.md 登记为 M31 第 **#322** 行。`ci.yml` 本切片**未改**（接线属 S13）。

## R1 口令边界的落地方式

修订后的 SC-CBE-001（design.md 修订记录 R1，用户裁定「收敛规格到日志与 handle」）允许
`GITHUB_ENV` 的 `DATABASE_URL` 承载 job 级一次性角色口令，但要求写入前先 `::add-mask::`。实现按此收敛：

| 边界 | 实现 | 钉住它的用例 |
|---|---|---|
| handle 不含任何口令 | `publicHandle()` 只写 database/role/marker/nonce + `stripPassword(adminUrl)`；键集合恰好 5 个 | #4、#5、#20 |
| 管理员口令只来自 job 环境 | `down` 用 `AIFI45_CI_ADMIN_URL`，**不**用 handle 里去口令的 URL 连接 | #12（断言连接 URL 的唯一集合 = job URL）、#16 |
| mask 先于任何写入 | `log(::add-mask::…)` 在三次 `appendEnv` 之前；`log` 与 `appendEnv` 共用一个 journal，顺序可观测 | #3 |
| 除 mask 命令外无明文口令 | 任何日志行都不含角色口令或管理员口令；`GITHUB_ENV` 不含管理员口令 | #5 |
| 驱动报错也脱敏 | `redact()` 同时替换管理员口令与任何 `PASSWORD '…'` 字面量（`provision.mjs` 内部生成的角色口令可能出现在 `CREATE ROLE` 报错里） | #18、#19 |
| handle 单行 | 多行值会破坏 `GITHUB_ENV` 的「一行一变量」 | #6 |
| 缺 handle 是成功 no-op | `down` 返回 `{dropped:false,reason:"no-handle"}`，**零连接** | #13、#23 |
| 坏 handle 硬失败 | JSON 解析失败、非对象、缺 database/role/marker 一律 throw，不降级成 no-op | #14、#15、#24 |
| marker 不符拒绝删除 | 直接复用 `dropDisposableDatabase` 的 marker 复核，无 DROP 语句 | #10、#11、#17 |

**如实说明一处无法回避的事实**：`::add-mask::<口令>` 这条命令本身必然把口令送到原始 stdout，
这是 GitHub Actions 规定的遮蔽协议——runner 只遮蔽它**已经见过**的值，所以 mask 必须先发。
R1 的「日志不含明文口令」指的是 mask 生效后的 runner 日志；本地用例断言的是
「除这一条 mask 命令外，没有任何一行携带口令」，而不是「stdout 从头到尾不含口令」。
已记为 ADJ-009，最终报告须一并呈报。

## RED

| 对象 | RED 方式 | 结果 | 文件 |
|---|---|---|---|
| `ci-provision.mjs` | 实现不存在时跑其用例文件 | 文件级加载失败 `ERR_MODULE_NOT_FOUND: …ci-provision.mjs`，1 tests / 0 pass / **1 fail** | `red-ci-provision.tap` |

## GREEN

| 命令 | 退出码 | tests | pass | fail | skipped | 文件 |
|---|---|---|---|---|---|---|
| `node --test --test-reporter=tap "scripts/aifi45-disposable/ci-provision.test.mjs"` | 0 | 26 | 26 | 0 | 0 | `green-ci-provision.tap` |
| `node --test --test-reporter=tap "scripts/aifi45-disposable/*.test.mjs"`（目录全量回归） | 0 | 154 | 154 | 0 | 0 | `regression-directory.tap` |

目录回归 154 = S5 结束时的 128 + 本切片 26。26 项覆盖成功路径（#1、#2、#7、#8、#10、#17、#26）、
失败路径（#9、#14、#15、#16、#21、#22、#24）与安全边界（#3、#4、#5、#6、#11、#12、#13、#18、#19、#20、#23、#25）。

> Windows Node 24 上 `node --test <目录>` 会 `MODULE_NOT_FOUND`，必须用上面的 glob 形式。

## 变异验证（8 条守卫逐条中和）

每条守卫单独改成失效写法，跑全量 26 项，要求变红，然后按原始字节恢复并核对 sha256。

| 守卫 | 结果 | 变红用例数 |
|---|---|---|
| mask 必须先于任何 env 写入（改成后置） | DETECTED | 1 |
| handle 存去口令管理员 URL（改成原样存） | DETECTED | 3 |
| down 对驱动报错脱敏管理员口令（改成原样 throw） | DETECTED | 1 |
| 坏 handle 硬失败（改成返回 no-handle） | DETECTED | 2 |
| down 必须要求 job 管理员 URL（改成不校验） | DETECTED | 2 |
| `PASSWORD '…'` 字面量脱敏（改成不处理） | DETECTED | 1 |
| handle 必须带 database/role/marker（改成恒真） | DETECTED | 1 |
| pg 走 CJS 解析器（改回 `await import("pg")`） | DETECTED | 1 |

`sha256 before = after = 2718a61f7cb6f98febb782cf3f9358ea0b3adf17974383bf6d9ab319d22fef51`。
见 `mutation-guards.txt`。8/8 DETECTED，无缺口。

## pg 取得与解析实测（任务 6.3）

- 根 `package.json` 声明 `pg = ^8.20.0`；`npm install --prefix <tmp>/aifi45-s6-pg 'pg@^8.20.0' --no-audit --no-fund`
  实际装到 **8.23.1**，14 packages，15s。**未跑全仓 `pnpm install`**。
- **NODE_PATH 只被 CJS 解析器读取**（实测，不是假设）：探针目录无 `node_modules`、祖先链上也没有 `pg`。

| 条件 | `await import("pg")` | `createRequire(import.meta.url)("pg")` |
|---|---|---|
| 无 NODE_PATH | FAILED `ERR_MODULE_NOT_FOUND` | FAILED `MODULE_NOT_FOUND` |
| 有 NODE_PATH=`<prefix>/node_modules` | **FAILED `ERR_MODULE_NOT_FOUND`** | **OK function** |

因此 `pgConnect()` 用 `createRequire`，并由第 25 项**静态契约用例**钉住（读源码、先滤掉 `//` 注释行，
断言存在 `createRequire(import.meta.url)("pg")` 且不存在 `await import("pg")`）。
若用 ESM 写法，开发机因仓库 `node_modules` 里有 `pg` 而通过、CI 的 `--prefix` 安装下必然失败——
正是会静默漂移的那类差异。已记为 ADJ-008。证据：`pg-node-path-probe.txt`、`esm.mjs`、`req.mjs`。

> 第 25 项用例第一版曾把**我自己的解释性注释**匹配成违规（`doesNotMatch` 命中注释里的 `await import("pg")`），
> 修法是先滤掉注释行再断言。GREEN 已在修正后重跑（26/26），本目录的 `green-ci-provision.tap` 是修正后的结果。

## 未验证 / 范围外（不得记为通过）

1. **未对真实 Postgres 跑过 up/down**：本切片全部用假连接。真实服务容器里的建库→迁移→测试→删库
   全链路属 S13 接线后的 TC-CBE-005（真实 CI run），当前**未验证**。
2. **`ci.yml` 未接线**：`AIFI45_CI_ADMIN_URL` 的 job 级声明、`npm install --prefix` + `NODE_PATH` 步骤、
   `up`/`down` 步骤顺序（`down` 放 `if: always()`）都属 S13。本切片只交付脚本与用例。
3. **`AIFI45_CI_ADMIN_URL` 的口令来源未核实**：R1 指出上游 `ci.yml` 既有固定 fixture `multica`；
   该值由工作流配置提供，本 change 不写出、不读取、不打印任何真实凭据。
4. **ubuntu-latest 上 `npm install --prefix` 的耗时与稳定性未测**（design 未验证事实 #6），本机 15s 只是 Windows 数据。
5. **`quality.test`（`make test`）本切片未执行**：属 U5 范围外的整仓命令，留待 Part C 统一处置。
6. **S3 改动的 4 个 runtime 守卫仍未在「环境变量缺失」下实跑验证**，仍挂在 S7。
7. **nonce 门禁本身一行未改**，但门禁的 11 个拒绝条件逐条测试属 S7（TC-CBE-002），本切片未覆盖。

## 证据文件索引

| 文件 | 内容 |
|---|---|
| `red-ci-provision.tap` | 实现不存在时的 RED（1/0/1） |
| `green-ci-provision.tap` | 26 项 GREEN（修正静态用例后重跑） |
| `regression-directory.tap` | `scripts/aifi45-disposable/*.test.mjs` 全量 154/154 |
| `mutation-guards.txt` | 8 条守卫逐条中和 + sha256 复原核对 |
| `pg-node-path-probe.txt` | pg 版本取得与 NODE_PATH/ESM/CJS 解析实测结论 |
| `esm.mjs` / `req.mjs` | 上述实测用的两个探针脚本原文 |