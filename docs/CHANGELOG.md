# CHANGELOG（加法性变更簿记）

> 口径：每工作包登记「日期 / 工作包 / 新增 pub 声明 / 快照 diff 结论 / 测试增量」；
> 快照由 `moon info` 生成（禁手编）；#skip/SKIPPED 永不计入通过。
> 配套设计文档：[2026-11-16-ndk-config-fidelity-dev-plan.md](2026-11-16-ndk-config-fidelity-dev-plan.md)。

## 2026-11-26 · M3（W5 宿主平台与 API 矩阵纵深）

> 新增三宿主 clang 路径（含 darwin）与 API 上限 advisory；纯加法 API，
> 旧 `generate`/`validate`/`cc_path` 一行不动、输出逐字节不变（防火墙 T-W5-2）。

- 新增 pub 声明：`NdkHost`（enum：`WindowsX86_64` / `LinuxX86_64` / `DarwinX86_64`）、`host_tag(NdkHost) -> String`、`generate_with_host(NdkProfile, Abi, NdkHost) -> LinkNativeConfig`、`api_level_advisory(NdkProfile) -> Array[String]`。快照 diff：纯加法 +4 声明（12 行增、0 删；`pkg.generated.mbti`）。
- **易变事实核实（2026-11-26 联网）**：
  - 宿主标签：`toolchains/llvm/prebuilt/<host>` 在 NDK r22+ 为 `windows-x86_64` / `linux-x86_64` / `darwin-x86_64`（多个 NDK 目录样本与 r27c 实测记录一致）。
  - NDK major → 已知最高 API：r22→30、r23→31、r24→32、r25→33、r26→34、r27→35（Android 各版本 NDK 修订记录与 r27c「api 35 默认」记录一致）。来源：Android NDK 修订历史（developer.android.com/ndk/downloads/revision_history）及 r23/r25/r26/r27 变更记录；结论登记本文件，若后续核实不符仅调整新函数数据表（旧 API 不受影响）。
- 行为/契约（纯加法，旧 CLI 零漂移）：
  - `generate_with_host`：路径分隔符与 `prebuilt` 宿主标签均由 `NdkHost` 决定，**忽略** `profile.windows_path_style`（新函数文档明示）；其余注入（校验顺序、`--target`、extra flag/lib、`stub_cc`）与 `generate` 一致；Windows/Linux 两宿主输出与旧 `generate` 逐字节相同。
  - `api_level_advisory`：level 高于该 NDK major 已知最高 API → 返回一条警告串（含 level / 上限 / major）；版本不可解析或 major 不在表内 → 空数组（不猜测、不阻断）。
- 测试增量：+5（94→99；wasm 与 native 双目标各 99/99，旧用例零改动全绿，#skip=0）。
  - ndk_host_test.mbt +4：T-W5-1 三宿主标签 + 三宿主 golden cc 路径；T-W5-2 win/linux 与旧 `generate` 逐字节一致；T-W5-3 advisory 边界三态（不可解析/未知 major 零警告、恰等于上限零警告、超上限告警、全版本号写法可解析）。
  - truncation_scan_wbtest.mbt +1：`api_level_advisory` 对 `ndk_version` 全前缀无 panic 扫描（W5 新解析路径一行接入）。
- 实现要点：新文件 `ndk_host.mbt`；`cc_path_with_host`（私有）与旧 `cc_path` 同构但宿主由参数决定，不触碰旧 `cc_path`；`known_max_api` 内置保守数据表；`api_level_advisory` 复用私有 `ndk_major`。
- 门禁状态：`moon check --deny-warn` / `moon build` / `moon test`（wasm 与 native 各 99/99） / `moon fmt --check` / `moon info` 快照 diff 纯加法 全绿；CLI 冒烟复跑（help=0、gen-ok=0、no-args=2、bad-abi=2、api20=2、space-path=1、multi-out=2、multi-stdout=0）零漂移。
- 验收：T-W5-1 ✓、T-W5-2 ✓、T-W5-3 ✓、T-W5-4 ✓（快照 diff 纯加法 + CHANGELOG 登记）。
- 待落地（仍按原排期）：W6-A 外部 oracle runner（M4，脚本层零 API）。

## 2026-11-26 · M2（W4 CLI extra 选项 + 多 ABI）

> 新增 CLI `gen` 扩展：`--abi` 可重复（≥1，去重保序）、新增 `--extra-lib`/`--extra-cc-flag`（均可重复、原序、空值拒绝）。
> 纯加法 API：`GenCommandExt` + `parse_gen_args_ext` + `generate_multi`；旧 `parse_gen_args`/`generate` 一行不动。
> cmd/main 切换到扩展解析器，旧参数组合（单 ABI、`--out`、路径风格覆盖等）的 stdout/stderr/退出码/落盘内容逐字节不变（防火墙 T-W4-4）。

