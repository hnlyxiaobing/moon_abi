// Blackbox tests for the R4 NDK probe: pure core with injected fake directories.
// 覆盖：显式根命中、ANDROID_NDK_HOME 回退、ANDROID_HOME/ndk 版本目录取最高、
// 候选不完整告警、全未找到、版本回退目录名、文本/JSON 结构化输出。

///|
/// 全空的探测输入（不注入任何环境变量/显式根）。
fn no_inputs() -> @moon_abi.NdkProbeInputs {
  {
    explicit_root: None,
    ndk_home: None,
    android_home: None,
    android_sdk_root: None,
    home_dir: None,
    local_app_data: None,
  }
}

///|
test "probe_ndk_with: 显式根可用（伪目录，不依赖真 NDK）" {
  let root = "C:\\fake-ndk"
  let props = root + "\\source.properties"
  let prebuilt = root + "\\toolchains\\llvm\\prebuilt"
  let exists = path => path == root || path == prebuilt
  let list = _path => ([] : Array[String])
  let read = path => {
    if path == props {
      Some("Pkg.Desc = Android NDK\nPkg.Revision = 27.0.12077973\n")
    } else {
      None
    }
  }
  let inputs = @moon_abi.NdkProbeInputs::{
    explicit_root: Some(root),
    ndk_home: None,
    android_home: None,
    android_sdk_root: None,
    home_dir: None,
    local_app_data: None,
  }
  let result = @moon_abi.probe_ndk_with(inputs, exists, list, read)
  assert_true(result.found)
  match result.selected {
    Some(path) => assert_eq(path, root)
    None => fail("expected selected root")
  }
  match result.version {
    Some(version) => assert_eq(version, "27.0.12077973")
    None => fail("expected version from source.properties")
  }
  match result.candidates[0].source {
    @moon_abi.NdkSource::Explicit => ()
    _ => fail("expected Explicit source")
  }
  assert_true(result.candidates[0].usable)
  assert_eq(result.warnings.length(), 0)
}

///|
test "probe_ndk_with: 显式根缺失时回退 ANDROID_NDK_HOME" {
  let missing = "/missing-ndk"
  let valid = "/opt/ndk"
  let prebuilt = valid + "/toolchains/llvm/prebuilt"
  let exists = path => path == valid || path == prebuilt
  let list = _path => ([] : Array[String])
  let read = _path => (None : String?)
  let inputs = @moon_abi.NdkProbeInputs::{
    explicit_root: Some(missing),
    ndk_home: Some(valid),
    android_home: None,
    android_sdk_root: None,
    home_dir: None,
    local_app_data: None,
  }
  let result = @moon_abi.probe_ndk_with(inputs, exists, list, read)
  assert_true(result.found)
  match result.selected {
    Some(path) => assert_eq(path, valid)
    None => fail("expected fallback root")
  }
  match result.version {
    Some(_) =>
      fail(
        "expected unknown version (no source.properties, dir not version-like)",
      )
    None => ()
  }
  assert_true(result.warnings.length() > 0)
}

///|
test "probe_ndk_with: ANDROID_HOME/ndk 版本目录取最高版本" {
  let sdk_ndk = "/sdk/ndk"
  let v26 = sdk_ndk + "/26.1.1"
  let v27 = sdk_ndk + "/27.0.1"
  let prebuilt26 = v26 + "/toolchains/llvm/prebuilt"
  let prebuilt27 = v27 + "/toolchains/llvm/prebuilt"
  let exists = path => {
    path == sdk_ndk ||
    path == v26 ||
    path == v27 ||
    path == prebuilt26 ||
    path == prebuilt27
  }
  let list = path => if path == sdk_ndk { ["26.1.1", "27.0.1"] } else { [] }
  let props27 = v27 + "/source.properties"
  let read = path => {
    if path == props27 {
      Some("Pkg.Revision = 27.0.12077973")
    } else {
      None
    }
  }
  let inputs = @moon_abi.NdkProbeInputs::{
    explicit_root: None,
    ndk_home: None,
    android_home: Some("/sdk"),
    android_sdk_root: None,
    home_dir: None,
    local_app_data: None,
  }
  let result = @moon_abi.probe_ndk_with(inputs, exists, list, read)
  assert_true(result.found)
  match result.selected {
    Some(path) => assert_eq(path, v27)
    None => fail("expected highest version root")
  }
  match result.version {
    Some(version) => assert_eq(version, "27.0.12077973")
    None => fail("expected version from source.properties")
  }
  assert_eq(result.candidates[0].path, v27)
}

