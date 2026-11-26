// Blackbox tests for the R4 CLI core: argument parsing, exit-code contract,
// managed-block merge, idempotent write, and injected I/O failures.
// 覆盖：合法/非法 ABI 名、参数错误、退出码 2/1 契约、幂等合并、权限拒绝与磁盘满注入。

///|
/// 测试用配置（无空格 token，`managed_block` 可安全渲染）。
fn sample_config() -> @moon_abi.LinkNativeConfig {
  {
    cc: "C:\\android-ndk\\toolchains\\llvm\\prebuilt\\windows-x86_64\\bin\\aarch64-linux-android21-clang",
    cc_flags: ["--target=aarch64-linux-android21"],
    cc_link_flags: ["-llog", "-landroid"],
    stub_cc: None,
    supported_targets: "native",
    triple: @moon_abi.TargetTriple::Aarch64LinuxAndroid,
    abi: @moon_abi.Abi::Arm64V8a,
    api_level: @moon_abi.ApiLevel::{ level: 21, },
  }
}

///|
/// 测试用受管块（渲染失败视为测试失败）。
fn block_or_fail() -> String raise Failure {
  @moon_abi.managed_block(sample_config()) catch {
    e => fail("unexpected render error: " + @moon_abi.error_message(e))
  }
}

///|
/// ABI 名解析（非法即测试失败）。
fn abi_or_fail(name : String) -> @moon_abi.Abi raise Failure {
  @moon_abi.abi_from_name(name) catch {
    e =>
      fail("unexpected error for '" + name + "': " + @moon_abi.error_message(e))
  }
}

///|
/// 参数解析（错误即测试失败）。
fn parse_or_fail(argv : Array[String]) -> @moon_abi.GenCommand raise Failure {
  @moon_abi.parse_gen_args(argv) catch {
    e => fail("unexpected parse error: " + @moon_abi.error_message(e))
  }
}

///|
/// 合并（错误即测试失败）。
fn merge_or_fail(
  existing : String,
  block : String,
) -> @moon_abi.MergeResult raise Failure {
  @moon_abi.merge_link_config(existing, block) catch {
    e => fail("unexpected merge error: " + @moon_abi.error_message(e))
  }
}

///|
test "abi_from_name: 规范名与别名" {
  for name in ["armeabi-v7a", "armv7", "ARMv7A", "v7a"] {
    match abi_or_fail(name) {
      @moon_abi.Abi::ArmeabiV7a => ()
      _ => fail("expected ArmeabiV7a for " + name)
    }
  }
  for name in ["arm64-v8a", "arm64", "aarch64"] {
    match abi_or_fail(name) {
      @moon_abi.Abi::Arm64V8a => ()
      _ => fail("expected Arm64V8a for " + name)
    }
  }
  match abi_or_fail("x86") {
    @moon_abi.Abi::X86 => ()
    _ => fail("expected X86")
  }
  for name in ["x86_64", "x64", "X86-64"] {
    match abi_or_fail(name) {
      @moon_abi.Abi::X86_64 => ()
      _ => fail("expected X86_64 for " + name)
    }
  }
}

///|
test "abi_from_name: 非法名抛 UnsupportedAbi 且映射退出码 2" {
  for name in ["mips", "armv8", "", "armeabi-v8a"] {
    let err = @test.expect_error(() => @moon_abi.abi_from_name(name))
    match err {
      @moon_abi.MoonAbiError::UnsupportedAbi(got) => assert_eq(got, name)
      _ => fail("expected UnsupportedAbi for '" + name + "'")
    }
    assert_eq(@moon_abi.exit_code_for_error(err), 2)
  }
}

///|
test "parse_gen_args: 最小合法命令" {
  let cmd = parse_or_fail(["--abi", "arm64-v8a", "--api", "21"])
  assert_eq(cmd.api_level.level, 21)
  match cmd.abi {
    @moon_abi.Abi::Arm64V8a => ()
    _ => fail("expected Arm64V8a")
  }
  match cmd.ndk_root {
    Some(_) => fail("expected no ndk root")
    None => ()
  }
  match cmd.ndk_version {
    Some(_) => fail("expected no ndk version")
    None => ()
  }
  match cmd.output {
    @moon_abi.GenOutput::Stdout => ()
    _ => fail("expected stdout output")
  }
  match cmd.path_style {
    @moon_abi.PathStyle::Auto => ()
    _ => fail("expected auto path style")
  }
}

