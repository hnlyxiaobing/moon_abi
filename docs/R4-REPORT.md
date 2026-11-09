# R4 交付与验证报告（moon_abi）

> 日期：2026-11-09 ｜ 本仓库锁定的工具链：`moon 0.1.20261104` / `moonc v0.10.20+65efd5b93` / `moonrun 0.1.20261104` / `moonbitlang/core 0.10.20+65efd5b93`
> 范围：R4 的 P1 项（CLI `gen` / 本机 NDK 探测 / zig-cross 复议）与错误路径加固；**E3 未做**，见 §6。
> 证据等级：`[已复验]` = 本机命令/文件实测；`[仍需实测]` = 尚无证据。

## 1. 交付摘要

| 项 | 状态 | 证据 |
|---|---|---|
| CLI `moon-abi gen --abi/--api`（只读打印 + `--out` 写文件两种模式） | ✅ | `[已复验]` §2、§3 |
| `../moon.pkg` 受管块幂等追加/替换（块外内容不改写） | ✅ | `[已复验]` 单测 + 真实临时目录测试 |
| 参数/路径错误退出码契约（0 / 2 / 1） | ✅ | `[已复验]` §3 |
| 本机 NDK 探测（`ANDROID_NDK_HOME` / `ANDROID_HOME/ndk` / `ANDROID_SDK_ROOT/ndk` / 常见路径；版本目录取最高；`source.properties` 版本） | ✅ | `[已复验]` 伪目录 + 真实临时目录 + CLI `probe` |
| 结构化输出（文本行 / 单行 JSON） | ✅ | `[已复验]` 单测 + CLI `probe --json` |
| 错误注入（权限拒绝 / 磁盘满 / 读失败 / 畸形标记）不 panic | ✅ | `[已复验]` 注入闭包单测 |
| `zig-cross` 引入复议书面结论 | ✅ 结论：**不引入** | `[已复验-网络]` registry/GitHub 查询（2026-11-09）+ `DECISIONS.md` 决策 1 R4 复议节 |
| E3（MoonBit→C→NDK clang 可加载 `.so`） | ❌ 未做 | `[仍需实测]` §6 |

## 2. 门禁实跑（2026-11-09，本机）

| # | 命令 | 退出码 | 结果 |
|---|---|---|---|
| 1 | `moon check --deny-warn` | 0 | 0 error / 0 warn |
| 2 | `moon build` | 0 | 产物 `_build/wasm/debug/build/cmd/main/main.wasm` |
| 3 | `moon test` | 0 | **Total tests: 68, passed: 68, failed: 0** |
| 4 | `moon fmt --check` | 0 | 无格式差异 |
| 5 | `moon info && git diff --exit-code -- ../pkg.generated.mbti ../cmd/main/pkg.generated.mbti` | 0 | 快照与源码一致 |

测试数基线：R1–R3 为 **30**；R4 新增 38（CLI 纯逻辑 16 + 探测纯逻辑 7 + 真实 fs 6 + 边界 9），**68/68**，只增不减。

## 3. CLI 冒烟（真实进程，临时目录）

在 `%TEMP%\moon_abi_cli_smoke_*`（测试后递归删除，无临时文件残留）：

| 场景 | 命令要点 | 退出码 | 输出摘要 |
|---|---|---|---|
| 只读打印 | `gen --abi armv7 --api 21 --ndk-root C:\android-ndk --ndk-version r27` | 0 | 受管块含 `cc` / `--target=` / `-llog -landroid` |
| 首次写文件 | 同上 + `--out <tmp>\../moon.pkg` | 0 | `<path>: appended` |
| 二次写（幂等） | 同上重复 | 0 | `<path>: unchanged`（文件逐字未变） |
| 手工改块后写 | 修改 `api_level=` 后重跑 | 0 | `<path>: replaced`，块外内容保留 |
| 非法 ABI | `--abi mips` | **2** | `error: unsupported ABI: mips` |
| API 越界 | `--api 20` | **2** | `error: API level 20 is below minimum 21` |
| 未知选项 | `--bogus` | **2** | `error: unknown option: --bogus` |
| 写入失败（父目录缺失） | `--out <tmp>\nope\../moon.pkg` | **1** | `error: I/O failure at ...: @fs.open() ... 系统找不到指定的路径` |
| 真实探测（伪 NDK） | `ANDROID_NDK_HOME=<tmp>\android-ndk-r27 probe` | 0 | `NDK\|found=true\|...\|version=27.0.12077973` |
| 真实探测 JSON | 同上 + `--json` | 0 | 单行 JSON，路径反斜杠正确转义 |

