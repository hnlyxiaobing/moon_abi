# oracle-reports（W6-A 产物目录）

本目录存放 `tools/oracle-run.ps1` 生成的**结构化差分报告**（`oracle-*.json`）。

- 报告产物被本目录 `.gitignore` 排除，不入库。
- 报告字段：`timestamp` / `status`（`PASS`|`FAIL`|`SKIPPED`）/ `exit_code` /
  `counted_as_pass` / `ndk_root` / `ndk_version` / `ndk_source_properties_sha256` /
  `toolchain` / `api_level` / `abi` / `detail`。
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
```

`-HashFile` 首个非空且非 `#` 行 = `<NdkRoot>/source.properties` 的 SHA-256。
