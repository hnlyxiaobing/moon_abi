///|
/// Android 交叉编译 `link.native` 配置生成器的类型与实现。
///
/// 本库是纯 MoonBit 的「配置值 + 渲染」库：不执行外部命令、不修改构建系统、
/// 不写入文件、不链接任何 C 库。它只产出可被粘贴进 `moon.pkg` 的配置片段。
/// 所有函数均为纯函数、确定性、可并发；失败一律 `raise MoonAbiError`。

///|
/// 目标 ABI。
pub(all) enum Abi {
  ArmeabiV7a
  Arm64V8a
  X86
  X86_64
}

///|
/// NDK clang 目标三元组（仅前缀，不含 API level 后缀）。
pub(all) enum TargetTriple {
  Armv7aLinuxAndroideabi
  Aarch64LinuxAndroid
  I686LinuxAndroid
  X86_64LinuxAndroid
}

///|
/// Android API level 包装，防止裸 Int 与 minSdk / targetSdk 混用。
pub(all) struct ApiLevel {
  level : Int32
}

///|
/// NDK 工具链 Profile：路径、版本、API level 与额外链接库。
pub(all) struct NdkProfile {
  ndk_root : String
  ndk_version : String
  api_level : ApiLevel
  extra_link_libs : Array[String]
  extra_cc_flags : Array[String]
  windows_path_style : Bool
}

///|
/// 生成结果：等价于 `moon.pkg` 中 `options(link.native...)` 片段的纯数据。
pub(all) struct LinkNativeConfig {
  cc : String
  cc_flags : Array[String]
  cc_link_flags : Array[String]
  stub_cc : String?
  supported_targets : String
  triple : TargetTriple
  abi : Abi
  api_level : ApiLevel
}

///|
/// 配置校验报告，用于 CI 门禁；`warnings` 不阻断生成，`errors` 阻断。
pub(all) struct ValidationReport {
  ok : Bool
  warnings : Array[String]
  errors : Array[String]
}

///|
/// 配置生成错误模型。
#derive(Debug)
pub suberror MoonAbiError {
  UnsupportedAbi(String)
  UnsupportedApiLevel(Int32, Int32)
  MissingNdkRoot
  MissingClang(String)
  PathContainsSpace(String)
  InvalidTriple(String)
  VersionMismatch(String, String)
}

///|
pub extend MoonAbiError with Debug::{to_repr}

///|
/// 配置渲染契约；实现必须保证输出是确定性、可复现的纯文本。
pub trait ConfigRenderer {
  fn render(Self) -> String raise MoonAbiError
}

///|
/// 内部常量：API level 下限。统一取 21（64 位 ABI 的 NDK 最低 API），
/// 是 r22+ 全系 NDK 的安全下限；精确版本锁由 `moon_android::ToolchainVersions` 持有。
const MIN_API_LEVEL : Int32 = 21

///|
/// 内部常量：最低支持的 NDK 主版本与对外描述串（输出面向 NDK r22+）。
const MIN_NDK_MAJOR : Int32 = 22

///|
const MIN_NDK_VERSION : String = "r22+"

///|
/// 内部常量：生成片段中 `supported_targets` 的取值（native 后端）。
const SUPPORTED_TARGETS_VALUE : String = "native"

///|
/// `Abi` 的规范 Android 名称。
fn abi_name(abi : Abi) -> String {
  match abi {
    ArmeabiV7a => "armeabi-v7a"
    Arm64V8a => "arm64-v8a"
    X86 => "x86"
    X86_64 => "x86_64"
  }
}

///|
/// `TargetTriple` 对应的 NDK 目标三元组前缀（不含 API level 后缀）。
fn triple_name(triple : TargetTriple) -> String {
  match triple {
    Armv7aLinuxAndroideabi => "armv7a-linux-androideabi"
    Aarch64LinuxAndroid => "aarch64-linux-android"
    I686LinuxAndroid => "i686-linux-android"
    X86_64LinuxAndroid => "x86_64-linux-android"
  }
}

///|
/// 不可变映射表：ABI 规范名 → NDK 目标三元组前缀（NDK r22+ 统一工具链命名）。
/// 名称不在表中即为非法 ABI，抛 `UnsupportedAbi(name)`。
fn triple_of_name(name : String) -> TargetTriple raise MoonAbiError {
  if name == "armeabi-v7a" {
    Armv7aLinuxAndroideabi
  } else if name == "arm64-v8a" {
    Aarch64LinuxAndroid
  } else if name == "x86" {
    I686LinuxAndroid
  } else if name == "x86_64" {
    X86_64LinuxAndroid
  } else {
    raise UnsupportedAbi(name)
  }
}

