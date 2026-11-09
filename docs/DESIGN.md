# moon_abi · 设计契约（DESIGN.md）

> 起草 / 2026-11-06 ｜ **API 冻结前对账 / 2026-11-07** ｜ **R4 更新 / 2026-11-09**（CLI + NDK 探测落地；核心仍为纯值）｜ 状态：**已实现**。核心纯值 API 冻结后签名变更即破坏性变更；R4 新增均为加法性（快照已随源码提交）。

## 1. 分层位置与职责

工程交付层的**纯 MoonBit 配置生成叶子库**。职责：把「ABI + API level + NDK Profile」映射为 `link.native` 配置值，并渲染成确定性文本。它是所有 Android FFI 项目的**公共配置前置**，但已从「FFI 硬前置」降级为「上板软依赖」——桌面用预编译 `.so` 即可验证 `tflite_ffi` / `camera2`，不需要 NDK（决策依据见 `DECISIONS.md` 决策 4）。

## 2. 模块边界 / 依赖方向 / 数据流

```
NdkProfile + Abi（调用方注入）            NdkProbeInputs + 环境变量
   └─► moon_abi::generate ──► LinkNativeConfig       └─► probe_ndk / probe_ndk_with
                                  ├─► render ──► options(link.native…) 文本片段        └─► NdkProbeResult（结构化）
                                  ├─► managed_block ──► 带起止标记的受管块
                                  └─► sync_config_file / write_config_with ──► ../moon.pkg（幂等追加/替换）
                                                   │
                                                   ▼
                                    moon_android::plan_build ──► BuildPlan
```

`moon_abi` → `moon_android` 是**数据契约（配置片段文本），不是 import**（消解与 `moon_android` 的潜在循环依赖，见 `DECISIONS.md` 决策 3）。`moon_abi` **不读打包产物**，否则会与 `moon_android` 形成环。本库零跨模块 import、零 FFI、零外部句柄；R4 的 I/O 只依赖工具链随附的 `moonbitlang/core/async/fs` 与 `core/env`。

## 3. 核心数据结构

| 类型 | 作用 |
|---|---|
| `Abi` | `ArmeabiV7a` / `Arm64V8a` / `X86` / `X86_64` |
| `TargetTriple` | `Armv7aLinuxAndroideabi` / `Aarch64LinuxAndroid` / `I686LinuxAndroid` / `X86_64LinuxAndroid`（不含 API level 后缀） |
| `ApiLevel { level : Int32 }` | 包装类型，防止裸 `Int32` 在 minSdk / targetSdk / clang 后缀之间混用 |
| `NdkProfile` | `ndk_root` / `ndk_version` / `api_level` / `extra_link_libs` / `extra_cc_flags` / `windows_path_style` |
| `LinkNativeConfig` | 生成结果：`cc` / `cc_flags` / `cc_link_flags` / `stub_cc?` / `supported_targets` / `triple` / `abi` / `api_level` |
| `ValidationReport { ok, warnings, errors }` | CI 门禁用；`warnings` 不阻断、`errors` 阻断 |
| `MoonAbiError` | `pub suberror`，11 个可判定错误构造（原 7 个 + R4 的 `CliUsage` / `IoFailure` / `MalformedConfig` / `NdkNotFound`） |
| `ConfigRenderer` trait | `fn render(Self) -> String raise MoonAbiError`；契约要求**确定性、可复现** |
| `GenCommand` / `GenOutput` / `PathStyle` | R4 CLI 参数解析结果：ABI / API / NDK 覆盖 / 输出模式（stdout 或文件）/ 路径风格 |
| `MergeResult` / `MergeAction` / `ReadOutcome` | R4 幂等合并结果（追加/替换/已一致）与注入式读结果（存在/不存在/失败） |
| `NdkProbeInputs` / `NdkCandidate` / `NdkProbeResult` / `NdkSource` | R4 结构化 NDK 探测：输入（显式根 + 各环境变量路径）、候选事实、结果与来源分类 |

> 设计取舍：`LinkNativeConfig` 是**纯数据**而非直接返回字符串，让 `validate` 与 `render` 可分别单测，也让组合根能在写文件前检查字段。`stub_cc` 用 `String?` 是因为 `native-stub` 的编译器可能与主 cc 不同或不存在。

## 4. 错误模型

`MoonAbiError`：`UnsupportedAbi(String)`、`UnsupportedApiLevel(Int32, Int32)`、`MissingNdkRoot`、`MissingClang(String)`、`PathContainsSpace(String)`、`InvalidTriple(String)`、`VersionMismatch(String, String)`，R4 追加 `CliUsage(String)`、`IoFailure(path, reason)`、`MalformedConfig(String)`、`NdkNotFound(String)`（共 11 个构造；既有 7 个语义不变）。

