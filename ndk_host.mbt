///|
/// 宿主平台与 API 矩阵纵深（W5/M3）：三宿主 clang 路径与 API 上限 advisory。
///
/// 纯加法：新增 `NdkHost` / `host_tag` / `generate_with_host` / `api_level_advisory`。
/// 旧 `generate` / `validate` / `cc_path` 一行不动、语义与输出逐字节不变（防火墙 T-W5-2）。
/// 宿主标签数据表已联网核实（2026-11-26，见 docs/CHANGELOG.md）；advisory 只产警告、不阻断。

///|
/// NDK 工具链宿主平台（决定 `toolchains/llvm/prebuilt/<host>` 标签与路径分隔符）。
pub(all) enum NdkHost {
  WindowsX86_64
  LinuxX86_64
  DarwinX86_64
}

///|
/// 宿主平台标签：`windows-x86_64` / `linux-x86_64` / `darwin-x86_64`。
/// 与 NDK r22+ `toolchains/llvm/prebuilt/` 下的目录名一致（darwin 标签 2026-11-26 联网核实）。
pub fn host_tag(host : NdkHost) -> String {
  match host {
    WindowsX86_64 => "windows-x86_64"
    LinuxX86_64 => "linux-x86_64"
    DarwinX86_64 => "darwin-x86_64"
  }
}

///|
/// 宿主平台路径分隔符：Windows `\`，其余 `/`。
fn host_sep(host : NdkHost) -> String {
  match host {
    WindowsX86_64 => "\\"
    LinuxX86_64 => "/"
    DarwinX86_64 => "/"
  }
}

///|
/// 按显式宿主标签/分隔符拼接 clang 路径（与 `cc_path` 同构，但宿主由参数决定）。
fn cc_path_with_host(
  ndk_root : String,
  sep : String,
  host : String,
  triple_prefix : String,
  level : Int32,
) -> String {
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
/// 按显式宿主生成 `LinkNativeConfig`：分隔符与 `prebuilt` 宿主标签均由 `host` 决定，
/// **忽略** `profile.windows_path_style`（该字段仅影响旧 `generate`；新函数以 host 为准）。
/// 其余注入逻辑（校验顺序、`--target`、extra flag/lib、`stub_cc`）与 `generate` 一致；
/// Windows/Linux 两宿主输出与旧 `generate` 逐字节相同（T-W5-2 防火墙）。
/// - 错误：`MissingNdkRoot` / `UnsupportedApiLevel` / `VersionMismatch` 同 `generate`。
/// - 纯函数、确定性、可并发。
pub fn generate_with_host(
  profile : NdkProfile,
  abi : Abi,
  host : NdkHost,
) -> LinkNativeConfig raise MoonAbiError {
  if profile.ndk_root.is_blank() {
    raise MissingNdkRoot
  }
  check_api_level(profile.api_level)
  check_ndk_version(profile.ndk_version)
  let t = triple_of(abi)
  let tname = triple_name(t)
  let sep = host_sep(host)
  let tag = host_tag(host)
  let cc = cc_path_with_host(
    profile.ndk_root,
    sep,
    tag,
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
/// 内置「NDK major → 已知最高 API」保守数据表（2026-11-26 联网核实）：
/// r22→30 / r23→31 / r24→32 / r25→33 / r26→34 / r27→35。
fn known_max_api(major : Int32) -> Int32? {
  if major == 22 {
    Some(30)
  } else if major == 23 {
    Some(31)
  } else if major == 24 {
    Some(32)
  } else if major == 25 {
    Some(33)
  } else if major == 26 {
    Some(34)
  } else if major == 27 {
    Some(35)
  } else {
    None
  }
}

///|
/// API level 上限 advisory：`profile.api_level` 高于该 NDK major 已知最高 API 时，
/// 返回一条警告串；否则返回空数组。
/// - 版本不可解析或 major 不在数据表内 → 空数组（不猜测、不告警）。
/// - 纯函数、确定性、不阻断（仅提示 clang 可能缺头文件）。
pub fn api_level_advisory(profile : NdkProfile) -> Array[String] {
  let out : Array[String] = []
  match ndk_major(profile.ndk_version) {
    Some(major) =>
      match known_max_api(major) {
        Some(limit) =>
          if profile.api_level.level > limit {
            out.push(
              "API level " +
              profile.api_level.level.to_string() +
              " exceeds the known maximum " +
              limit.to_string() +
              " for NDK r" +
              major.to_string() +
              "; clang may not provide headers for it",
            )
          }
        None => ()
      }
    None => ()
  }
  out
}