- 新增 pub 声明：`GenCommandExt`（struct，含 `base`/`abis`/`extra_link_libs`/`extra_cc_flags`）、`parse_gen_args_ext(ArrayView[String]) -> GenCommandExt`、`generate_multi(NdkProfile, Array[Abi]) -> Array[LinkNativeConfig]`。快照 diff：纯加法 +3 声明 +1 struct（pkg.generated.mbti）。
- 行为/契约（相对旧 CLI）：
  - 多 ABI（去重后 ≥2）stdout 打印按输入序两个受管块、块间单空行分隔；`generate_multi` 按输入序逐 ABI 生成同一 profile。
  - 多 ABI + `--out` 互斥 → `CliUsage`（退出码 2，消息明示「single managed block contract」，零落盘）；去重后单 ABI + `--out` 仍合法。
  - `--extra-lib <name>` 追加 `-l<name>` 到 cc-link-flags；`--extra-cc-flag <f>` 追加到 cc-flags 末尾。值以 `-` 开头需用内联 `=` 形式（共享 `take_flag_value` 语义，独立 token 以 `-` 开头抛 `CliUsage`）。
  - extra 空值（独立参数 `""` 或内联 `=` 空）→ `CliUsage` 退出码 2；`generate_multi` 空数组 → `CliUsage` 退出码 2。
- 测试增量：+8（86→94；wasm 与 native 双目标各 94/94，旧用例零改动全绿，#skip=0）。
  - gen_cli_test.mbt +7：T-W4-1 base 与旧 `parse_gen_args` 逐字段等价（指纹串）、多 ABI 去重保序 + extra 原序、cc flag 内联 `=` 原序保留、cc flag 独立 token 以 `-` 开头抛 `CliUsage`、extra 空值抛 `CliUsage` 退出码 2、T-W4-3 多 ABI+`--out` 互斥抛 `CliUsage`、T-W4-2 `generate_multi` 顺序/确定性/extra 落到 flags/空数组错误。
  - truncation_scan_wbtest.mbt +1：`parse_gen_args_ext` 参数序列全前缀无 panic 扫描（含多 ABI/extra/内联 `=` 种子），新解析路径一行接入扫描。
- 实现要点：`gen_cli_ext.mbt` 复用旧解析器同一组辅助（`split_flag`/`take_flag_value`/`abi_from_name`/`parse_api_level_value`/`path_style_from_name`/`check_api_level`）；`base.abi = abis[0]` 使单 ABI 语义与旧解析器逐字一致；`abi_index` 供去重保序（不新增 `Abi` 的 `Eq` derive 以免污染快照）。
- 门禁状态：`moon check --deny-warn` / `moon build` / `moon test`（wasm 与 native 各 94/94） / `moon fmt --check` / `moon info` 快照 diff 纯加法 全绿；CLI 冒烟复跑：17 场景防火墙逐字节符合（version=0、unknown-sub=2、missing-abi=2、r21=1、probe-bad-opt=2、probe-notfound=1、out-first=0、out-idempotent=0、out-malformed=1 且原文件未改写、out-missing-dir=1、bad-abi=2、api20=2、space-path=1、multi-end out=1）+ W4 新场景（multi-stdout=0 两块单空行、multi-out=2、extra 落到 flags）。
- 验收：T-W4-1 ✓、T-W4-2 ✓、T-W4-3 ✓、T-W4-4 ✓（17 场景逐字节防火墙）、T-W4-5 ✓（快照 diff 纯加法 + CHANGELOG 登记）。
- 待落地（仍按原排期）：W5 宿主/API 矩阵（M3，数据表先联网核实）、W6-A 外部 oracle runner（M4）。

## 2026-11-26 · M1（W3 fail-closed 输入加固）

> 关闭 B6 / B15 / B19 三处静默放行：以前静默放行的损坏/不安全输入现在拒绝。
> 行为增强例外流程（退出码集合与消息文本冻结，复用既有变体），见开发文档 §5 W3。

- 新增 pub 声明：无。快照 diff：空（pkg.generated.mbti 与 cmd/main/pkg.generated.mbti 均零漂移）。
- 测试增量：+5（81→86；wasm 与 native 双目标各 86/86，旧用例零改动全绿，#skip=0）。
  - moon_abi_test.mbt +2：render 对全部空白字符（tab/CR/LF/VT/FF/空格）token 抛 `PathContainsSpace`；
    validate 对含 tab 的 ndk_root 报 `PathContainsSpace` 进 errors。
  - gen_cli_test.mbt +1：merge 单 begin + 多 end 标记抛 `MalformedConfig("multiple managed block end markers")`，退出码 1。
  - moon_abi_wbtest.mbt +1：`parse_pkg_revision` 对 `Pkg.RevisionFoo=…` 键不误命中，标准键（带空格/紧邻 `=`）仍正确解析。
  - truncation_scan_wbtest.mbt +1：新增「render 含空白 token 全前缀无 panic」扫描；既有 merge 畸形标记种子扩入多 END 变体、`parse_pkg_revision` 种子扩入误命中/紧邻 `=` 变体。