///|
/// ABI → 目标三元组前缀；委托不可变映射表，非法名称抛 `UnsupportedAbi`。
fn triple_of(abi : Abi) -> TargetTriple raise MoonAbiError {
  triple_of_name(abi_name(abi))
}

///|
/// clang 驱动名：`<triple><api>-clang`（NDK 统一工具链 wrapper 命名）。
fn clang_driver(triple_prefix : String, level : Int32) -> String {
  triple_prefix + level.to_string() + "-clang"
}

///|
/// 解析 NDK 版本主版本号：接受 `r27` / `r27c` 与 `27.0.12077973` 两种官方写法。
/// 取 `r` 之后（或开头）的连续数字段；无法解析返回 `None`。
fn ndk_major(version : String) -> Int32? {
  let chars = version.to_array()
  let mut i = 0
  if chars.length() > 0 && chars[0] == 'r' {
    i = 1
  }
  let mut acc = 0
  let mut seen = false
  while i < chars.length() {
    let c = chars[i]
    if c >= '0' && c <= '9' {
      acc = acc * 10 + (c.to_int() - '0'.to_int())
      seen = true
      i = i + 1
    } else {
      break
    }
  }
  if seen {
    Some(acc)
  } else {
    None
  }
}

///|
/// 校验 API level 下限；越界抛 `UnsupportedApiLevel(got, min)`。
fn check_api_level(api : ApiLevel) -> Unit raise MoonAbiError {
  if api.level < MIN_API_LEVEL {
    raise UnsupportedApiLevel(api.level, MIN_API_LEVEL)
  }
}

///|
/// 校验 NDK 版本不低于最低支持版本；不满足或无法解析抛 `VersionMismatch(expected, actual)`。
fn check_ndk_version(version : String) -> Unit raise MoonAbiError {
  let ok = match ndk_major(version) {
    Some(major) => major >= MIN_NDK_MAJOR
    None => false
  }
  if !ok {
    raise VersionMismatch(MIN_NDK_VERSION, version)
  }
}

///|
/// 校验单个命令行 token 不含空格；空格会把 cc 命令断裂，抛 `PathContainsSpace(token)`。
/// 这是 Windows 路径空格的统一策略：提前拒绝、不自动加引号（引号语义随 shell 变化）。
fn check_no_space(token : String) -> Unit raise MoonAbiError {
  if token.contains_char(' ') {
    raise PathContainsSpace(token)
  }
}

///|
/// 以单空格连接 flag 数组（`cc-flags` / `cc-link-flags` 是空白分隔字符串）。
fn join_flags(flags : Array[String]) -> String {
  let mut out = ""
  let mut first = true
  for f in flags {
    if first {
      first = false
    } else {
      out = out + " "
    }
    out = out + f
  }
  out
}

///|
/// 把字符串转义为 `moon.pkg` DSL 字符串字面量内容（转义 `\` 与 `"`）。
fn escape_dsl(s : String) -> String {
  s.replace_all(old="\\", new="\\\\").replace_all(old="\"", new="\\\"")
}

///|
/// 去掉路径末尾的路径分隔符（`\` 或 `/`），避免拼接出双分隔符。
fn trim_trailing_sep(path : String) -> String {
  let chars = path.to_array()
  let mut n = chars.length()
  while n > 1 && (chars[n - 1] == '\\' || chars[n - 1] == '/') {
    n = n - 1
  }
  path[:n].to_owned()
}

///|
/// 拼接 NDK clang 的完整路径：
/// `<ndk_root>/toolchains/llvm/prebuilt/<host>/bin/<triple><api>-clang`。
/// `windows_path_style` 决定分隔符（`\` / `/`）与 prebuilt 宿主标签
/// （`windows-x86_64` / `linux-x86_64`）。
fn cc_path(
  ndk_root : String,
  windows_path_style : Bool,
  triple_prefix : String,
  level : Int32,
) -> String {
  let sep = if windows_path_style { "\\" } else { "/" }
  let host = if windows_path_style { "windows-x86_64" } else { "linux-x86_64" }
  trim_trailing_sep(ndk_root) +
  sep +
  "toolchains" +
  sep +
  "llvm" +
  sep +
  "prebuilt" +
  sep +
  host +
  sep +
  "bin" +
  sep +
  clang_driver(triple_prefix, level)
}

