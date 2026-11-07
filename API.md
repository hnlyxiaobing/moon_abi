# moon_abi · 公开 API（API.md）

> **API 冻结前对账（R2 准备轮，2026-11-07）**：本文已与 `pkg.generated.mbti` 快照及源码公开签名逐项对账一致；**冻结后签名变更即破坏性变更**。
> 4 个函数均为**真实实现**（`pub fn`，非 `declare` 占位，0 条 `0068`）。
> `preferred_target = "wasm"`（未改动）。错误传播统一 `raise MoonAbiError`。
> **纯 MoonBit 库**：无 `#external` 句柄、无 `extern "C"`、无 `#borrow/#owned`、无回调、无 I/O。

## 类型

| 类型 | 种类 | 说明 |
|---|---|---|
| `Abi` | `pub(all) enum` | `ArmeabiV7a` / `Arm64V8a` / `X86` / `X86_64` |
| `TargetTriple` | `pub(all) enum` | 4 种 NDK 目标三元组前缀（不含 API level 后缀） |
| `ApiLevel` | `pub(all) struct` | `{ level : Int32 }` 包装，防止裸 Int 混用（快照字段类型为 `Int32`） |
| `NdkProfile` | `pub(all) struct` | `ndk_root` / `ndk_version` / `api_level` / `extra_link_libs` / `extra_cc_flags` / `windows_path_style` |
| `LinkNativeConfig` | `pub(all) struct` | `cc` / `cc_flags` / `cc_link_flags` / `stub_cc : String?` / `supported_targets` / `triple` / `abi` / `api_level` |
| `ValidationReport` | `pub(all) struct` | `ok : Bool` / `warnings : Array[String]` / `errors : Array[String]` |
| `MoonAbiError` | `pub suberror` | 7 个错误构造 |
| `ConfigRenderer` | `pub trait` | `fn render(Self) -> String raise MoonAbiError`（确定性、可复现） |

## 函数签名

| 签名 | 参数与所有权 | 返回 / 错误 | 资源与线程约束 | 实现要点 / 备注 |
|---|---|---|---|---|
| `generate(profile : NdkProfile, abi : Abi) -> LinkNativeConfig raise MoonAbiError` | `profile` 只读注入，不探测本机 | 纯值配置 / `UnsupportedAbi`、`UnsupportedApiLevel`、`MissingNdkRoot`、`VersionMismatch` | **纯函数、无 I/O、可并发**；不含句柄 | **已实现**：NDK 统一工具链命名 `<triple><api>-clang`；注入 `--target=<triple><api>`、`-llog -landroid`（`extra_link_libs` 自动补 `-l`）；校验顺序 `MissingNdkRoot` → `UnsupportedApiLevel` → `VersionMismatch` |
| `render(config : LinkNativeConfig) -> String raise MoonAbiError` | `config` 只读 | `options(link.native…)` 文本片段 / `InvalidTriple`、`MissingClang`、`PathContainsSpace` | 确定性输出，同输入两次逐字相等 | **已实现**：Windows 路径空格提前拒绝、不自动加引号；`stub_cc : None` 时省略 `stub-cc` 行 |
| `validate(profile : NdkProfile, abi : Abi) -> ValidationReport raise MoonAbiError` | `profile` 只读 | 校验报告 / `UnsupportedAbi`（无法建模为报告的映射失败）；`warnings` 不阻断、`errors` 阻断 | 纯函数、可并发 | **已实现**：缺 NDK 路径、API level 越界、版本不匹配、含空格 token 进 `errors`；空条目 / 重复链接库 / 路径风格不一致进 `warnings` |
| `clang_name(abi : Abi, api : ApiLevel) -> String raise MoonAbiError` | 纯值 | clang 可执行文件名（含 API level 后缀）/ `UnsupportedAbi`、`UnsupportedApiLevel` | 纯函数 | **已实现**：以当前 NDK 文档为准，不得引用「r23 移除 GNU make」这一已证伪说法 |

## 错误构造速查

`UnsupportedAbi(name)` · `UnsupportedApiLevel(got, min)` · `MissingNdkRoot` · `MissingClang(path)` · `PathContainsSpace(path)` · `InvalidTriple(triple)` · `VersionMismatch(expected, actual)`

## 与骨架 README 的接口差异

骨架写的是 CLI `moon-abi gen --abi armv7 --api 21`。本轮**不实现 CLI**：命令行解析、stdout 输出、写 `moon.pkg` 属组合根 / 未来 App 工程，理由见 `README.md`「定位修正」与 ADR-0002。库 API 保持纯值，便于快照测试与零 import 独立 `moon check`。

## Wire / 跨模块提示

`moon_abi` 输出的是**文本片段**，不向 `moon_android` 传递 `LinkNativeConfig` 类型（两模块名义类型隔离、零 import，ADR-0002 / K5）。`Abi` 在 `moon_abi` 与 `moon_android` 中**各自定义、结构同构**，由组合根转换。

## 非目标

执行 NDK / clang / 任何外部命令 · 写文件或修改 `moon.pkg` · 探测本机环境 · CLI 与参数解析 · APK 打包与签名 · 版本下载与 SDK 分发。

## 状态

**API 冻结前对账（R2 准备轮）**：API.md ↔ `pkg.generated.mbti` ↔ 源码公开签名三方一致；**冻结后签名变更即破坏性变更**。
四道门禁实跑全绿（2026-11-07）：`moon check --deny-warn`（0 error / 0 warn）· `moon build` · `moon test`（**30 tests** 全过）· `moon fmt --check`。
API 快照：`pkg.generated.mbti`（只读，未改动）。实现：✅ 已完成（纯值库，无 I/O、无 FFI、无链接期阻塞）。
