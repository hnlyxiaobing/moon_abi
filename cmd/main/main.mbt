///|
/// `moon-abi` CLI 入口：gen（生成/写入 link 配置）与 probe（本机 NDK 探测）。
///
/// 契约：
/// - 退出码 `0` 成功 · `2` 用法/参数错误 · `1` 运行/环境/IO 错误
///   （NDK 未找到、版本不匹配、读写失败；probe 未找到 NDK 亦为 1）。
/// - `gen` 默认只读打印受管配置块；`--out <path>` 写入/幂等替换该文件的受管块。
/// - 所有业务逻辑在 `hnlyxiaobing/moon_abi` 库内（纯函数 + 注入式 I/O），本文件只做
///   进程参数/环境变量接线与退出码落地。
///
/// 注：MoonBit 的 async 调用在跨包边界携带 `Error` 错误通道，因此本文件的 async
/// 调用一律 `catch` 归一（库内 `MoonAbiError` 用 `report_lib` 保留 2/1 契约，
/// 其余 I/O 失败统一 1）。

///|
let tool_name = "moon-abi"

///|
let tool_version = "0.1.0"

///|
fn usage_text() -> String {
  let lines : Array[String] = [
    tool_name +
    " " +
    tool_version +
    " — Android NDK link.native config generator",
    "",
    "Usage:",
    "  " + tool_name + " gen --abi <abi> --api <level> [options]",
    "  " + tool_name + " probe [--json]",
    "  " + tool_name + " --help | --version",
    "",
    "gen options:",
    "  --abi <name>        repeatable, >=1; armeabi-v7a|armv7 | arm64-v8a|arm64 | x86 | x86_64|x64",
    "  --api <level>       Android API level, >= 21",
    "  --ndk-root <path>   NDK root (else probe ANDROID_NDK_HOME/ANDROID_HOME/common paths)",
    "  --ndk-version <ver> NDK version, e.g. r27c or 27.0.12077973 (else read from NDK)",
    "  --out <path>        write/merge into moon.pkg instead of printing to stdout",
    "  --path-style <s>    auto|windows|unix (default auto, inferred from ndk root)",
    "  --host <h>          windows|linux|darwin (default: path style, darwin on macOS)",
    "  --extra-lib <name>  repeatable; append -l<name> to link libraries (log,android are default)",
    "  --extra-cc-flag <f> repeatable; extra cc flags appended after --target",
    "",
    "Exit codes: 0 success | 2 usage/argument error | 1 runtime/env/IO error",
    "",
  ]
  let mut out = ""
  for line in lines {
    out = out + line + "\n"
  }
  out
}

///|
/// 空串（含仅空白）视为未设置。
fn non_blank(value : String?) -> String? {
  match value {
    Some(s) => if s.trim().is_empty() { None } else { Some(s) }
    None => None
  }
}

///|
/// 第一个非空值。
fn first_some(a : String?, b : String?) -> String? {
  match a {
    Some(_) => a
    None => b
  }
}

///|
/// 从进程环境变量构造探测输入；`explicit_root` 来自 `--ndk-root`。
fn env_inputs(explicit_root : String?) -> @moon_abi.NdkProbeInputs {
  let home = first_some(
    non_blank(@env.get_env_var("USERPROFILE")),
    non_blank(@env.get_env_var("HOME")),
  )
  {
    explicit_root: non_blank(explicit_root),
    ndk_home: non_blank(@env.get_env_var("ANDROID_NDK_HOME")),
    android_home: non_blank(@env.get_env_var("ANDROID_HOME")),
    android_sdk_root: non_blank(@env.get_env_var("ANDROID_SDK_ROOT")),
    home_dir: home,
    local_app_data: non_blank(@env.get_env_var("LOCALAPPDATA")),
  }
}

///|
/// 库错误（`MoonAbiError`）：打印人读消息并保留 2/1 退出码契约。
fn report_lib(err : @moon_abi.MoonAbiError) -> Int32 {
  eprintln("error: " + @moon_abi.error_message(err))
  eprintln("run '" + tool_name + " --help' for usage")
  @moon_abi.exit_code_for_error(err)
}