///|
/// 渲染实现：先校验（clang 缺失 / triple 与 abi 一致性 / 空格拒绝），
/// 再产出确定性文本。供 `render` 与 `ConfigRenderer` 实现共用。
fn do_render(config : LinkNativeConfig) -> String raise MoonAbiError {
  if config.cc.is_blank() {
    raise MissingClang(config.cc)
  }
  let expected = triple_name(triple_of(config.abi))
  let actual = triple_name(config.triple)
  if expected != actual {
    raise InvalidTriple(actual)
  }
  check_no_space(config.cc)
  match config.stub_cc {
    Some(stub) => check_no_space(stub)
    None => ()
  }
  for f in config.cc_flags {
    check_no_space(f)
  }
  for f in config.cc_link_flags {
    check_no_space(f)
  }
  let mut out = "// generated by moon_abi; do not edit by hand\n"
  out = out +
    "// abi=" +
    abi_name(config.abi) +
    " triple=" +
    expected +
    " api_level=" +
    config.api_level.level.to_string() +
    "\n"
  out = out +
    "supported_targets = \"" +
    escape_dsl(config.supported_targets) +
    "\"\n"
  out = out + "options(\n"
  out = out + "  link: {\n"
  out = out + "    \"native\": {\n"
  out = out + "      \"cc\": \"" + escape_dsl(config.cc) + "\",\n"
  out = out +
    "      \"cc-flags\": \"" +
    escape_dsl(join_flags(config.cc_flags)) +
    "\",\n"
  out = out +
    "      \"cc-link-flags\": \"" +
    escape_dsl(join_flags(config.cc_link_flags)) +
    "\",\n"
  match config.stub_cc {
    Some(stub) =>
      out = out + "      \"stub-cc\": \"" + escape_dsl(stub) + "\",\n"
    None => ()
  }
  out = out + "    },\n"
  out = out + "  },\n"
  out = out + ")\n"
  out
}

///|
/// 生成 Android 交叉编译的 `link.native` 配置值。
///
/// - 参数：`profile` 为只读配置；`abi` 决定三元组与 `--target` 后缀。
/// - 返回：`LinkNativeConfig` 纯值，不含句柄、不触发任何 I/O。
///   `cc` 指向 NDK clang wrapper（`<triple><api>-clang`）；`cc_flags` 注入
///   `--target=<triple><api>` 与 `extra_cc_flags`；`cc_link_flags` 注入
///   `-llog -landroid` 与 `extra_link_libs`（裸库名，自动加 `-l` 前缀）；
///   `stub_cc` 与 `cc` 保持一致（NDK 文档建议两者一致）。
/// - 错误：校验顺序为 MissingNdkRoot → UnsupportedApiLevel → VersionMismatch；
///   ABI 名称非法时抛 `UnsupportedAbi`。
/// - 线程：纯函数，无状态，可并发调用。
/// - 非目标：不调用 NDK、不修改 `moon.pkg`、不执行打包、不探测本机环境。
pub fn generate(
  profile : NdkProfile,
  abi : Abi,
) -> LinkNativeConfig raise MoonAbiError {
  if profile.ndk_root.is_blank() {
    raise MissingNdkRoot
  }
  check_api_level(profile.api_level)
  check_ndk_version(profile.ndk_version)
  let t = triple_of(abi)
  let tname = triple_name(t)
  let cc = cc_path(
    profile.ndk_root,
    profile.windows_path_style,
    tname,
    profile.api_level.level,
  )
  let cc_flags = ["--target=" + tname + profile.api_level.level.to_string()]
  for f in profile.extra_cc_flags {
    cc_flags.push(f)
  }
  let cc_link_flags = ["-llog", "-landroid"]
  for lib in profile.extra_link_libs {
    cc_link_flags.push("-l" + lib)
  }
  {
    cc,
    cc_flags,
    cc_link_flags,
    stub_cc: Some(cc),
    supported_targets: SUPPORTED_TARGETS_VALUE,
    triple: t,
    abi,
    api_level: profile.api_level,
  }
}

