///|
/// 本机 NDK 探测（R4）：按 `ANDROID_NDK_HOME` → `ANDROID_HOME/ndk/<ver>` →
/// `ANDROID_SDK_ROOT/ndk/<ver>` → 常见安装路径 的顺序找 NDK 根。
///
/// 分两层：
/// - `probe_ndk_with`：**纯函数**核心，目录存在性 / 目录列举 / 文件读取全部由调用方
///   注入闭包；测试用伪目录即可覆盖全部分支，不依赖真机、真 NDK、真环境变量。
/// - `probe_ndk`：真实文件系统包装（`@fs`），只做「预取事实 + 交给纯核心判定」，
///   不重复算法。
/// 结果结构化：候选列表（来源 / 路径 / 是否存在 / 是否可用 / 版本 / 备注）+ 警告。

///|
/// NDK 候选来源分类（顺序即探测优先级）。
pub(all) enum NdkSource {
  Explicit
  NdkHomeEnv
  AndroidHomeNdk
  AndroidSdkRootNdk
  CommonPath
}

///|
/// 探测输入：纯数据。CLI 从环境变量/参数构造；测试直接注入受控值。
/// 空串与 `None` 等价（不产生候选）。
pub(all) struct NdkProbeInputs {
  explicit_root : String?
  ndk_home : String?
  android_home : String?
  android_sdk_root : String?
  home_dir : String?
  local_app_data : String?
}

///|
/// 单个候选的探测事实。
pub(all) struct NdkCandidate {
  source : NdkSource
  path : String
  exists : Bool
  usable : Bool
  version : String?
  note : String
}

///|
/// 探测结果：`found` 为真时 `selected`/`version` 给出首个可用候选。
pub(all) struct NdkProbeResult {
  found : Bool
  selected : String?
  version : String?
  candidates : Array[NdkCandidate]
  warnings : Array[String]
}

///|
/// 内部：候选「父路径」的种类。
priv enum ProbeParentKind {
  DirectRoot
  SdkNdkDir
  SdkNdkBundleDir
}

///|
/// 内部：待展开的父路径。
priv struct ProbeParent {
  source : NdkSource
  path : String
  kind : ProbeParentKind
}

///|
/// 版本号排序用的主版本号；不可解析时为 `-1`（排到最后）。
fn version_rank(name : String) -> Int32 {
  match ndk_major(name) {
    Some(n) => n
    None => -1
  }
}

///|
/// 稳定的降序比较：主版本大者在前，同主版本按字符串升序，保证确定性。
fn compare_version_names(a : String, b : String) -> Int32 {
  let ra = version_rank(a)
  let rb = version_rank(b)
  if ra != rb {
    rb - ra
  } else {
    a.compare(b)
  }
}

///|
/// 目录名是否像 NDK 版本（`27.0.12077973` / `r27c` / `27`）。
fn looks_like_version(name : String) -> Bool {
  let chars = name.to_array()
  if chars.length() == 0 {
    return false
  }
  let c0 = chars[0]
  if c0 >= '0' && c0 <= '9' {
    return true
  }
  if (c0 == 'r' || c0 == 'R') && chars.length() > 1 {
    let c1 = chars[1]
    return c1 >= '0' && c1 <= '9'
  }
  false
}

///|
/// 只保留版本形态的目录名，并按版本降序排序（确定性）。
fn sort_version_dirs(names : Array[String]) -> Array[String] {
  let versions : Array[String] = []
  for name in names {
    if looks_like_version(name) {
      versions.push(name)
    }
  }
  versions.sort_by((a, b) => compare_version_names(a, b))
  versions
}

///|
/// 拼接路径：分隔符由父路径形态推断（Windows / Unix），并去掉父路径尾部重复分隔符。
fn join_path(parent : String, child : String) -> String {
  let sep = if windows_path_style_of(parent) { "\\" } else { "/" }
  trim_trailing_sep(parent) + sep + child
}

