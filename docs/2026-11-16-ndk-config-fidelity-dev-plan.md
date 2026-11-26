# moon_abi NDK 配置忠实性与边界加固开发文档

> 建立：2026-11-16 ｜ 状态：M0–M4 全部交付（M1/W3、M2/W4、M3/W5、M4/W6-A 均于 2026-11-26 完成）；2026-11-26 追加 CLI 宿主接线补丁（`--host`，双目标 109/109）与 E3 真实 NDK PASS（WSL/Linux，见 B40）｜ 适用仓库：本仓库（独立自包含）
> 裁决记录：2026-11-16 用户确认采纳推荐项——**W2-A**（NdkNotFound 接线）、**W6-A**（本地 NDK oracle runner）。
> 配套文档：[2026-11-16-test-system-design.md](2026-11-16-test-system-design.md)（验收测试 ID `T-W*-*` 出自该文档）
> 本文所有「现状」结论均为 2026-11-16 对本仓库源码的实测核对，非转述历史文档。
> 五门禁 2026-11-16 实跑（开发前基线）：`moon check --deny-warn` 退出 0；`moon build` 退出 0；`moon test` **68/68 通过、0 条 #skip**（默认 wasm 目标）；`moon test --target native` 亦 **68/68**；`moon fmt --check` 退出 0；`moon info` 后 `git diff --exit-code -- pkg.generated.mbti cmd/main/pkg.generated.mbti` 退出 0（双快照零漂移）。工具链：moon 0.1.20261104 / moonc v0.10.20+65efd5b93。
> M0 交付后 2026-11-16 复跑：五门禁全绿；wasm/native 双目标各 **76/76**（+8，旧用例零改动）；#skip=0；快照 diff 纯加法 +2 行（`resolve_ndk_values` 声明）；CLI 17 场景冒烟全符合契约；resolve 两条失败路径 stdout/stderr SHA-256 与改动前基线逐字节一致（T-W2-2）。

## 0. 现状基线（实测核对，开发前必读）

能力点清单（P1 基准，与 README/公开 API 面核对后确立）：

- F1 ABI/triple 映射与 clang wrapper 命名（`clang_name` / `abi_from_name`）
- F2 配置值生成（`generate`：cc 路径、`--target=`、`-llog -landroid`、extra 注入）
- F3 确定性渲染（`render` / `ConfigRenderer` / DSL 转义）
- F4 校验报告（`validate`：errors 阻断 / warnings 不阻断）
- F5 CLI gen 参数解析与退出码契约（`parse_gen_args` / `exit_code_for_error`）
- F6 受管块幂等合并（`managed_block` / `merge_link_config` / `merge_action_name`）
- F7 注入式与真实 FS 写配置（`write_config_with` / `sync_config_file`）
- F8 本机 NDK 探测与结构化输出（`probe_ndk_with` / `probe_ndk` / `ndk_probe_text` / `ndk_probe_json`）
- F9 错误模型与人读消息（`MoonAbiError` 11 变体 / `error_message`）
- F10 路径风格推断（`windows_path_style_of` / `PathStyle`）

非目标清单：不调用真实 NDK clang / CMake、不产出 `.so`；不引入 `zig-cross`（R4 复议结论）；含空格路径提前拒绝、不自动加引号；受管块外用户内容永不改写；本仓库/CI 不安装或下载 NDK（本地 E3 复验在仓库外手动准备，不入库）；E3 可加载产物（`.so` + CMake 组合根）不在本库；模块侧 oracle 由 W6-A 脚本层按需触发。

### B# 基线事实表