///|
/// 把配置渲染为 `moon.pkg` 的 `options(...)` 片段文本（确定性输出，同输入两次逐字相等）。
///
/// 输出为可直接粘贴进 `moon.pkg` 的文本：`supported_targets` 赋值 + `options(link…)` 块，
/// 含 `abi` / `triple` / `api_level` 元信息注释；`stub_cc` 为 `None` 时省略 `stub-cc` 行。
/// - 错误：clang 缺失抛 `MissingClang`；`triple` 与 `abi` 不一致抛 `InvalidTriple`；
///   任何命令行 token 含空格抛 `PathContainsSpace`（Windows 路径空格提前拒绝、不自动加引号）。
pub fn render(config : LinkNativeConfig) -> String raise MoonAbiError {
  ConfigRenderer::render(config)
}

///|
/// 配置渲染契约的 `LinkNativeConfig` 实现：与 `render` 同一确定性语义。
impl ConfigRenderer for LinkNativeConfig with fn render(self) -> String raise MoonAbiError {
  do_render(self)
}

///|
/// 校验配置的完整性与平台约束，供 CI 与人工评审使用。
///
/// - 硬问题（缺 NDK 路径、API level 越界、版本不匹配、含空格 token）进 `errors`，
///   `ok = false` 阻断 CI；需人工确认但不阻断的问题进 `warnings`。
/// - 本函数只出报告不抛上述校验错误；仅在 ABI 名称非法（`UnsupportedAbi`）等
///   无法建模为报告的映射失败时抛 `MoonAbiError`。
/// - 纯函数、可并发；`warnings` 与 `errors` 的条目顺序确定。
pub fn validate(
  profile : NdkProfile,
  abi : Abi,
) -> ValidationReport raise MoonAbiError {
  let errors : Array[String] = []
  let warnings : Array[String] = []
  let t = triple_of(abi)
  let tname = triple_name(t)
  if profile.ndk_root.is_blank() {
    errors.push("MissingNdkRoot: ndk_root is empty")
  }
  if profile.api_level.level < MIN_API_LEVEL {
    errors.push(
      "UnsupportedApiLevel: api level " +
      profile.api_level.level.to_string() +
      " is below minimum " +
      MIN_API_LEVEL.to_string(),
    )
  }
  match ndk_major(profile.ndk_version) {
    Some(major) =>
      if major < MIN_NDK_MAJOR {
        errors.push(
          "VersionMismatch: expected " +
          MIN_NDK_VERSION +
          ", got " +
          profile.ndk_version,
        )
      }
    None =>
      errors.push(
        "VersionMismatch: expected " +
        MIN_NDK_VERSION +
        ", got " +
        profile.ndk_version,
      )
  }
  if !profile.ndk_root.is_blank() {
    let cc = cc_path(
      profile.ndk_root,
      profile.windows_path_style,
      tname,
      profile.api_level.level,
    )
    if cc.contains_char(' ') {
      errors.push("PathContainsSpace: " + cc)
    }
    for f in profile.extra_cc_flags {
      if f.contains_char(' ') {
        errors.push("PathContainsSpace: " + f)
      }
      if f.is_empty() {
        warnings.push("empty_entry: extra_cc_flags contains an empty entry")
      }
    }
    for lib in profile.extra_link_libs {
      let flag = "-l" + lib
      if flag.contains_char(' ') {
        errors.push("PathContainsSpace: " + flag)
      }
      if lib.is_empty() {
        warnings.push("empty_entry: extra_link_libs contains an empty entry")
      }
      if lib == "log" || lib == "android" {
        warnings.push("duplicate_link_lib: " + flag + " is already injected")
      }
    }
    if profile.windows_path_style {
      if profile.ndk_root.contains("/") {
        warnings.push(
          "path_style_mismatch: windows_path_style is true but ndk_root contains '/'",
        )
      }
    } else if profile.ndk_root.contains("\\") {
      warnings.push(
        "path_style_mismatch: windows_path_style is false but ndk_root contains '\\'",
      )
    }
  }
  { ok: errors.is_empty(), warnings, errors, }
}

///|
/// 返回该 ABI 对应的 NDK clang 可执行文件名（含 API level 后缀），
/// 如 `armv7a-linux-androideabi21-clang`（NDK 统一工具链 wrapper 命名）。
/// - 错误：API level 低于 21 抛 `UnsupportedApiLevel(got, min)`；
///   ABI 名称非法抛 `UnsupportedAbi(name)`。
pub fn clang_name(abi : Abi, api : ApiLevel) -> String raise MoonAbiError {
  check_api_level(api)
  clang_driver(triple_name(triple_of(abi)), api.level)
}
