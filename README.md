# moon_abi · NDK 交叉编译配置生成

> 独立发布单元 ｜ L4 工程交付 ｜ `preferred_target = wasm` ｜ Apache-2.0
> 状态：`moon test` **109/109** 通过（2026-11-26 本机实测，wasm 与 native 双目标）；本文件是本仓库的**入口**文档，带日期的开发/测试文档与变更簿记见 [docs/](docs/)。
> 公开 API 以 `pkg.generated.mbti` 为准（由 `moon info` 生成，禁手工编辑）；加法性变更须登记簿记 + 快照审阅 + 快照门禁。

## 1. 定位与边界

把 Android NDK/API 约束变成可校验、可渲染的交叉编译配置文本，而不是直接调用工具链。

**能力**

- 四个核心纯函数 `generate` / `render` / `validate` / `clang_name`
- API level ≥ 21、NDK major ≥ 22 校验；`ConfigRenderer` trait 与文本契约
- R4 加法性：`gen` / `probe` CLI、`ndk_probe`（异步 FS 探测）、`sync_config_file` 等
- W4 加法性：`parse_gen_args_ext` / `generate_multi` / `GenCommandExt`（多 ABI、`--extra-lib` / `--extra-cc-flag`）
- W5 加法性：`NdkHost` / `host_tag` / `generate_with_host`（三宿主含 darwin）/ `api_level_advisory`；CLI `gen` 已接线 `--host`（macOS 默认修正为 darwin）
- `moon-abi gen` / `moon-abi probe`，退出码 0/1/2

**非目标**

- 库 API 与 CI 不调用真实 NDK clang / CMake，不产出 `.so`（真实构建仅在 W6-A 脚本层按需触发，见 §5/§6）
- 不引入 `zig-cross`（R4 复议结论：不引入）

## 2. 关键设计决策（本仓库自足记录）

- 只生成配置文本，不做构建；模块侧外部 oracle 已在真实 NDK 上 PASS（2026-11-26，WSL/Linux + NDK r27c + API 28/arm64），但「产出可加载 `.so` 的组合根集成」仍不在本仓库范围。
- CLI 早期计划「后移组合根」，实际 R4 已在本仓库内落地；旧文档标题中的「后移」已作废。
- NDK 为软依赖（数据契约），不是开发顺序的硬前置。
- `moon.pkg` 主包仅引 core 的 async/fs（test 块另引 async/test；derive 引入 debug，cmd/main 引 env）；`preferred_target = wasm`。

## 3. 公开 API 索引（抽取 `pkg.generated.mbti` 的全部 `pub` 声明，含 async fn/方法/trait；完整字段见快照）

```text
pub fn abi_from_name(String) -> Abi raise MoonAbiError
pub fn api_level_advisory(NdkProfile) -> Array[String]
pub fn clang_name(Abi, ApiLevel) -> String raise MoonAbiError
pub fn error_message(MoonAbiError) -> String
pub fn exit_code_for_error(MoonAbiError) -> Int32
pub fn generate(NdkProfile, Abi) -> LinkNativeConfig raise MoonAbiError
pub fn generate_multi(NdkProfile, Array[Abi]) -> Array[LinkNativeConfig] raise MoonAbiError
pub fn generate_multi_with_host(NdkProfile, Array[Abi], NdkHost) -> Array[LinkNativeConfig] raise MoonAbiError
pub fn generate_with_host(NdkProfile, Abi, NdkHost) -> LinkNativeConfig raise MoonAbiError
pub fn host_from_name(String) -> NdkHost raise MoonAbiError
pub fn host_tag(NdkHost) -> String
pub fn managed_block(LinkNativeConfig) -> String raise MoonAbiError
pub fn merge_action_name(MergeAction) -> String
pub fn merge_link_config(String, String) -> MergeResult raise MoonAbiError
pub fn ndk_probe_json(NdkProbeResult) -> String
pub fn ndk_probe_text(NdkProbeResult) -> String
pub fn parse_gen_args(ArrayView[String]) -> GenCommand raise MoonAbiError
pub fn parse_gen_args_ext(ArrayView[String]) -> GenCommandExt raise MoonAbiError
pub fn parse_gen_args_with_host(ArrayView[String]) -> GenCommandWithHost raise MoonAbiError
pub async fn probe_ndk(NdkProbeInputs) -> NdkProbeResult
pub fn probe_ndk_with(NdkProbeInputs, (String) -> Bool, (String) -> Array[String], (String) -> String?) -> NdkProbeResult
pub fn render(LinkNativeConfig) -> String raise MoonAbiError
pub fn resolve_default_host(Bool, NdkHost) -> NdkHost
pub fn resolve_ndk_values(GenCommand, NdkProbeResult) -> (String, String) raise MoonAbiError
pub async fn sync_config_file(String, String) -> MergeResult raise MoonAbiError
pub fn validate(NdkProfile, Abi) -> ValidationReport raise MoonAbiError
pub fn windows_path_style_of(String) -> Bool
pub fn write_config_with(String, String, (String) -> ReadOutcome, (String, String) -> Result[Unit, String]) -> MergeResult raise MoonAbiError
pub fn MoonAbiError::to_repr(Self) -> @debug.Repr
pub(all) enum Abi {
pub(all) struct ApiLevel {
pub(all) struct GenCommand {
pub(all) struct GenCommandExt {
pub(all) struct GenCommandWithHost {
pub(all) enum GenOutput {
pub(all) struct LinkNativeConfig {
pub(all) enum MergeAction {
pub(all) struct MergeResult {
pub(all) struct NdkCandidate {
pub(all) enum NdkHost {
pub(all) struct NdkProbeInputs {
pub(all) struct NdkProbeResult {
pub(all) struct NdkProfile {
pub(all) enum NdkSource {
pub(all) enum PathStyle {
pub(all) enum ReadOutcome {
pub(all) enum TargetTriple {
pub(all) struct ValidationReport {
pub trait ConfigRenderer {
```

