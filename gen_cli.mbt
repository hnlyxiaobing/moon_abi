///|
/// CLI `moon-abi gen` 的纯逻辑层：参数解析、退出码契约、受管配置块与幂等合并。
///
/// 本文件不直接读写文件：真实 I/O 集中在 `sync_config_file`（测试可用
/// `write_config_with` 注入读/写失败，覆盖权限拒绝、磁盘满等路径，不 panic）。
/// 解析与合并均为纯函数、确定性、可并发。

///|
/// 路径风格：`Auto` 按 NDK 根路径形态推断（见 `windows_path_style_of`），
/// `Windows` / `Unix` 为显式覆盖。
pub(all) enum PathStyle {
  Auto
  Windows
  Unix
}

///|
/// `gen` 的输出模式：`Stdout` 只读打印（默认），`File(path)` 写入/追加 `moon.pkg`。
pub(all) enum GenOutput {
  Stdout
  File(String)
}

///|
/// `gen` 子命令的解析结果（纯值，不含任何 I/O 结果）。
pub(all) struct GenCommand {
  abi : Abi
  api_level : ApiLevel
  ndk_root : String?
  ndk_version : String?
  output : GenOutput
  path_style : PathStyle
}

///|
/// 受管配置块开始标记：幂等替换的锚点。块外的用户内容永不改写。
const BLOCK_BEGIN : String = "// >>> moon_abi gen:managed (do not edit this block) >>>"

///|
/// 受管配置块结束标记。
const BLOCK_END : String = "// <<< moon_abi gen:managed <<<"

///|
/// 合并动作：追加 / 替换受管块 / 内容已一致（不写盘）。
pub(all) enum MergeAction {
  Appended
  Replaced
  Unchanged
}

///|
/// 合并结果：新的完整文件内容 + 动作分类。
pub(all) struct MergeResult {
  content : String
  action : MergeAction
}

///|
/// 注入式读结果：存在 / 不存在 / 读取失败（权限、IO 等）。
pub(all) enum ReadOutcome {
  Found(String)
  NotFound
  Failed(String)
}

///|
/// 合并动作的稳定名称（CLI 输出与测试断言共用，避免依赖 Debug 格式）。
pub fn merge_action_name(action : MergeAction) -> String {
  match action {
    Appended => "appended"
    Replaced => "replaced"
    Unchanged => "unchanged"
  }
}

///|
/// 按路径形态推断 `windows_path_style`：含 `\` 或形如 `C:` 盘符即为 Windows 风格。
/// 纯函数；空串返回 `false`。
pub fn windows_path_style_of(root : String) -> Bool {
  if root.contains("\\") {
    true
  } else {
    let chars = root.to_array()
    if chars.length() >= 2 {
      chars[1] == ':'
    } else {
      false
    }
  }
}

///|
/// ABI 名称解析（CLI `--abi`）：接受规范名与常见别名，大小写不敏感。
/// 非法名称抛 `UnsupportedAbi(原始输入)`（CLI 映射为退出码 2）。
pub fn abi_from_name(name : String) -> Abi raise MoonAbiError {
  let n = name.trim().to_owned().to_lower()
  if n == "armeabi-v7a" || n == "armv7" || n == "armv7a" || n == "v7a" {
    ArmeabiV7a
  } else if n == "arm64-v8a" || n == "arm64" || n == "aarch64" || n == "v8a" {
    Arm64V8a
  } else if n == "x86" || n == "i686" {
    X86
  } else if n == "x86_64" || n == "x86-64" || n == "x64" {
    X86_64
  } else {
    raise UnsupportedAbi(name)
  }
}

///|
/// 把非负十进制字符串解析为 `Int32`（不依赖额外包；溢出与非法字符都走 `CliUsage`）。
fn parse_api_level_value(text : String) -> Int32 raise MoonAbiError {
  let s = text.trim().to_owned()
  if s.is_empty() {
    raise CliUsage("--api expects a positive integer, got empty value")
  }
  let chars = s.to_array()
  let mut i = 0
  let mut acc : Int32 = 0
  while i < chars.length() {
    let c = chars[i]
    if c < '0' || c > '9' {
      raise CliUsage("--api expects a positive integer, got '" + s + "'")
    }
    acc = acc * 10 + (c.to_int() - '0'.to_int())
    if acc > 100000 {
      raise CliUsage("--api out of range: " + s)
    }
    i = i + 1
  }
  acc
}

///|
/// 拆分 `--flag=value` 形式；非 `--` 开头或没有 `=` 时返回 `(原文, None)`。
fn split_flag(raw : String) -> (String, String?) {
  if raw.has_prefix("--") {
    match raw.find("=") {
      Some(pos) => (raw[:pos].to_owned(), Some(raw[pos + 1:].to_owned()))
      None => (raw, None)
    }
  } else {
    (raw, None)
  }
}

