// Blackbox tests for CLI host wiring: `--host` parsing, host-aware generation,
// and the backward-compatible default-host resolution.
// 覆盖：宿主别名、旧参数等价、错误通道、三宿主 golden、多 ABI 顺序/确定性、
// 默认宿主矩阵（Windows/Linux 旧行为不变，macOS 修正为 darwin）。

///|
/// 宿主稳定标签（`NdkHost` 未 derive `Eq`，比较走标签）。
fn host_tag_of(host : @moon_abi.NdkHost) -> String {
  match host {
    @moon_abi.NdkHost::WindowsX86_64 => "windows-x86_64"
    @moon_abi.NdkHost::LinuxX86_64 => "linux-x86_64"
    @moon_abi.NdkHost::DarwinX86_64 => "darwin-x86_64"
  }
}

///|
/// 参数解析（错误即测试失败）。
fn parse_hosted_or_fail(
  argv : Array[String],
) -> @moon_abi.GenCommandWithHost raise Failure {
  @moon_abi.parse_gen_args_with_host(argv) catch {
    e => fail("unexpected parse error: " + @moon_abi.error_message(e))
  }
}

///|
/// 旧解析器参数解析（用于 base 等价性断言）。
fn parse_old_or_fail(
  argv : Array[String],
) -> @moon_abi.GenCommand raise Failure {
  @moon_abi.parse_gen_args(argv) catch {
    e => fail("unexpected old parse error: " + @moon_abi.error_message(e))
  }
}

///|
/// `GenCommand` 字段指纹串（与旧解析器逐字段比较）。
fn hosted_cmd_fingerprint(cmd : @moon_abi.GenCommand) -> String {
  let root = match cmd.ndk_root {
    Some(s) => "@" + s
    None => "-"
  }
  let ver = match cmd.ndk_version {
    Some(s) => "@" + s
    None => "-"
  }
  let out = match cmd.output {
    @moon_abi.GenOutput::Stdout => "stdout"
    @moon_abi.GenOutput::File(p) => "file:" + p
  }
  let style = match cmd.path_style {
    @moon_abi.PathStyle::Auto => "auto"
    @moon_abi.PathStyle::Windows => "windows"
    @moon_abi.PathStyle::Unix => "unix"
  }
  let abi = match cmd.abi {
    @moon_abi.Abi::ArmeabiV7a => "armeabi-v7a"
    @moon_abi.Abi::Arm64V8a => "arm64-v8a"
    @moon_abi.Abi::X86 => "x86"
    @moon_abi.Abi::X86_64 => "x86_64"
  }
  abi +
  "|" +
  cmd.api_level.level.to_string() +
  "|" +
  root +
  "|" +
  ver +
  "|" +
  out +
  "|" +
  style
}

///|
/// 测试用 profile（无空格 token）。
fn host_case_profile(
  root : String,
  windows_path_style : Bool,
) -> @moon_abi.NdkProfile {
  {
    ndk_root: root,
    ndk_version: "r27",
    api_level: @moon_abi.ApiLevel::{ level: 21, },
    extra_link_libs: [],
    extra_cc_flags: [],
    windows_path_style,
  }
}

///|
/// `host_from_name`：规范标签与别名，大小写/首尾空白归一。
test "host_from_name: 规范标签与别名" {
  for name in ["windows", "Windows", "win", "windows-x86_64", " WINDOWS "] {
    assert_eq(host_tag_of(@moon_abi.host_from_name(name)), "windows-x86_64")
  }
  for name in ["linux", "Linux", "linux-x86_64"] {
    assert_eq(host_tag_of(@moon_abi.host_from_name(name)), "linux-x86_64")
  }
  for name in ["darwin", "macOS", "mac", "osx", "darwin-x86_64"] {
    assert_eq(host_tag_of(@moon_abi.host_from_name(name)), "darwin-x86_64")
  }
  for name in ["android", "", "linux-musl", "mips"] {
    let err = @test.expect_error(() => @moon_abi.host_from_name(name))
    match err {
      @moon_abi.MoonAbiError::CliUsage(_) => ()
      _ => fail("expected CliUsage for host '" + name + "'")
    }
    assert_eq(@moon_abi.exit_code_for_error(err), 2)
  }
}

