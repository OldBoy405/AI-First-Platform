# FR-14 启动回执（plan.md §5.4 第 4 项落点）

来源 run 的启动入口 = PATH 上的稳定入口 `multica`（采集指令硬边界 4：该 run 的存在本身就是「已发布入口」的判据）。

> **落盘口径**（plan.md §5.4 第 5 行「执行者提供原样事实，dev-agent 原样落盘（不加工、不改写）」）：
> 以下内容为受控采集 run 的**原样回执逐字转录**，未加工、未改写、未判优劣；判定由人工与 `review-code` 消费。
>
> - 来源评论：`01a128dd-e63f-7cba-a31e-f8bec61cc6e5`（Issue AIFI-62 `01a120c6-4681-7c18-ae40-e13067c94ed6`）
> - 采集指令原文：`01a128d7-0ad6-7763-ac2d-df83af0e7ec6`（plan.md §5.4 第 4、5 项受控采集 run）
> - 采集执行者署名（原样）：执行者：`cr-coordinator-agent` `87ca2271-f4d8-4865-aef1-9a24523e1a20` · runtime `dfdfbb04-15da-4235-bf55-9e9935f8e903`（`multica runtime list` 原样：name=`Qoder (DESKTOP-OT18TRG)`，provider=`qoder`，status=online）· model 字段原样 `qfmodel`（`multica agent get 87ca2271-f4d8-4865-aef1-9a24523e1a20 --output json` → `"model": "qfmodel"`，`runtime_mode: local`，`runtime_bound: true`）
> - 落盘：`CR-2026-076` TASK-17；该来源评论的其余段（`## 验收项原样回报`）仍留在上述评论内，本文件不重复。

## 1. 入口版本

```
$ which multica
/d/Program Files (x86)/multica/resources/app.asar.unpacked/resources/bin/multica

$ multica --version
multica v0.6.1-429-ge5f0fc089 (commit: e5f0fc089, built: 2026-10-10T23:58:07Z)
go: go1.27.1, os/arch: windows/amd64
```

## 2. 监督进程

```
$ multica daemon status --output json
```

七字段原样：

```
cli_version  = "v0.6.1-429-ge5f0fc089"
daemon_id    = "019fb3d6-67d5-7591-b597-26a04c9f6fd6"
pid          = 112364
profile      = "desktop-localhost-8080"
launched_by  = "desktop"
uptime       = "1h54m7s"
status       = "running"
```

同一回执其余字段原样：`active_task_count=1`、`running_task_count=1`、`resource_wait_task_count=0`、`device_name="DESKTOP-OT18TRG"`、`os="windows"`、`server_url="http://localhost:8080"`、`failed_terminal_report_bytes=0`、`failed_terminal_report_count=0`、`pending_terminal_report_bytes=0`、`pending_terminal_report_count=0`、`agents=["qoder","claude","codex","opencode","pi","cursor","kimi","codebuddy"]`、`workspaces=[{id:"30641781-762e-401b-b541-f33387fe2294",runtimes:[9 项]}]`。
