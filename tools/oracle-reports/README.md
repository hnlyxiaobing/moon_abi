# oracle-reports（W6-A 产物目录）

本目录存放 `tools/oracle-run.ps1` 生成的**结构化差分报告**（`oracle-*.json`）。

- 报告产物被本目录 `.gitignore` 排除，不入库。
- 报告字段：`timestamp` / `status`（`PASS`|`FAIL`|`SKIPPED`）/ `exit_code` /
  `counted_as_pass` / `ndk_root` / `ndk_version` / `ndk_source_properties_sha256` /
  `toolchain` / `host_os` / `cross_cc` / `cross_ar` / `api_level` / `abi` / `detail`。
- 口径：`SKIPPED`（退出码 78，NDK 缺失）与 `FAIL` 的 `counted_as_pass` 恒为 `false`，
  **永不进入通过计数**（T-W6-3）。
- 本 README 是报告模板说明，保留入库。

## 用法

```powershell
# 无 NDK：显式 SKIPPED（退出码 78）
pwsh tools/oracle-run.ps1

# 有 NDK：真实构建差分（退出码 0 通过 / 1 失败）
pwsh tools/oracle-run.ps1 -NdkRoot C:\android-ndk\27.0.12077973

# 可选：先用 source.properties 的 SHA-256 锁版本（不符拒绝执行，T-W6-2）
pwsh tools/oracle-run.ps1 -NdkRoot /opt/android-ndk -HashFile tools/oracle-reports/ndk-hash.txt

# 非 Android 宿主：交叉编译只在临时项目构建阶段注入（MoonBit 要求全局 MOON_CC/MOON_AR）
pwsh tools/oracle-run.ps1 -NdkRoot ~/android-ndk/android-ndk-r27c -ApiLevel 28 `
  -CrossCc ~/android-ndk/android-ndk-r27c/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android28-clang `
  -CrossAr ~/android-ndk/android-ndk-r27c/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar
```

`-HashFile` 首个非空且非 `#` 行 = `<NdkRoot>/source.properties` 的 SHA-256。

## 已登记的真实 PASS（2026-11-26）

- 环境：WSL Ubuntu 24.04.4 LTS；NDK r27c `27.2.12479018`；moon `0.1.20261126`；API 28 / arm64。
- 命令：`-CrossCc .../aarch64-linux-android28-clang -CrossAr .../llvm-ar`。
- 结果：`status=PASS`、`exit_code=0`、`counted_as_pass=true`；报告 `oracle-20261126-210303.json`（gitignore 排除）。
- `source.properties` SHA-256：`70f1c5165e6d997b18782a49cff71da7a3caacd0c4cd811da24c43359fb83cf6`。
- 限制：package-level `link.native.cc` 不能改变共享 runtime 目标，故必须注入 `MOON_CC`/`MOON_AR`；API 21 会在 runtime `getentropy` 处失败；Windows 宿主受 core `platform` cfg 固定为 Windows 影响，当前工具链无法完成 Windows→Android 差分。