| # | 事实（已实现/缺口/漂移） | 证据位置 |
|---|---|---|
| B1 | 已实现：核心四纯函数 `generate`/`render`/`validate`/`clang_name` 实存且语义与 README 一致；generate 校验顺序 MissingNdkRoot→UnsupportedApiLevel→VersionMismatch；render 委托 ConfigRenderer 实现 | moon_abi.mbt `generate`/`do_render`/`validate`/`clang_name`；pkg.generated.mbti L17/L35/L39/L11 |
| B2 | 已实现：4 ABI × 4 triple 不可变映射表完整且与 `triple_name` 互逆；非法名抛 UnsupportedAbi | moon_abi.mbt `triple_of_name`/`triple_name`；moon_abi_wbtest.mbt「映射表完整」 |
| B3 | 已实现：API≥21（MIN_API_LEVEL=21）、NDK major≥22（MIN_NDK_VERSION="r22+"）；`ndk_major` 接受 rXX/rXXc/点分版本号，不可解析→VersionMismatch | moon_abi.mbt 常量区与 `ndk_major`/`check_ndk_version`；wbtest「ndk_major」两例 |
| B4 | 已实现：generate 注入 `--target=<triple><api>`、`-llog -landroid`、extra_cc_flags 原序、extra_link_libs 加 `-l` 前缀；stub_cc=Some(cc)；supported_targets="native" | moon_abi.mbt `generate` L350-385；moon_abi_test.mbt「4 ABI 字段逐项断言」「extra flags 注入顺序」 |
| B5 | 已实现：render 确定性文本（内嵌 golden：4 ABI×API21、API35、Windows 风格）；escape_dsl 转义 `\` 与 `"`；stub_cc=None 省略 stub-cc 行；双次渲染逐字相等有测试 | moon_abi.mbt `do_render`/`escape_dsl`；moon_abi_test.mbt golden 三例与「双次渲染确定性」 |
| B6 | **已修复（W3，2026-11-26）**：空格策略原仅检查 `' '`（`contains_char(' ')`）；现 `check_no_space` 拒绝全部空白字符（`Char::is_ascii_whitespace`：空格/tab/CR/LF/VT/FF），含 tab/换行/回车于 cc/stub/flags 时不再静默放行，渲染不再产生断裂 DSL | moon_abi.mbt `contains_whitespace` / `check_no_space` L208-224；moon_abi_test.mbt「render: 全部空白字符 token 抛 PathContainsSpace (W3)」 |
| B7 | 已实现（含边界）：validate ok=errors.is_empty()；warnings 三类 empty_entry/duplicate_link_lib/path_style_mismatch；ndk_root 为空时 extra token 的空格检查被跳过（位于 !is_blank 分支内） | moon_abi.mbt `validate` L412-492；moon_abi_test.mbt validate 三例 |
| B8 | 已实现：MoonAbiError 共 11 变体（7 核心 + 4 R4 加法），与历史口径一致 | moon_abi.mbt L69-82；pkg.generated.mbti L47-59 |
| B9 | 缺口（死变体）：`NdkNotFound(String)` 全仓库零 raise 点，仅在 exit_code_for_error/error_message/CLI report_error 被匹配；CLI resolve_ndk 失败走 Err(String) 旁路；显式测试 0 条 | Grep 全仓库 NdkNotFound（5 处均为声明/匹配）；cmd/main/main.mbt `resolve_ndk` L126-169 |
| B10 | 缺口（簿记）：`CliUsage` 无显式变体名断言（仅退出码 2 与消息间接覆盖）；其余 9 变体有显式用例 → 显式簿记现状 9/11 | Grep 测试文件 CliUsage/NdkNotFound 零命中；gen_cli_test.mbt「参数错误映射退出码 2」 |
| B11 | 已实现：parse_gen_args 支持 6 选项 + 内联 `=`；重复/缺值/未知选项/空值→CliUsage；--api 累加器 >100000→CliUsage；API<21→UnsupportedApiLevel。缺口：无 `--extra-lib`/`--extra-cc-flag`/多 ABI（历史「后续」清单未实现，库层 extra 字段已具备） | gen_cli.mbt `parse_gen_args` L196-295；gen_cli_test.mbt；r4_edge_test.mbt |
| B12 | 已实现：abi_from_name 别名（armv7/aarch64/x64 等）+ 大小写/前后空白归一；非法名抛 UnsupportedAbi(原始输入) | gen_cli.mbt L95-108；gen_cli_test.mbt 两例 |
| B13 | 已实现（实跑验证）：退出码契约 0/1/2。2026-11-16 native CLI 17 场景实跑全部符合：no-args=2、help=0、version=0、unknown-sub=2、bad-abi=2、api20=2、missing-abi=2、ok-stdout=0、space-path=1、r21=1、probe-bad-opt=2、probe-notfound=1、out-first=0(appended)、out-idempotent=0(unchanged)、out-malformed=1、out-missing-dir=1 | gen_cli.mbt `exit_code_for_error`；cmd/main/main.mbt；本机冒烟脚本实跑记录 |
| B14 | 已实现：managed_block=BEGIN+render+END+`\n`；merge 三态 Appended/Replaced/Unchanged；块外内容逐字保留；CRLF 块收敛到 LF 规范块；畸形标记（不成对/多 begin/end 先于 begin/空块）→MalformedConfig | gen_cli.mbt `managed_block`/`merge_link_config` L343-408；gen_cli_test.mbt、r4_edge_test.mbt |
| B15 | **已修复（W3，2026-11-26）**：merge 原只检测多个 BEGIN，不检测多个 END，「1 begin + 2 end」被接受致孤儿 end 残留；现单 begin + 多 end 抛 `MalformedConfig("multiple managed block end markers")` | gen_cli.mbt `merge_link_config` L374-381（after_end 对称检查）；gen_cli_test.mbt「多 END 标记抛 MalformedConfig (W3)」 |
| B16 | 已实现：write_config_with 注入式读/写；Unchanged 不调用 write；读/写失败→IoFailure(path,reason)；空路径→IoFailure；权限拒绝/磁盘满/读失败注入均有显式变体断言 | gen_cli.mbt L416-439；gen_cli_test.mbt write_config_with 三例 |
| B17 | 已实现：sync_config_file 真实 FS 版语义与注入版一致；exists 失败→按不存在处理；读/写失败→IoFailure；临时目录受控测试 3 条（写入/幂等/替换、父目录缺失、空路径） | gen_cli.mbt L445-470；gen_cli_fs_test.mbt |
| B18 | 已实现：probe_ndk_with 纯核心；优先级 Explicit→NDK_HOME→ANDROID_HOME/ndk→SDK_ROOT/ndk→常见路径；ndk-bundle 展开；版本目录降序（major 降序、同 major 字符串升序）；路径去重；usable=toolchains/llvm/prebuilt 存在；版本=source.properties Pkg.Revision 优先、目录名回退；结构化告警 | ndk_probe.mbt `probe_parents`/`roots_from_parents`/`evaluate_roots`；ndk_probe_test.mbt 7 例、r4_edge_test.mbt |
| B19 | **已修复（W3，2026-11-26）**：parse_pkg_revision 原用 `has_prefix("Pkg.Revision")` 前缀匹配，`Pkg.RevisionFoo=…` 误命中；现要求前缀下一字符为 `=` 或空白，误命中键不再被当作版本，回退目录名/None 路径不变 | ndk_probe.mbt `parse_pkg_revision` L258-282；moon_abi_wbtest.mbt「parse_pkg_revision: Pkg.RevisionFoo 不误命中 (W3)」 |
| B20 | 已实现：probe_ndk 真实 FS 包装「预取事实→纯核心判定」，权限失败降级为不存在/不可读、不 panic；伪 NDK/伪 SDK 临时目录测试 2 条；「全未找到」用全空闭包经纯核心确定性覆盖（注释明示 GitHub runner 预装 NDK 不可确定性构造） | ndk_probe.mbt L440-489；ndk_probe_fs_test.mbt 3 例 |
| B21 | 已实现（含契约局限）：ndk_probe_text 记录行 `NDK|…`/`CAND|…`/`WARN|…`；ndk_probe_json 单行、字段序确定、json_escape 覆盖引号/反斜杠/控制字符（\uXXXX）。局限：路径含 `|` 或换行时文本记录行无转义，解析会歧义（未文档化） | ndk_probe.mbt L603-677；ndk_probe_test.mbt「转义合法」、r4_edge_test.mbt「JSON 单行」 |
| B22 | 缺口（宿主覆盖）：cc_path 宿主标签仅 windows-x86_64 / linux-x86_64，无 darwin 宿主；macOS 主机无法生成正确 prebuilt 路径 | moon_abi.mbt `cc_path` L255-276 |
| B23 | 缺口（版本纵深）：无 API 上限/NDK 版本×API 矩阵校验；level=100000 可通过 generate（parse 层仅 cap 100000）；无「level 高于该 NDK 已知最高 API」告警 | moon_abi.mbt `check_api_level`；gen_cli.mbt `parse_api_level_value` |
| B24 | 实测基线：五门禁全绿（见文档头）；M3/W5 后 wasm 与 native 双目标各 99/99（2026-11-26）；#skip=0；工作树干净 | 2026-11-26 本机实跑 |
| B25 | 计数重测：测试声明 68 条 = gen_cli_test 16 + moon_abi_test 21 + wbtest 9 + ndk_probe_test 7 + ndk_probe_fs_test 3 + gen_cli_fs_test 3 + r4_edge_test 9；与 README「68/68」口径一致 | 逐文件 Select-String 重数 + moon test 实跑 |
| B26 | 漂移（计数）：`git rev-list --count HEAD` = **16**，历史申报口径「15 条有效提交」滞后 +1 | 2026-11-16 git 实测 |
| B27 | 漂移（API 索引）：README §3 索引缺 4 条 pub 声明：`pub async fn probe_ndk`、`pub async fn sync_config_file`、`pub fn MoonAbiError::to_repr`、`pub trait ConfigRenderer`（索引只抽 `pub fn` 行，漏 async/方法/trait） | README.md L32-65 ↔ pkg.generated.mbti 逐条核对 |
| B28 | 漂移（计数）：历史申报「8 个值类型」为 R1 口径；实测 pub(all) 类型 **16**（9 struct + 7 enum）；MoonAbiError 11 变体口径不变 | pkg.generated.mbti L63-176 逐个数 |
| B29 | 漂移（失效引用）：ci.yml Gate5 失败消息引用 `docs/API.md`；该文件已在 HEAD 提交 93c6364 删除（docs/API.md、DECISIONS.md、DESIGN.md、R4-REPORT.md 四份合并入 README.md，docs/ 目录现已不存在） | .github/workflows/ci.yml L122；git show 93c6364 --stat |
| B30 | 漂移（失效引用）：ci.yml 注释引用 `pkg.generated.mbti.r1`（R1 基线存档）；该文件已在提交 d4b18a8 删除 | .github/workflows/ci.yml L16；git show d4b18a8 |
| B31 | 漂移（兄弟口径误植）：ci.yml L29 与 copilot-setup-steps.yml L7 以 `bobzhang/zip@0.1.2` 为「本仓库钉死依赖」示例；本模块 moon.mod 零第三方依赖，示例系他模块口径误植 | .github/workflows/*.yml ↔ moon.mod |
| B32 | 漂移（自包含）：moon_abi.mbt L95 注释引用外部仓库符号 `ToolchainVersions`（「精确版本锁由 … 持有」），假定可访问本仓库之外的代码 | moon_abi.mbt L94-95 |
| B33 | 漂移（外部引用失效）：历史申报文档引用 `moon_abi/docs/DECISIONS.md`，该文件已随 93c6364 删除；复议结论现仅存于 README §1/§2 | README.md L21/L26；git show 93c6364 --stat |
| B34 | 口径待调整：README 称「本文件是本仓库唯一说明文档」；本文与配套测试文档落 docs/ 后须改为「唯一入口文档」并补 docs/ 索引（AGENTS.md/README.mbt.md/.githooks/README.md 为辅助文件） | README.md L4 |
| B35 | 依赖面实测：moon.pkg 引 core/async/fs（test 块另引 async/test）；mbti 显示 core/debug（derive 引入）；cmd/main 引 core/env+async；零第三方 ✓。README「仅 async/fs」口径略窄（未列 debug/env/test） | moon.pkg、cmd/main/moon.pkg、pkg.generated.mbti import 块 |
| B36 | fixture 形态：无 tests/fixtures 目录；全部测试为程序化构造 + 内嵌 golden 字符串；无死资产、无登记文件缺失问题 | 目录实测 + 测试文件通读 |
| B37 | 观察（非缺陷）：probe 实跑（本机无 NDK）found=false 退出 1、6 候选；join_path 对含 `/` 的 child 产生混合分隔符（如 `C:\…\Android/Sdk\ndk`），Windows 接受、风格推断不受影响 | ndk_probe.mbt `join_path`；本机 probe --json 实跑 |
| B38 | 版本一致性：CLI tool_version "0.1.0" 与 moon.mod version 一致；--version 输出 "moon-abi 0.1.0" | cmd/main/main.mbt L19；moon.mod L14；实跑 |
| B39 | **已修复（CLI 宿主接线，2026-11-26）**：W5 宿主能力接入 CLI（`--host windows|linux|darwin`；未指定时显式 `--path-style` 维持旧的 windows/linux 映射，`auto` 下 macOS + unix 风格根修正为 darwin）；旧 Windows/Linux 参数组合输出逐字节不变；wasm/native 各 109/109，快照 +4 声明 +1 struct | gen_cli_ext.mbt `parse_gen_args_with_host`/`generate_multi_with_host`/`resolve_default_host`；cmd/main main.mbt `current_platform_host`；CHANGELOG |
| B40 | **E3 真实 PASS（2026-11-26）**：WSL Ubuntu 24.04.4 + NDK r27c `27.2.12479018` + moon 0.1.20261126，API 28/arm64，`moon build --target native` 退出码 0，`counted_as_pass=true`；报告 `oracle-20261126-210303.json`（gitignore）。runner 新增 `-CrossCc/-CrossAr`（仅临时构建注入 `MOON_CC/MOON_AR`）与 `host_os/cross_cc/cross_ar` 字段。Windows 宿主 FAIL 取证：NDK 无 `<triple>-ar`、package cc 不改变共享 runtime 目标、全局 `MOON_CC` 受 core `platform` cfg 限制 | tools/oracle-run.ps1；oracle-reports/README；CHANGELOG |

**对历史口径的修正**：

1. 提交数 15 → **16**（B26，git 实测）。
2. 值类型数 8 → **16**（B28，R1 口径滞后于 R4 加法）。
3. README API 索引并非完整 pub 面：漏 2 条 async fn、1 条方法、1 条 trait（B27）。
4. 「docs/DECISIONS.md 可查」失效：docs/ 四份文档已在 HEAD 合并入 README 并删除（B29/B33）；ci.yml 仍引用 docs/API.md 与 .r1 存档（B29/B30）。
5. 错误变体显式簿记并非满覆盖：9/11，CliUsage 仅间接覆盖、NdkNotFound 为死变体（B9/B10）。
6. 「68/68 通过」口径本次复验成立（B24/B25），但 README 标注日期为 2026-11-11，本文以 2026-11-16 实跑为准。

## 1. 硬约束（每个工作包都必须满足）

1. API 冻结：`pkg.generated.mbti`（含 cmd/main 快照）为冻结基线，只允许纯加法（新 pub fn / 新 struct / 新 enum / 新 trait 实现）；禁止给既有 pub(all) struct（GenCommand、LinkNativeConfig、NdkProfile、NdkProbeResult、ValidationReport 等 9 个）加字段；禁止新增错误变体（MoonAbiError 11 变体冻结；破坏性需求走 ADR+用户裁决+CHANGELOG+主版本四件例外）；校验失败用值字段（ValidationReport.errors/warnings、NdkProbeResult.warnings）表达，解析失败复用既有变体；语义变更走新函数新类型防火墙（W4/W5），旧 API 语义永不改变。
2. 加法三件套：快照随源码同提交且 diff 纯加法 + docs/CHANGELOG.md 登记 + CI 快照门禁绿。
3. 依赖不动：本模块零第三方依赖；core 随工具链钉死（moon 0.1.20261104 / moonc v0.10.20+65efd5b93 / core 0.10.20+65efd5b93，ci.yml 版本断言强制）。`@fs` 接口为一次性 read_text/write_text/readdir/exists，无流式限额参数 → 合并/探测均为全量字符串操作，内存上界=目标文件大小；moon.pkg 属小文本，不引入流式处理。
4. 许可红线：第三方 NDK 安装包/.so/真实 SDK 样本不入库；真实差分只允许「仓库外本地路径 + SHA-256 登记 + 显式 SKIPPED」（W6 R runner）；入库测试资产一律确定性自产（现有临时目录伪 NDK 模式延续）。
5. 五门禁全绿才可合入；#skip/SKIPPED/退出码 78 不得写成通过。fail-closed 修复（W3：以前静默放行的 tab/换行 token、多 END 标记、误命中版本键现在拒绝）属行为增强非契约破坏（退出码集合不变），但须 CHANGELOG 显式登记 + 回归语料确认仅受影响样本变化。
6. 边界不变量（非目标 + 防火墙）：不调用 NDK/clang/CMake、不产出 .so、不引入 zig-cross、不自动加引号、块外用户内容永不改写、不安装/下载 NDK；W4/W5 新函数合入后，旧函数在全部既有语料上输出逐字节不变、旧用例零改动全绿。
7. 文档自包含：本文与配套文档、代码注释、CLI 帮助文本、ci.yml、脚本不得引用或假定可访问本仓库之外的目录/符号（B31/B32 为现存违例，W1 清理）。

## 2. 业界对标摘要（P2 结论，证据三级标注）

**渠道与限定**：2026-11-16 经公开 web 渠道（GitHub 镜像/官方文档/mooncakes 包页/搜索引擎）调研。mooncakes 站内搜索此前四轮实测不可用（422/SPA 无法穷举），本轮未做站内穷举，仅直接核验 zig-cross 包页；「未见同类」结论限定为：**MoonBit 语言 + 「不执行构建的 link.native 配置纯值生成器」组合语义 + 2026-11-16 时点 + 上述公开渠道**。

| 能力（F#） | 本模块（B# 实测） | cargo-ndk（Rust CLI） | NDK android.toolchain.cmake（官方 CMake 工具链文件） | zig-cross 0.4.1（MoonBit CLI） | AGP externalNativeBuild（Gradle DSL） | gomobile（Go CLI） |
|---|---|---|---|---|---|---|
| F1 ABI/triple 命名 | ✓ 4 ABI 纯值映射（B2） | ✓ 内部推导并设置环境变量 | ✓ ANDROID_ABI→编译器/ sysroot | ✗ 无 Android 目标（仅 linux/darwin/windows 桌面） | ✓ abiFilters | ✓ GOARCH→NDK clang |
| F2 配置值生成 | ✓ 纯值、零 I/O（B4） | 部分：生成环境变量后**执行 cargo build** | 文件即配置，由 CMake 消费执行 | 写 cc/ar wrapper 后**执行 moon build** | DSL 声明后驱动 CMake/ndk-build | 直接驱动 go build |
| F3 确定性文本渲染 | ✓ moon.pkg DSL 片段 + golden（B5） | ✗ 不产出配置文本 | ✗（自身是被消费的文件） | ✗ | ✗ | ✗ |
| F4 校验报告 | ✓ errors/warnings 分值化（B7） | 构建期报错 | ✓ 工具链文件内 ABI/API 合法性检查 | ✓ doctor 结构化 JSON 诊断（0/1/2 退出码） | Gradle 配置期校验 | 构建期报错 |
| F5 CLI 参数/退出码 | ✓ 0/1/2 契约实跑验证（B13） | ✓ | n/a（CMake 参数） | ✓（invalid args=2） | n/a | ✓ |
| F6 幂等受管块合并 | ✓ 三态 + 块外保留（B14） | ✗ | ✗ | ✗ | ✗（Gradle 文件由用户自管） | ✗ |
| F7 注入式/真实写配置 | ✓ 双通道（B16/B17） | ✗ | ✗ | ✗ | ✗ | ✗ |
| F8 只读 NDK 探测 | ✓ 纯核心+FS 包装、结构化输出（B18/B20） | ✓ 读 ANDROID_NDK_HOME 定位 | ✗（路径由调用方给定） | ✓ doctor 探测工具链（含版本指纹） | ✓ SDK/NDK 自动定位 | ✓ ANDROID_HOME/ANDROID_NDK_ROOT |
| F9 错误模型 | ✓ 11 变体冻结（B8） | anyhow 类通用错误 | CMake message | findings code/severity 结构化 | Gradle 异常 | Go error |
| F10 路径风格推断 | ✓（B12 相关、windows_path_style_of） | 宿主 OS 决定 | 宿主 OS 决定 | 仅 Linux/macOS 宿主（Windows 上停止） | 宿主 OS 决定 | 宿主 OS 决定 |
| 多 ABI 批量 | ✗ 单次单 ABI（B11 缺口） | ✓ `-t` 可重复 | 单 ABI 单配置 | ✓ 多 target 一次 | ✓ abiFilters 列表 | ✓ 多架构 |
| 宿主覆盖 | win/linux x86_64（B22 缺口） | 全宿主 | 全宿主（含 darwin） | linux/darwin（windows 交叉仅头校验） | 全宿主 | 全宿主 |

- 证据等级：cargo-ndk 行为 [已知常识]（2026-11-16 多篇公开实战文章交叉印证；版本/star/维护状态 [需联网核实]）；NDK CMake 工具链参数与行为 [已知常识]（developer.android.com/ndk/guides/cmake 官方文档，本轮经镜像站核对）；zig-cross 0.4.1 目标表/宿主限制/doctor 契约 [仅据本轮 mooncakes 包页核验]（版本号/下载数/更新时间为易变事实 [需联网核实]；申报时参照的 0.3.2 已非 latest）；AGP/gomobile [已知常识]（NDK 版本兼容矩阵等易变细节 [需联网核实]）。
- 最接近 1–3 名与重叠度：**cargo-ndk**（重叠最高：NDK 定位 + wrapper 命名 + API level 注入，但它以执行构建为终点，不产出可审计配置文本）；**NDK 官方 CMake 工具链文件**（职责同构：把 ABI/API 约束变成工具链配置，但形态是被 CMake 消费的执行脚本，非纯值）；**zig-cross**（同语言同生态、doctor 结构化诊断与退出码契约神似，但目标域不含 Android，且执行构建）。
- 差异化判断：本模块是「**配置即值**」路线——generate/render/validate 纯函数、输出确定性 moon.pkg DSL 文本、受管块幂等落盘、探测只读且事实/判定分层；对标全部以「驱动一次构建」为终点。组合语义（MoonBit + 纯值 + 不执行构建 + 受管块合并）在调研渠道内未见同类。
- 缺失能力清单：已声明非目标 = 执行构建/产出 .so/zig-cross 路线/自动加引号/安装 NDK；真缺口 = 多 ABI 批量与 CLI extra 选项（B11）、darwin 宿主（B22）、API 上限矩阵（B23）、tab/换行与多 END fail-open（B6/B15）、版本键误命中（B19）、死变体与簿记（B9/B10）、文本记录行转义局限未文档化（B21）。

## 3. 边界裁决（P3 结论）

**本质职责（一句话）**：把 Android NDK 交叉编译约束变成**确定性、可校验、可粘贴的配置值与文本**——只回答「配置应该是什么、可信吗」，永不回答「怎么构建」。

**边界判据**：输出是否停留在「配置事实/值/文本」层面且不触发、不决策构建执行；副作用是否仅限只读探测与受管块内幂等写。凡满足者界内；凡需要调用工具链、改写用户语义、猜测修复损坏配置者界外。

| 灰区 | 判据结论 | 裁决 | 落点（W#） |
|---|---|---|---|
| G1 probe 环境探测与 SDK 管理器职责重叠 | 界内（只读事实，不安装/不下载/不决策） | 冻结现有 API + README 归属声明「探测仅报告事实」；外部一致性锁：候选优先级/记录行格式进 golden | W1（声明）、W6（oracle 不改探测） |
| G2 sync_config_file 写盘与构建系统文件管理重叠 | 界内（仅受管块，块外逐字保留） | 冻结 + 块外不变量固化为恒等式断言；多 END fail-open 属损坏输入静默放行 → fail-closed 加固 | W3 |
| G3 NdkNotFound 死变体 vs CLI Err(String) 双通道 | 界内（错误模型统一性） | **已裁决 A（2026-11-16）**：接线（消息/退出码逐字节不变）；变体冻结不删 | W2 |
| G4 tab/换行 token、Pkg.Revision 前缀误命中 | 界内（输入安全/完整性） | fail-closed 修复例外：复用 PathContainsSpace/MalformedConfig/None 回退，零新变体；CHANGELOG 登记 + 回归确认仅受影响样本变化 | W3 |
| G5 宿主平台/API 矩阵纵深与「21 统一下限」语义 | 界内但须防火墙 | 旧 generate/validate 语义冻结；新函数新类型（NdkHost/generate_with_host/api_level_advisory）承载纵深 | W5 |
| G6 E3 真实构建差分（生成片段是否真能编出 .so） | 界外（触发构建执行） | 归属组合根；本库侧仅以**脚本层可选 oracle**（本地 NDK + 显式 SKIPPED + 哈希登记）做只读差分，不进库 API、不进通过计数 | W6（已裁决 A） |
| G7 文本记录行路径含 `|`/换行的歧义 | 界内（契约稳定） | 现有格式冻结不改；W1 在 README 显式文档化局限；如需转义走未来新函数，不在本轮 | W1 |

## 4. 工作包总览

| 包 | 名称 | 优先级 | 规模 | API 影响 | 对应缺口（B#） |
|---|---|---|---|---|---|
| W1 | 漂移清理与文档自包含 | P0 | S | 无（纯文档/注释/CI 文案） | B26-B34、B21、B35 |
| W2 | 错误簿记补齐与 NdkNotFound 接线（已裁决 A，已交付） | P0 | S | 加法：resolve_ndk_values（语言约束偏差，见 W2 回写） | B9、B10 |
| W3 | fail-closed 输入加固 | P1 | S | 无（内部行为增强，复用既有变体） | B6、B15、B19 |
| W4 | CLI 扩展：extra 选项与多 ABI | P1 | M | 加法：GenCommandExt / parse_gen_args_ext / generate_multi | B11 |
| W5 | 宿主平台与 API 矩阵纵深 | P2 | M | 加法：NdkHost / host_tag / generate_with_host / api_level_advisory | B22、B23 |
| W6 | 外部 oracle 本地 runner（已裁决 A） | P2 | L | 无（脚本层，零 API） | B13 纵深、G6 |

## 5. 工作包详细设计

### W1 漂移清理与文档自包含（P0/S）

**目标**：消除 B26-B34 全部已登记漂移，使文档/注释/CI 文案与代码现状一致且自包含。
**非目标**：不改任何 .mbt 逻辑代码（仅注释）；不恢复已删除的 docs/ 历史四件套（README 为唯一入口的裁决维持）。
**新增 API**：无。
**实现要点**：
- ci.yml L122：`docs/API.md` → 改为「README.md §3 API 索引」；L16：`.r1` 句改为历史说明（「R1 基线存档已于发布前清理删除，不在 diff 范围」）；L29 与 copilot-setup-steps.yml L7：删除 bobzhang/zip 示例，改为「本模块零第三方依赖；如未来引入，按 moon.mod 钉死版本声明由 check/build 自动同步」。
- moon_abi.mbt L94-95 注释：删除外部仓库符号引用，改为自足表述（「21 为 r22+ 全系 NDK 的保守安全下限；精确版本策略由调用方 profile 持有」）。
- README §3 索引补齐 4 条（probe_ndk/sync_config_file/to_repr/ConfigRenderer），抽取口径改为「全部 pub 声明（含 async/方法/trait）」；§4 依赖口径补 debug/env/test 注记；L4「唯一说明文档」→「唯一入口文档；带日期的开发/测试文档见 docs/」；§6 补 B21 记录行局限声明与提交数 16 口径。
- 新建 docs/CHANGELOG.md，登记 W1（日期/工作包/新增 pub 声明=无/快照 diff=空/测试增量=0）。
- 本文与配套测试文档即 W1 交付物的一部分；历史申报口径修正以本文 §0 为准（申报文档在仓库外，不回写）。
**验收**：T-W1-1（引用实存性扫描零失效）、T-W1-2（README 索引 ↔ mbti 逐条一致）、T-W1-3（五门禁绿 + 快照 diff 空）、T-W1-4（CHANGELOG 建立并登记）。

### W2 错误簿记补齐与 NdkNotFound 接线（P0/S，已裁决 A，已交付）

**目标**：错误变体显式簿记 11/11（B10）；消除 NdkNotFound 死变体状态（B9）。——均已达成（2026-11-16）。
**非目标**：不新增/删除任何变体；不改退出码集合与消息文本。——均满足。
**新增 API**：`resolve_ndk_values`（纯加法，语言约束下的必要偏差，见下方回写）。
**裁决（2026-11-16 用户确认采纳推荐项 A，已交付）**：
- **A（采纳，已落地）**：判定逻辑下沉为库内新纯函数 `resolve_ndk_values(GenCommand, NdkProbeResult) -> (String, String) raise MoonAbiError`（NdkNotFound 的唯一 raise 点，消息与历史文案逐字一致）；cmd/main `resolve_ndk` 委托该函数，失败经 `error_message` 归一为单行 stderr（退出码 1）；probe 自身失败属异步基础设施通道，保留 String 旁路（文案不变）。旧 API 零变化，防火墙实测通过。
  - **偏差回写（语言约束，实测发现）**：① 原草案「零新增 API、cmd 内构造 NdkNotFound」不可行——MoonBit `pub suberror` 变体在定义包外只读（错误 4036），cmd/main 无法构造，故新增库内纯函数承载 raise（纯加法，快照 +2 行，CHANGELOG 已登记）；② 原草案「经 report_lib 落地」会附加 usage 提示行（第二行 stderr）破坏逐字节一致，改为单行 `error: <message>`；③ `--deny-warn` 的 result_error_return lint 禁止 `Result[T, MoonAbiError]` 返回形态，CLI 维持 `Result[T, String]` 归一；④ 构造级断言只能落库包内 whitebox 测试（ndk_resolve_wbtest.mbt），黑盒/跨包构造均只读。
- B（零成本降级，未采纳，存档备选）：实现不动；补构造级显式用例；README 声明该变体为「预留」。
- C（未采纳）：维持现状。
**实现要点（实测落地）**：CliUsage 显式变体断言 6 例（gen_cli_test.mbt）；NdkNotFound 触发级 2 例（ndk_resolve_test.mbt 注入式探测结果，含历史 CLI 无法确定性构造的 not-found 路径）+ 构造级 1 例（ndk_resolve_wbtest.mbt）；resolve_ndk_values 行为样例共 6 例；簿记表（测试文档 §6.2）已刷新为 11/11。
**验收（实测结果）**：T-W2-1 ✓（11/11 显式变体断言）；T-W2-2 ✓（两条失败路径 stdout/stderr SHA-256 与基线一致、exit=1）；T-W2-3 ✓（触发 2 例 + 构造 1 例）。测试增量 +8（68→76），旧用例零改动全绿；快照 diff 纯加法。

### W3 fail-closed 输入加固（P1/S，已交付 2026-11-26）

**目标**：关闭 B6/B15/B19 三处静默放行。——已达成（2026-11-26）。
**非目标**：不新增错误变体；不改合法输入的任何输出；不做自动引号/自动修复。——均满足。
**新增 API**：无（mbti diff 为空，双快照零漂移）。
**实现要点**：
- `check_no_space` 扩展为拒绝全部空白字符（空格/tab/CR/LF/垂直制表/换页），复用 `PathContainsSpace(token)`；`validate` 的空格检查同步扩展（含 ndk_root 为空分支外的 extra token 检查维持现序）。错误消息不变（仍 "path contains a space: …"，消息文本冻结）。
- `merge_link_config`：统计 BLOCK_END 出现次数 ≥2 → `MalformedConfig("multiple managed block end markers")`（复用变体，新消息文本属加法）。
- `parse_pkg_revision`：前缀命中后要求下一字符为 `=` 或空白，否则继续扫描；`Pkg.RevisionFoo` 不再误命中，回退目录名/None 路径不变。
- 三项均属 fail-closed 修复例外：CHANGELOG 显式登记「以前静默放行的损坏/不安全输入现在拒绝」；回归确认既有 68 用例零改动全绿、仅含 tab/换行/多 END/误命中键的构造样本行为变化。
**验收（实测结果）**：T-W3-1 ✓（render 全空白字符 token 抛 PathContainsSpace，validate 含 tab 报 PathContainsSpace）；T-W3-2 ✓（多 END → MalformedConfig）；T-W3-3 ✓（Pkg.RevisionFoo 不误命中）；T-W3-4 ✓（旧用例零改动全绿，wasm/native 各 86/86）；T-W3-5 ✓（截断/变异扫描无 panic，新解析路径随包一行接入扫描）。测试增量 +5（81→86），快照 diff 空。

### W4 CLI 扩展：extra 选项与多 ABI（P1/M）

**目标**：落地历史「后续」清单（B11）：`--extra-lib`/`--extra-cc-flag` 多值、一次生成多 ABI。
**非目标**：不改 `parse_gen_args`/`GenCommand` 语义与字段；不支持多 ABI 写单文件（受管块单块契约冻结）；不做 ABI 间依赖推导。
**新增 API（mbti 草案，纯加法）**：

```text
pub(all) struct GenCommandExt {
  base : GenCommand
  abis : Array[Abi]
  extra_link_libs : Array[String]
  extra_cc_flags : Array[String]
}
pub fn parse_gen_args_ext(ArrayView[String]) -> GenCommandExt raise MoonAbiError
pub fn generate_multi(NdkProfile, Array[Abi]) -> Array[LinkNativeConfig] raise MoonAbiError
```

**实现要点**：
- 新文件 gen_cli_ext.mbt：`parse_gen_args_ext` 复用既有 split_flag/take_flag_value/abi_from_name/parse_api_level_value；`--abi` 可重复（≥1，去重保序），`--extra-lib`/`--extra-cc-flag` 可重复（原序收集，空值→CliUsage）；其余选项语义与旧解析器逐字一致；`base` 由旧解析逻辑等价构造（base.abi=abis[0]）。旧 `parse_gen_args` 一行不动。
- `generate_multi`：空数组→CliUsage；按输入序逐个 generate（错误原样传播，首个失败即抛）；纯函数、确定性。
- cmd/main 切换到新解析器：旧参数组合的 stdout/stderr/退出码/落盘内容逐字节不变（防火墙 T-W4-4）；多 ABI + `--out` → CliUsage（退出码 2，消息明示单块契约）；多 ABI stdout 按序打印多个受管块（块间单空行分隔，格式进 golden）。
- extra 选项含空格 token 由 render 既有 PathContainsSpace 拒绝（W3 后含全部空白）。
**验收**：T-W4-1（新选项解析 + 旧参数 base 等价）、T-W4-2（generate_multi 顺序/确定性/空数组错误）、T-W4-3（--out+多 ABI → 退出码 2）、T-W4-4（旧 CLI 17 场景逐字节防火墙）、T-W4-5（快照 diff 纯加法 + CHANGELOG）。

**验收（实测结果）**：T-W4-1 ✓（base 与旧 `parse_gen_args` 逐字段指纹等价；多 ABI 去重保序；extra 原序；空值→CliUsage 退出码 2）；T-W4-2 ✓（generate_multi 按输入序、确定性、extra 落到 flags、空数组→CliUsage 退出码 2）；T-W4-3 ✓（多 ABI+`--out`→CliUsage 退出码 2 且零落盘；去重后单 ABI+`--out` 仍合法）；T-W4-4 ✓（17 场景逐字节防火墙全符合：version=0、unknown-sub=2、missing-abi=2、r21=1、probe-bad-opt=2、probe-notfound=1、out-first=0、out-idempotent=0、out-malformed=1 且原文件未改写、out-missing-dir=1、bad-abi=2、api20=2、space-path=1、multi-end out=1）+ W4 新场景（multi-stdout=0 两块单空行、multi-out=2）；T-W4-5 ✓（快照 diff 纯加法 +3 声明 +1 struct，CHANGELOG 已登记）。测试增量 +8（86→94；wasm/native 各 94/94，旧用例零改动全绿，#skip=0）。

### W5 宿主平台与 API 矩阵纵深（P2/M）

**目标**：补 darwin 宿主（B22）与 API 上限 advisory（B23），全部走新函数防火墙。
**非目标**：不改 generate/validate/cc_path 旧语义；不做 NDK 版本自动下载/探测绑定；advisory 只产警告不阻断。
**新增 API（mbti 草案，纯加法）**：

```text
pub(all) enum NdkHost {
  WindowsX86_64
  LinuxX86_64
  DarwinX86_64
}
pub fn host_tag(NdkHost) -> String
pub fn generate_with_host(NdkProfile, Abi, NdkHost) -> LinkNativeConfig raise MoonAbiError
pub fn api_level_advisory(NdkProfile) -> Array[String]
```

**实现要点**：
- `host_tag`：windows-x86_64 / linux-x86_64 / darwin-x86_64。darwin 标签与「NDK r22+ macOS prebuilt 目录名」[需联网核实]（合入前以 NDK 官方文档/真实安装目录核对，核对结论登记 CHANGELOG；若核实不符则仅调整新函数数据表，旧 API 不受影响）。
- `generate_with_host`：分隔符与宿主标签均由 NdkHost 决定（Windows→`\`，其余→`/`），**忽略** profile.windows_path_style（新函数文档明示）；其余注入逻辑与 generate 一致；旧 generate 委托关系不动。
- `api_level_advisory`：内置「NDK major → 已知最高 API」保守数据表（r22→30、r23→31、r24→32、r25→33、r26→34、r27→35；各值 [需联网核实]，合入前逐项核对官方文档）；level 高于表值→警告串；版本不可解析或 major 不在表内→空数组（不猜测）；纯函数、确定性、不阻断。
**验收**：T-W5-1（三宿主 golden 路径/标签）、T-W5-2（旧 generate 输出逐字节不变）、T-W5-3（advisory 边界：未知版本零警告/超上限告警/恰等于上限零警告）、T-W5-4（快照 diff 纯加法 + CHANGELOG）。

**验收（实测结果）**：T-W5-1 ✓（三宿主标签与 golden cc 路径逐字断言）；T-W5-2 ✓（win/linux 与旧 `generate` cc/flags/link-flags 逐字节一致）；T-W5-3 ✓（banana/r28 零警告、r27@35 零警告、r27@36 告警、r22@30 零警告/r22@31 告警、27.0.12077973@36 告警）；T-W5-4 ✓（快照 diff 纯加法 +4 声明，CHANGELOG 已登记；darwin 标签与 NDK major→API 表 2026-11-26 联网核实结论见 CHANGELOG）。测试增量 +5（94→99；wasm/native 各 99/99，旧用例零改动全绿，#skip=0）。

### W6 外部 oracle 本地 runner（P2/L，已裁决 A）

**目标**：在许可与边界约束内回答「生成的配置真的能被 moon + NDK 消费吗」（G6/E3 的模块侧只读差分）。
**非目标**：不把工具链调用引入库 API；不在 CI 通过计数中计入真实构建结果；不入库任何第三方 NDK/产物。
**新增 API**：无（tools/ 脚本层）。
**裁决（2026-11-16 用户确认采纳推荐项 A）**：
- **A（采纳）**：建 tools/oracle-run.ps1（仓库自包含）：输入=仓库外 NDK 根路径 + SHA-256 登记文件；哈希不符拒绝执行；在系统临时目录构造最小 MoonBit 项目（确定性自产源码），粘贴 generate+render 产物为 moon.pkg，跑 `moon build --target native`；成功/失败均输出结构化差分报告（NDK 哈希+日期+工具链版本+退出码）；NDK 缺失→显式 SKIPPED（退出码 78 口径），永不计入通过。
- B（降级，未采纳，存档备选）：仅做 `moon check` 级语法 oracle（不触发 C 编译，验证 DSL 可解析），真实构建差分维持「E3 未决」登记。
- C（零成本，未采纳）：不建 runner；README 维持 E3 未决声明，测试文档 L3/R 层全部标「未实现」。
**实现要点（A）**：脚本不引用仓库外目录（样本路径由参数注入）；临时项目用后即焚；报告落 tools/oracle-reports/（.gitignore 排除产物，仅保留报告模板）；入库 #skip 占位用例保留不删。
**验收**：T-W6-1（有 NDK→差分报告；无 NDK→显式 SKIPPED）、T-W6-2（哈希不符拒绝执行）、T-W6-3（SKIPPED 不进通过计数）。

**验收（实测结果）**：T-W6-1 ✓（无 NDK→SKIPPED 退出码 78 + 结构化报告；假 NDK + 通过哈希门→gen 成功并执行 `moon build --target native`，因假 cc 不存在 FAIL 退出码 1，报告含 NDK 哈希/版本/工具链/退出码）；T-W6-2 ✓（错误哈希→FAIL 退出码 1，`SHA-256 mismatch ... refuse to execute`，不进入构建）；T-W6-3 ✓（SKIPPED 报告 `counted_as_pass=false`，退出码 78，脚本不参与 `moon test` 通过计数）。无新增 pub 声明、快照 diff 空。真实 NDK 下的 E3 成功路径需在装有 NDK 的机器复验（本机无 NDK，按设计 SKIPPED）。

## 6. 里程碑与合入顺序

```text
M0（第1日）   W1 漂移清理（零风险）＋ W2-A 落地（簿记补齐 + NdkNotFound 接线）
M1            W3 fail-closed 加固（安全缺口，行为增强例外流程）✅ 已交付 2026-11-26
M2            W4 CLI extra/多 ABI（高价值低成本，历史「后续」清单）✅ 已交付 2026-11-26
M3            W5 宿主/API 矩阵纵深（数据表先联网核实再合入）✅ 已交付 2026-11-26
M4            W6-A 外部 oracle runner（已裁决 A，M3 后启动）✅ 已交付 2026-11-26
```

排序判据：先零风险文档、再安全缺口、再高价值低成本、最后安全敏感/大件；每包独立提交、独立过五门禁；W2/W6 已于 2026-11-16 裁决（均采纳 A）。

## 7. 簿记与变更管理

- docs/CHANGELOG.md（W1 建立）：每包登记「日期/工作包/新增 pub 声明/快照 diff 结论/测试增量」；W3 另登记 fail-closed 行为增强条目与受影响样本清单。
- README API 索引随 moon info 快照同步（禁手编 mbti）；索引抽取口径含 async/方法/trait（W1 修正）。
- 破坏性需求一律走四件例外流程（ADR+用户裁决+CHANGELOG+主版本）；本轮六包均无破坏性需求。
- 易变事实（NDK 版本矩阵、darwin 标签、对标库版本）核实后在 CHANGELOG 登记核实日期与来源。

## 8. 完成定义（DoD，逐包勾选）

> M0–M4 全部六包均已交付（2026-11-26），逐项核验通过。
> M4/W6-A：脚本层 `tools/oracle-run.ps1` 落地；T-W6-1..3 实测（无 NDK→SKIPPED 78、错误哈希→拒绝 1、
> SKIPPED 不计通过）；无新增 pub 声明、快照 diff 空；零第三方 NDK/产物入库；报告目录 .gitignore 排除产物。
> 真实 NDK 下 E3 成功路径已于 2026-11-26 在 WSL/Linux 宿主取得 PASS（见 B40）；Windows 宿主受
> package-level cc 不改变共享 runtime 目标与 core `platform` cfg 限制，保持 FAIL 取证；可加载 `.so`
> 的 CMake/组合根集成仍不在本库范围。

- [x] 新增 API 与 mbti 草案一致（偏差回写本文）—— W3 无新增；W4 三声明一 struct；W5 一 enum 三函数；W6 脚本层无 API，均与草案逐字一致
- [x] 快照 diff 纯加法（W1/W2/W3 为空 diff；W4 +3 声明 +1 struct；W5 +4 声明；W6 空 diff），CHANGELOG 已登记
- [x] T-W*-* 验收全绿；#skip 显式标注原因（#skip=0）
- [x] 五门禁全绿；CLI 对外契约零意外漂移（退出码矩阵 + 记录行格式 + 消息文本）
- [x] 防火墙回归：新函数合入后旧 API 在既有语料上输出逐字节不变/旧用例零改动全绿
- [x] 畸形语料无 panic（新增解析路径进截断扫描）
- [x] 零新第三方依赖；零许可不明二进制入库
- [x] README 能力/非目标同步；本文状态行更新「已交付+日期」

## 9. 风险登记

| 风险 | 等级 | 缓解 |
|---|---|---|
| W3 fail-closed 改变下游含 tab/换行样本的行为 | 中 | 已执行（M1 落地 2026-11-26）：CHANGELOG 显式登记受影响样本清单；回归确认仅受影响样本变化、旧用例零改动全绿；消息文本与退出码集合冻结（CLI 冒烟复跑符合契约） |
| W4 cmd 解析器切换引入旧参数行为漂移 | 中 | T-W4-4 十七场景逐字节防火墙差分；base 构造与旧解析器等价性单测 |
| W5 darwin 标签/API 矩阵数据未核实即合入 | 中 | 数据表逐项 [需联网核实] 前置；核实前 W5 不合入；新函数隔离，旧 API 零风险 |
| W2 选项 A 改动 CLI 错误通道 | 低 | 消息/退出码逐字节断言；选项 B 零成本降级随时可退 |
| W6 oracle 触发真实工具链被误读为库行为 | 低 | 脚本层隔离 + 显式 SKIPPED + 报告不计入通过计数；README 归属声明 |
| mooncakes 渠道不可穷举导致「未见同类」过强 | 低 | §2 已限定语言+组合语义+时点+渠道；结论随核实更新 |