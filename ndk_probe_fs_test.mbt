// R4 真实 NDK 探测测试：仅使用系统临时目录中的伪 NDK/SDK 目录，
// 不依赖真机、真 NDK、真实环境变量；`ANDROID_HOME` 等输入由结构体显式注入。

///|
async test "probe_ndk: 受控伪 NDK 目录（显式根，不依赖真 NDK）" {
  let dir = temp_dir("moon_abi_r4_ndk")
  let root = dir + "/android-ndk-r27"
  @fs.mkdir(
    root + "/toolchains/llvm/prebuilt",
    recursive=true,
    allow_exist=true,
  ) catch {
    e => fail("mkdir failed: " + e.to_string())
  }
  @fs.write_text(root + "/source.properties", "Pkg.Revision = 27.0.12077973\n") catch {
    e => fail("write props failed: " + e.to_string())
  }
  let inputs = @moon_abi.NdkProbeInputs::{
    explicit_root: Some(root),
    ndk_home: None,
    android_home: None,
    android_sdk_root: None,
    home_dir: None,
    local_app_data: None,
  }
  let result = @moon_abi.probe_ndk(inputs)
  assert_true(result.found)
  match result.selected {
    Some(path) => assert_true(path.contains("android-ndk-r27"))
    None => fail("expected selected fake NDK root")
  }
  match result.version {
    Some(version) => assert_eq(version, "27.0.12077973")
    None => fail("expected version from fake source.properties")
  }
  @fs.rmdir(dir, recursive=true, allow_missing=true) catch {
    _ => ()
  }
}

///|
async test "probe_ndk: ANDROID_HOME/ndk 版本目录取最高（伪 SDK）" {
  let dir = temp_dir("moon_abi_r4_sdk")
  let sdk = dir + "/sdk"
  let v26 = sdk + "/ndk/26.1.1"
  let v27 = sdk + "/ndk/27.0.1"
  @fs.mkdir(v26 + "/toolchains/llvm/prebuilt", recursive=true, allow_exist=true) catch {
    e => fail("mkdir failed: " + e.to_string())
  }
  @fs.mkdir(v27 + "/toolchains/llvm/prebuilt", recursive=true, allow_exist=true) catch {
    e => fail("mkdir failed: " + e.to_string())
  }
  @fs.write_text(v27 + "/source.properties", "Pkg.Revision = 27.0.12077973\n") catch {
    e => fail("write props failed: " + e.to_string())
  }
  let inputs = @moon_abi.NdkProbeInputs::{
    explicit_root: None,
    ndk_home: None,
    android_home: Some(sdk),
    android_sdk_root: None,
    home_dir: None,
    local_app_data: None,
  }
  let result = @moon_abi.probe_ndk(inputs)
  assert_true(result.found)
  match result.selected {
    Some(path) => assert_true(path.contains("27.0.1"))
    None => fail("expected highest SDK NDK version")
  }
  match result.version {
    Some(version) => assert_eq(version, "27.0.12077973")
    None => fail("expected version from source.properties")
  }
  @fs.rmdir(dir, recursive=true, allow_missing=true) catch {
    _ => ()
  }
}

///|
async test "probe_ndk: 无 NDK 环境 → found=false 且结构化告警" {
  let result = @moon_abi.probe_ndk({
    explicit_root: None,
    ndk_home: None,
    android_home: None,
    android_sdk_root: None,
    home_dir: None,
    local_app_data: None,
  })
  assert_false(result.found)
  assert_true(result.warnings.length() > 0)
  assert_true(@moon_abi.ndk_probe_json(result).contains("\"found\":false"))
}
