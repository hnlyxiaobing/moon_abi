// R4 边界用例：合并换行收敛、探测去重、SDK_ROOT 来源、错误消息、
// 结构化输出确定性与参数边界。全部为纯函数测试，不触碰文件系统。

///|
test "merge_link_config: CRLF 受管块替换收敛到 LF 规范块" {
  let block = block_or_fail()
  let crlf = block.replace(old="\n", new="\r\n")
  let merged = merge_or_fail(crlf, block)
  match merged.action {
    @moon_abi.MergeAction::Replaced => ()
    _ => fail("expected Replaced for CRLF block")
  }
  assert_eq(merged.content, block)
  let again = merge_or_fail(merged.content, block)
  match again.action {
    @moon_abi.MergeAction::Unchanged => ()
    _ => fail("expected Unchanged after normalization")
  }
}

///|
test "merge_link_config: 块外用户内容逐字保留" {
  let block = block_or_fail()
  let existing = "// head\n\n" + block + "// tail\n"
  let merged = merge_or_fail(existing, block)
  match merged.action {
    @moon_abi.MergeAction::Unchanged => ()
    _ => fail("expected Unchanged when block already canonical")
  }
  assert_eq(merged.content, existing)
}

///|
test "probe_ndk_with: 相同路径的显式根与 NDK_HOME 去重" {
  let root = "/same-ndk"
  let prebuilt = root + "/toolchains/llvm/prebuilt"
  let exists = path => path == root || path == prebuilt
  let list = _path => ([] : Array[String])
  let read = _path => (None : String?)
  let result = @moon_abi.probe_ndk_with(
    {
      explicit_root: Some(root),
      ndk_home: Some(root),
      android_home: None,
      android_sdk_root: None,
      home_dir: None,
      local_app_data: None,
    },
    exists,
    list,
    read,
  )
  let mut hits = 0
  for candidate in result.candidates {
    if candidate.path == root {
      hits = hits + 1
    }
  }
  assert_eq(hits, 1)
  match result.selected {
    Some(path) => assert_eq(path, root)
    None => fail("expected selected root")
  }
}

///|
test "probe_ndk_with: ANDROID_SDK_ROOT/ndk 来源与版本目录" {
  let sdk_ndk = "/sdk-root/ndk"
  let root = sdk_ndk + "/27.0.12077973"
  let prebuilt = root + "/toolchains/llvm/prebuilt"
  let props = root + "/source.properties"
  let exists = path => path == sdk_ndk || path == root || path == prebuilt
  let list = path => if path == sdk_ndk { ["27.0.12077973"] } else { [] }
  let read = path => {
    if path == props {
      Some("Pkg.Revision = 27.0.12077973\n")
    } else {
      None
    }
  }
  let result = @moon_abi.probe_ndk_with(
    {
      explicit_root: None,
      ndk_home: None,
      android_home: None,
      android_sdk_root: Some("/sdk-root"),
      home_dir: None,
      local_app_data: None,
    },
    exists,
    list,
    read,
  )
  assert_true(result.found)
  match result.selected {
    Some(path) => assert_eq(path, root)
    None => fail("expected SDK_ROOT candidate")
  }
  match result.version {
    Some(version) => assert_eq(version, "27.0.12077973")
    None => fail("expected version")
  }
  match result.candidates[0].source {
    @moon_abi.NdkSource::AndroidSdkRootNdk => ()
    _ => fail("expected AndroidSdkRootNdk source")
  }
}

///|
test "parse_gen_args: 空内联值 / 重复 path-style / 未知位置参数" {
  let cases : Array[Array[String]] = [
    ["--abi", "x86", "--api", "21", "--ndk-root="],
    ["--abi", "x86", "--api", "21", "--ndk-version="],
    ["--abi", "x86", "--api", "21", "--out="],
    [
      "--abi", "x86", "--api", "21", "--path-style", "unix", "--path-style", "auto",
    ],
    ["--abi", "x86", "--api", "21", "moon.pkg"],
  ]
  for argv in cases {
    let err = @test.expect_error(() => @moon_abi.parse_gen_args(argv))
    assert_eq(@moon_abi.exit_code_for_error(err), 2)
  }
}

///|
test "abi_from_name: 前后空白与大小写归一" {
  match abi_or_fail(" arm64 ") {
    @moon_abi.Abi::Arm64V8a => ()
    _ => fail("expected Arm64V8a")
  }
  match abi_or_fail("X86_64") {
    @moon_abi.Abi::X86_64 => ()
    _ => fail("expected X86_64")
  }
}

///|
test "error_message: IoFailure / MalformedConfig 的人读消息" {
  let block = block_or_fail()
  let io_error = @test.expect_error(() => {
    @moon_abi.write_config_with(
      "moon.pkg",
      block,
      _p => @moon_abi.ReadOutcome::NotFound,
      (_p, _c) => Err("permission denied"),
    )
  })
  let io_message = @moon_abi.error_message(io_error)
  assert_true(io_message.contains("I/O failure"))
  assert_true(io_message.contains("permission denied"))
  let malformed = @test.expect_error(() => {
    @moon_abi.merge_link_config("// <<< moon_abi gen:managed <<<\n", block)
  })
  assert_true(
    @moon_abi.error_message(malformed).contains("malformed managed config"),
  )
}

///|
test "ndk_probe_text / ndk_probe_json: 输出确定性且 JSON 单行" {
  let result = @moon_abi.probe_ndk_with(
    {
      explicit_root: Some("/ndk"),
      ndk_home: None,
      android_home: None,
      android_sdk_root: None,
      home_dir: None,
      local_app_data: None,
    },
    _p => false,
    _p => ([] : Array[String]),
    _p => (None : String?),
  )
  assert_eq(@moon_abi.ndk_probe_text(result), @moon_abi.ndk_probe_text(result))
  let json = @moon_abi.ndk_probe_json(result)
  assert_eq(json, @moon_abi.ndk_probe_json(result))
  assert_false(json.contains("\n"))
  assert_true(json.contains("\"warning"))
}

///|
test "write_config_with: 追加保留既有用户内容" {
  let block = block_or_fail()
  let written : Array[String] = []
  let result = @moon_abi.write_config_with(
    "moon.pkg",
    block,
    _p => @moon_abi.ReadOutcome::Found("// user header\n"),
    (_p, content) => {
      written.push(content)
      Ok(())
    },
  ) catch {
    e => fail("unexpected: " + @moon_abi.error_message(e))
  }
  match result.action {
    @moon_abi.MergeAction::Appended => ()
    _ => fail("expected Appended")
  }
  assert_true(written[0].has_prefix("// user header\n// >>> moon_abi"))
}
