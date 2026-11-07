# moon_abi · 设计契约（DESIGN.md）

> Round-1 / 2026-11-06 ｜ 状态：架构与声明可评审，无生成逻辑、无 I/O

## 1. 分层位置与职责

L4 工程交付层的**纯 MoonBit 配置生成叶子库**。职责：把「ABI + API level + NDK Profile」映射为 `link.native` 配置值，并渲染成确定性文本。它是所有 Android FFI 项目的**公共配置前置**，但按 ADR-0005 已从「FFI 硬前置」降级为「上板软依赖」——桌面用预编译 `.so` 即可验证 `tflite_ffi` / `camera2`，不需要 NDK。

## 2. 模块边界 / 依赖方向 / 数据流

```
NdkProfile + Abi（调用方注入）
   └─► moon_abi::generate ──► LinkNativeConfig（纯值）
                                 ├─► render ──► options(link.native…) 文本片段
                                 └─► 组合根写入未来 App 的 moon.pkg
                                                  │
                                                  ▼
                                    moon_android::plan_build ──► BuildPlan
```

`moon_abi` → `moon_android` 是**数据契约（配置片段文本），不是 import**（K5 消解）。`moon_abi` **不读打包产物**，否则会与 `moon_android` 形成环。本库零 import、零 FFI、零外部句柄。

## 3. 核心数据结构

| 类型 | 作用 |
|---|---|
| `Abi` | `ArmeabiV7a` / `Arm64V8a` / `X86` / `X86_64` |
| `TargetTriple` | `Armv7aLinuxAndroideabi` / `Aarch64LinuxAndroid` / `I686LinuxAndroid` / `X86_64LinuxAndroid`（不含 API level 后缀） |
| `ApiLevel { level : Int }` | 包装类型，防止裸 `Int` 在 minSdk / targetSdk / clang 后缀之间混用 |
| `NdkProfile` | `ndk_root` / `ndk_version` / `api_level` / `extra_link_libs` / `extra_cc_flags` / `windows_path_style` |
| `LinkNativeConfig` | 生成结果：`cc` / `cc_flags` / `cc_link_flags` / `stub_cc?` / `supported_targets` / `triple` / `abi` / `api_level` |
| `ValidationReport { ok, warnings, errors }` | CI 门禁用；`warnings` 不阻断、`errors` 阻断 |
| `MoonAbiError` | `pub suberror`，7 个可判定错误构造 |
| `ConfigRenderer` trait | `fn render(Self) -> String raise MoonAbiError`；契约要求**确定性、可复现** |

> 设计取舍：`LinkNativeConfig` 是**纯数据**而非直接返回字符串，让 `validate` 与 `render` 可分别单测，也让组合根能在写文件前检查字段。`stub_cc` 用 `String?` 是因为 `native-stub` 的编译器可能与主 cc 不同或不存在。

## 4. 错误模型

`MoonAbiError`：`UnsupportedAbi(String)`、`UnsupportedApiLevel(Int, Int)`、`MissingNdkRoot`、`MissingClang(String)`、`PathContainsSpace(String)`、`InvalidTriple(String)`、`VersionMismatch(String, String)`。

失败型 API 统一 `-> T raise MoonAbiError`；`validate` 则把「需人工确认但不阻断」的问题放进 `ValidationReport.warnings`，避免把警告误报成异常。错误只在本模块内，组合根负责映射为 CI 失败信息。

## 5. 资源生命周期

**全部纯值**：无句柄、无 fd、无文件、无进程、无缓存。`generate` / `render` / `clang_name` 返回新值，不修改输入 `NdkProfile`；无需释放函数，无 close 语义。这是本库能在 wasm 目标与桌面 CI 上直接单测的根本原因。

## 6. 线程 / 并发边界

纯函数、无可变全局状态、无环境读取、无静态查表缓存；可并发调用。实现轮若引入 NDK 版本表，必须为**不可变常量**，不得 `lazy` 初始化可变全局。

## 7. 平台约束与外部依赖