///|
/// `--host` 解析：显式宿主三种取值 + 未指定时为 None。
test "parse_gen_args_with_host: --host 取值与缺省" {
  let cases : Array[(Array[String], String)] = [
    (["--abi", "arm64", "--api", "21", "--host", "windows"], "windows-x86_64"),
    (["--abi", "arm64", "--api", "21", "--host=linux"], "linux-x86_64"),
    (["--abi", "arm64", "--api", "21", "--host", "darwin"], "darwin-x86_64"),
    (["--abi", "arm64", "--api", "21", "--host", "macos"], "darwin-x86_64"),
  ]
  for pair in cases {
    let (argv, expected) = pair
    let parsed = parse_hosted_or_fail(argv)
    match parsed.host {
      Some(h) => assert_eq(host_tag_of(h), expected)
      None => fail("expected explicit host for " + argv.join(" "))
    }
  }
  let legacy = parse_hosted_or_fail(["--abi", "arm64", "--api", "21"])
  match legacy.host {
    Some(_) => fail("expected no host when --host is absent")
    None => ()
  }
}

///|
/// 旧参数组合上 `parse_gen_args_with_host().command.base` 与 `parse_gen_args` 等价。
test "parse_gen_args_with_host: 旧参数 base 与旧解析器等价" {
  let cases : Array[Array[String]] = [
    ["--abi", "arm64-v8a", "--api", "21"],
    [
      "--abi", "armv7", "--api", "28", "--ndk-root", "/opt/android-ndk", "--ndk-version",
      "r27c", "--out", "moon.pkg", "--path-style", "unix",
    ],
    ["--abi", "x86_64", "--api", "34", "--out", "p.pkg"],
  ]
  for argv in cases {
    let parsed = parse_hosted_or_fail(argv)
    let old = parse_old_or_fail(argv)
    assert_eq(
      hosted_cmd_fingerprint(parsed.command.base),
      hosted_cmd_fingerprint(old),
    )
  }
}

///|
/// `--host` 错误通道：缺值 / 空值 / 非法值 / 重复 / 与 `--path-style` 互斥。
test "parse_gen_args_with_host: 错误一律 CliUsage 退出码 2" {
  let cases : Array[Array[String]] = [
    ["--abi", "arm64", "--api", "21", "--host"],
    ["--abi", "arm64", "--api", "21", "--host="],
    ["--abi", "arm64", "--api", "21", "--host", "android"],
    ["--abi", "arm64", "--api", "21", "--host", "linux", "--host", "darwin"],
    [
      "--abi", "arm64", "--api", "21", "--host", "darwin", "--path-style", "unix",
    ],
    [
      "--abi", "arm64", "--api", "21", "--host", "linux", "--path-style", "windows",
    ],
  ]
  for argv in cases {
    let err = @test.expect_error(() => @moon_abi.parse_gen_args_with_host(argv))
    match err {
      @moon_abi.MoonAbiError::CliUsage(_) => ()
      _ => fail("expected CliUsage for " + argv.join(" "))
    }
    assert_eq(@moon_abi.exit_code_for_error(err), 2)
  }
}

///|
/// 多 ABI + `--out` 的单块契约在带宿主解析下保持不变。
test "parse_gen_args_with_host: 多 ABI + --out 仍拒绝" {
  let err = @test.expect_error(() => {
    @moon_abi.parse_gen_args_with_host([
      "--abi", "arm64", "--abi", "x86", "--api", "21", "--out", "moon.pkg", "--host",
      "darwin",
    ])
  })
  match err {
    @moon_abi.MoonAbiError::CliUsage(msg) =>
      assert_true(msg.contains("single managed block"))
    _ => fail("expected CliUsage for multi ABI + --out")
  }
  assert_eq(@moon_abi.exit_code_for_error(err), 2)
}

