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

---

# 切换后窗口（2026-10-12）：已发布入口即 CR 版本、监督进程已重启一次

> **本窗口落盘口径**：以下为切换后窗口内两次真实 run 的**原样观测逐字转录**，未加工、未改写、未判优劣；判定由人工与 `review-code` 消费。切换前窗口的既有正文（上方全文，来源评论 `01a128dd-e63f-7cba-a31e-f8bec61cc6e5`）原样保留，未被覆盖或改写。
>
> - **授权依据**：Ray 选 B——「选 B，接受本次受控采集与原样落盘的角色合并；关于绑定根的，按照当前已通过的方式处理。」由 Issue AIFI-62 评论 `01a12df0-d4e9-7904-8400-2150b1c4b9a9`（2026-10-12T02:28:40Z）逐字转述。据此本次仅解除 TASK-17「该回执由人类 owner（Ray）提供、本 TASK 原样落盘」针对**本次事实提供方**的单一角色限制（本次执行者 = 落盘者）；不合并作者与独立评审角色、不代签、不修改其他批准范围。
> - **采集来源 1（受控采集 run）**：task `01a12dd9-b2be-73ea-b693-42b2ee5a6cdb`（`dev-agent`），其原样回执评论 `01a12de2-57af-741a-9bb0-44efb90bab3c`，发布时刻 2026-10-12T02:12:50Z；该 run 实跑 `cmd-15` 的入口／守护版本事实逐字转录于 §1.1。
> - **采集来源 2（本续接任务补采的只读观测）**：task `01a12df0-d4f9-73c1-8abe-68da53302132`（`dev-agent`，`MULTICA_TASK_ID` 原样），原始观测时刻 **2026-10-12T02:32:37Z（UTC）**；原始命令与输出逐字转录于 §1.2、§2、§3。
> - **原始采集时刻 ≠ 落盘时刻**：本节落盘于 2026-10-12T02:34Z（本续接 run 执行窗口内，UTC）；上述时刻分别是各来源的原始观测／发布时刻，不得以后者冒充前者。

## 1. 入口版本

### 1.1 来源 run 的 `cmd-15` 实跑（原样，其回执发布时刻 2026-10-12T02:12:50Z）

```text
$ node -e <plan.md §6.2 cmd-15 原样 args>      # cwd = KB CR worktree
installed-entry: multica v0.6.1-cr076 (commit: d0b8fef9d, built: 2026-10-12T07:29:55Z)
daemon-cli-version: v0.6.1-cr076
```

该次实跑 `exit=1`，唯一失败项为「启动回执未载明现场入口版本: v0.6.1-cr076」——失败落在**回执面**，版本面本身全绿；原始回执全文见评论 `01a12de2-57af-741a-9bb0-44efb90bab3c` §三.1。本次落盘即针对该失败项。

### 1.2 本续接 run 补采（原样，原始时刻 2026-10-12T02:32:37Z）

```text
$ which multica
/d/Program Files (x86)/multica/resources/app.asar.unpacked/resources/bin/multica

$ multica --version
multica v0.6.1-cr076 (commit: d0b8fef9d, built: 2026-10-12T07:29:55Z)
go: go1.27.1, os/arch: windows/amd64
```

## 2. 监督进程（原样，原始时刻 2026-10-12T02:32:37Z）

```text
$ multica daemon status --output json
{
  "active_task_count": 1,
  "agents": [
    "pi",
    "cursor",
    "kimi",
    "codebuddy",
    "qoder",
    "claude",
    "codex",
    "opencode"
  ],
  "cli_version": "v0.6.1-cr076",
  "daemon_id": "019fb3d6-67d5-7591-b597-26a04c9f6fd6",
  "device_name": "DESKTOP-OT18TRG",
  "failed_terminal_report_bytes": 0,
  "failed_terminal_report_count": 0,
  "launched_by": "desktop",
  "os": "windows",
  "pending_terminal_report_bytes": 0,
  "pending_terminal_report_count": 0,
  "pid": 121988,
  "profile": "desktop-localhost-8080",
  "resource_wait_task_count": 0,
  "running_task_count": 1,
  "server_url": "http://localhost:8080",
  "status": "running",
  "uptime": "2h41m25s",
  "workspaces": [
    {
      "id": "30641781-762e-401b-b541-f33387fe2294",
      "runtimes": [
        "88cd4956-b1ea-4dcd-ab6e-6f549e0a8bd0",
        "3ef529fe-6a8b-425f-9d37-d05887e8c221",
        "9ae32e54-95e3-4d1f-a40a-9f42f45d2f62",
        "fe283ab1-8560-4c3e-a28f-e1f9384727ac",
        "0ceb8aa8-d73b-490a-8364-d5170e3855a4",
        "47fb333f-1a4f-4025-b032-98fd752afd74",
        "f459199d-9ee5-4db3-a6a5-da88e468d614",
        "dfdfbb04-15da-4235-bf55-9e9935f8e903",
        "43059d61-c36b-4e01-84e2-9b782231954a"
      ]
    }
  ]
}
```

切换前后同 profile 对照（「重启桌面监督一次」的直接观测；两列均为上述两窗口各自回执的**原样取值**）：

| 字段 | 切换前窗口（上方 §2） | 切换后窗口（本节 §2） |
|---|---|---|
| `cli_version` | `v0.6.1-429-ge5f0fc089` | `v0.6.1-cr076` |
| `pid` | `112364` | `121988` |
| `daemon_id` | `019fb3d6-67d5-7591-b597-26a04c9f6fd6` | `019fb3d6-67d5-7591-b597-26a04c9f6fd6`（同） |
| `uptime` | `1h54m7s` | `2h41m25s` |
| `profile` | `desktop-localhost-8080` | `desktop-localhost-8080`（同） |

## 3. 本窗口启动的 run 身份（原样，补采时刻 2026-10-12T02:32:36Z–02:32:38Z）

```text
$ printenv MULTICA_TASK_ID MULTICA_AGENT_NAME
01a12df0-d4f9-73c1-8abe-68da53302132
dev-agent

$ pwd
/c/Users/GOBAO/multica_workspaces_desktop-localhost-8080/ai-first-f33387fe2294/aifi-62-68da53302132/worktree
```

本 run 的任务上下文文件 `.multica/daemon_task_context.json` 原样为 `{"managed_by": "multica-daemon-task", "agent_id": "ff6fcbb6-6bb6-42fb-9d88-03493c771411", "issue_id": "01a120c6-4681-7c18-ae40-e13067c94ed6"}`，即由守护进程托管；同一观测时刻的守护回执为 `active_task_count=1`、`running_task_count=1`（§2 原样值）。本 run 的 CR 绑定投影与目标行为原样结果见 `fr14-run-behavior.md`「切换后窗口（2026-10-12）」节，本节不重复。
