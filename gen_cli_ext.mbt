///|
/// CLI `moon-abi gen` 扩展纯逻辑层（W4/M2）：多 ABI 与 extra 选项。
///
/// 与 gen_cli.mbt 的旧解析器 `parse_gen_args` 并行共存。本文件新增
/// `parse_gen_args_ext` 复用旧解析器同一组辅助函数（split_flag / take_flag_value /
/// abi_from_name / parse_api_level_value / path_style_from_name / check_api_level），
/// `base` 字段由等价逻辑构造（`base.abi = abis[0]`），保证旧参数组合语义逐字一致
/// （防火墙 T-W4-1 / T-W4-4）。旧 `parse_gen_args` 一行不动。
///
/// 受管块「单块契约」冻结：多 ABI 与写入单文件互斥（多 ABI + `--out` → CliUsage，
/// 退出码 2，消息明示单块契约），故多 ABI 仅走 stdout 打印多块。

///|
/// W4：`abi` 的稳定序号，供「去重保序」与测试比较使用（`Abi` 未 derive `Eq`，
/// 且新增 derive 会污染 mbti 快照，故用序号判定相等）。
fn abi_index(abi : Abi) -> Int32 {
  match abi {
    ArmeabiV7a => 0
    Arm64V8a => 1
    X86 => 2
    X86_64 => 3
  }
}

///|
/// 扩展解析结果：旧解析器结果 `base` + 多 ABI 列表 + extra 选项。
/// `base` 与 `parse_gen_args` 在「旧参数组合」上等价（`base.abi = abis[0]`），
/// 使 cmd/main 切换解析器时旧参数路径输出逐字节不变。
pub(all) struct GenCommandExt {
  base : GenCommand
  abis : Array[Abi]
  extra_link_libs : Array[String]
  extra_cc_flags : Array[String]
}