///|
test "parse_gen_args: 全部选项 + 内联 = 写法" {
  let cmd = parse_or_fail([
    "--abi=armv7", "--api=28", "--ndk-root", "/opt/android-ndk", "--ndk-version",
    "r27c", "--out", "moon.pkg", "--path-style", "unix",
  ])
  assert_eq(cmd.api_level.level, 28)
  match cmd.abi {
    @moon_abi.Abi::ArmeabiV7a => ()
    _ => fail("expected ArmeabiV7a")
  }
  match cmd.ndk_root {
    Some(root) => assert_eq(root, "/opt/android-ndk")
    None => fail("expected ndk root")
  }
  match cmd.ndk_version {
    Some(version) => assert_eq(version, "r27c")
    None => fail("expected ndk version")
  }
  match cmd.output {
    @moon_abi.GenOutput::File(path) => assert_eq(path, "moon.pkg")
    _ => fail("expected file output")
  }
  match cmd.path_style {
    @moon_abi.PathStyle::Unix => ()
    _ => fail("expected unix path style")
  }
}

///|
test "parse_gen_args: 参数错误映射退出码 2" {
  let cases : Array[Array[String]] = [
    [],
    ["--api", "21"],
    ["--abi", "x86_64"],
    ["--abi", "mips", "--api", "21"],
    ["--abi", "x86", "--api", "20"],
    ["--abi", "x86", "--api", "abc"],
    ["--abi", "x86", "--api"],
    ["--abi", "x86", "--api", "21", "--bogus"],
    ["--abi", "x86", "--api", "21", "--api", "28"],
    ["--abi", "x86", "--api", "21", "--out"],
    ["--abi", "x86", "--api", "21", "--out", "a", "--out", "b"],
    ["--abi", "x86", "--api", "21", "--path-style", "plan9"],
    ["--abi", "x86", "--api", "99999999999"],
    ["unexpected"],
  ]
  for argv in cases {
    let err = @test.expect_error(() => @moon_abi.parse_gen_args(argv))
    assert_eq(@moon_abi.exit_code_for_error(err), 2)
  }
}

///|
test "parse_gen_args: CliUsage 显式变体簿记（W2）" {
  let cases : Array[Array[String]] = [
    [],
    ["--api", "21"],
    ["--abi", "x86", "--api", "21", "--bogus"],
    ["--abi", "x86", "--api"],
    ["--abi", "x86", "--api", "21", "--out"],
    ["--abi", "x86", "--api", "21", "--path-style", "plan9"],
  ]
  for argv in cases {
    let err = @test.expect_error(() => @moon_abi.parse_gen_args(argv))
    match err {
      @moon_abi.MoonAbiError::CliUsage(reason) =>
        assert_false(reason.is_empty())
      _ => fail("expected CliUsage variant")
    }
    assert_eq(@moon_abi.exit_code_for_error(err), 2)
  }
}

///|
test "exit_code_for_error: 参数错误 2 / 运行错误 1" {
  let usage_error = @test.expect_error(() => {
    let _ = @moon_abi.parse_gen_args([])
  })
  assert_eq(@moon_abi.exit_code_for_error(usage_error), 2)
  let abi_error = @test.expect_error(() => @moon_abi.abi_from_name("mips"))
  assert_eq(@moon_abi.exit_code_for_error(abi_error), 2)
  let api_error = @test.expect_error(() => {
    @moon_abi.clang_name(@moon_abi.Abi::X86, @moon_abi.ApiLevel::{ level: 20, })
  })
  assert_eq(@moon_abi.exit_code_for_error(api_error), 2)
  let ndk_root_error = @test.expect_error(() => {
    @moon_abi.generate(
      {
        ndk_root: "",
        ndk_version: "r27",
        api_level: @moon_abi.ApiLevel::{ level: 21, },
        extra_link_libs: [],
        extra_cc_flags: [],
        windows_path_style: false,
      },
      @moon_abi.Abi::X86,
    )
  })
  assert_eq(@moon_abi.exit_code_for_error(ndk_root_error), 1)
  let version_error = @test.expect_error(() => {
    @moon_abi.generate(
      {
        ndk_root: "/opt/ndk",
        ndk_version: "r1",
        api_level: @moon_abi.ApiLevel::{ level: 21, },
        extra_link_libs: [],
        extra_cc_flags: [],
        windows_path_style: false,
      },
      @moon_abi.Abi::X86,
    )
  })
  assert_eq(@moon_abi.exit_code_for_error(version_error), 1)
}

