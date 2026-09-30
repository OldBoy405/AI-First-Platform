# collect-evidence.ps1 — 采集 U/S/P 三案本地 reviewer run 的证据（人运行）
#
# 用法（在本地交互式 PowerShell 中，人执行）：
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\collect-evidence.ps1 -Case U
#
# 前置：该案的本地 reviewer run 已跑完（canonical dev-plan.yml 已由 crctl review-record 落盘），
#       且原始 run 日志已重定向到 <本目录>\<Case>\reviewer-run.log。
# 本脚本只读夹具、只写本 CR 的 test-evidence 目录；不写任何业务 CR、不写平台。

param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('U', 'S', 'P')]
  [string]$Case
)

$ErrorActionPreference = 'Stop'

$caseMap = @{
  U = @{ Cr = 'CR-2026-901'; Axis = 'plan 把全仓 make test 设为关键 cmd-01、TASK 附加全仓绿色（无已批准的全量要求）'; Expect = 'block（+具体 FR/AC 与证据 ID、repair-target=write-dev-plan）' }
  S = @{ Cr = 'CR-2026-902'; Axis = '关键 cmd 只跑两个定向用例，plan/TASK 声称全量通过'; Expect = 'block（子集不得冒充全量）' }
  P = @{ Cr = 'CR-2026-903'; Axis = '定向 cmd-NN 覆盖 FR/AC、范围标注一致、不附加全量'; Expect = '不因缺全仓测试被 block' }
}
$Cr = $caseMap[$Case].Cr

$KitRoot  = 'C:\Users\GOBAO\Downloads\AI\cr073-scope-fixtures'
$Kb       = Join-Path $KitRoot ".rayai-worktrees\knowledge-base\requirement\$Cr"
$ToolsWt  = Join-Path $KitRoot ".rayai-worktrees\tools\requirement\$Cr"
$Crctl    = 'C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-073\skills\shared\crctl\scripts\crctl.mjs'
$Evidence = 'C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-073\change-requests\CR-2026-073\test-evidence\scope-review\independent-run'
$Out      = Join-Path $Evidence $Case
$Canon    = Join-Path $Out 'canonical'

New-Item -ItemType Directory -Force -Path $Out   | Out-Null
New-Item -ItemType Directory -Force -Path $Canon | Out-Null

if (-not (Test-Path $Kb))     { throw "KB worktree 不存在: $Kb" }
if (-not (Test-Path $ToolsWt)){ throw "tools worktree 不存在: $ToolsWt" }

foreach ($p in @('MULTICA_TASK_ID', 'MULTICA_TOKEN', 'MULTICA_TASK_CONFIG_ROOT')) {
  if (Test-Path "env:$p") { throw "本会话存在 Multica task context 变量 $p —— 本地执行要求无 task context，请换一个干净的终端" }
}

# 1) canonical 三件 + cr.md 原文副本
$relFiles = @(
  "change-requests\$Cr\review-annotations\dev-plan.yml",
  "change-requests\$Cr\review-loop.yml",
  "change-requests\$Cr\traceability.yml",
  "change-requests\$Cr\cr.md"
)
$copied = @()
foreach ($rel in $relFiles) {
  $src = Join-Path $Kb $rel
  if (Test-Path $src) {
    $dst = Join-Path $Canon ($rel -replace '[\\/:]', '_')
    Copy-Item $src $dst -Force
    $copied += $dst
  } else {
    $copied += "MISSING: $rel"
  }
}

# 2) crctl next 原样输出 + git 状态
& node $Crctl next $Cr --workspace $Kb *>&1 | Tee-Object -FilePath (Join-Path $Out 'crctl-next.txt') | Out-Null
& git -C $Kb rev-parse HEAD    *>&1 | Tee-Object -FilePath (Join-Path $Out 'fixture-head.txt') | Out-Null
& git -C $Kb status --porcelain *>&1 | Tee-Object -FilePath (Join-Path $Out 'fixture-status.txt') | Out-Null

# 3) MANIFEST：逐文件 sha256 + 采集时间 + 该案判据登记
$lines = @()
$lines += "case=$Case"
$lines += "cr=$Cr"
$lines += "axis=$($caseMap[$Case].Axis)"
$lines += "expected_by_design=$($caseMap[$Case].Expect)   # 判据登记，不写入 reviewer 输入"
$lines += "kb_worktree=$Kb"
$lines += "tools_worktree=$ToolsWt"
$lines += "collected_at=$(Get-Date -Format o)"
$lines += "reviewer_run_log_present=$(Test-Path (Join-Path $Out 'reviewer-run.log'))"
$lines += "canonical_dev_plan_present=$(Test-Path (Join-Path $Kb "change-requests\$Cr\review-annotations\dev-plan.yml"))"
$lines += "fixture_head=$((& git -C $Kb rev-parse HEAD) | Select-Object -First 1)"
$lines += ""
$lines += "sha256 采到的文件："
foreach ($f in $copied) {
  if ($f -like 'MISSING:*') { $lines += "  $f"; continue }
  $h = (Get-FileHash -Algorithm SHA256 -Path $f).Hash.ToLower()
  $lines += "  $h  $(Split-Path $f -Leaf)"
}
if (Test-Path (Join-Path $Out 'reviewer-run.log')) {
  $h = (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Out 'reviewer-run.log')).Hash.ToLower()
  $lines += "  $h  reviewer-run.log"
}
$lines | Set-Content -Path (Join-Path $Out 'MANIFEST.txt') -Encoding UTF8

Write-Host "已采集 $Case ($Cr) 证据到 $Out"
Get-Content (Join-Path $Out 'MANIFEST.txt')