- `preferred_target = "wasm"`（未改动），全后端；输出面向 NDK r22+。
- 外部依赖：**无**（本轮）。`moonrockz/zig-cross@0.3.2` 只作设计参照，不引入（ADR-0010）。
- `[事实]` `moon build --target` 无 android；native 后端不能导出可链接 `.so/.dll`；`#export_name` 仅限 `foreign_library` 包。
- `[事实-证伪]` NDK r23 移除的是 GNU binutils / GDB 支持，**不是** GNU make / standalone toolchain；实现轮不得据此设计回退路径。
- `[待验证假设]` E3：Android 上「MoonBit → C 源码/对象 → NDK clang + CMake」能否产出可加载产物，本工作区无 `mvp/` 资产，未复现。

## 8. 输入输出类型与错误传播（纯 MoonBit 库）

| 输入 | 输出 | 错误传播 |
|---|---|---|
| `NdkProfile + Abi` | `LinkNativeConfig`（纯值，无 I/O） | `UnsupportedAbi` / `UnsupportedApiLevel` / `MissingNdkRoot` / `VersionMismatch` |
| `LinkNativeConfig` | `String`（`options(...)` 片段，确定性） | `InvalidTriple` / `MissingClang` / `PathContainsSpace` |
| `NdkProfile + Abi` | `ValidationReport` | `MoonAbiError`；报告内 `warnings` 不阻断 |
| `Abi + ApiLevel` | `String`（clang 可执行文件名） | `UnsupportedAbi` / `UnsupportedApiLevel` |

`declare` 只用于 4 个函数签名；具体 `enum` / `struct` / `trait` / `suberror` 用真实类型定义（ADR-0001）。**无 `#external`、无 `extern "C"`、无 `#borrow/#owned`、无回调**。

## 9. 可替换性与实现细节不泄漏

上层只看到 `LinkNativeConfig` / `ValidationReport` / 文本片段；看不到 NDK 目录布局、clang 命名规则推导、Windows 引号策略、SDK 版本探测。换 NDK 版本、换交叉编译器（如 zig-cross）只改 `NdkProfile` 与渲染实现，不改 `generate` / `render` 签名。`moon_android::BuildPlan` 只消费文本，不引用本库类型（K5）。

## 10. 测试策略

| 层次 | 内容 |
|---|---|
| 快照 | 4 种 ABI × 多组 API level 的 `render` golden；`generate` 字段逐项断言 |
| 确定性 | 同一输入连跑两次逐字相等；禁止时间戳 / 绝对路径随机化 |
| 负例 | `MissingNdkRoot` / `UnsupportedAbi` / `UnsupportedApiLevel` / `PathContainsSpace` / `MissingClang` / `VersionMismatch` |
| CI | `validate` 的 `errors` 非空即失败；`warnings` 仅记录；版本锁一致（`ToolchainVersions` 由 `moon_android` 持有） |
| 门禁 | `moon fmt --check` / `moon check` / `moon test --enable-coverage` / `moon info` 快照 |

## 11. 验收标准（实现轮）

1. 生成片段可直接粘贴进 `moon.pkg` 并被 `moon check` 接受；2. 快照测试全绿且输出确定性可证；3. 所有非法配置返回 `MoonAbiError`；4. R4 `--deny-warn` 转绿。

## 12. 未解决问题 / 待验证假设

E3（P0）Android native 产物链路能否产出可加载 `.so` · Q1（未解决）`mvp/android/build.ps1` 与本工作区资产缺失 · NDK r23+ 前缀 clang 命名规则需按当前文档锁定 · `-llog -landroid` 注入策略、Windows 路径引号策略属 `TODO(实现轮)` · zig-cross 是否值得在 R4 复议未定。

## 13. 当前状态与 TODO

`moon_abi.mbt` 已写入全部值类型、`ConfigRenderer` trait、`MoonAbiError` 与 4 个 `declare` 函数，公开 API 有 `///` 文档注释与 `TODO(实现轮)`。**未实现任何配置生成 / 渲染 / 校验逻辑，未写文件、未执行命令**。

## References

`../docs/architecture.md` §2 / §5.4 / §6 L4 / §7 · `../docs/dependency-graph.md` K5 / O3 · `../docs/adr/ADR-0001`、`ADR-0002`、`ADR-0005`、`ADR-0010` · `../docs/capability-matrix.md` 序 17 · `../docs/open-questions.md` E3 / Q1