说明：伪 NDK 目录由测试脚本在临时目录内创建（`toolchains/llvm/prebuilt` + `source.properties`），**未使用真机/真 NDK**。

## 4. 错误路径覆盖（不 panic）

| 路径 | 机制 | 断言 |
|---|---|---|
| 非法 ABI 名（`mips` / 空 / 大小写别名） | `abi_from_name` → `UnsupportedAbi` | 退出码 2；消息含原输入 |
| 参数错误（缺值/重复/未知/非数字/越界/`--flag=` 空值） | `parse_gen_args` → `CliUsage` / `UnsupportedApiLevel` | 退出码 2 |
| 权限拒绝 | `write_config_with` 注入 `Err("permission denied")` | `IoFailure(path, reason)`，退出码 1 |
| 磁盘满 | 注入 `Err("No space left on device")` | `IoFailure`，消息含原因 |
| 读失败 | 注入 `ReadOutcome::Failed(...)` | `IoFailure`，不写盘 |
| 既有配置畸形（单边/重复标记） | `merge_link_config` → `MalformedConfig` | 退出码 1；不猜测修复 |
| 既有内容已一致 | `Unchanged` | **不调用 write**（注入「写即失败」验证） |
| 父目录缺失（真实 fs） | `@fs.write_text` 抛错 → `IoFailure` | 错误消息定位到路径 |
| 探测全未找到 | `NdkProbeResult{found:false}` + warnings | 不抛异常；CLI 退出码 1 |

## 5. 设计边界与红线自查

- **零跨模块 import**：未 import 任何 `hnlyxiaobing/*`；只依赖工具链随附 `moonbitlang/core/{async,async/fs,env,test}`。未新建模块目录。
- **无真实资产入库**：未下载/落盘/链接任何 `.so`、模型、NDK devkit；无 frida 相关内容。
- **测试只增**：30 → 68；未删除/静默重录既有 golden（原有测试文件除新增外未改语义）。
- **快照**：`moon info` 生成；R4 diff 为纯加法（103 行插入、0 删除）；随源码同一提交入库。
- **加法性变更已在本仓库 `docs/API.md` 登记**；快照随源码同一提交入库，未改动任何仓库外文件。
- **未 push**。

## 6. 未决项（如实登记）

| 项 | 状态 | 证据等级 |
|---|---|---|
| E3：MoonBit → C 源码/对象 → NDK clang + CMake 产出可加载 `.so` | **本轮不做**（P2）；仍未复现 | `[仍需实测]` |
| 生成片段实际粘贴进真实 `../moon.pkg` 并被 `moon check` 接受 / 上板加载 | 未做（需 NDK + 组合根工程） | `[仍需实测]` |
| 真实 NDK 本机探测（非伪目录） | 本机未安装 NDK；真实 fs 路径已用伪目录覆盖 | `[仍需实测]`（真实 NDK 情形） |
| GitHub Actions 上的五道门禁 | 未实跑；本机等价实跑全绿 | `[仍需实测]` |
| NDK 大版本升级后的 clang wrapper 命名 | 未复核（当前按文档锁定 `<triple><api>-clang`） | `[仍需实测]` |
| `zig-cross` 引入 | 已书面结论：不引入（0 外部依赖）；重评条件见 `DECISIONS.md` 决策 1 | 结论 `[已复验-网络]`（2026-11-09 registry/GitHub 查询）；其依赖/工具链的真实集成成本未实测 |