///|
/// 添加父路径（去重、去空）。
fn add_probe_parent(
  out : Array[ProbeParent],
  seen : Array[String],
  source : NdkSource,
  path : String,
  kind : ProbeParentKind,
) -> Unit {
  let p = trim_trailing_sep(path)
  if p.is_blank() || seen.contains(p) {
    return
  }
  seen.push(p)
  out.push({ source, path: p, kind, })
}

///|
/// 按优先级构造父路径列表：显式 → `ANDROID_NDK_HOME` → `ANDROID_HOME` →
/// `ANDROID_SDK_ROOT` → 常见路径（`%LOCALAPPDATA%\Android\Sdk`、`~/Android/Sdk`、
/// `~/Library/Android/sdk`、`/opt/android-sdk`、`/usr/local/lib/android/sdk`）。
/// 每个 SDK 父目录展开出 `<sdk>/ndk` 与旧版 `<sdk>/ndk-bundle`。
fn probe_parents(inputs : NdkProbeInputs) -> Array[ProbeParent] {
  let out : Array[ProbeParent] = []
  let seen : Array[String] = []
  match inputs.explicit_root {
    Some(p) => add_probe_parent(out, seen, Explicit, p, DirectRoot)
    None => ()
  }
  match inputs.ndk_home {
    Some(p) => add_probe_parent(out, seen, NdkHomeEnv, p, DirectRoot)
    None => ()
  }
  let sdks : Array[(NdkSource, String)] = []
  match inputs.android_home {
    Some(p) => if !p.is_blank() { sdks.push((AndroidHomeNdk, p)) }
    None => ()
  }
  match inputs.android_sdk_root {
    Some(p) => if !p.is_blank() { sdks.push((AndroidSdkRootNdk, p)) }
    None => ()
  }
  match inputs.local_app_data {
    Some(p) =>
      if !p.is_blank() {
        sdks.push((CommonPath, join_path(p, "Android/Sdk")))
      }
    None => ()
  }
  match inputs.home_dir {
    Some(p) =>
      if !p.is_blank() {
        sdks.push((CommonPath, join_path(p, "Android/Sdk")))
        sdks.push((CommonPath, join_path(p, "Library/Android/sdk")))
      }
    None => ()
  }
  sdks.push((CommonPath, "/opt/android-sdk"))
  sdks.push((CommonPath, "/usr/local/lib/android/sdk"))
  for (source, sdk) in sdks {
    add_probe_parent(out, seen, source, join_path(sdk, "ndk"), SdkNdkDir)
    add_probe_parent(
      out,
      seen,
      source,
      join_path(sdk, "ndk-bundle"),
      SdkNdkBundleDir,
    )
  }
  out
}

///|
/// 添加候选根（去重、去空）。
fn push_candidate_root(
  out : Array[(NdkSource, String)],
  seen : Array[String],
  source : NdkSource,
  path : String,
) -> Unit {
  let p = trim_trailing_sep(path)
  if p.is_blank() || seen.contains(p) {
    return
  }
  seen.push(p)
  out.push((source, p))
}

///|
/// 把父路径展开为候选根：`<sdk>/ndk` 下的版本目录按降序展开；无版本目录时把
/// 该目录自身当作候选（可能是直接落盘的 NDK 根），不存在时保留一条「未找到」记录。
fn roots_from_parents(
  parents : Array[ProbeParent],
  dir_exists : (String) -> Bool,
  list_dirs : (String) -> Array[String],
) -> Array[(NdkSource, String)] {
  let roots : Array[(NdkSource, String)] = []
  let seen : Array[String] = []
  for parent in parents {
    match parent.kind {
      DirectRoot => push_candidate_root(roots, seen, parent.source, parent.path)
      SdkNdkBundleDir =>
        if dir_exists(parent.path) {
          push_candidate_root(roots, seen, parent.source, parent.path)
        }
      SdkNdkDir =>
        if dir_exists(parent.path) {
          let versions = sort_version_dirs(list_dirs(parent.path))
          if versions.is_empty() {
            push_candidate_root(roots, seen, parent.source, parent.path)
          } else {
            for version in versions {
              push_candidate_root(
                roots,
                seen,
                parent.source,
                join_path(parent.path, version),
              )
            }
          }
        } else {
          push_candidate_root(roots, seen, parent.source, parent.path)
        }
    }
  }
  roots
}

