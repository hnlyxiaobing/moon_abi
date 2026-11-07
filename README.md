# hnlyxiaobing/moon_abi

**Android 交叉编译 `link.native` 配置生成器 —— 按 ABI 与 API level 产出确定性配置值与文本片段。**

> 状态：**实现完成，API 冻结前对账（R2 准备轮）**。8 个值类型、`ConfigRenderer` trait、`MoonAbiError` 与 4 个 API（`generate` / `render` / `validate` / `clang_name`）全部为真实实现，四道门禁 `moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check` 全绿（30 tests，`pkg.generated.mbti` 与源码逐字对账一致；冻结后签名变更即破坏性变更）。**纯值、无 I/O、无外部命令执行**。
> `preferred_target = "wasm"`（骨架原值，未改动）；全后端、桌面可测。
> **与原 README 定位差异**：骨架描述的是 CLI `moon-abi gen --abi armv7 --api 21`（约 300 行脚本），本轮契约改为**纯 MoonBit 库 API** `generate` / `render` / `validate` / `clang_name`。理由与影响见下文「定位修正」。

## 定位修正（重要）

| 项 | 骨架 README | 本轮契约 | 原因 |
|---|---|---|---|
| 接口形态 | `moon-abi gen …` CLI，输出配置片段 | `generate(profile, abi) -> LinkNativeConfig` 等 4 个纯函数 | ADR-0002 规定 11 模块零 import、各自独立 `moon check`；CLI 与进程/文件 I/O 属于组合根或未来 App 工程，本轮不引入 |
| 副作用 | 脚本可写文件 / 探测本机 | **纯值、确定性、可并发、无 I/O** | 用户要求「不实现业务逻辑、不破坏骨架」，且纯值可用快照测试做 CI 门禁 |
| 处理 NDK 路径 | 直接探测本机 clang | `NdkProfile` 由调用方注入，`PathContainsSpace` 只做校验 | 不探测本机环境，避免把主机差异带入单元测试 |

CLI 包装**没有被删除**，只是后移：由组合根把 `render` 的文本写入 `moon.pkg` 或打印到 stdout（`architecture.md` §2 交付流）。

## 定位与为什么存在

路线图「拼图四」复核（2026-11-06）：MoonBit 没有 Android 编译目标，`moon build --target` 只有 wasm / wasm-gc / js / native / llvm / all；新 native 后端平台覆盖仅 macOS ARM、Linux x86-64、Windows MSVC；`#export_name` 仅限 `foreign_library` 包；且 native 后端**不能把 `foreign_library` 导出为可链接 `.so/.dll`**。因此 Android 集成必须走「MoonBit → C 源码/对象 → NDK clang + CMake 宿主工程」，任何 FFI 项目都得手写 `link.native` 的 `cc` / `cc-flags` / `cc-link-flags`。本库把这一步标准化。

**选「纯 MoonBit 自研」而非复用**（`capability-matrix.md` 序 17）：`moonrockz/zig-cross@0.3.2`（Apache-2.0）是「用 zig 编译 native」的另一条路径，引入会带来 zig 工具链依赖，属无依据大型依赖，本轮**仅作参照、不引入**（ADR-0010）。

**报告事实修正**：`[事实-证伪]` 不得引用「NDK r23 移除 GNU make / standalone toolchain」；r23 移除的是 GNU binutils / GDB 支持。clang 命名规则已按当前 NDK 文档实现为统一工具链 wrapper（`<triple><api>-clang`）。

## 能力范围 / 非目标

- **做**：按 `Abi` + `ApiLevel` 生成 `LinkNativeConfig`（cc、cc_flags、cc_link_flags、stub_cc、supported_targets、triple），渲染为 `moon.pkg` 的 `options(link.native…)` 文本，校验配置完整性，给出 NDK clang 可执行文件名。
- **不做**：不调用 NDK / clang、不修改 `moon.pkg`、不写文件、不探测本机环境、不执行打包、不链接任何 C 库、不实现 CLI。
- 与 `moon_android` 之间是**数据契约（配置片段文本），不是 import**（K5 循环风险消解，`architecture.md` §2）。

## 公开接口（速览）

`generate(profile, abi)` · `render(config)` · `validate(profile, abi)` · `clang_name(abi, api)`。完整签名与错误构造见 `API.md`。

## 依赖

- **本轮零依赖**：无 `moon add`、未改 `moon.pkg`、无 FFI、无外部句柄。
- 后续轮仍**不需要**任何 MoonBit 包；只消费调用方传入的 `NdkProfile`（含 `ndk_root`、`ndk_version`、`api_level`、`extra_link_libs`、`extra_cc_flags`、`windows_path_style`）。

## 平台与许可风险

| 风险 | 说明 |
|---|---|
| NDK 版本差异 | clang 前缀命名随 NDK 版本变化；`VersionMismatch` / `InvalidTriple` 已生效；已按最低 NDK 主版本常量（`MIN_NDK_MAJOR`，面向 r22+）校验，ADR-0010 版本锁由 `moon_android::ToolchainVersions` 持有 |
| Windows 路径 | NDK / JDK 路径含空格会导致 cc 命令断裂；`windows_path_style` + `PathContainsSpace` 提前拒绝、不自动加引号（**已实现**） |
| 分发许可 | NDK 二进制不可再分发（Android SDK License 3.4）；**本库只分发配置文本**，不含任何 SDK 构件 |
| API level | `UnsupportedApiLevel(got, min)` 显式化；不猜测默认 minSdk |
| 平台 | 库自身全后端（`wasm`）；产出的配置只面向 Linux / Android 交叉编译 |

## 测试与验收

- **快照测试（桌面 CI 可跑）**：4 种 ABI × 多组 API level 的 `render` 输出与 golden 逐字比对；同一输入连跑两次结果必须一致（确定性）。
- **负例**：缺 `ndk_root` → `MissingNdkRoot`；未知 ABI → `UnsupportedAbi`；路径含空格 → `PathContainsSpace`；clang 缺失 → `MissingClang`；`validate` 的 `warnings` 不阻断、`errors` 阻断。
- **验收标准**：生成片段可直接粘贴进 `moon.pkg` 并被 `moon check` 接受；快照全绿；`moon check --deny-warn` 转绿（✅ R2 准备轮实跑，0 error / 0 warn）。
- **门禁实跑（R2 准备轮，2026-11-07）**：`moon clean` → `moon check --deny-warn` → `moon build` → `moon test`（**30 tests** 全过）→ `moon fmt --check`，全部 exit 0；无链接期阻塞（无 FFI）。

## 当前状态 / 本轮产物

| 项 | 状态 |
|---|---|
| `moon_abi.mbt`：值类型 ×8、`ConfigRenderer` trait、`MoonAbiError`（7 构造）、API ×4 | ✅ |
| `pkg.generated.mbti` API 快照（与源码公开签名对账一致） | ✅ |
| cc / flags 生成、clang 命名、路径空格拒绝策略、golden 快照 | ✅ 已实现 |
| 四道门禁：`moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check` | ✅ 全绿（30 tests） |

## 文档索引

`DESIGN.md` · `API.md` · `../docs/architecture.md` §2 / §6 L4 / §7 · `../docs/adr/ADR-0002`、`ADR-0005`（NDK 硬依赖降级为软）、`ADR-0010`（零新增依赖） · `../docs/capability-matrix.md` 序 17 · `../docs/open-questions.md` E3 / Q1