///|
test "error_message: 人读消息稳定且不 panic" {
  let err = @test.expect_error(() => {
    let _ = @moon_abi.parse_gen_args([])
  })
  assert_true(
    @moon_abi.error_message(err).contains("missing required option --abi"),
  )
  let abi_err = @test.expect_error(() => @moon_abi.abi_from_name("mips"))
  assert_true(@moon_abi.error_message(abi_err).contains("mips"))
}

///|
test "windows_path_style_of: 盘符与反斜杠" {
  assert_true(@moon_abi.windows_path_style_of("C:\\android-ndk"))
  assert_true(@moon_abi.windows_path_style_of("C:/android-ndk"))
  assert_false(@moon_abi.windows_path_style_of("/opt/android-ndk"))
  assert_false(@moon_abi.windows_path_style_of(""))
}

///|
test "managed_block: 起止标记 + 渲染文本 + 确定性" {
  let block = block_or_fail()
  assert_true(block.has_prefix("// >>> moon_abi gen:managed"))
  assert_true(block.contains("options("))
  assert_true(block.has_suffix("// <<< moon_abi gen:managed <<<\n"))
  assert_eq(block, block_or_fail())
}

///|
test "merge_link_config: 空文件追加 + 二次合并幂等" {
  let block = block_or_fail()
  let first = merge_or_fail("", block)
  match first.action {
    @moon_abi.MergeAction::Appended => ()
    _ => fail("expected Appended")
  }
  assert_eq(first.content, block)
  let second = merge_or_fail(first.content, block)
  match second.action {
    @moon_abi.MergeAction::Unchanged => ()
    _ => fail("expected Unchanged")
  }
  assert_eq(second.content, first.content)
  assert_eq(@moon_abi.merge_action_name(second.action), "unchanged")
}

///|
test "merge_link_config: 保留块外用户内容并补尾换行" {
  let block = block_or_fail()
  let merged = merge_or_fail("// user header\n", block)
  assert_true(merged.content.has_prefix("// user header\n"))
  assert_true(merged.content.contains(block))
  let no_newline = merge_or_fail("// user header", block)
  assert_true(no_newline.content.has_prefix("// user header\n// >>> moon_abi"))
}

///|
test "merge_link_config: 既有受管块被替换" {
  let block = block_or_fail()
  let old = "// >>> moon_abi gen:managed (do not edit this block) >>>\noptions(old)\n// <<< moon_abi gen:managed <<<\n"
  let existing = "// head\n" + old + "// tail\n"
  let merged = merge_or_fail(existing, block)
  match merged.action {
    @moon_abi.MergeAction::Replaced => ()
    _ => fail("expected Replaced")
  }
  assert_true(merged.content.has_prefix("// head\n// >>> moon_abi"))
  assert_true(
    merged.content.has_suffix("// <<< moon_abi gen:managed <<<\n// tail\n"),
  )
  assert_false(merged.content.contains("options(old)"))
}

///|
test "merge_link_config: 畸形标记抛 MalformedConfig 且退出码 1" {
  let block = block_or_fail()
  let unterminated = "// >>> moon_abi gen:managed (do not edit this block) >>>\noptions()\n"
  let err1 = @test.expect_error(() => {
    @moon_abi.merge_link_config(unterminated, block)
  })
  match err1 {
    @moon_abi.MoonAbiError::MalformedConfig(_) => ()
    _ => fail("expected MalformedConfig (unterminated)")
  }
  assert_eq(@moon_abi.exit_code_for_error(err1), 1)
  let orphan_end = "// <<< moon_abi gen:managed <<<\n"
  let err2 = @test.expect_error(() => {
    @moon_abi.merge_link_config(orphan_end, block)
  })
  match err2 {
    @moon_abi.MoonAbiError::MalformedConfig(_) => ()
    _ => fail("expected MalformedConfig (orphan end)")
  }
  let doubled = block + block
  let err3 = @test.expect_error(() => {
    @moon_abi.merge_link_config(doubled, block)
  })
  match err3 {
    @moon_abi.MoonAbiError::MalformedConfig(_) => ()
    _ => fail("expected MalformedConfig (multiple blocks)")
  }
  let empty_block = @test.expect_error(() => @moon_abi.merge_link_config("", ""))
  match empty_block {
    @moon_abi.MoonAbiError::MalformedConfig(_) => ()
    _ => fail("expected MalformedConfig (empty block)")
  }
}