///|
/// 解析 `source.properties` 中的 `Pkg.Revision`（官方 NDK 的版本来源）。
/// 找不到返回 `None`；纯函数、不读取文件。
fn parse_pkg_revision(text : String) -> String? {
  for raw in text.split("\n") {
    let line = raw.trim().to_owned()
    if line.has_prefix("Pkg.Revision") {
      match line.find("=") {
        Some(pos) => {
          let value = line[pos + 1:].trim().to_owned()
          if !value.is_empty() {
            return Some(value)
          }
        }
        None => ()
      }
    }
  }
  None
}

///|
/// 从目录名推断版本（`.../27.0.12077973`、`.../r27c`）；不像版本则 `None`。
fn version_from_dir_name(root : String) -> String? {
  let chars = root.to_array()
  let mut end = chars.length()
  while end > 0 && (chars[end - 1] == '\\' || chars[end - 1] == '/') {
    end = end - 1
  }
  let mut start = end
  while start > 0 && chars[start - 1] != '\\' && chars[start - 1] != '/' {
    start = start - 1
  }
  if end <= start {
    return None
  }
  let segment = root[start:end].to_owned()
  if looks_like_version(segment) {
    Some(segment)
  } else {
    None
  }
}

///|
/// 读取候选根的版本：优先 `source.properties` 的 `Pkg.Revision`，回退目录名。
fn ndk_version_at(root : String, read_text : (String) -> String?) -> String? {
  let props_path = join_path(root, "source.properties")
  match read_text(props_path) {
    Some(text) =>
      match parse_pkg_revision(text) {
        Some(v) => Some(v)
        None => version_from_dir_name(root)
      }
    None => version_from_dir_name(root)
  }
}

///|
/// 候选根的可用性判定路径：`<root>/toolchains/llvm/prebuilt`。
fn toolchain_prebuilt_path(root : String) -> String {
  join_path(join_path(join_path(root, "toolchains"), "llvm"), "prebuilt")
}

///|
/// 对候选根求值，产出结构化结果。纯函数：所有 I/O 由注入闭包提供。
fn evaluate_roots(
  roots : Array[(NdkSource, String)],
  dir_exists : (String) -> Bool,
  read_text : (String) -> String?,
) -> NdkProbeResult {
  let candidates : Array[NdkCandidate] = []
  let warnings : Array[String] = []
  let mut selected : String? = None
  let mut selected_version : String? = None
  for (source, root) in roots {
    let exists = dir_exists(root)
    let mut version : String? = None
    let mut usable = false
    if exists {
      version = ndk_version_at(root, read_text)
      usable = dir_exists(toolchain_prebuilt_path(root))
    }
    let note = if !exists {
      "not found"
    } else if !usable {
      "missing toolchains/llvm/prebuilt"
    } else {
      "ok"
    }
    candidates.push({ source, path: root, exists, usable, version, note, })
    if usable && selected is None {
      selected = Some(root)
      selected_version = version
    }
    if exists && !usable {
      warnings.push(
        "incomplete NDK candidate (missing toolchains/llvm/prebuilt): " + root,
      )
    }
  }
  match selected {
    Some(root) => {
      match selected_version {
        Some(_) => ()
        None =>
          warnings.push(
            "NDK version unknown at " +
            root +
            " (source.properties missing or unparsable)",
          )
      }
      {
        found: true,
        selected: Some(root),
        version: selected_version,
        candidates,
        warnings,
      }
    }
    None => {
      warnings.push(
        "NDK not found: checked " +
        candidates.length().to_string() +
        " candidate(s); set ANDROID_NDK_HOME/ANDROID_HOME or pass --ndk-root",
      )
      { found: false, selected: None, version: None, candidates, warnings, }
    }
  }
}

