# moon_abi · 公开 API（API.md）

> **API 冻结前对账（2026-11-07）**：原有 4 个函数与值类型已与 `../pkg.generated.mbti` 快照逐项对账一致；**冻结后签名变更即破坏性变更**。
> **R4 更新（2026-11-09）**：CLI 纯逻辑、幂等写文件、NDK 探测落地；全部为**加法性新增**（`../pkg.generated.mbti` 纯加法 diff，已随源码提交）。
> 核心配置生成仍为**纯 MoonBit**：无 `#external` 句柄、无 `extern "C"`、无 `#borrow/#owned`、无回调。R4 的 I/O 只出现在 `sync_config_file` / `probe_ndk` / `cmd/main` 三个明确入口。

## 类型

| 类型 | 种类 | 说明 |
|---|---|---|
| `Abi` | `pub(all) enum` | `ArmeabiV7a` / `Arm64V8a` / `X86` / `X86_64` |
| `TargetTriple` | `pub(all) enum` | 4 种 NDK 目标三元组前缀（不含 API level 后缀） |
| `ApiLevel` | `pub(all) struct` | `{ level : Int32 }` 包装，防止裸 Int 混用 |
| `NdkProfile` | `pub(all) struct` | `ndk_root` / `ndk_version` / `api_level` / `extra_link_libs` / `extra_cc_flags` / `windows_path_style` |
| `LinkNativeConfig` | `pub(all) struct` | `cc` / `cc_flags` / `cc_link_flags` / `stub_cc : String?` / `supported_targets` / `triple` / `abi` / `api_level` |
| `ValidationReport` | `pub(all) struct` | `ok : Bool` / `warnings : Array[String]` / `errors : Array[String]` |
| `MoonAbiError` | `pub suberror` | 11 个错误构造（原 7 个 + R4 的 4 个） |
| `ConfigRenderer` | `pub trait` | `fn render(Self) -> String raise MoonAbiError`（确定性、可复现） |
| `PathStyle` | `pub(all) enum` | `Auto` / `Windows` / `Unix`（CLI 路径风格） |
| `GenOutput` | `pub(all) enum` | `Stdout`（只读打印）/ `File(String)`（写/追加 `../moon.pkg`） |
| `GenCommand` | `pub(all) struct` | CLI `gen` 解析结果：`abi` / `api_level` / `ndk_root?` / `ndk_version?` / `output` / `path_style` |
| `MergeAction` | `pub(all) enum` | `Appended` / `Replaced` / `Unchanged` |
| `MergeResult` | `pub(all) struct` | `content : String` / `action : MergeAction` |
| `ReadOutcome` | `pub(all) enum` | `Found(String)` / `NotFound` / `Failed(String)`（注入式读结果） |
| `NdkSource` | `pub(all) enum` | `Explicit` / `NdkHomeEnv` / `AndroidHomeNdk` / `AndroidSdkRootNdk` / `CommonPath` |
| `NdkProbeInputs` | `pub(all) struct` | `explicit_root?` / `ndk_home?` / `android_home?` / `android_sdk_root?` / `home_dir?` / `local_app_data?` |
| `NdkCandidate` | `pub(all) struct` | `source` / `path` / `exists` / `usable` / `version?` / `note` |
| `NdkProbeResult` | `pub(all) struct` | `found` / `selected?` / `version?` / `candidates` / `warnings` |

## 函数签名（核心，R1–R3 冻结）

| 签名 | 参数与所有权 | 返回 / 错误 | 资源与线程约束 | 实现要点 / 备注 |
|---|---|---|---|---|
| `generate(profile : NdkProfile, abi : Abi) -> LinkNativeConfig raise MoonAbiError` | `profile` 只读注入，不探测本机 | 纯值配置 / `UnsupportedAbi`、`UnsupportedApiLevel`、`MissingNdkRoot`、`VersionMismatch` | **纯函数、无 I/O、可并发** | **已实现**：NDK 统一工具链命名 `<triple><api>-clang`；注入 `--target=<triple><api>`、`-llog -landroid`；校验顺序 `MissingNdkRoot` → `UnsupportedApiLevel` → `VersionMismatch` |
| `render(config : LinkNativeConfig) -> String raise MoonAbiError` | `config` 只读 | `options(link.native…)` 文本片段 / `InvalidTriple`、`MissingClang`、`PathContainsSpace` | 确定性输出，同输入两次逐字相等 | **已实现**：Windows 路径空格提前拒绝、不自动加引号；`stub_cc : None` 时省略 `stub-cc` 行 |
| `validate(profile : NdkProfile, abi : Abi) -> ValidationReport raise MoonAbiError` | `profile` 只读 | 校验报告 / `UnsupportedAbi`；`warnings` 不阻断、`errors` 阻断 | 纯函数、可并发 | **已实现**：缺 NDK 路径、API level 越界、版本不匹配、含空格 token 进 `errors`；空条目 / 重复链接库 / 路径风格不一致进 `warnings` |
| `clang_name(abi : Abi, api : ApiLevel) -> String raise MoonAbiError` | 纯值 | clang 可执行文件名（含 API level 后缀）/ `UnsupportedAbi`、`UnsupportedApiLevel` | 纯函数 | **已实现**：以当前 NDK 文档为准 |

## 函数签名（R4 加法性新增）