///|
/// 其余错误（进程/异步/IO 通道）：能识别为库错误时打印人读消息，统一退出码 1。
fn report_error(err : Error) -> Int32 {
  let message = match err {
    @moon_abi.MoonAbiError::UnsupportedAbi(name) => "unsupported ABI: " + name
    @moon_abi.MoonAbiError::UnsupportedApiLevel(got, min) =>
      "API level " + got.to_string() + " is below minimum " + min.to_string()
    @moon_abi.MoonAbiError::MissingNdkRoot => "missing NDK root"
    @moon_abi.MoonAbiError::MissingClang(path) => "missing clang: " + path
    @moon_abi.MoonAbiError::PathContainsSpace(path) =>
      "path contains a space: " + path
    @moon_abi.MoonAbiError::InvalidTriple(triple) =>
      "invalid target triple: " + triple
    @moon_abi.MoonAbiError::VersionMismatch(expected, actual) =>
      "expected NDK " + expected + ", got " + actual
    @moon_abi.MoonAbiError::CliUsage(reason) => reason
    @moon_abi.MoonAbiError::IoFailure(path, reason) =>
      "I/O failure at " + path + ": " + reason
    @moon_abi.MoonAbiError::MalformedConfig(reason) =>
      "malformed managed config: " + reason
    @moon_abi.MoonAbiError::NdkNotFound(detail) => detail
    _ => err.to_string()
  }
  eprintln("error: " + message)
  eprintln("run '" + tool_name + " --help' for usage")
  1
}

///|
/// 解析 NDK 根与版本：命令行显式值优先，缺失时用本机探测补齐。
/// 判定委托库纯函数 `resolve_ndk_values`（失败抛 NdkNotFound，W2-A）；
/// 本函数把错误归一为可读原因（CLI 映射为退出码 1，stderr 单行与历史逐字节一致）。
/// probe 自身失败属异步基础设施通道，保留 String 旁路（文案不变）。
async fn resolve_ndk(
  cmd : @moon_abi.GenCommand,
) -> Result[(String, String), String] {
  let mut probe : @moon_abi.NdkProbeResult = {
    found: false,
    selected: None,
    version: None,
    candidates: [],
    warnings: [],
  }
  if cmd.ndk_root is None || cmd.ndk_version is None {
    probe = @moon_abi.probe_ndk(env_inputs(cmd.ndk_root)) catch {
      e => return Err("NDK probe failed: " + e.to_string())
    }
  }
  let pair = @moon_abi.resolve_ndk_values(cmd, probe) catch {
    e => return Err(@moon_abi.error_message(e))
  }
  Ok(pair)
}

///|
/// 当前运行平台的 NDK prebuilt 宿主标签（CLI 默认宿主推断用）。
/// 仅 native 后端区分平台；wasm 构建（`moon check` 等）回退 linux 以保证可编译，
/// 该分支不参与实际 CLI 运行。
#cfg(platform="windows")
fn current_platform_host() -> @moon_abi.NdkHost {
  @moon_abi.NdkHost::WindowsX86_64
}

///|
#cfg(platform="macos")
fn current_platform_host() -> @moon_abi.NdkHost {
  @moon_abi.NdkHost::DarwinX86_64
}

///|
#cfg(all(target="native", not(platform="windows"), not(platform="macos")))
fn current_platform_host() -> @moon_abi.NdkHost {
  @moon_abi.NdkHost::LinuxX86_64
}

///|
#cfg(not(target="native"))
fn current_platform_host() -> @moon_abi.NdkHost {
  @moon_abi.NdkHost::LinuxX86_64
}