- **fail-closed 行为增强登记（以前静默放行 → 现在拒绝）与受影响样本**：
  1. tab/CR/LF/VT/FF 任一空白字符出现在 cc / stub / cc-flags / cc-link-flags 时，`render` 与 `validate` 由「静默放行 → 拒绝」，抛/报 `PathContainsSpace`（消息文本冻结，仍为 "path contains a space: …"）。受影响样本：含上述空白字符的 token（空格拒绝路径不变）。
  2. 受管块既有文本出现单 begin + 多 end 标记时，`merge_link_config` 由「接受、孤儿 end 永久残留用户区 → 拒绝」，抛 `MalformedConfig("multiple managed block end markers")`。受影响样本：含多 END 的既有 moon.pkg（CLI `--out` 退出码 1、原文件逐字节未被改写）。
  3. `parse_pkg_revision` 对 `Pkg.RevisionFoo=…` 类键由「前缀误命中 → 不误命中」，回退目录名/None 路径不变。受影响样本：含该误命中键的 source.properties。
- 实现要点：`check_no_space`/`validate` 统一走新增私有辅助 `contains_whitespace`（`Char::is_ascii_whitespace`，覆盖 `\u{09}`..`\u{0D}` 与空格）；merge 的多 END 检测与既有多 begin 检测对称（检查首个 END 之后是否还有 END）；`parse_pkg_revision` 要求前缀下一字符为 `=` 或空白。
- 门禁状态：`moon check --deny-warn` / `moon build` / `moon test`（wasm 与 native 各 86/86） / `moon fmt --check` / `moon info` 快照零漂移 全绿；CLI 冒烟复跑（gen-ok=0、no-args=2、bad-abi=2、api20=2、space-path=1、multi-end out=1 且原文件未改写）符合契约。
- 验收：T-W3-1 ✓、T-W3-2 ✓、T-W3-3 ✓、T-W3-4 ✓（旧用例零改动全绿）、T-W3-5 ✓（截断/变异扫描无 panic，新解析路径已一行接入扫描）。
- 待落地（仍按原排期）：W4 CLI extra/多 ABI（M2）、W5 宿主/API 矩阵（M3，数据表先联网核实）、W6-A 外部 oracle runner（M4）。

## 2026-11-26 · M0-completion（技能 §3 M0 必做项补齐 + 工具链漂移修复）

> 从第一性原理审查 `moonbit-rollout-orchestration` 技能对本仓库的匹配度后，确认
> M0 基础并未完全落地（截断扫描驱动与错误簿记门禁被推迟到 W3/W4），且当前本地
> 工具链（moonc v0.10.22）与开发文档记录的基线（v0.10.20）存在 API 漂移导致
> `moon test` 编译失败。本增量在 W3 之前补齐 M0 必做项并把基线恢复全绿。

- 新增 pub 声明：无。快照 diff：零漂移（pkg.generated.mbti 与 cmd/main/pkg.generated.mbti 均无变化）。
- 测试增量：+5（76→81；wasm 与 native 双目标各 81/81，旧用例仅 @fs 重命名、无语义改动，#skip=0）。
  - truncation_scan_wbtest.mbt +4：可复用截断扫描驱动 `run_truncation_scan` / `run_truncation_scan_args`，
    覆盖 `merge_link_config` 既有文本、畸形标记边界、`parse_pkg_revision` source.properties、
    `parse_gen_args` 参数序列的全前缀（0..n 字符边界天然含全部结构边界点）；断言仅允许
    `MoonAbiError` 通道，任何越界/溢出等无关 panic 即测试失败。
  - error_ledger_wbtest.mbt +1：错误簿记门禁，把 §6.2「变体 → 触发 fixture」固化为代码，
    11/11 变体可构造、人读消息非空、退出码 ∈ {1,2}、清单无缺无余；缺一即红。
- 修复（工具链漂移，moonc v0.10.22 的 @fs API 改名）：
  - @fs.mkdir 参数 `allow_exist` → `allow_existing`；`@fs.rmdir`（已弃用）→ `@fs.remove`。
    gen_cli_fs_test.mbt / ndk_probe_fs_test.mbt。
  - cmd/main/moon.pkg 删除未使用的 `moonbitlang/core/async` 依赖（此前 `moon check --deny-warn`
    因 unused_package 告警而失败）。
