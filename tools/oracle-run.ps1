#requires -Version 5.1
<#
.SYNOPSIS
  moon_abi 外部 oracle 本地 runner（W6-A / M4，只读差分；G6/E3 模块侧）。

.DESCRIPTION
  在系统临时目录构造最小 MoonBit 项目，把 `moon-abi gen` 的受管块产物粘贴为
  `moon.pkg`，跑 `moon build --target native`，把「生成的 link.native 配置是否
  真能被 moon + NDK 消费」变成可复验的结构化差分报告。永不修改本仓库源码。

  边界（许可红线，见开发文档 W6-A 裁决 A）：
  - 不引用任何仓库外目录；NDK 根与哈希登记文件全部由参数注入。
  - 临时项目用后即焚；不入库任何第三方 NDK 或构建产物。
  - NDK 缺失/不可用 → 显式 SKIPPED（退出码 78），永不进入通过计数。
  - `SKIPPED` 与 `FAIL` 的 `counted_as_pass` 恒为 false。

.PARAMETER NdkRoot
  仓库外真实 NDK 根路径。为空或目录不存在 → SKIPPED（退出码 78）。

.PARAMETER HashFile
  可选：SHA-256 登记文件。首个非空且非 `#` 开头的行 = `<NdkRoot>/source.properties`
  的 64 位十六进制 SHA-256（可带 `sha256sum` 文件名后缀）。提供且不符 → 拒绝执行
  （退出码 1，T-W6-2），不进入构建。

.PARAMETER ApiLevel
  API level（默认 21）。

.PARAMETER Abi
  目标 ABI（默认 arm64；接受 `arm64`/`arm64-v8a`/`x86_64` 等 CLI 别名）。

.PARAMETER ReportDir
  报告输出目录（默认 `tools/oracle-reports`）。该目录内 `*.json` 产物被 .gitignore 排除。

.PARAMETER KeepTemp
  保留临时项目目录用于排查（默认用后即焚）。

.EXAMPLE
  pwsh tools/oracle-run.ps1 -NdkRoot C:\android-ndk\27.0.12077973

.EXAMPLE
  pwsh tools/oracle-run.ps1 -NdkRoot /opt/android-ndk -HashFile tools/oracle-reports/ndk-hash.txt
#>
[CmdletBinding()]
param(
  [string]$NdkRoot = "",
  [string]$HashFile = "",
  [string]$ApiLevel = "21",
  [string]$Abi = "arm64",
  [string]$ReportDir = "",
  [switch]$KeepTemp
)

$ErrorActionPreference = "Continue"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
if ([string]::IsNullOrWhiteSpace($ReportDir)) {
  $ReportDir = Join-Path $scriptDir "oracle-reports"
}
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null

$timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
$reportPath = Join-Path $ReportDir ("oracle-" + (Get-Date).ToString("yyyyMMdd-HHmmss") + ".json")

function Write-OracleReport {
  param(
    [string]$Status,
    [int]$ExitCode,
    [string]$Detail,
    [string]$NdkVersion = "",
    [string]$SourceHash = "",
    [string]$Toolchain = ""
  )
  $obj = [ordered]@{
    timestamp                    = $timestamp
    status                       = $Status
    exit_code                    = $ExitCode
    counted_as_pass              = ($Status -eq "PASS")
    ndk_root                     = $NdkRoot
    ndk_version                  = $NdkVersion
    ndk_source_properties_sha256 = $SourceHash
    toolchain                    = $Toolchain
    api_level                    = $ApiLevel
    abi                          = $Abi
    detail                       = $Detail
  }
  $obj | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8
  Write-Output ("[oracle] " + $Status + " exit=" + $ExitCode)
  Write-Output ("[oracle] report: " + $reportPath)
  Write-Output ("[oracle] " + $Detail)
  exit $ExitCode
}

# ---- 0. 解析 NDK 根（缺失 → SKIPPED，T-W6-1） ----
if ([string]::IsNullOrWhiteSpace($NdkRoot) -or -not (Test-Path -LiteralPath $NdkRoot -PathType Container)) {
  Write-OracleReport -Status "SKIPPED" -ExitCode 78 -Detail "no NDK root provided or path does not exist; oracle skipped (never counted as pass)"
}

$sourceProps = Join-Path $NdkRoot "source.properties"
if (-not (Test-Path -LiteralPath $sourceProps -PathType Leaf)) {
  Write-OracleReport -Status "SKIPPED" -ExitCode 78 -Detail "NDK source.properties not found; oracle skipped"
}