失败型 API 统一 `-> T raise MoonAbiError`；`validate` 则把「需人工确认但不阻断」的问题放进 `ValidationReport.warnings`，避免把警告误报成异常。错误只在本模块内，组合根负责映射为 CI 失败信息。R4 CLI 把错误映射为退出码契约：**2 = 用法/参数错误**（`CliUsage` / `UnsupportedAbi` / `UnsupportedApiLevel`），**1 = 运行/环境/IO 错误**（`IoFailure` / `MalformedConfig` / `NdkNotFound` / `MissingNdkRoot` / `VersionMismatch` / `PathContainsSpace` / `InvalidTriple` / `MissingClang`）。

**畸形输入不 panic**：解析、合并、探测全部返回 `MoonAbiError` 或结构化报告；`write_config_with` / `probe_ndk_with` 以注入闭包覆盖权限拒绝、磁盘满、目录缺失等失败路径。

## 5. 资源生命周期

**核心全部纯值**：`generate` / `render` / `clang_name` / `validate` / `merge_link_config` / `probe_ndk_with` 无句柄、无 fd、无文件、无进程、无缓存，不修改输入，无需释放函数，无 close 语义。这是本库能在 wasm 目标与桌面 CI 上直接单测的根本原因。

R4 的 I/O 被限制在三个明确入口：`sync_config_file`（读/写 `../moon.pkg`）、`probe_ndk`（只读 stat/read 探测 NDK）、`cmd/main`（进程参数/环境变量/退出码）。它们不持有跨调用句柄；临时目录测试在 `@fs.tmpdir()` 内完成并递归清理。

## 6. 线程 / 并发边界

纯函数核心（`generate` / `render` / `validate` / `clang_name` / `merge_link_config` / `probe_ndk_with`）无可变全局状态、无环境读取、无静态查表缓存；可并发调用。NDK 版本表与 ABI → 三元组映射表均为**不可变常量**（`MIN_NDK_MAJOR` / `MIN_API_LEVEL` / `triple_of_name`），不使用 `lazy` 初始化可变全局。R4 的 `probe_ndk` / `cmd/main` 会读取环境变量与文件系统，但不写共享可变状态；`sync_config_file` 的写入目标由调用方显式给出。

## 7. 平台约束与外部依赖

- `preferred_target = "wasm"`（未改动），全后端；输出面向 NDK r22+。
- 外部依赖：**无**。`moonrockz/zig-cross`（0.3.2 / 0.4.1）**R4 复议结论仍为不引入**：其直接依赖 `moonbitlang/async` + `moonbitlang/x`、需要 zig 工具链、且走的是另一条编译路径，不能替代本库的 NDK clang 配置生成；详见 `DECISIONS.md` 决策 1 的 R4 复议节（2026-11-09 复核证据）。
- R4 I/O 依赖：`moonbitlang/core/async/fs` 与 `moonbitlang/core/env` 随工具链 core 下发，**不是 mooncakes 外部依赖**；`../moon.pkg` 用 `allow-experimental-packages` 显式承认 `async/fs` 的实验状态。
- `[事实]` `moon build --target` 无 android；native 后端不能导出可链接 `.so/.dll`；`#export_name` 仅限 `foreign_library` 包。
- `[事实-证伪]` NDK r23 移除的是 GNU binutils（除 GAS）与 GDB 支持，**不是** GNU make / standalone toolchain（standalone toolchain 脚本仍在，仅提示不再必要）；不得据此错误前提设计回退路径。
- `[待验证假设]` Android 上「MoonBit → C 源码/对象 → NDK clang + CMake」能否产出可加载 `.so`，尚未复现（开发环境无最小实验资产）；详见 `DECISIONS.md` 决策 7。

## 8. 输入输出类型与错误传播（纯 MoonBit 库）

| 输入 | 输出 | 错误传播 |
|---|---|---|
| `NdkProfile + Abi` | `LinkNativeConfig`（纯值，无 I/O） | `UnsupportedAbi` / `UnsupportedApiLevel` / `MissingNdkRoot` / `VersionMismatch` |
| `LinkNativeConfig` | `String`（`options(...)` 片段，确定性） | `InvalidTriple` / `MissingClang` / `PathContainsSpace` |
| `NdkProfile + Abi` | `ValidationReport` | `MoonAbiError`；报告内 `warnings` 不阻断 |
| `Abi + ApiLevel` | `String`（clang 可执行文件名） | `UnsupportedAbi` / `UnsupportedApiLevel` |
| `ArrayView[String]`（CLI 参数） | `GenCommand` | `CliUsage` / `UnsupportedAbi` / `UnsupportedApiLevel` |
| `LinkNativeConfig` | 受管块 `String` / `MergeResult` | `InvalidTriple` / `MissingClang` / `PathContainsSpace` / `MalformedConfig` |
| 既有文本 + 受管块 + 读/写闭包 | `MergeResult`（`Appended` / `Replaced` / `Unchanged`） | `IoFailure` / `MalformedConfig` |
| 既有文件路径 + 受管块（真实 fs） | `MergeResult` | `IoFailure` / `MalformedConfig` |
| `NdkProbeInputs` + 注入闭包 / 真实 fs | `NdkProbeResult`（结构化候选 + 告警） | 无异常（失败降级为 `found=false` + warnings） |
| `NdkProbeResult` | 结构化文本 / 单行 JSON | 无异常 |

