# hnlyxiaobing/moon_abi

**Android 交叉编译 `link.native` 配置生成器 —— 按 ABI 与 API level 产出确定性配置值与文本片段。**

> 状态：**R1–R3 纯值库 + R4 CLI/NDK 探测已交付**。核心 API（`generate` / `render` / `validate` / `clang_name`）保持纯值、确定性；R4 新增 `moon-abi gen` / `moon-abi probe`（只读打印 / 幂等写 `moon.pkg` / 结构化 NDK 探测）。五道门禁 `moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check` / 快照门禁全绿（**68 tests**；`pkg.generated.mbti` 与源码一致，R4 为纯加法 diff）。
> `preferred_target = "wasm"`（骨架原值，未改动）；全后端、桌面可测。
> **与骨架 README 的关系**：骨架描述的 CLI `moon-abi gen --abi armv7 --api 21` 在 R4 已落地；R1–R3 期间先以纯库 API 交付，理由与演进见「定位修正」。

## 定位修正（重要）

| 项 | 骨架 README | 当前契约 | 原因 |
|---|---|---|---|
| 接口形态 | `moon-abi gen …` CLI，输出配置片段 | 核心为 `generate` / `render` / `validate` / `clang_name` 纯函数；R4 另交付 `cmd/main` CLI（`gen` / `probe`） | 零跨模块 import、各自独立 `moon check` 的红线不变；CLI 的 I/O 被隔离到明确入口，核心仍可无文件系统单测 |
| 副作用 | 脚本可写文件 / 探测本机 | 核心**纯值、确定性、可并发、无 I/O**；写文件与探测仅在 `sync_config_file` / `probe_ndk` / `cmd/main` | 纯核心可用快照测试做 CI 门禁；I/O 用注入闭包 + 临时目录测试 |
| 处理 NDK 路径 | 直接探测本机 clang | `NdkProfile` 由调用方注入；R4 的 `probe_ndk` 只读 stat/read 探测 NDK 根，`PathContainsSpace` 只做校验 | 不执行 clang；探测不引入外部命令与主机差异 |

R4 的 CLI 覆盖三种行为：无 `--out` 时只读打印受管块；`--out` 时幂等追加/替换 `moon.pkg` 的受管块；参数/路径错误按 **2（用法）/ 1（运行、环境、IO）** 退出码契约返回（详见 `API.md` 与 `DECISIONS.md` 决策 2 的 R4 更新）。

## 定位与为什么存在

平台能力复核（2026-11-06）：MoonBit 没有 Android 编译目标，`moon build --target` 只有 wasm / wasm-gc / js / native / llvm / all；新 native 后端平台覆盖仅 macOS ARM、Linux x86-64、Windows MSVC；`#export_name` 仅限 `foreign_library` 包；且 native 后端**不能把 `foreign_library` 导出为可链接 `.so/.dll`**。因此 Android 集成必须走「MoonBit → C 源码/对象 → NDK clang + CMake 宿主工程」，任何 FFI 项目都得手写 `link.native` 的 `cc` / `cc-flags` / `cc-link-flags`。本库把这一步标准化。

**选「纯 MoonBit 自研」而非复用（R4 复核对账）**：`moonrockz/zig-cross`（0.3.2 / 0.4.1，Apache-2.0）是「用 zig 编译 native」的另一条路径，引入会带来 2 个直接依赖（`moonbitlang/async` + `moonbitlang/x`）与 zig 工具链依赖，且不能替代本库的 NDK clang 配置生成。2026-11-09 书面复议结论：**仍不引入，维持 0 外部依赖**（证据与成本/许可/维护分析见 `DECISIONS.md` 决策 1 的 R4 复议节）。

**事实修正**：`[事实-证伪]` 不得引用「NDK r23 移除 GNU make / standalone toolchain」；r23 移除的是 GNU binutils（除 GAS）与 GDB 支持。clang 命名规则已按当前 NDK 文档实现为统一工具链 wrapper（`<triple><api>-clang`）。

## 能力范围 / 非目标

- **做**：按 `Abi` + `ApiLevel` 生成 `LinkNativeConfig` 并渲染 `options(link.native…)` 文本；校验配置完整性；给出 NDK clang 可执行文件名。R4 另有：CLI 参数解析与退出码契约、受管块幂等写 `moon.pkg`、结构化 NDK 探测（文本 / JSON）。
- **不做**：执行 NDK / clang 或任何外部命令（探测仅 stat/read）、执行打包/签名、下载或分发 SDK/NDK 二进制、链接任何 C 库、验证设备可加载（E3 待实测）。
- 与 `moon_android` 之间是**数据契约（配置片段文本），不是 import**（消解与 `moon_android` 的潜在循环依赖，详见 `DECISIONS.md` 决策 3）。