///|
/// 纯函数探测核心：目录存在性 / 目录列举 / 文本读取全部注入。
///
/// 测试用受控伪目录（闭包）即可覆盖「环境变量命中、SDK 版本目录取最高、
/// 候选不完整、全未找到」等分支，**不依赖**真机、真 NDK 或进程环境变量。
pub fn probe_ndk_with(
  inputs : NdkProbeInputs,
  dir_exists : (String) -> Bool,
  list_dirs : (String) -> Array[String],
  read_text : (String) -> String?,
) -> NdkProbeResult {
  let roots = roots_from_parents(probe_parents(inputs), dir_exists, list_dirs)
  evaluate_roots(roots, dir_exists, read_text)
}

///|
/// 空目录列举（`@fs.readdir` 失败时的安全回退）。
fn empty_dirs() -> Array[String] {
  []
}

///|
/// 在预取的目录列举表中查找。
fn lookup_listing(
  listings : Array[(String, Array[String])],
  path : String,
) -> Array[String] {
  for (p, names) in listings {
    if p == path {
      return names
    }
  }
  []
}

///|
/// 在预取的文本表中查找。
fn lookup_text(entries : Array[(String, String)], path : String) -> String? {
  for (p, text) in entries {
    if p == path {
      return Some(text)
    }
  }
  None
}

///|
/// 真实文件系统探测：先预取候选父路径的存在性/列举，再用同一纯核心判定；
/// `source.properties` 与 `toolchains/llvm/prebuilt` 同样预取。
/// 不执行任何外部命令，只做只读 stat/read；权限失败按「不存在/不可读」降级，
/// 不 panic。
pub async fn probe_ndk(inputs : NdkProbeInputs) -> NdkProbeResult {
  let parents = probe_parents(inputs)
  let parent_exists : Array[String] = []
  let listings : Array[(String, Array[String])] = []
  for parent in parents {
    let exists = @fs.exists(parent.path) catch { _ => false }
    if exists {
      parent_exists.push(parent.path)
      match parent.kind {
        SdkNdkDir => {
          let names = @fs.readdir(parent.path, sort=true) catch {
            _ => empty_dirs()
          }
          listings.push((parent.path, names))
        }
        _ => ()
      }
    }
  }
  let roots = roots_from_parents(
    parents,
    path => parent_exists.contains(path),
    path => lookup_listing(listings, path),
  )
  let root_exists : Array[String] = []
  let toolchain_paths : Array[String] = []
  let props : Array[(String, String)] = []
  for (_, root) in roots {
    let exists = @fs.exists(root) catch { _ => false }
    if exists {
      root_exists.push(root)
      let props_path = join_path(root, "source.properties")
      let has_props = @fs.exists(props_path) catch { _ => false }
      if has_props {
        let text = @fs.read_text(props_path) catch { _ => "" }
        props.push((props_path, text))
      }
      let prebuilt = toolchain_prebuilt_path(root)
      let has_prebuilt = @fs.exists(prebuilt) catch { _ => false }
      if has_prebuilt {
        toolchain_paths.push(prebuilt)
      }
    }
  }
  evaluate_roots(
    roots,
    path => root_exists.contains(path) || toolchain_paths.contains(path),
    path => lookup_text(props, path),
  )
}

///|
/// 来源的稳定名称（文本/JSON 输出用）。
fn source_name(source : NdkSource) -> String {
  match source {
    Explicit => "explicit"
    NdkHomeEnv => "ANDROID_NDK_HOME"
    AndroidHomeNdk => "ANDROID_HOME/ndk"
    AndroidSdkRootNdk => "ANDROID_SDK_ROOT/ndk"
    CommonPath => "common-path"
  }
}