///|
test "probe_ndk_with: 候选存在但缺 toolchains/llvm/prebuilt → 告警且不可用" {
  let root = "/broken-ndk"
  let exists = path => path == root
  let list = _path => ([] : Array[String])
  let read = _path => (None : String?)
  let inputs = @moon_abi.NdkProbeInputs::{
    explicit_root: Some(root),
    ndk_home: None,
    android_home: None,
    android_sdk_root: None,
    home_dir: None,
    local_app_data: None,
  }
  let result = @moon_abi.probe_ndk_with(inputs, exists, list, read)
  assert_false(result.found)
  match result.candidates[0].path {
    path => assert_eq(path, root)
  }
  assert_true(result.candidates[0].exists)
  assert_false(result.candidates[0].usable)
  assert_eq(result.candidates[0].note, "missing toolchains/llvm/prebuilt")
  let mut has_incomplete = false
  for warning in result.warnings {
    if warning.contains("incomplete NDK candidate") {
      has_incomplete = true
    }
  }
  assert_true(has_incomplete)
}

///|
test "probe_ndk_with: 全未找到 → found=false 且告警" {
  let exists = _path => false
  let list = _path => ([] : Array[String])
  let read = _path => (None : String?)
  let result = @moon_abi.probe_ndk_with(no_inputs(), exists, list, read)
  assert_false(result.found)
  match result.selected {
    Some(_) => fail("expected no selection")
    None => ()
  }
  assert_eq(result.candidates.length(), 2)
  assert_eq(result.warnings.length(), 1)
  assert_true(result.warnings[0].contains("NDK not found"))
}

///|
test "probe_ndk_with: 版本回退目录名" {
  let root = "/ndk/27.0.12077973"
  let prebuilt = root + "/toolchains/llvm/prebuilt"
  let exists = path => path == root || path == prebuilt
  let list = _path => ([] : Array[String])
  let read = _path => (None : String?)
  let inputs = @moon_abi.NdkProbeInputs::{
    explicit_root: Some(root),
    ndk_home: None,
    android_home: None,
    android_sdk_root: None,
    home_dir: None,
    local_app_data: None,
  }
  let result = @moon_abi.probe_ndk_with(inputs, exists, list, read)
  assert_true(result.found)
  match result.version {
    Some(version) => assert_eq(version, "27.0.12077973")
    None => fail("expected version from dir name")
  }
}

///|
test "ndk_probe_text / ndk_probe_json: 结构化输出且转义合法" {
  let root = "C:\\fake\"ndk"
  let prebuilt = root + "\\toolchains\\llvm\\prebuilt"
  let exists = path => path == root || path == prebuilt
  let list = _path => ([] : Array[String])
  let read = _path => (None : String?)
  let inputs = @moon_abi.NdkProbeInputs::{
    explicit_root: Some(root),
    ndk_home: None,
    android_home: None,
    android_sdk_root: None,
    home_dir: None,
    local_app_data: None,
  }
  let result = @moon_abi.probe_ndk_with(inputs, exists, list, read)
  let text = @moon_abi.ndk_probe_text(result)
  assert_true(text.contains("NDK|found=true"))
  assert_true(text.contains("CAND|source=explicit"))
  let json = @moon_abi.ndk_probe_json(result)
  assert_true(json.contains("\"found\":true"))
  assert_true(json.contains("\\\\"))
  assert_true(json.contains("\\\""))
  assert_true(json.has_suffix("]}"))
}