///|
/// W3 fail-closed：单 begin + 多 end 标记抛 MalformedConfig（旧 B15：孤儿 end 静默残留）。
test "merge_link_config: 多 END 标记抛 MalformedConfig (W3)" {
  let block = block_or_fail()
  let multi_end = "// >>> moon_abi gen:managed (do not edit this block) >>>\noptions()\n// <<< moon_abi gen:managed <<<\n// <<< moon_abi gen:managed <<<\n"
  let err = @test.expect_error(() => {
    @moon_abi.merge_link_config(multi_end, block)
  })
  match err {
    @moon_abi.MoonAbiError::MalformedConfig(msg) =>
      assert_true(msg.contains("multiple managed block end markers"))
    _ => fail("expected MalformedConfig (multiple end markers)")
  }
  assert_eq(@moon_abi.exit_code_for_error(err), 1)
}

///|
test "write_config_with: 不存在则追加并写盘" {
  let block = block_or_fail()
  let written : Array[String] = []
  let read = _path => @moon_abi.ReadOutcome::NotFound
  let write = (_path, content) => {
    written.push(content)
    Ok(())
  }
  let result = @moon_abi.write_config_with("moon.pkg", block, read, write) catch {
    e => fail("unexpected: " + @moon_abi.error_message(e))
  }
  match result.action {
    @moon_abi.MergeAction::Appended => ()
    _ => fail("expected Appended")
  }
  assert_eq(written.length(), 1)
  assert_eq(written[0], result.content)
}

///|
test "write_config_with: 已一致时不写盘" {
  let block = block_or_fail()
  let read = _path => @moon_abi.ReadOutcome::Found(block)
  let write = (_path, _content) => Err("write must not be called")
  let result = @moon_abi.write_config_with("moon.pkg", block, read, write) catch {
    e => fail("unexpected: " + @moon_abi.error_message(e))
  }
  match result.action {
    @moon_abi.MergeAction::Unchanged => ()
    _ => fail("expected Unchanged")
  }
}

///|
test "write_config_with: 权限拒绝/磁盘满/读失败注入 → IoFailure" {
  let block = block_or_fail()
  let not_found = _path => @moon_abi.ReadOutcome::NotFound
  let permission = @test.expect_error(() => {
    @moon_abi.write_config_with("moon.pkg", block, not_found, (_p, _c) => {
      Err("permission denied")
    })
  })
  match permission {
    @moon_abi.MoonAbiError::IoFailure(path, reason) => {
      assert_eq(path, "moon.pkg")
      assert_true(reason.contains("permission denied"))
    }
    _ => fail("expected IoFailure (permission)")
  }
  let disk_full = @test.expect_error(() => {
    @moon_abi.write_config_with("moon.pkg", block, not_found, (_p, _c) => {
      Err("No space left on device")
    })
  })
  match disk_full {
    @moon_abi.MoonAbiError::IoFailure(_, reason) =>
      assert_true(reason.contains("No space left on device"))
    _ => fail("expected IoFailure (disk full)")
  }
  let read_failed = @test.expect_error(() => {
    @moon_abi.write_config_with(
      "moon.pkg",
      block,
      _p => @moon_abi.ReadOutcome::Failed("permission denied"),
      (_p, _c) => Ok(()),
    )
  })
  match read_failed {
    @moon_abi.MoonAbiError::IoFailure(_, reason) =>
      assert_true(reason.contains("permission denied"))
    _ => fail("expected IoFailure (read)")
  }
  assert_eq(@moon_abi.exit_code_for_error(permission), 1)
  assert_eq(@moon_abi.exit_code_for_error(disk_full), 1)
}

///|
/// W4：扩展解析（错误即测试失败）。
fn parse_ext_or_fail(
  argv : Array[String],
) -> @moon_abi.GenCommandExt raise Failure {
  @moon_abi.parse_gen_args_ext(argv) catch {
    e => fail("unexpected parse_ext error: " + @moon_abi.error_message(e))
  }
}