- 仓库卫生（技能 §4.2）：新增 `.gitattributes` 强制 `*.mbt / *.mbt.md / *.mbti / moon.mod /
  moon.pkg / *.md / *.c / *.h` 为 `text eol=lf`，并执行 `git add --renormalize .` 收敛
  Windows 主机 `core.autocrlf=true` 导致的「git status M 而 git diff 为空」误报。
- 门禁状态：`moon check --deny-warn` / `moon build` / `moon test`（wasm+native 81/81）/
  `moon fmt --check` / `moon info` 快照零漂移 全绿。
- 待落地（仍按原排期）：W3 fail-closed（M1，合入时把新解析路径以一行 `run_truncation_scan*`
  接入本扫描并登记受影响样本）、W4（M2）、W5（M3）、W6-A（M4）。

## 2026-11-16 · M0（W1 + W2，用户裁决 W2-A / W6-A 后落地）

### W1 漂移清理与文档自包含（纯文档/注释/CI 文案）

- 新增 pub 声明：无。快照 diff：空。测试增量：0。
- ci.yml：Gate5 失败消息 `docs/API.md`（已删文件）→ README.md API 索引 + docs/CHANGELOG.md；`.r1` 存档注释改为历史说明（文件已于 d4b18a8 删除）；删除 `bobzhang/zip@0.1.2` 误植示例（本模块零第三方依赖）。
- copilot-setup-steps.yml：同步删除 bobzhang/zip 误植示例。
- moon_abi.mbt：MIN_API_LEVEL 注释删除跨仓库符号引用（`moon_android::ToolchainVersions`），改自足表述。
- README.md：「唯一说明文档」→「入口文档」+ docs/ 索引；API 索引补齐 4 条漏抽 pub 声明（probe_ndk / sync_config_file / MoonAbiError::to_repr / ConfigRenderer），抽取口径改为全部 pub 声明（含 async/方法/trait）；依赖口径补 debug/env/test 注记；§6 补 probe 文本记录行 `|`/换行歧义局限声明与提交数实测口径。
- 新建 docs/ 开发文档与测试系统设计文档（2026-11-16）、本 CHANGELOG。
- 历史口径修正（实测推翻，详见开发文档 §0 B#）：提交数 15→16；pub(all) 值类型 8→16；错误显式簿记「全覆盖」→9/11（W2 前）。

### W2 错误簿记补齐与 NdkNotFound 接线（裁决 A）

- 新增 pub 声明：`pub fn resolve_ndk_values(GenCommand, NdkProbeResult) -> (String, String) raise MoonAbiError`（纯加法）。
- 快照 diff：pkg.generated.mbti +2 行（上述声明）；cmd/main/pkg.generated.mbti 零漂移。
- 测试增量：+8（68→76；wasm 与 native 双目标各 76/76，旧用例零改动全绿，#skip=0）。
  - gen_cli_test.mbt +1：CliUsage 显式变体断言 6 例。
  - ndk_resolve_test.mbt +6：resolve_ndk_values 注入式行为样例（含 NdkNotFound 两条失败路径的确定性触发与消息冻结断言）。
  - ndk_resolve_wbtest.mbt +1：NdkNotFound 构造级 exit/message 断言（whitebox，见下方语言约束）。
- 行为变更：无对外契约变更。NdkNotFound 由死变体转为库内 raise（resolve_ndk_values）；CLI resolve_ndk 委托库纯函数，失败路径 stderr 单行文案与退出码 1 逐字节不变（T-W2-2：改动前后 stdout/stderr SHA-256 一致，2026-11-16 实测）；17 场景 CLI 冒烟复跑全符合契约。错误显式簿记 9/11 → **11/11**。
- 语言约束登记（实测发现，设计偏差已回写开发文档 W2）：
  1. MoonBit `pub suberror` 变体在定义包外只读（错误 4036）：cmd/main 无法构造 NdkNotFound，故 raise 点必须落库内（新增纯函数承载）；构造级测试只能落库包内 whitebox（`_wbtest.mbt`）。
  2. `moon check --deny-warn` 的 result_error_return lint 禁止 `Result[T, MoonAbiError]` 返回形态：CLI 维持 `Result[T, String]` 归一。
  3. 主包（executable）黑盒测试（`_test.mbt`）触发未来弃用警告：cmd/main 不落黑盒测试文件。

### 待落地（已裁决/已排期）

- W3 fail-closed 输入加固（M1）：合入时须在此登记「以前静默放行的损坏/不安全输入现在拒绝」条目与受影响样本清单。
- W4 CLI extra/多 ABI（M2）、W5 宿主/API 矩阵（M3，数据表先联网核实）、W6-A 外部 oracle runner（M4，脚本层零 API）。