| 签名 | 说明 |
|---|---|
| `abi_from_name(name : String) -> Abi raise MoonAbiError` | CLI `--abi` 解析；接受规范名与别名（`armv7` / `arm64` / `x64` 等），大小写不敏感；非法名抛 `UnsupportedAbi` |
| `parse_gen_args(args : ArrayView[String]) -> GenCommand raise MoonAbiError` | 解析 `gen` 参数；支持 `--abi` / `--api` / `--ndk-root` / `--ndk-version` / `--out` / `--path-style` 与 `--flag=value`；参数错误抛 `CliUsage`（或 `UnsupportedAbi` / `UnsupportedApiLevel`） |
| `exit_code_for_error(err : MoonAbiError) -> Int32` | 退出码契约：`2` = 用法/参数（`CliUsage` / `UnsupportedAbi` / `UnsupportedApiLevel`）；`1` = 运行/环境/IO（其余） |
| `error_message(err : MoonAbiError) -> String` | 人读错误消息（CLI 输出与测试共用） |
| `windows_path_style_of(root : String) -> Bool` | 按 `\` 或盘符 `C:` 推断 Windows 路径风格 |
| `managed_block(config : LinkNativeConfig) -> String raise MoonAbiError` | 生成带起止标记的受管块（开始标记 + `render` 文本 + 结束标记） |
| `merge_link_config(existing : String, block : String) -> MergeResult raise MoonAbiError` | 幂等合并：无块追加 / 有块只替换块区间 / 已一致不写；标记不成对抛 `MalformedConfig` |
| `merge_action_name(action : MergeAction) -> String` | `appended` / `replaced` / `unchanged` |
| `write_config_with(path, block, read, write) -> MergeResult raise MoonAbiError` | **注入式**读/写；读失败与写失败统一 `IoFailure(path, reason)`；`Unchanged` 时不调用写 |
| `sync_config_file(path : String, block : String) -> MergeResult raise MoonAbiError` | 真实文件系统版本（async）：不存在视为空、幂等合并、必要时写回 |
| `probe_ndk_with(inputs, dir_exists, list_dirs, read_text) -> NdkProbeResult` | **纯函数**探测核心；目录/文件访问全部注入，测试用伪目录 |
| `probe_ndk(inputs : NdkProbeInputs) -> NdkProbeResult` | 真实文件系统探测（async，只读 stat/read）；不执行外部命令 |
| `ndk_probe_text(result : NdkProbeResult) -> String` | 结构化文本（`NDK|…` / `CAND|…` / `WARN|…`） |
| `ndk_probe_json(result : NdkProbeResult) -> String` | 单行 JSON（字段顺序固定、转义合法） |

## CLI 契约（`cmd/main`）

- `moon-abi gen --abi <abi> --api <level> [--ndk-root <path>] [--ndk-version <ver>] [--out <path>] [--path-style auto|windows|unix]`
  - 无 `--out`：只读打印受管块到 stdout（退出码 0）。
  - 有 `--out`：写入/幂等替换该文件的受管块；输出 `<path>: appended|replaced|unchanged`。
- `moon-abi probe [--json]`：结构化输出本机 NDK 探测；未找到返回 1。
- 退出码：**0 成功 / 2 用法或参数错误 / 1 运行、环境或 IO 错误**（写失败、NDK 未找到、版本不匹配、既有配置畸形等）。

## 错误构造速查（11 个）

`UnsupportedAbi(name)` · `UnsupportedApiLevel(got, min)` · `MissingNdkRoot` · `MissingClang(path)` · `PathContainsSpace(path)` · `InvalidTriple(triple)` · `VersionMismatch(expected, actual)` · `CliUsage(reason)` · `IoFailure(path, reason)` · `MalformedConfig(reason)` · `NdkNotFound(detail)`

## 与骨架 README 的接口差异

骨架写的是 CLI `moon-abi gen --abi armv7 --api 21`。R1–R3 先以**纯值库 API** 落地（`generate` / `render` / `validate` / `clang_name`），把 CLI 后移；**R4 已按任务要求在本模块内落地 CLI**（`gen` / `probe`），并保留纯核心不变。CLI 的解析、退出码与合并逻辑同样可在无文件系统的情况下单测（见 `write_config_with` / `probe_ndk_with` 的注入设计）。

## Wire / 跨模块提示

`moon_abi` 输出的是**文本片段**，不向 `moon_android` 传递 `LinkNativeConfig` 类型（两模块名义类型隔离、零 import，消解潜在循环依赖，详见 `DECISIONS.md` 决策 3）。`Abi` 在 `moon_abi` 与 `moon_android` 中**各自定义、结构同构**，由组合根转换。

## 非目标

执行 NDK / clang / 任何外部命令（探测仅 stat/read）· 执行打包与签名 · 下载或分发 SDK/NDK 二进制 · 链接任何 C 库 · 验证产物在设备上可加载（E3 待实测）· 自动添加链接库/编译 flag 的启发式规则。

## 状态

**API 冻结前对账（2026-11-07）**：原 API ↔ `../pkg.generated.mbti` ↔ 源码公开签名三方一致；冻结后原有签名变更即破坏性变更。**R4 追加均为加法性**，快照已随源码提交。
五道门禁实跑全绿（2026-11-09）：`moon check --deny-warn`（0 error / 0 warn）· `moon build` · `moon test`（**68 tests** 全过）· `moon fmt --check` · 第 5 道快照门禁 `moon info && git diff --exit-code -- ../pkg.generated.mbti ../cmd/main/pkg.generated.mbti`。
API 快照：`../pkg.generated.mbti`（R4 纯加法）。