## 公开接口（速览）

核心：`generate(profile, abi)` · `render(config)` · `validate(profile, abi)` · `clang_name(abi, api)`。
R4：`parse_gen_args` · `exit_code_for_error` · `managed_block` · `merge_link_config` · `write_config_with` · `sync_config_file` · `probe_ndk_with` · `probe_ndk` · `ndk_probe_text` · `ndk_probe_json` · `abi_from_name`。完整签名见 `API.md`。

## 依赖

- **外部依赖为零**：无 `moon add`、无 mooncakes 依赖、无 FFI、无外部句柄；`preferred_target = "wasm"` 未改。
- R4 的 I/O 只使用工具链随附的 `moonbitlang/core/async/fs` 与 `moonbitlang/core/env`（core 不是第三方依赖）。

## 平台与许可风险

| 风险 | 说明 |
|---|---|
| NDK 版本差异 | clang 前缀命名随 NDK 版本变化；`VersionMismatch` / `InvalidTriple` 已生效；按最低 NDK 主版本常量（`MIN_NDK_MAJOR`，面向 r22+）校验，精确版本锁由 `moon_android::ToolchainVersions` 持有（文本契约，详见 `DECISIONS.md` 决策 6） |
| Windows 路径 | NDK / JDK 路径含空格会导致 cc 命令断裂；`windows_path_style` + `PathContainsSpace` 提前拒绝、不自动加引号（**已实现**） |
| 分发许可 | NDK 二进制不可再分发（Android SDK License 3.4）；**本库只分发配置文本**，不含任何 SDK 构件；探测只读不复制 |
| API level | `UnsupportedApiLevel(got, min)` 显式化；不猜测默认 minSdk |
| 平台 | 库自身全后端（`wasm`）；产出的配置只面向 Linux / Android 交叉编译 |

## 测试与验收

- **快照/确定性**：4 种 ABI × 多组 API level 的 `render` golden；同一输入连跑两次逐字相等。
- **负例**：缺 `ndk_root` → `MissingNdkRoot`；未知 ABI → `UnsupportedAbi`；路径含空格 → `PathContainsSpace`；clang 缺失 → `MissingClang`；`validate` 的 `warnings` 不阻断、`errors` 阻断。
- **R4 新测试**：参数解析/退出码 2/1；受管块追加/替换/幂等；权限拒绝、磁盘满、读失败的错误注入；`@fs.tmpdir()` 临时目录内的真实写入与伪 NDK/SDK 探测（结束递归清理）；畸形标记 `MalformedConfig`。
- **门禁实跑（2026-11-09）**：`moon check --deny-warn` → `moon build` → `moon test`（**68 tests** 全过）→ `moon fmt --check` → `moon info && git diff --exit-code -- pkg.generated.mbti cmd/main/pkg.generated.mbti`，全部 exit 0。

## 当前状态 / 本轮产物

| 项 | 状态 |
|---|---|
| 核心：值类型、`ConfigRenderer` trait、`MoonAbiError`（11 构造）、4 个 API | ✅ |
| R4：CLI 纯逻辑 + 幂等合并 + 注入式 I/O + 真实写文件 | ✅ |
| R4：结构化 NDK 探测（`ANDROID_NDK_HOME` / `ANDROID_HOME/ndk` / `ANDROID_SDK_ROOT/ndk` / 常见路径） | ✅ |
| R4：`cmd/main` CLI（`gen` / `probe`，退出码 0/2/1） | ✅ |
| `pkg.generated.mbti` / `cmd/main/pkg.generated.mbti` 快照 | ✅ 一致（纯加法） |
| 五道门禁 | ✅ 全绿（68 tests） |

## 文档索引

`DESIGN.md`（设计契约）· `API.md`（公开 API）· `DECISIONS.md`（设计决策：自研选型与 zig-cross R4 复议 / CLI 定位演进 / 文本契约与名义类型隔离 / NDK 软依赖定位 / 声明与实现策略 / NDK 事实基线 / 风险与待验证）· `R4-REPORT.md`（R4 交付与验证证据：门禁/CLI 冒烟/错误路径/未决项）