///|
/// 解析 `gen` 子命令参数（含多 ABI 与 extra 选项），复用旧解析器辅助函数。
///
/// 与 `parse_gen_args` 的差异：
/// - `--abi` 可重复（≥1，去重保序）；单个 `--abi` 时语义与旧解析器逐字一致。
/// - 新增 `--extra-lib` / `--extra-cc-flag`，均可重复、原序收集、空值 → CliUsage。
/// - 多 ABI（去重后 ≥2）与 `--out` 互斥 → CliUsage（受管块单块契约）。
/// 其余选项（`--api`/`--ndk-root`/`--ndk-version`/`--path-style`）语义与旧解析器
/// 逐字一致（重复项、缺值、未知选项、非法值的消息文本与旧解析器相同）。
/// 纯函数、确定性、不做 I/O；错误走 `MoonAbiError`。
pub fn parse_gen_args_ext(
  args : ArrayView[String],
) -> GenCommandExt raise MoonAbiError {
  let abis : Array[Abi] = []
  let seen_abi : Array[Bool] = [false, false, false, false]
  let mut api : ApiLevel? = None
  let mut ndk_root : String? = None
  let mut ndk_version : String? = None
  let mut out_path : String? = None
  let mut path_style = PathStyle::Auto
  let mut path_style_seen = false
  let extra_link_libs : Array[String] = []
  let extra_cc_flags : Array[String] = []
  let mut i = 0
  while i < args.length() {
    let raw = args[i]
    if raw.is_empty() {
      raise CliUsage("empty argument")
    }
    let (flag, inline) = split_flag(raw)
    match flag {
      "--abi" => {
        let (v, next) = take_flag_value(flag, inline, args, i)
        i = next
        let abi = abi_from_name(v)
        let idx = abi_index(abi)
        if !seen_abi[idx] {
          seen_abi[idx] = true
          abis.push(abi)
        }
      }
      "--extra-lib" => {
        let (v, next) = take_flag_value(flag, inline, args, i)
        i = next
        if v.is_blank() {
          raise CliUsage("--extra-lib must not be empty")
        }
        extra_link_libs.push(v)
      }
      "--extra-cc-flag" => {
        let (v, next) = take_flag_value(flag, inline, args, i)
        i = next
        if v.is_blank() {
          raise CliUsage("--extra-cc-flag must not be empty")
        }
        extra_cc_flags.push(v)
      }
      "--api" => {
        if api is Some(_) {
          raise CliUsage("duplicate option --api")
        }
        let (v, next) = take_flag_value(flag, inline, args, i)
        i = next
        api = Some(ApiLevel::{ level: parse_api_level_value(v), })
      }
      "--ndk-root" => {
        if ndk_root is Some(_) {
          raise CliUsage("duplicate option --ndk-root")
        }
        let (v, next) = take_flag_value(flag, inline, args, i)
        i = next
        if v.is_blank() {
          raise CliUsage("--ndk-root must not be empty")
        }
        ndk_root = Some(v)
      }
      "--ndk-version" => {
        if ndk_version is Some(_) {
          raise CliUsage("duplicate option --ndk-version")
        }
        let (v, next) = take_flag_value(flag, inline, args, i)
        i = next
        if v.is_blank() {
          raise CliUsage("--ndk-version must not be empty")
        }
        ndk_version = Some(v)
      }
      "--out" => {
        if out_path is Some(_) {
          raise CliUsage("duplicate option --out")
        }
        let (v, next) = take_flag_value(flag, inline, args, i)
        i = next
        if v.is_blank() {
          raise CliUsage("--out must not be empty")
        }
        out_path = Some(v)
      }
      "--path-style" => {
        if path_style_seen {
          raise CliUsage("duplicate option --path-style")
        }
        path_style_seen = true
        let (v, next) = take_flag_value(flag, inline, args, i)
        i = next
        path_style = path_style_from_name(v)
      }
      _ => {
        if flag.has_prefix("-") {
          raise CliUsage("unknown option: " + flag)
        }
        raise CliUsage("unexpected positional argument: " + raw)
      }
    }
    i = i + 1
  }
  if abis.length() == 0 {
    raise CliUsage("missing required option --abi")
  }
  let api = match api {
    Some(a) => a
    None => raise CliUsage("missing required option --api")
  }
  check_api_level(api)
  let output = match out_path {
    Some(p) => GenOutput::File(p)
    None => GenOutput::Stdout
  }
  if abis.length() > 1 {
    match output {
      File(_) =>
        raise CliUsage(
          "--out cannot be used with multiple --abi values (single managed block contract)",
        )
      Stdout => ()
    }
  }
  let base : GenCommand = {
    abi: abis[0],
    api_level: api,
    ndk_root,
    ndk_version,
    output,
    path_style,
  }
  { base, abis, extra_link_libs, extra_cc_flags, }
}

///|
/// 按输入序为每个 ABI 生成一份 `LinkNativeConfig`（同一 profile）。
///
/// - 空数组 → `CliUsage`（至少需要一个 ABI）。
/// - 逐个调用 `generate(profile, abi)`；错误原样传播，首个失败即抛。
/// - 纯函数、确定性、可并发；不读取任何外部状态。
pub fn generate_multi(
  profile : NdkProfile,
  abis : Array[Abi],
) -> Array[LinkNativeConfig] raise MoonAbiError {
  if abis.is_empty() {
    raise CliUsage("generate_multi requires at least one ABI")
  }
  let out : Array[LinkNativeConfig] = []
  for abi in abis {
    out.push(generate(profile, abi))
  }
  out
}

///|
/// CLI `--host` 名称解析：接受宿主标签与常见别名，大小写不敏感、忽略首尾空白。
/// 非法名称抛 `CliUsage`（CLI 映射为退出码 2）。
pub fn host_from_name(name : String) -> NdkHost raise MoonAbiError {
  let n = name.trim().to_owned().to_lower()
  if n == "windows" || n == "win" || n == "windows-x86_64" {
    WindowsX86_64
  } else if n == "linux" || n == "linux-x86_64" {
    LinuxX86_64
  } else if n == "darwin" ||
    n == "macos" ||
    n == "mac" ||
    n == "osx" ||
    n == "darwin-x86_64" {
    DarwinX86_64
  } else {
    raise CliUsage("--host expects windows|linux|darwin, got '" + name + "'")
  }
}

