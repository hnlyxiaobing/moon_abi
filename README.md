# moon_abi · NDK 交叉编译配置生成

> 独立发布单元 ｜ L4 工程交付 ｜ `preferred_target = wasm` ｜ Apache-2.0
> 状态：`moon test` **68/68** 通过（2026-11-11 本机实测）；本文件是本仓库**唯一**说明文档。
> 公开 API 以 `pkg.generated.mbti` 为准（由 `moon info` 生成，禁手工编辑）；加法性变更须登记簿记 + 快照审阅 + 快照门禁。

## 1. 定位与边界

把 Android NDK/API 约束变成可校验、可渲染的交叉编译配置文本，而不是直接调用工具链。

**能力**

- 四个核心纯函数 `generate` / `render` / `validate` / `clang_name`
- API level ≥ 21、NDK major ≥ 22 校验；`ConfigRenderer` trait 与文本契约
- R4 加法性：`gen` / `probe` CLI、`ndk_probe`（异步 FS 探测）、`sync_config_file` 等
- `moon-abi gen` / `moon-abi probe`，退出码 0/1/2

**非目标**

- 不调用真实 NDK clang / CMake，不产出 `.so`
- 不引入 `zig-cross`（R4 复议结论：不引入）

## 2. 关键设计决策（本仓库自足记录）

- 只生成配置文本，不做构建；交付通路 A4 的可加载产物仍属 E3 未复现项。
- CLI 早期计划「后移组合根」，实际 R4 已在本仓库内落地；旧文档标题中的「后移」已作废。
- NDK 为软依赖（数据契约），不是开发顺序的硬前置。
- `moon.pkg` 仅引 core 的 async/fs；`preferred_target = wasm`。

## 3. 公开 API 索引（自动抽取 `pkg.generated.mbti` 的 `pub` 声明行；完整字段见快照）

```text
pub fn abi_from_name(String) -> Abi raise MoonAbiError
pub fn clang_name(Abi, ApiLevel) -> String raise MoonAbiError
pub fn error_message(MoonAbiError) -> String
pub fn exit_code_for_error(MoonAbiError) -> Int32
pub fn generate(NdkProfile, Abi) -> LinkNativeConfig raise MoonAbiError
pub fn managed_block(LinkNativeConfig) -> String raise MoonAbiError
pub fn merge_action_name(MergeAction) -> String
pub fn merge_link_config(String, String) -> MergeResult raise MoonAbiError
pub fn ndk_probe_json(NdkProbeResult) -> String
pub fn ndk_probe_text(NdkProbeResult) -> String
pub fn parse_gen_args(ArrayView[String]) -> GenCommand raise MoonAbiError
pub fn probe_ndk_with(NdkProbeInputs, (String) -> Bool, (String) -> Array[String], (String) -> String?) -> NdkProbeResult
pub fn render(LinkNativeConfig) -> String raise MoonAbiError
pub fn validate(NdkProfile, Abi) -> ValidationReport raise MoonAbiError
pub fn windows_path_style_of(String) -> Bool
pub fn write_config_with(String, String, (String) -> ReadOutcome, (String, String) -> Result[Unit, String]) -> MergeResult raise MoonAbiError
pub(all) enum Abi {
pub(all) struct ApiLevel {
pub(all) struct GenCommand {
pub(all) enum GenOutput {
pub(all) struct LinkNativeConfig {
pub(all) enum MergeAction {
pub(all) struct MergeResult {
pub(all) struct NdkCandidate {
pub(all) struct NdkProbeInputs {
pub(all) struct NdkProbeResult {
pub(all) struct NdkProfile {
pub(all) enum NdkSource {
pub(all) enum PathStyle {
pub(all) enum ReadOutcome {
pub(all) enum TargetTriple {
pub(all) struct ValidationReport {
```

## 4. 依赖、平台与许可

零第三方依赖（仅 `moonbitlang/core/async/fs`）；`preferred_target = wasm`；Apache-2.0。

## 5. 命令行与验证

- `moon run cmd/main --target native -- gen ...` / `probe ...`。
- 复验：`moon clean` → `moon check --deny-warn` → `moon build` → `moon test` → `moon fmt --check` → `moon info` 后检查 `pkg.generated.mbti` 无意外 diff。
- 本仓库为独立 Git 仓库，文档与 CI 均自包含，不依赖工作区其他目录。

## 6. 风险与未决

- E3（MoonBit → C → NDK clang + CMake 产出可加载 `.so`）未复现，本工作区无 `mvp/` 目录。
- 「NDK r23 移除 standalone toolchain」是误述，实际移除的是 GNU binutils 与 GDB。