///|
/// `generate_multi_with_host`：三宿主 golden cc 路径与分隔符。
test "generate_multi_with_host: 三宿主 golden cc 路径" {
  let win = @moon_abi.generate_multi_with_host(
    host_case_profile("C:\\android-ndk", false),
    [@moon_abi.Abi::Arm64V8a],
    @moon_abi.NdkHost::WindowsX86_64,
  ) catch {
    e => fail("unexpected windows host error: " + @moon_abi.error_message(e))
  }
  assert_eq(
    win[0].cc,
    "C:\\android-ndk\\toolchains\\llvm\\prebuilt\\windows-x86_64\\bin\\aarch64-linux-android21-clang",
  )
  let lin = @moon_abi.generate_multi_with_host(
    host_case_profile("/opt/ndk", true),
    [@moon_abi.Abi::Arm64V8a],
    @moon_abi.NdkHost::LinuxX86_64,
  ) catch {
    e => fail("unexpected linux host error: " + @moon_abi.error_message(e))
  }
  assert_eq(
    lin[0].cc,
    "/opt/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang",
  )
  let mac = @moon_abi.generate_multi_with_host(
    host_case_profile("/opt/ndk", true),
    [@moon_abi.Abi::Arm64V8a],
    @moon_abi.NdkHost::DarwinX86_64,
  ) catch {
    e => fail("unexpected darwin host error: " + @moon_abi.error_message(e))
  }
  assert_eq(
    mac[0].cc,
    "/opt/ndk/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android21-clang",
  )
  assert_eq(mac[0].cc_flags[0], "--target=aarch64-linux-android21")
  assert_eq(mac[0].cc_link_flags[0], "-llog")
  assert_eq(mac[0].cc_link_flags[1], "-landroid")
}

///|
/// `generate_multi_with_host`：按输入序、确定性、extra 落到 flags。
test "generate_multi_with_host: 顺序/确定性/extra" {
  let profile : @moon_abi.NdkProfile = {
    ndk_root: "/opt/ndk",
    ndk_version: "r27",
    api_level: @moon_abi.ApiLevel::{ level: 34, },
    extra_link_libs: ["foo"],
    extra_cc_flags: ["-DNDEBUG"],
    windows_path_style: false,
  }
  let first = @moon_abi.generate_multi_with_host(
    profile,
    [@moon_abi.Abi::X86, @moon_abi.Abi::Arm64V8a],
    @moon_abi.NdkHost::DarwinX86_64,
  ) catch {
    e => fail("unexpected generate error: " + @moon_abi.error_message(e))
  }
  let second = @moon_abi.generate_multi_with_host(
    profile,
    [@moon_abi.Abi::X86, @moon_abi.Abi::Arm64V8a],
    @moon_abi.NdkHost::DarwinX86_64,
  ) catch {
    e => fail("unexpected generate error: " + @moon_abi.error_message(e))
  }
  assert_eq(first.length(), 2)
  assert_eq(first[0].cc, second[0].cc)
  assert_eq(first[1].cc, second[1].cc)
  assert_true(first[0].cc.contains("i686-linux-android34-clang"))
  assert_true(first[1].cc.contains("aarch64-linux-android34-clang"))
  assert_eq(first[1].cc_flags[1], "-DNDEBUG")
  assert_eq(first[1].cc_link_flags[2], "-lfoo")
}

///|
/// `generate_multi_with_host`：空数组 → CliUsage 退出码 2。
test "generate_multi_with_host: 空数组 CliUsage" {
  let err = @test.expect_error(() => {
    @moon_abi.generate_multi_with_host(
      host_case_profile("/opt/ndk", false),
      [],
      @moon_abi.NdkHost::LinuxX86_64,
    )
  })
  match err {
    @moon_abi.MoonAbiError::CliUsage(_) => ()
    _ => fail("expected CliUsage for empty ABI list")
  }
  assert_eq(@moon_abi.exit_code_for_error(err), 2)
}

///|
/// `resolve_default_host` 矩阵：Windows/Linux 维持旧路径风格行为，macOS 修正为 darwin。
test "resolve_default_host: 兼容矩阵" {
  let hosts : Array[@moon_abi.NdkHost] = [
    @moon_abi.NdkHost::WindowsX86_64,
    @moon_abi.NdkHost::LinuxX86_64,
    @moon_abi.NdkHost::DarwinX86_64,
  ]
  for running in hosts {
    assert_eq(
      host_tag_of(@moon_abi.resolve_default_host(true, running)),
      "windows-x86_64",
    )
  }
  assert_eq(
    host_tag_of(
      @moon_abi.resolve_default_host(false, @moon_abi.NdkHost::DarwinX86_64),
    ),
    "darwin-x86_64",
  )
  assert_eq(
    host_tag_of(
      @moon_abi.resolve_default_host(false, @moon_abi.NdkHost::LinuxX86_64),
    ),
    "linux-x86_64",
  )
  assert_eq(
    host_tag_of(
      @moon_abi.resolve_default_host(false, @moon_abi.NdkHost::WindowsX86_64),
    ),
    "linux-x86_64",
  )
}