///|
/// 带宿主覆盖的扩展解析结果：W4 扩展命令 + 可选宿主。
/// `host = None` 表示未显式指定，由调用方按「路径风格 + 当前平台」解析默认宿主
/// （见 `resolve_default_host`）；解析层保持纯函数，不做平台推断。
pub(all) struct GenCommandWithHost {
  command : GenCommandExt
  host : NdkHost?
}

///|
/// 解析 `gen` 子命令参数（W4 全部选项 + 可选 `--host`）。
///
/// 实现方式：先剥离 `--host` / `--host=<name>`，其余参数原样交给
/// `parse_gen_args_ext`，因此旧选项的解析语义、错误消息与顺序保持不变。
/// - `--host` 至多一次；缺值 / 空值 / 非法值 / 重复 → `CliUsage`。
/// - `--host` 与显式 `--path-style windows|unix` 互斥 → `CliUsage`
///   （宿主已决定分隔符与 prebuilt 标签，路径风格不再参与）。
/// 纯函数、确定性、不做 I/O。
pub fn parse_gen_args_with_host(
  args : ArrayView[String],
) -> GenCommandWithHost raise MoonAbiError {
  let kept : Array[String] = []
  let mut host : NdkHost? = None
  let mut host_seen = false
  let mut i = 0
  while i < args.length() {
    let raw = args[i]
    let (flag, inline) = split_flag(raw)
    if flag == "--host" {
      if host_seen {
        raise CliUsage("duplicate option --host")
      }
      host_seen = true
      let (v, next) = take_flag_value(flag, inline, args, i)
      i = next
      if v.is_blank() {
        raise CliUsage("--host must not be empty")
      }
      host = Some(host_from_name(v))
    } else {
      kept.push(raw)
    }
    i = i + 1
  }
  let command = parse_gen_args_ext(kept)
  if host is Some(_) {
    match command.base.path_style {
      Auto => ()
      _ => raise CliUsage("--host cannot be combined with --path-style")
    }
  }
  { command, host, }
}

///|
/// 按输入序为每个 ABI 以显式宿主生成 `LinkNativeConfig`。
///
/// - 空数组 → `CliUsage`（至少需要一个 ABI）。
/// - 逐个调用 `generate_with_host`；错误原样传播，首个失败即抛。
/// - 纯函数、确定性；不读取任何外部状态。
pub fn generate_multi_with_host(
  profile : NdkProfile,
  abis : Array[Abi],
  host : NdkHost,
) -> Array[LinkNativeConfig] raise MoonAbiError {
  if abis.is_empty() {
    raise CliUsage("generate_multi_with_host requires at least one ABI")
  }
  let out : Array[LinkNativeConfig] = []
  for abi in abis {
    out.push(generate_with_host(profile, abi, host))
  }
  out
}

///|
/// 未显式指定 `--host` 且路径风格为 `auto` 时的默认宿主解析：保持既有路径风格
/// 推断的兼容语义，仅修正 macOS 上 unix 风格 NDK 根被误判为 linux 的缺口。
/// （显式 `--path-style windows|unix` 由调用方直接映射，不经本函数。）
/// - `path_looks_windows = true` → `WindowsX86_64`（与旧 `generate` 一致）。
/// - 否则：当前平台为 macOS → `DarwinX86_64`；其余平台（Windows/Linux）→
///   `LinuxX86_64`（与旧 `generate` 在 unix 风格根上的输出逐字节一致）。
/// 纯函数、确定性。
pub fn resolve_default_host(
  path_looks_windows : Bool,
  running_host : NdkHost,
) -> NdkHost {
  if path_looks_windows {
    WindowsX86_64
  } else {
    match running_host {
      DarwinX86_64 => DarwinX86_64
      _ => LinuxX86_64
    }
  }
}
