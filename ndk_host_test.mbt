// W5 宿主平台与 API 矩阵纵深（blackbox）：
// 三宿主标签/路径 golden、旧 generate 逐字节防火墙、API 上限 advisory 边界三态。

///|
/// 测试用 profile（`windows_path_style` 由具体用例决定）。
fn host_profile(
  ndk_root : String,
  ndk_version : String,
  level : Int32,
  windows_path_style : Bool,
) -> @moon_abi.NdkProfile {
  {
    ndk_root,
    ndk_version,
    api_level: @moon_abi.ApiLevel::{ level, },
    extra_link_libs: [],
    extra_cc_flags: [],
    windows_path_style,
  }
}

///|
/// T-W5-1：三宿主标签冻结。
test "host_tag: 三宿主标签 (T-W5-1)" {
  assert_eq(
    @moon_abi.host_tag(@moon_abi.NdkHost::WindowsX86_64),
    "windows-x86_64",
  )
  assert_eq(@moon_abi.host_tag(@moon_abi.NdkHost::LinuxX86_64), "linux-x86_64")
  assert_eq(
    @moon_abi.host_tag(@moon_abi.NdkHost::DarwinX86_64),
    "darwin-x86_64",
  )
}

///|
/// T-W5-1：三宿主 golden cc 路径（分隔符 + `prebuilt` 标签）。
test "generate_with_host: 三宿主 golden cc 路径 (T-W5-1)" {
  let win = @moon_abi.generate_with_host(
    host_profile("C:\\ndk", "r27", 21, true),
    @moon_abi.Abi::Arm64V8a,
    @moon_abi.NdkHost::WindowsX86_64,
  )
  assert_eq(
    win.cc,
    "C:\\ndk\\toolchains\\llvm\\prebuilt\\windows-x86_64\\bin\\aarch64-linux-android21-clang",
  )
  let lin = @moon_abi.generate_with_host(
    host_profile("/opt/ndk", "r27", 21, false),
    @moon_abi.Abi::Arm64V8a,
    @moon_abi.NdkHost::LinuxX86_64,
  )
  assert_eq(
    lin.cc,
    "/opt/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang",
  )
  let mac = @moon_abi.generate_with_host(
    host_profile("/opt/ndk", "r27", 21, false),
    @moon_abi.Abi::Arm64V8a,
    @moon_abi.NdkHost::DarwinX86_64,
  )
  assert_eq(
    mac.cc,
    "/opt/ndk/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android21-clang",
  )
}

///|
/// T-W5-2：Windows/Linux 两宿主输出与旧 `generate` 逐字节一致
/// （新函数忽略 `profile.windows_path_style`，旧 API 输出不变）。
test "generate_with_host: win/linux 与旧 generate 逐字节一致 (T-W5-2)" {
  let abi = @moon_abi.Abi::Arm64V8a
  let win_profile = host_profile("C:\\ndk", "r27", 21, true)
  let old_win = @moon_abi.generate(win_profile, abi)
  let new_win = @moon_abi.generate_with_host(
    win_profile,
    abi,
    @moon_abi.NdkHost::WindowsX86_64,
  )
  assert_eq(old_win.cc, new_win.cc)
  assert_eq(old_win.cc_flags.join(" "), new_win.cc_flags.join(" "))
  assert_eq(old_win.cc_link_flags.join(" "), new_win.cc_link_flags.join(" "))
  let lin_profile = host_profile("/opt/ndk", "r27", 21, false)
  let old_lin = @moon_abi.generate(lin_profile, abi)
  let new_lin = @moon_abi.generate_with_host(
    lin_profile,
    abi,
    @moon_abi.NdkHost::LinuxX86_64,
  )
  assert_eq(old_lin.cc, new_lin.cc)
  assert_eq(old_lin.cc_flags.join(" "), new_lin.cc_flags.join(" "))
}

///|
/// T-W5-3：advisory 边界三态（不可解析/未知 major 零警告；恰等于上限零警告；超上限告警）。
test "api_level_advisory: 边界三态 (T-W5-3)" {
  assert_eq(
    @moon_abi.api_level_advisory(host_profile("/opt/ndk", "banana", 99, false)).length(),
    0,
  )
  assert_eq(
    @moon_abi.api_level_advisory(host_profile("/opt/ndk", "r28", 99, false)).length(),
    0,
  )
  assert_eq(
    @moon_abi.api_level_advisory(host_profile("/opt/ndk", "r27", 35, false)).length(),
    0,
  )
  let warn = @moon_abi.api_level_advisory(
    host_profile("/opt/ndk", "r27", 36, false),
  )
  assert_eq(warn.length(), 1)
  assert_true(warn[0].contains("36"))
  assert_true(warn[0].contains("35"))
  assert_eq(
    @moon_abi.api_level_advisory(host_profile("/opt/ndk", "r22", 30, false)).length(),
    0,
  )
  assert_eq(
    @moon_abi.api_level_advisory(host_profile("/opt/ndk", "r22", 31, false)).length(),
    1,
  )
  assert_eq(
    @moon_abi.api_level_advisory(
      host_profile("/opt/ndk", "27.0.12077973", 36, false),
    ).length(),
    1,
  )
}
