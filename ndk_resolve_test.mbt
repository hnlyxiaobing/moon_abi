// W2-A：resolve_ndk_values 纯函数判定测试（注入式探测结果，零 I/O、零环境依赖）。
// NdkNotFound 的两条失败路径在此获得确定性触发（含历史 CLI 无法确定性构造的
// "NDK not found" 路径）；消息文本与 CLI 历史失败文案逐字一致（防火墙）。

///|
/// 测试用 GenCommand（显式 root/version 可覆写）。
fn resolve_cmd(root : String?, version : String?) -> @moon_abi.GenCommand {
  {
    abi: @moon_abi.Abi::Arm64V8a,
    api_level: @moon_abi.ApiLevel::{ level: 21, },
    ndk_root: root,
    ndk_version: version,
    output: @moon_abi.GenOutput::Stdout,
    path_style: @moon_abi.PathStyle::Auto,
  }
}

///|
/// 测试用探测结果（selected/version 可覆写）。
fn resolve_probe(
  selected : String?,
  version : String?,
) -> @moon_abi.NdkProbeResult {
  {
    found: selected is Some(_),
    selected,
    version,
    candidates: [],
    warnings: [],
  }
}

///|
test "resolve_ndk_values: 显式 root+version 直接透传（不消费探测）" {
  let (root, version) = @moon_abi.resolve_ndk_values(
    resolve_cmd(Some("/opt/android-ndk"), Some("r27c")),
    resolve_probe(None, None),
  ) catch {
    e => fail("unexpected: " + @moon_abi.error_message(e))
  }
  assert_eq(root, "/opt/android-ndk")
  assert_eq(version, "r27c")
}

///|
test "resolve_ndk_values: 缺 root 时探测补齐 root+version" {
  let (root, version) = @moon_abi.resolve_ndk_values(
    resolve_cmd(None, None),
    resolve_probe(Some("/opt/ndk-r27"), Some("27.0.12077973")),
  ) catch {
    e => fail("unexpected: " + @moon_abi.error_message(e))
  }
  assert_eq(root, "/opt/ndk-r27")
  assert_eq(version, "27.0.12077973")
}

///|
test "resolve_ndk_values: 显式 root 与探测 selected 一致时补 version" {
  let (root, version) = @moon_abi.resolve_ndk_values(
    resolve_cmd(Some("/opt/ndk-r27"), None),
    resolve_probe(Some("/opt/ndk-r27"), Some("r27c")),
  ) catch {
    e => fail("unexpected: " + @moon_abi.error_message(e))
  }
  assert_eq(root, "/opt/ndk-r27")
  assert_eq(version, "r27c")
}

///|
test "resolve_ndk_values: 探测未找到 → NdkNotFound（消息冻结）" {
  let err = @test.expect_error(() => {
    @moon_abi.resolve_ndk_values(
      resolve_cmd(None, None),
      resolve_probe(None, None),
    )
  })
  match err {
    @moon_abi.MoonAbiError::NdkNotFound(detail) =>
      assert_eq(
        detail, "NDK not found: set ANDROID_NDK_HOME/ANDROID_HOME or pass --ndk-root",
      )
    _ => fail("expected NdkNotFound (not found)")
  }
  assert_eq(@moon_abi.exit_code_for_error(err), 1)
}

///|
test "resolve_ndk_values: 显式假 root + 缺 version → NdkNotFound（消息冻结）" {
  let err = @test.expect_error(() => {
    @moon_abi.resolve_ndk_values(
      resolve_cmd(Some("Z:\\moonabi-nonexistent-ndk-root"), None),
      resolve_probe(Some("/opt/other-ndk"), Some("r27c")),
    )
  })
  match err {
    @moon_abi.MoonAbiError::NdkNotFound(detail) =>
      assert_eq(
        detail, "NDK version unknown: pass --ndk-version or provide source.properties",
      )
    _ => fail("expected NdkNotFound (version unknown)")
  }
  assert_eq(@moon_abi.exit_code_for_error(err), 1)
}

///|
test "resolve_ndk_values: 显式 version 优先于探测版本" {
  let (root, version) = @moon_abi.resolve_ndk_values(
    resolve_cmd(None, Some("r26b")),
    resolve_probe(Some("/opt/ndk-r27"), Some("r27c")),
  ) catch {
    e => fail("unexpected: " + @moon_abi.error_message(e))
  }
  assert_eq(root, "/opt/ndk-r27")
  assert_eq(version, "r26b")
}