///|
/// 取出选项值：内联 `=value` 优先，否则消费下一个参数（拒绝下一个参数以 `-` 开头）。
/// 返回 `(值, 新的索引)`。
fn take_flag_value(
  flag : String,
  inline : String?,
  args : ArrayView[String],
  i : Int32,
) -> (String, Int32) raise MoonAbiError {
  match inline {
    Some(v) => (v, i)
    None => {
      let next = i + 1
      if next >= args.length() {
        raise CliUsage(flag + " requires a value")
      }
      let v = args[next]
      if v.has_prefix("-") {
        raise CliUsage(flag + " requires a value, got option '" + v + "'")
      }
      (v, next)
    }
  }
}

///|
/// 解析 `--path-style` 取值（`auto` / `windows` / `unix`）。
fn path_style_from_name(name : String) -> PathStyle raise MoonAbiError {
  let n = name.trim().to_owned().to_lower()
  if n == "auto" {
    Auto
  } else if n == "windows" {
    Windows
  } else if n == "unix" {
    Unix
  } else {
    raise CliUsage("--path-style expects auto|windows|unix, got '" + name + "'")
  }
}

///|
/// 解析 `gen` 子命令参数（不含程序名与 `gen` 本身）。
///
/// 支持：`--abi <name>` / `--api <int>` / `--ndk-root <path>` /
/// `--ndk-version <ver>` / `--out <path>` / `--path-style auto|windows|unix`，
/// 以及 `--flag=value` 内联写法。`--help` 由 CLI 入口先行拦截。
/// - 参数错误（缺必选项、重复项、未知选项、非法 ABI、API < 21）抛
///   `CliUsage` / `UnsupportedAbi` / `UnsupportedApiLevel`，CLI 映射为退出码 2。
/// - 纯函数、确定性；不做任何 I/O。
pub fn parse_gen_args(
  args : ArrayView[String],
) -> GenCommand raise MoonAbiError {
  let mut abi : Abi? = None
  let mut api : ApiLevel? = None
  let mut ndk_root : String? = None
  let mut ndk_version : String? = None
  let mut out_path : String? = None
  let mut path_style = PathStyle::Auto
  let mut path_style_seen = false
  let mut i = 0
  while i < args.length() {
    let raw = args[i]
    if raw.is_empty() {
      raise CliUsage("empty argument")
    }
    let (flag, inline) = split_flag(raw)
    match flag {
      "--abi" => {
        if abi is Some(_) {
          raise CliUsage("duplicate option --abi")
        }
        let (v, next) = take_flag_value(flag, inline, args, i)
        i = next
        abi = Some(abi_from_name(v))
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
  let abi = match abi {
    Some(a) => a
    None => raise CliUsage("missing required option --abi")
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
  { abi, api_level: api, ndk_root, ndk_version, output, path_style, }
}

///|
/// CLI 错误 → 退出码契约：
/// - `0` 成功（由调用方返回；错误对象不产生 0）
/// - `2` 用法/参数错误：未知选项、缺值、重复项、非法 ABI 名、API 越界
/// - `1` 运行/环境/IO 错误：NDK 未找到、版本不匹配、含空格路径、
///   读/写失败（权限拒绝、磁盘满）、既有配置畸形
/// 纯函数、无 panic。
pub fn exit_code_for_error(err : MoonAbiError) -> Int32 {
  match err {
    CliUsage(_) => 2
    UnsupportedAbi(_) => 2
    UnsupportedApiLevel(_, _) => 2
    MalformedConfig(_) => 1
    MissingNdkRoot => 1
    MissingClang(_) => 1
    PathContainsSpace(_) => 1
    InvalidTriple(_) => 1
    VersionMismatch(_, _) => 1
    IoFailure(_, _) => 1
    NdkNotFound(_) => 1
  }
}

///|
/// 错误的人读描述（CLI 输出与测试共用；确定性、无 I/O）。
pub fn error_message(err : MoonAbiError) -> String {
  match err {
    UnsupportedAbi(name) => "unsupported ABI: " + name
    UnsupportedApiLevel(got, min) =>
      "API level " + got.to_string() + " is below minimum " + min.to_string()
    MissingNdkRoot => "missing NDK root"
    MissingClang(path) => "missing clang: " + path
    PathContainsSpace(path) => "path contains a space: " + path
    InvalidTriple(triple) => "invalid target triple: " + triple
    VersionMismatch(expected, actual) =>
      "expected NDK " + expected + ", got " + actual
    CliUsage(message) => message
    IoFailure(path, reason) => "I/O failure at " + path + ": " + reason
    MalformedConfig(message) => "malformed managed config: " + message
    NdkNotFound(detail) => detail
  }
}

///|
/// 生成受管配置块：开始标记 + `render(config)` 文本 + 结束标记。
/// 输出确定性（同输入两次逐字相等）；`render` 的错误原样传播。
pub fn managed_block(config : LinkNativeConfig) -> String raise MoonAbiError {
  let rendered = render(config)
  let body = if rendered.has_suffix("\n") { rendered } else { rendered + "\n" }
  BLOCK_BEGIN + "\n" + body + BLOCK_END + "\n"
}

///|
/// 幂等合并：把受管块写入既有文本。
///
/// - 无受管块：追加到末尾（原文末尾无换行时补一个 `\n`），动作 `Appended`。
/// - 有完整受管块：只替换块区间，块外内容逐字保留；内容已一致则 `Unchanged`。
/// - 标记不成对 / 出现多个开始标记：抛 `MalformedConfig`（退出码 1），不猜测修复。
/// 纯函数、确定性；错误走 `MoonAbiError`，不 panic。
pub fn merge_link_config(
  existing : String,
  block : String,
) -> MergeResult raise MoonAbiError {
  if block.is_blank() {
    raise MalformedConfig("managed block is empty")
  }
  let begin_at = existing.find(BLOCK_BEGIN)
  let end_at = existing.find(BLOCK_END)
  match (begin_at, end_at) {
    (Some(b), Some(e)) => {
      if e < b {
        raise MalformedConfig(
          "managed block end marker appears before begin marker",
        )
      }
      let tail = existing[b + BLOCK_BEGIN.length():].to_owned()
      if tail.find(BLOCK_BEGIN) is Some(_) {
        raise MalformedConfig("multiple managed blocks are not supported")
      }
      // 块文本自带结束标记后的换行；若原文在结束标记后还有一个行尾换行，
      // 该换行属于标记行本身，替换时吞掉，保证「同内容二次合并 = Unchanged」。
      let mut suffix = existing[e + BLOCK_END.length():].to_owned()
      if block.has_suffix("\n") {
        if suffix.has_prefix("\r\n") {
          suffix = suffix[2:].to_owned()
        } else if suffix.has_prefix("\n") {
          suffix = suffix[1:].to_owned()
        }
      }
      let replaced = existing[:b].to_owned() + block + suffix
      if replaced == existing {
        { content: existing, action: Unchanged, }
      } else {
        { content: replaced, action: Replaced, }
      }
    }
    (Some(_), None) =>
      raise MalformedConfig("managed block begin marker without end marker")
    (None, Some(_)) =>
      raise MalformedConfig("managed block end marker without begin marker")
    (None, None) =>
      if existing == block {
        { content: existing, action: Unchanged, }
      } else if existing.is_empty() {
        { content: block, action: Appended, }
      } else if existing.has_suffix("\n") {
        { content: existing + block, action: Appended, }
      } else {
        { content: existing + "\n" + block, action: Appended, }
      }
  }
}

///|
/// 注入式写配置：读 → 合并 → 仅在需要时写。
///
/// `read` / `write` 由调用方注入，测试可精确制造「权限拒绝」「磁盘满」等失败，
/// 无需真实文件系统。读失败与写失败统一抛 `IoFailure(path, 原因)`；
/// 已一致（`Unchanged`）时不调用 `write`，保证幂等且不产生多余写。
pub fn write_config_with(
  path : String,
  block : String,
  read : (String) -> ReadOutcome,
  write : (String, String) -> Result[Unit, String],
) -> MergeResult raise MoonAbiError {
  if path.is_blank() {
    raise IoFailure(path, "empty output path")
  }
  let existing = match read(path) {
    Found(text) => text
    NotFound => ""
    Failed(reason) => raise IoFailure(path, reason)
  }
  let merged = merge_link_config(existing, block)
  match merged.action {
    Unchanged => merged
    _ =>
      match write(path, merged.content) {
        Ok(_) => merged
        Err(reason) => raise IoFailure(path, reason)
      }
  }
}

///|
/// 真实文件系统版本：读既有 `moon.pkg`（不存在视为空）→ 幂等合并 → 必要时写回。
/// - 错误：读/写失败抛 `IoFailure(path, 原因)`；既有标记畸形抛 `MalformedConfig`。
/// - 语义与 `write_config_with` 一致；本函数是唯一直接触碰文件系统的合并入口。
pub async fn sync_config_file(
  path : String,
  block : String,
) -> MergeResult raise MoonAbiError {
  if path.is_blank() {
    raise IoFailure(path, "empty output path")
  }
  let exists = @fs.exists(path) catch { _ => false }
  let existing = if exists {
    @fs.read_text(path) catch {
      e => raise IoFailure(path, e.to_string())
    }
  } else {
    ""
  }
  let merged = merge_link_config(existing, block)
  match merged.action {
    Unchanged => merged
    _ => {
      @fs.write_text(path, merged.content) catch {
        e => raise IoFailure(path, e.to_string())
      }
      merged
    }
  }
}