///|
/// `gen` 主流程：解析参数（多 ABI + extra + 宿主）→ 补齐 NDK → 生成配置 → 打印或幂等写文件。
///
/// W4：切换到扩展解析器；旧参数组合（单 ABI、带 `--out`、路径风格覆盖等）的
/// stdout/stderr/退出码/落盘内容与旧解析器逐字节一致（防火墙 T-W4-4）。
/// 多 ABI + `--out` 在库解析层已抛 `CliUsage`（退出码 2），此处错误通道不变。
async fn gen_impl(rest : ArrayView[String]) -> Int32 {
  let parsed = @moon_abi.parse_gen_args_with_host(rest) catch {
    e => return report_lib(e)
  }
  let ext = parsed.command
  let (ndk_root, ndk_version) = match resolve_ndk(ext.base) {
    Ok(pair) => pair
    Err(reason) => {
      eprintln("error: " + reason)
      return 1
    }
  }
  let windows_path_style = match ext.base.path_style {
    @moon_abi.PathStyle::Auto => @moon_abi.windows_path_style_of(ndk_root)
    @moon_abi.PathStyle::Windows => true
    @moon_abi.PathStyle::Unix => false
  }
  let profile = @moon_abi.NdkProfile::{
    ndk_root,
    ndk_version,
    api_level: ext.base.api_level,
    extra_link_libs: ext.extra_link_libs,
    extra_cc_flags: ext.extra_cc_flags,
    windows_path_style,
  }
  let host = match parsed.host {
    Some(h) => h
    None =>
      match ext.base.path_style {
        // 显式 --path-style 维持旧语义：windows → windows，unix → linux（可跨宿主生成）。
        @moon_abi.PathStyle::Windows => @moon_abi.NdkHost::WindowsX86_64
        @moon_abi.PathStyle::Unix => @moon_abi.NdkHost::LinuxX86_64
        // auto：Windows 风格根沿用旧行为；unix 风格根在 macOS 上修正为 darwin。
        @moon_abi.PathStyle::Auto =>
          @moon_abi.resolve_default_host(
            windows_path_style,
            current_platform_host(),
          )
      }
  }
  let configs = @moon_abi.generate_multi_with_host(profile, ext.abis, host) catch {
    e => return report_lib(e)
  }
  let blocks : Array[String] = []
  for c in configs {
    blocks.push(@moon_abi.managed_block(c) catch { e => return report_lib(e) })
  }
  match ext.base.output {
    @moon_abi.GenOutput::Stdout => {
      let trimmed = blocks.map(fn(b) { b.trim_end(chars="\n").to_owned() })
      // 单 ABI：与旧实现 `println(block.trim_end("\n"))` 逐字节一致；
      // 多 ABI：按输入序打印，块间单空行分隔（`join("\n\n")`）。
      println(trimmed.join("\n\n"))
      0
    }
    @moon_abi.GenOutput::File(path) => {
      let merged = @moon_abi.sync_config_file(path, blocks[0]) catch {
        e => return report_error(e)
      }
      println(path + ": " + @moon_abi.merge_action_name(merged.action))
      0
    }
  }
}

///|
/// `gen` 子命令：async 调用错误归一为退出码。
async fn cmd_gen(rest : ArrayView[String]) -> Int32 {
  gen_impl(rest) catch {
    e => report_error(e)
  }
}

///|
/// `probe` 子命令：结构化输出本机 NDK 探测结果；未找到返回 1。
async fn cmd_probe(rest : ArrayView[String]) -> Int32 {
  let mut json = false
  for arg in rest {
    if arg == "--json" {
      json = true
    } else if arg == "--help" || arg == "-h" {
      println(usage_text().trim_end(chars="\n").to_owned())
      return 0
    } else {
      eprintln("error: unknown option for probe: " + arg)
      return 2
    }
  }
  let result = @moon_abi.probe_ndk(env_inputs(None)) catch {
    e => return report_error(e)
  }
  if json {
    println(@moon_abi.ndk_probe_json(result))
  } else {
    println(@moon_abi.ndk_probe_text(result))
  }
  if result.found {
    0
  } else {
    1
  }
}

///|
/// 子命令分发。
async fn run(args : Array[String]) -> Int32 {
  if args.length() < 2 {
    println(usage_text().trim_end(chars="\n").to_owned())
    return 2
  }
  let sub = args[1]
  let rest = args[2:]
  if sub == "gen" {
    cmd_gen(rest) catch {
      e => report_error(e)
    }
  } else if sub == "probe" {
    cmd_probe(rest) catch {
      e => report_error(e)
    }
  } else if sub == "--help" || sub == "-h" || sub == "help" {
    println(usage_text().trim_end(chars="\n").to_owned())
    0
  } else if sub == "--version" {
    println(tool_name + " " + tool_version)
    0
  } else {
    eprintln("error: unknown subcommand: " + sub)
    eprintln("run '" + tool_name + " --help' for usage")
    2
  }
}

///|
async fn main {
  let code = run(@env.args()) catch { e => report_error(e) }
  if code != 0 {
    @env.exit(code)
  }
}