///|
/// `Bool` → `true` / `false`（稳定文本，避免依赖 Debug 格式）。
fn bool_str(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
/// `String?` → 原值或空串（文本输出）。
fn option_str(value : String?) -> String {
  match value {
    Some(s) => s
    None => ""
  }
}

///|
/// 按 `\n` 拼接（不追加末尾换行）。
fn join_lines(lines : Array[String]) -> String {
  let mut out = ""
  let mut first = true
  for line in lines {
    if !first {
      out = out + "\n"
    }
    first = false
    out = out + line
  }
  out
}

///|
/// 拼接片段（无分隔符）。
fn concat_parts(parts : Array[String]) -> String {
  let mut out = ""
  for part in parts {
    out = out + part
  }
  out
}

///|
/// 十六进制 4 位小写（JSON `\uXXXX` 用）。
fn json_hex4(value : Int32) -> String {
  let digits = "0123456789abcdef"
  let mut out = ""
  let mut v = value
  let mut n = 0
  while n < 4 {
    let d = v & 0xF
    out = digits[d:d + 1].to_owned() + out
    v = v >> 4
    n = n + 1
  }
  out
}

///|
/// 最小 JSON 字符串转义（引号、反斜杠、控制字符）；输入含任意路径也安全。
fn json_escape(text : String) -> String {
  let parts : Array[String] = []
  parts.push("\"")
  for c in text.iter() {
    let v = c.to_int()
    if c == '"' {
      parts.push("\\\"")
    } else if c == '\\' {
      parts.push("\\\\")
    } else if c == '\n' {
      parts.push("\\n")
    } else if c == '\r' {
      parts.push("\\r")
    } else if c == '\t' {
      parts.push("\\t")
    } else if v < 0x20 {
      parts.push("\\u" + json_hex4(v))
    } else {
      parts.push(c.to_string())
    }
  }
  parts.push("\"")
  concat_parts(parts)
}

///|
/// `String?` → JSON 字符串或 `null`。
fn json_option(value : String?) -> String {
  match value {
    Some(s) => json_escape(s)
    None => "null"
  }
}

///|
/// 结构化文本输出（一行一条记录，字段顺序确定）：
/// `NDK|found=..|selected=..|version=..` / `CAND|source=..|exists=..|usable=..|version=..|path=..|note=..`
/// / `WARN|..`。供 CLI `probe` 默认模式使用。
pub fn ndk_probe_text(result : NdkProbeResult) -> String {
  let lines : Array[String] = []
  lines.push(
    "NDK|found=" +
    bool_str(result.found) +
    "|selected=" +
    option_str(result.selected) +
    "|version=" +
    option_str(result.version),
  )
  for candidate in result.candidates {
    lines.push(
      "CAND|source=" +
      source_name(candidate.source) +
      "|exists=" +
      bool_str(candidate.exists) +
      "|usable=" +
      bool_str(candidate.usable) +
      "|version=" +
      option_str(candidate.version) +
      "|path=" +
      candidate.path +
      "|note=" +
      candidate.note,
    )
  }
  for warning in result.warnings {
    lines.push("WARN|" + warning)
  }
  join_lines(lines)
}

///|
/// 结构化 JSON 输出（单行、字段顺序确定、转义合法）。供 CLI `probe --json` 使用。
pub fn ndk_probe_json(result : NdkProbeResult) -> String {
  let parts : Array[String] = []
  parts.push("{\"tool\":\"moon-abi\",\"found\":")
  parts.push(bool_str(result.found))
  parts.push(",\"selected\":")
  parts.push(json_option(result.selected))
  parts.push(",\"version\":")
  parts.push(json_option(result.version))
  parts.push(",\"candidates\":[")
  let mut first = true
  for candidate in result.candidates {
    if !first {
      parts.push(",")
    }
    first = false
    parts.push("{\"source\":")
    parts.push(json_escape(source_name(candidate.source)))
    parts.push(",\"path\":")
    parts.push(json_escape(candidate.path))
    parts.push(",\"exists\":")
    parts.push(bool_str(candidate.exists))
    parts.push(",\"usable\":")
    parts.push(bool_str(candidate.usable))
    parts.push(",\"version\":")
    parts.push(json_option(candidate.version))
    parts.push(",\"note\":")
    parts.push(json_escape(candidate.note))
    parts.push("}")
  }
  parts.push("],\"warnings\":[")
  first = true
  for warning in result.warnings {
    if !first {
      parts.push(",")
    }
    first = false
    parts.push(json_escape(warning))
  }
  parts.push("]}")
  concat_parts(parts)
}
