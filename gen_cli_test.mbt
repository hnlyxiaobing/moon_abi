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