原有 4 个函数与 R4 新增函数均为 `pub fn` **真实实现**（无 `declare` 占位、无 `0068` 告警）；具体 `enum` / `struct` / `trait` / `suberror` 用真实类型定义（`declare` 不支持具体类型定义的编译器限制与替代策略见 `DECISIONS.md` 决策 5）。**无 `#external`、无 `extern "C"`、无 `#borrow/#owned`、无回调**。

## 9. 可替换性与实现细节不泄漏

上层只看到 `LinkNativeConfig` / `ValidationReport` / 文本片段；看不到 NDK 目录布局、clang 命名规则推导、Windows 引号策略、SDK 版本探测。换 NDK 版本、换交叉编译器（如 zig-cross）只改 `NdkProfile` 与渲染实现，不改 `generate` / `render` 签名。`moon_android::BuildPlan` 只消费文本，不引用本库类型（名义类型隔离，见 `DECISIONS.md` 决策 3）。

## 10. 测试策略

| 层次 | 内容 |
|---|---|
| 快照 | 4 种 ABI × 多组 API level 的 `render` golden；`generate` 字段逐项断言 |
| 确定性 | 同一输入连跑两次逐字相等；禁止时间戳 / 绝对路径随机化 |
| 负例 | `MissingNdkRoot` / `UnsupportedAbi` / `UnsupportedApiLevel` / `PathContainsSpace` / `MissingClang` / `VersionMismatch` |
| R4 CLI 纯逻辑 | 参数解析合法/非法（含 `--flag=value`、重复项、缺值、越界 API）；退出码 2/1 映射；受管块追加/替换/幂等；畸形标记 `MalformedConfig` |
| R4 错误注入 | `write_config_with` 注入权限拒绝 / 磁盘满 / 读失败 → `IoFailure`；`probe_ndk_with` 注入伪目录覆盖命中/回退/取最高/不完整/全未找到 |
| R4 真实 fs | `@fs.tmpdir()` 临时目录内写 `../moon.pkg`（首次追加、二次 unchanged、手工改动后 replaced）；伪 NDK/SDK 目录真实探测；测试结束递归清理 |
| CI | `validate` 的 `errors` 非空即失败；`warnings` 仅记录；版本锁一致（`ToolchainVersions` 由 `moon_android` 持有） |
| 门禁 | 四道门禁 + 第 5 道快照门禁：`moon check --deny-warn` / `moon build` / `moon test`（**68 tests**）/ `moon fmt --check` / `moon info && git diff --exit-code -- ../pkg.generated.mbti ../cmd/main/pkg.generated.mbti` |

## 11. 验收标准（实现阶段；冻结前复核）

1. 生成片段为可直接粘贴进 `../moon.pkg` 的 `options(link.native…)` 文本（golden 快照覆盖；R4 CLI 的写文件模式进一步把「追加/替换/幂等」固化为可执行测试）；2. 快照测试全绿且输出确定性可证（✅，68 tests）；3. 所有非法配置/参数返回 `MoonAbiError`（✅ 负例与错误注入覆盖，畸形输入不 panic）；4. `moon check --deny-warn` 转绿（✅，0 error / 0 warn）；5. CLI 退出码契约 0/2/1 实测（✅ 本机 `moon run cmd/main` 实跑）。

## 12. 未解决问题 / 待验证假设

Android native 产物链路（「MoonBit → C 源码/对象 → NDK clang + CMake」）能否产出可加载 `.so` **仍未复现**，属高优先级待验证项（`[仍需实测]`；R4 未做 E3 复现） · 开发期引用的一次性打包脚本与真实 APK 样本资产未随本仓库分发，集成验证需自备样本 · NDK clang 命名已按当前文档锁定为统一工具链 wrapper（`<triple><api>-clang`），NDK 大版本升级时需复核 · zig-cross 引入复议**已有书面结论：不引入**（`DECISIONS.md` 决策 1 R4 复议节，2026-11-09）。

## 13. 当前状态

`../moon_abi.mbt` 的原有值类型、`ConfigRenderer` trait、`MoonAbiError`（11 构造）与 4 个核心 API（`generate` / `render` / `validate` / `clang_name`）均为**真实实现**；R4 追加 CLI 纯逻辑（`parse_gen_args` / `exit_code_for_error` / `managed_block` / `merge_link_config` / `write_config_with`）、真实写文件（`sync_config_file`）、NDK 探测（`probe_ndk` / `probe_ndk_with`）与结构化输出（`ndk_probe_text` / `ndk_probe_json`），以及 `cmd/main` 可执行入口。**核心配置生成仍不写文件、不执行外部命令**；I/O 仅在上述明确入口。`../pkg.generated.mbti` 与 `../cmd/main/pkg.generated.mbti` 快照与源码一致（R4 为纯加法 diff）。五道门禁全绿（**68 tests**，2026-11-09 本机实跑）。

## References

`../README.md` · `API.md` · `DECISIONS.md`（设计决策记录：自研选型 / 定位修正 / 文本契约与名义类型隔离 / 软依赖定位 / 声明与实现策略 / NDK 事实基线 / 风险与待验证）