///|
/// W4：多 ABI 生成（错误即测试失败）。
fn generate_multi_or_fail(
  profile : @moon_abi.NdkProfile,
  abis : Array[@moon_abi.Abi],
) -> Array[@moon_abi.LinkNativeConfig] raise Failure {
  @moon_abi.generate_multi(profile, abis) catch {
    e => fail("unexpected generate_multi error: " + @moon_abi.error_message(e))
  }
}

///|
/// W4 helper：`Abi` 稳定标签（`Abi` 未 derive `Eq`，比较走标签）。
fn abi_tag(abi : @moon_abi.Abi) -> String {
  match abi {
    @moon_abi.Abi::ArmeabiV7a => "armeabi-v7a"
    @moon_abi.Abi::Arm64V8a => "arm64-v8a"
    @moon_abi.Abi::X86 => "x86"
    @moon_abi.Abi::X86_64 => "x86_64"
  }
}

///|
/// W4 helper：把 `GenCommand` 归一为字段指纹串，供 base 与旧解析器等价性断言。
fn cmd_fingerprint(cmd : @moon_abi.GenCommand) -> String {
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
  abi_tag(cmd.abi) +
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
/// T-W4-1：旧参数组合上 `parse_gen_args_ext().base` 与 `parse_gen_args` 逐字段等价。
test "parse_gen_args_ext: base 与旧 parse_gen_args 等价 (T-W4-1)" {
  let cases : Array[Array[String]] = [
    ["--abi", "arm64-v8a", "--api", "21"],
    [
      "--abi=armv7", "--api=28", "--ndk-root", "/opt/android-ndk", "--ndk-version",
      "r27c", "--out", "moon.pkg", "--path-style", "unix",
    ],
    ["--abi", "x86_64", "--api", "34", "--out", "p.pkg"],
  ]
  for argv in cases {
    let ext = parse_ext_or_fail(argv)
    let old = parse_or_fail(argv)
    assert_eq(cmd_fingerprint(ext.base), cmd_fingerprint(old))
  }
}

///|
/// T-W4-1：多 ABI 去重保序 + extra 选项原序收集。
/// 注意：`--extra-cc-flag` 的下一个 token 若以 `-` 开头会被 `take_flag_value` 拒绝
/// （共享旧解析器语义），故 cc flag 用内联 `=` 形式传入。
test "parse_gen_args_ext: 多 ABI 去重保序 + extra 选项 (T-W4-1)" {
  let ext = parse_ext_or_fail([
    "--abi", "x86", "--abi", "arm64", "--abi", "x86", "--abi", "armeabi-v7a", "--api",
    "21", "--extra-lib", "foo", "--extra-lib", "bar", "--extra-cc-flag=-DNDEBUG",
  ])
  assert_eq(ext.abis.length(), 3)
  assert_eq(abi_tag(ext.abis[0]), "x86")
  assert_eq(abi_tag(ext.abis[1]), "arm64-v8a")
  assert_eq(abi_tag(ext.abis[2]), "armeabi-v7a")
  assert_eq(abi_tag(ext.base.abi), "x86")
  assert_eq(ext.extra_link_libs.length(), 2)
  assert_eq(ext.extra_link_libs[0], "foo")
  assert_eq(ext.extra_link_libs[1], "bar")
  assert_eq(ext.extra_cc_flags.length(), 1)
  assert_eq(ext.extra_cc_flags[0], "-DNDEBUG")
}

///|
/// T-W4-1：cc flag 内联 `=` 形式原序保留。
test "parse_gen_args_ext: cc flag 内联 = 形式原序保留 (T-W4-1)" {
  let ext = parse_ext_or_fail([
    "--abi", "arm64", "--api", "21", "--extra-cc-flag=-DNDEBUG", "--extra-cc-flag=-O2",
  ])
  assert_eq(ext.extra_cc_flags.length(), 2)
  assert_eq(ext.extra_cc_flags[0], "-DNDEBUG")
  assert_eq(ext.extra_cc_flags[1], "-O2")
}

///|
/// T-W4-1：`--extra-cc-flag` 后跟 `-` 开头的 token 按共享语义抛 CliUsage 退出码 2。
test "parse_gen_args_ext: cc flag 下一个 token 以 - 开头抛 CliUsage (T-W4-1)" {
  let err = @test.expect_error(() => {
    @moon_abi.parse_gen_args_ext([
      "--abi", "arm64", "--api", "21", "--extra-cc-flag", "-DNDEBUG",
    ])
  })
  match err {
    @moon_abi.MoonAbiError::CliUsage(_) => ()
    _ => fail("expected CliUsage (cc flag next token starts with -)")
  }
  assert_eq(@moon_abi.exit_code_for_error(err), 2)
}

///|
/// T-W4-1：extra 空值抛 CliUsage 退出码 2（内联 `=` 空值也拒绝）。
test "parse_gen_args_ext: extra 空值抛 CliUsage 退出码 2 (T-W4-1)" {
  let cases : Array[Array[String]] = [
    ["--abi", "arm64", "--api", "21", "--extra-lib", ""],
    ["--abi", "arm64", "--api", "21", "--extra-lib="],
    ["--abi", "arm64", "--api", "21", "--extra-cc-flag", ""],
    ["--abi", "arm64", "--api", "21", "--extra-cc-flag="],
  ]
  for argv in cases {
    let err = @test.expect_error(() => @moon_abi.parse_gen_args_ext(argv))
    match err {
      @moon_abi.MoonAbiError::CliUsage(_) => ()
      _ => fail("expected CliUsage for empty extra value")
    }
    assert_eq(@moon_abi.exit_code_for_error(err), 2)
  }
}

///|
/// T-W4-3：多 ABI + `--out` 互斥 → CliUsage 退出码 2（单块契约）；去重后单 ABI 仍合法。
test "parse_gen_args_ext: 多 ABI + --out 抛 CliUsage (T-W4-3)" {
  let err = @test.expect_error(() => {
    @moon_abi.parse_gen_args_ext([
      "--abi", "arm64", "--abi", "x86", "--api", "21", "--out", "moon.pkg",
    ])
  })
  match err {
    @moon_abi.MoonAbiError::CliUsage(reason) =>
      assert_true(reason.contains("single managed block contract"))
    _ => fail("expected CliUsage (multi abi + out)")
  }
  assert_eq(@moon_abi.exit_code_for_error(err), 2)
  let single = parse_ext_or_fail([
    "--abi", "arm64", "--abi", "arm64", "--api", "21", "--out", "moon.pkg",
  ])
  assert_eq(abi_tag(single.base.abi), "arm64-v8a")
  match single.base.output {
    @moon_abi.GenOutput::File(p) => assert_eq(p, "moon.pkg")
    _ => fail("expected file output after dedup to single abi")
  }
}

///|
/// T-W4-2：`generate_multi` 按输入序生成、确定性、extra 落到 flags、空数组错误。
test "generate_multi: 顺序/确定性/extra/空数组错误 (T-W4-2)" {
  let profile : @moon_abi.NdkProfile = {
    ndk_root: "/opt/ndk",
    ndk_version: "r27",
    api_level: @moon_abi.ApiLevel::{ level: 21, },
    extra_link_libs: ["foo"],
    extra_cc_flags: ["-DNDEBUG"],
    windows_path_style: false,
  }
  let configs = generate_multi_or_fail(profile, [
    @moon_abi.Abi::Arm64V8a,
    @moon_abi.Abi::X86_64,
  ])
  assert_eq(configs.length(), 2)
  assert_eq(abi_tag(configs[0].abi), "arm64-v8a")
  assert_eq(abi_tag(configs[1].abi), "x86_64")
  assert_true(configs[0].cc.contains("aarch64-linux-android21-clang"))
  assert_true(configs[1].cc.contains("x86_64-linux-android21-clang"))
  assert_eq(configs[0].api_level.level, 21)
  assert_true(configs[0].cc_link_flags.contains("-lfoo"))
  assert_true(configs[0].cc_flags.contains("-DNDEBUG"))
  let again = generate_multi_or_fail(profile, [
    @moon_abi.Abi::Arm64V8a,
    @moon_abi.Abi::X86_64,
  ])
  assert_eq(configs[0].cc, again[0].cc)
  assert_eq(configs[1].cc, again[1].cc)
  let err = @test.expect_error(() => @moon_abi.generate_multi(profile, []))
  match err {
    @moon_abi.MoonAbiError::CliUsage(_) => ()
    _ => fail("expected CliUsage for empty abis")
  }
  assert_eq(@moon_abi.exit_code_for_error(err), 2)
}
