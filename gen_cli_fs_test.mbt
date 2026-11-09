// R4 文件系统测试：受管配置写入/幂等/替换与错误路径。
// 全部在系统临时目录内进行（@fs.tmpdir），结束后递归清理；
// 不写入工作区、不依赖真机/真实 NDK。

///|
/// 创建受控临时目录（失败即测试失败）。
async fn temp_dir(prefix : String) -> String raise Failure {
  @fs.tmpdir(prefix~) catch {
    e => fail("tmpdir failed: " + e.to_string())
  }
}

///|
async test "sync_config_file: 写入 / 幂等 / 替换（临时目录受控）" {
  let dir = temp_dir("moon_abi_r4_cli")
  @fs.mkdir(dir, recursive=true, allow_exist=true) catch {
    e => fail("mkdir failed: " + e.to_string())
  }
  let path = dir + "/moon.pkg"
  let block = block_or_fail()
  let first = @moon_abi.sync_config_file(path, block) catch {
    e => fail("first write failed: " + @moon_abi.error_message(e))
  }
  match first.action {
    @moon_abi.MergeAction::Appended => ()
    _ => fail("expected Appended on first write")
  }
  let text1 = @fs.read_text(path) catch {
    e => fail("read failed: " + e.to_string())
  }
  assert_eq(text1, block)
  let second = @moon_abi.sync_config_file(path, block) catch {
    e => fail("second write failed: " + @moon_abi.error_message(e))
  }
  match second.action {
    @moon_abi.MergeAction::Unchanged => ()
    _ => fail("expected Unchanged on second write (idempotent)")
  }
  let text2 = @fs.read_text(path) catch {
    e => fail("read failed: " + e.to_string())
  }
  assert_eq(text2, text1)
  let edited = text1.replace(old="api_level=21", new="api_level=99")
  @fs.write_text(path, edited) catch {
    e => fail("edit failed: " + e.to_string())
  }
  let third = @moon_abi.sync_config_file(path, block) catch {
    e => fail("third write failed: " + @moon_abi.error_message(e))
  }
  match third.action {
    @moon_abi.MergeAction::Replaced => ()
    _ => fail("expected Replaced after manual edit")
  }
  let text3 = @fs.read_text(path) catch {
    e => fail("read failed: " + e.to_string())
  }
  assert_eq(text3, block)
  assert_false(text3.contains("api_level=99"))
  @fs.remove(path, allow_missing=true) catch {
    _ => ()
  }
  @fs.rmdir(dir, recursive=true, allow_missing=true) catch {
    _ => ()
  }
}

///|
async test "sync_config_file: 父目录缺失 → IoFailure（错误路径不 panic）" {
  let dir = temp_dir("moon_abi_r4_missing")
  let path = dir + "/missing/moon.pkg"
  let block = block_or_fail()
  let message = try {
    let _ = @moon_abi.sync_config_file(path, block)
    ""
  } catch {
    e => @moon_abi.error_message(e)
  }
  assert_true(message.contains("I/O failure"))
  assert_true(message.contains("missing"))
  @fs.rmdir(dir, recursive=true, allow_missing=true) catch {
    _ => ()
  }
}

///|
async test "sync_config_file: 空路径 → IoFailure" {
  let block = block_or_fail()
  let message = try {
    let _ = @moon_abi.sync_config_file("", block)
    ""
  } catch {
    e => @moon_abi.error_message(e)
  }
  assert_true(message.contains("empty output path"))
}