## 4. 依赖、平台与许可

零第三方依赖（主包仅 `moonbitlang/core/async/fs`；test 块另引 async/test，derive 引入 debug，cmd/main 引 env）；`preferred_target = wasm`；Apache-2.0。

## 5. 命令行与验证

- `moon run cmd/main --target native -- gen ...` / `probe ...`。
- `gen` 选项：`--abi`（可重复、去重保序）、`--api`、`--ndk-root`、`--ndk-version`、`--out`、`--path-style`、`--host windows|linux|darwin`、`--extra-lib`（可重复）、`--extra-cc-flag`（可重复）。多 ABI 仅打印 stdout（块间单空行），与 `--out` 互斥（退出码 2）。
- 宿主：显式 `--host` 优先（与显式 `--path-style` 互斥，退出码 2）；未指定时 `--path-style windows|unix` 维持旧宿主（windows / linux），`auto`（默认）下仅 macOS + unix 风格根路径修正为 `darwin-x86_64`（Windows/Linux 旧输出逐字节不变）。
- 复验：`moon clean` → `moon check --deny-warn` → `moon build` → `moon test` → `moon fmt --check` → `moon info` 后检查 `pkg.generated.mbti` 无意外 diff。
- 外部 oracle（W6-A，只读差分，仓库外 NDK 由参数注入）：`pwsh tools/oracle-run.ps1 -NdkRoot <NDK根> [-HashFile <SHA256登记>] [-CrossCc <交叉CC> -CrossAr <交叉AR>]`。无 NDK → 显式 SKIPPED（退出码 78，不计通过）；哈希不符 → 拒绝执行（退出码 1）；报告落 `tools/oracle-reports/`（产物 .gitignore 排除）。2026-11-26 真实 PASS：WSL Ubuntu 24.04.4 + NDK r27c `27.2.12479018` + moon 0.1.20261126，API 28 / arm64，`counted_as_pass=true`（报告 `oracle-20261126-210303.json`）。
- 本仓库为独立 Git 仓库，文档与 CI 均自包含，不依赖工作区其他目录。

## 6. 风险与未决

- E3/W6-A 模块侧已在真实 NDK 上取得 PASS（2026-11-26：WSL Ubuntu 24.04.4、NDK r27c `27.2.12479018`、moon 0.1.20261126、API 28 / arm64；`counted_as_pass=true`，报告 `tools/oracle-reports/oracle-20261126-210303.json`，`source.properties` SHA-256 `70f1c516…83cf6`）。限制：MoonBit 的 package-level `link.native.cc` 不能改变共享 runtime 目标，非 Android 宿主需 `MOON_CC` + `MOON_AR`（runner 新增 `-CrossCc/-CrossAr`，仅注入临时项目构建）；API 21 会在 runtime `getentropy` 处失败，故本轮用 API 28；Windows 宿主受 core `platform` cfg 固定为 Windows 影响，当前工具链无法完成 Windows→Android 差分。产出可加载 `.so` 的 CMake/组合根集成仍不在本仓库范围。
- 「NDK r23 移除 standalone toolchain」是误述，实际移除的是 GNU binutils 与 GDB。
- 已知局限：probe 文本记录行（`NDK|…`/`CAND|…`/`WARN|…`）在路径含 `|` 或换行时解析歧义；JSON 通道无此问题。记录行格式冻结，如需转义走未来新函数。
- 提交数口径：以 `git rev-list --count HEAD` 实测为准（2026-11-16 基线 16，历史申报口径 15 滞后）。