$sourceHash = (Get-FileHash -LiteralPath $sourceProps -Algorithm SHA256).Hash.ToLower()

# ---- 1. 哈希登记校验（T-W6-2：不符即拒绝执行） ----
if (-not [string]::IsNullOrWhiteSpace($HashFile)) {
  if (-not (Test-Path -LiteralPath $HashFile -PathType Leaf)) {
    Write-OracleReport -Status "FAIL" -ExitCode 1 -SourceHash $sourceHash -Detail ("hash file not found: " + $HashFile)
  }
  $expectedLine = Get-Content -LiteralPath $HashFile |
    Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") } |
    Select-Object -First 1
  if ($null -ne $expectedLine) {
    $expected = ($expectedLine.Trim() -split "\s+")[0].ToLower()
    if ($expected -ne $sourceHash) {
      Write-OracleReport -Status "FAIL" -ExitCode 1 -SourceHash $sourceHash -Detail ("SHA-256 mismatch: expected " + $expected + " but got " + $sourceHash + "; refuse to execute (T-W6-2)")
    }
  }
}

# ---- 2. 解析 NDK 版本 ----
$ndkVersion = ""
$spContent = Get-Content -LiteralPath $sourceProps -Raw
$m = [regex]::Match($spContent, "Pkg\.Revision\s*=\s*([0-9][0-9.]*)")
if ($m.Success) { $ndkVersion = $m.Groups[1].Value }

$toolchain = ""
try {
  $toolchain = (& moon version 2>&1 | Out-String).Trim()
} catch {
  $toolchain = "moon version unavailable"
}

# ---- 3. 构造临时最小项目（确定性自产源码 + gen 产物） ----
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("moonabi-oracle-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$tempKept = $false

try {
  $moonMod = Join-Path $tmp "moon.mod"
  @(
    'name = "moonabitest/oracle_probe"',
    'version = "0.1.0"'
  ) | Set-Content -LiteralPath $moonMod -Encoding ASCII

  $mainFile = Join-Path $tmp "main.mbt"
  @(
    '///|',
    'fn main {',
    '  println("oracle-ok")',
    '}'
  ) | Set-Content -LiteralPath $mainFile -Encoding ASCII

  $moonPkg = Join-Path $tmp "moon.pkg"
  # 先声明可执行包类型，再由 CLI `gen --out` 追加受管块（追加语义与真实 moon.pkg 一致）。
  'pkgtype(kind: "executable")' | Set-Content -LiteralPath $moonPkg -Encoding ASCII
  $ndkArg = if ([string]::IsNullOrWhiteSpace($ndkVersion)) { "r27" } else { $ndkVersion }
  $genArgs = @(
    "run", "cmd/main", "--target", "native", "--",
    "gen", "--abi", $Abi, "--api", $ApiLevel,
    "--ndk-root", $NdkRoot, "--ndk-version", $ndkArg,
    "--out", $moonPkg
  )
  Push-Location $repoRoot
  try {
    $genOut = & moon @genArgs 2>&1
    $genCode = $LASTEXITCODE
  } finally {
    Pop-Location
  }
  if ($genCode -ne 0 -or -not (Test-Path -LiteralPath $moonPkg -PathType Leaf)) {
    Write-OracleReport -Status "FAIL" -ExitCode 1 -NdkVersion $ndkVersion -SourceHash $sourceHash -Toolchain $toolchain -Detail ("gen failed (exit " + $genCode + "): " + (($genOut | Out-String).Trim()))
  }

  # ---- 4. 真实构建差分：moon build --target native ----
  Push-Location $tmp
  try {
    $buildOut = & moon build --target native 2>&1
    $buildCode = $LASTEXITCODE
  } finally {
    Pop-Location
  }

  $status = if ($buildCode -eq 0) { "PASS" } else { "FAIL" }
  $tail = (($buildOut | Out-String).Trim())
  if ($tail.Length -gt 2000) { $tail = $tail.Substring($tail.Length - 2000) }
  Write-OracleReport -Status $status -ExitCode $(if ($buildCode -eq 0) { 0 } else { 1 }) -NdkVersion $ndkVersion -SourceHash $sourceHash -Toolchain $toolchain -Detail ("moon build --target native exit " + $buildCode + ": " + $tail)
} finally {
  if (-not $KeepTemp -and (Test-Path -LiteralPath $tmp)) {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    $tempKept = $true
  }
  if ($KeepTemp) {
    Write-Output ("[oracle] temp kept: " + $tmp)
  }
}