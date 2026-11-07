// Blackbox tests run against the package's public API. Use `@moon_abi` to import.
// 覆盖：4 ABI × 多 API level、clang 命名、golden 快照、确定性、
// 非法配置负例（MissingNdkRoot / UnsupportedApiLevel / VersionMismatch /
// PathContainsSpace / MissingClang / InvalidTriple）与 validate 报告。

///|
fn abi_str(abi : @moon_abi.Abi) -> String {
  match abi {
    @moon_abi.Abi::ArmeabiV7a => "armeabi-v7a"
    @moon_abi.Abi::Arm64V8a => "arm64-v8a"
    @moon_abi.Abi::X86 => "x86"
    @moon_abi.Abi::X86_64 => "x86_64"
  }
}

///|
fn triple_str(triple : @moon_abi.TargetTriple) -> String {
  match triple {
    @moon_abi.TargetTriple::Armv7aLinuxAndroideabi => "armv7a-linux-androideabi"
    @moon_abi.TargetTriple::Aarch64LinuxAndroid => "aarch64-linux-android"
    @moon_abi.TargetTriple::I686LinuxAndroid => "i686-linux-android"
    @moon_abi.TargetTriple::X86_64LinuxAndroid => "x86_64-linux-android"
  }
}

///|
fn profile(
  ndk_root : String,
  ndk_version : String,
  level : Int32,
  windows : Bool,
) -> @moon_abi.NdkProfile {
  @moon_abi.NdkProfile::{
    ndk_root,
    ndk_version,
    api_level: @moon_abi.ApiLevel::{ level, },
    extra_link_libs: [],
    extra_cc_flags: [],
    windows_path_style: windows,
  }
}

///|
fn unix_profile(level : Int32) -> @moon_abi.NdkProfile {
  profile("/opt/android-ndk", "r27", level, false)
}

///|
fn win_profile(level : Int32) -> @moon_abi.NdkProfile {
  profile("C:\\android-ndk", "r27", level, true)
}

///|
fn all_abis() -> Array[@moon_abi.Abi] {
  [
    @moon_abi.Abi::ArmeabiV7a,
    @moon_abi.Abi::Arm64V8a,
    @moon_abi.Abi::X86,
    @moon_abi.Abi::X86_64,
  ]
}

///|
/// clang_name：4 种 ABI × 多组 API level 的命名正确性。
test "clang_name: 4 ABI × 多 API level 命名正确" {
  assert_eq(
    @moon_abi.clang_name(@moon_abi.Abi::ArmeabiV7a, @moon_abi.ApiLevel::{
      level: 21,
    }),
    "armv7a-linux-androideabi21-clang",
  )
  assert_eq(
    @moon_abi.clang_name(@moon_abi.Abi::ArmeabiV7a, @moon_abi.ApiLevel::{
      level: 35,
    }),
    "armv7a-linux-androideabi35-clang",
  )
  assert_eq(
    @moon_abi.clang_name(@moon_abi.Abi::Arm64V8a, @moon_abi.ApiLevel::{
      level: 21,
    }),
    "aarch64-linux-android21-clang",
  )
  assert_eq(
    @moon_abi.clang_name(@moon_abi.Abi::Arm64V8a, @moon_abi.ApiLevel::{
      level: 24,
    }),
    "aarch64-linux-android24-clang",
  )
  assert_eq(
    @moon_abi.clang_name(@moon_abi.Abi::X86, @moon_abi.ApiLevel::{ level: 28, }),
    "i686-linux-android28-clang",
  )
  assert_eq(
    @moon_abi.clang_name(@moon_abi.Abi::X86_64, @moon_abi.ApiLevel::{
      level: 21,
    }),
    "x86_64-linux-android21-clang",
  )
  assert_eq(
    @moon_abi.clang_name(@moon_abi.Abi::X86_64, @moon_abi.ApiLevel::{
      level: 35,
    }),
    "x86_64-linux-android35-clang",
  )
}

///|
/// clang_name：API level 低于下限报 `UnsupportedApiLevel(got, min)`。
test "clang_name: API level 低于下限抛 UnsupportedApiLevel" {
  let e = @test.expect_error(() => {
    @moon_abi.clang_name(@moon_abi.Abi::Arm64V8a, @moon_abi.ApiLevel::{
      level: 20,
    })
  })
  match e {
    @moon_abi.MoonAbiError::UnsupportedApiLevel(got, min) => {
      assert_eq(got, 20)
      assert_eq(min, 21)
    }
    _ => fail("expected UnsupportedApiLevel")
  }
  let e0 = @test.expect_error(() => {
    @moon_abi.clang_name(@moon_abi.Abi::X86, @moon_abi.ApiLevel::{ level: 0, })
  })
  assert_true(e0 is @moon_abi.MoonAbiError::UnsupportedApiLevel(0, 21))
}

///|
/// generate：4 种 ABI 的字段逐项断言（unix 风格路径）。
test "generate: 4 ABI 字段逐项断言" {
  let cases : Array[(@moon_abi.Abi, Int32, String, String)] = [
    (
      @moon_abi.Abi::ArmeabiV7a,
      21,
      "armv7a-linux-androideabi",
      "/opt/android-ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi21-clang",
    ),
    (
      @moon_abi.Abi::Arm64V8a,
      24,
      "aarch64-linux-android",
      "/opt/android-ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang",
    ),
    (
      @moon_abi.Abi::X86,
      29,
      "i686-linux-android",
      "/opt/android-ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/i686-linux-android29-clang",
    ),
    (
      @moon_abi.Abi::X86_64,
      35,
      "x86_64-linux-android",
      "/opt/android-ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android35-clang",
    ),
  ]
  for entry in cases {
    let (abi, level, tname, cc) = entry
    let cfg = @moon_abi.generate(unix_profile(level), abi)
    assert_eq(cfg.cc, cc)
    assert_eq(cfg.cc_flags.length(), 1)
    assert_eq(cfg.cc_flags[0], "--target=" + tname + level.to_string())
    assert_eq(cfg.cc_link_flags.length(), 2)
    assert_eq(cfg.cc_link_flags[0], "-llog")
    assert_eq(cfg.cc_link_flags[1], "-landroid")
    assert_eq(cfg.supported_targets, "native")
    assert_eq(cfg.api_level.level, level)
    assert_eq(abi_str(cfg.abi), abi_str(abi))
    assert_eq(triple_str(cfg.triple), tname)
    match cfg.stub_cc {
      Some(stub) => assert_eq(stub, cc)
      None => fail("stub_cc should equal cc")
    }
  }
}

///|
/// generate：Windows 路径风格与尾分隔符归一化。
test "generate: Windows 路径风格与尾分隔符归一" {
  let cfg = @moon_abi.generate(win_profile(21), @moon_abi.Abi::X86_64)
  assert_eq(
    cfg.cc,
    "C:\\android-ndk\\toolchains\\llvm\\prebuilt\\windows-x86_64\\bin\\x86_64-linux-android21-clang",
  )
  let cfg2 = @moon_abi.generate(
    profile("C:\\android-ndk\\", "r27", 21, true),
    @moon_abi.Abi::X86_64,
  )
  assert_eq(cfg2.cc, cfg.cc)
  let cfg3 = @moon_abi.generate(
    profile("/opt/android-ndk/", "r27", 21, false),
    @moon_abi.Abi::Arm64V8a,
  )
  assert_eq(
    cfg3.cc,
    "/opt/android-ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang",
  )
}

///|
/// generate：extra_cc_flags / extra_link_libs 按输入顺序注入。
test "generate: extra flags 注入顺序" {
  let p = @moon_abi.NdkProfile::{
    ndk_root: "/opt/android-ndk",
    ndk_version: "r27",
    api_level: @moon_abi.ApiLevel::{ level: 21, },
    extra_link_libs: ["z", "m"],
    extra_cc_flags: ["-fPIC", "-O2"],
    windows_path_style: false,
  }
  let cfg = @moon_abi.generate(p, @moon_abi.Abi::Arm64V8a)
  assert_eq(cfg.cc_flags.length(), 3)
  assert_eq(cfg.cc_flags[1], "-fPIC")
  assert_eq(cfg.cc_flags[2], "-O2")
  assert_eq(cfg.cc_link_flags.length(), 4)
  assert_eq(cfg.cc_link_flags[2], "-lz")
  assert_eq(cfg.cc_link_flags[3], "-lm")
}

///|
/// generate：缺 NDK 根路径报 `MissingNdkRoot`。
test "generate: MissingNdkRoot" {
  for root in ["", "   "] {
    let e = @test.expect_error(() => {
      @moon_abi.generate(
        profile(root, "r27", 21, false),
        @moon_abi.Abi::Arm64V8a,
      )
    })
    assert_true(e is @moon_abi.MoonAbiError::MissingNdkRoot)
  }
}

///|
/// generate：非法 API 报 `UnsupportedApiLevel`。
test "generate: UnsupportedApiLevel" {
  let e = @test.expect_error(() => {
    @moon_abi.generate(unix_profile(16), @moon_abi.Abi::ArmeabiV7a)
  })
  assert_true(e is @moon_abi.MoonAbiError::UnsupportedApiLevel(16, 21))
}

///|
/// generate：NDK 版本低于下限或不可解析报 `VersionMismatch(expected, actual)`。
test "generate: VersionMismatch" {
  for version in ["r21", "banana", ""] {
    let e = @test.expect_error(() => {
      @moon_abi.generate(
        profile("/opt/ndk", version, 21, false),
        @moon_abi.Abi::X86,
      )
    })
    match e {
      @moon_abi.MoonAbiError::VersionMismatch(expected, actual) => {
        assert_eq(expected, "r22+")
        assert_eq(actual, version)
      }
      _ => fail("expected VersionMismatch")
    }
  }
}

///|
/// generate：合法 NDK 版本写法均被接受（rXX / rXX 字母 / 点分版本号）。
test "generate: 合法 NDK 版本写法接受" {
  for version in ["r22", "r27c", "27.0.12077973"] {
    let cfg = @moon_abi.generate(
      profile("/opt/ndk", version, 21, false),
      @moon_abi.Abi::Arm64V8a,
    )
    assert_eq(cfg.api_level.level, 21)
  }
}

///|
/// render：4 种 ABI 的 golden 快照（API level 21）。
test "render: golden 4 ABI × API 21" {
  let expected_v7 = (
      #|// generated by moon_abi; do not edit by hand
      #|// abi=armeabi-v7a triple=armv7a-linux-androideabi api_level=21
      #|supported_targets = "native"
      #|options(
      #|  link: {
      #|    "native": {
      #|      "cc": "/opt/android-ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi21-clang",
      #|      "cc-flags": "--target=armv7a-linux-androideabi21",
      #|      "cc-link-flags": "-llog -landroid",
      #|      "stub-cc": "/opt/android-ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi21-clang",
      #|    },
      #|  },
      #|)
    ) +
    "\n"
  assert_eq(
    @moon_abi.render(
      @moon_abi.generate(unix_profile(21), @moon_abi.Abi::ArmeabiV7a),
    ),
    expected_v7,
  )
  let expected_a64 = (
      #|// generated by moon_abi; do not edit by hand
      #|// abi=arm64-v8a triple=aarch64-linux-android api_level=21
      #|supported_targets = "native"
      #|options(
      #|  link: {
      #|    "native": {
      #|      "cc": "/opt/android-ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang",
      #|      "cc-flags": "--target=aarch64-linux-android21",
      #|      "cc-link-flags": "-llog -landroid",
      #|      "stub-cc": "/opt/android-ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang",
      #|    },
      #|  },
      #|)
    ) +
    "\n"
  assert_eq(
    @moon_abi.render(
      @moon_abi.generate(unix_profile(21), @moon_abi.Abi::Arm64V8a),
    ),
    expected_a64,
  )
  let expected_x86 = (
      #|// generated by moon_abi; do not edit by hand
      #|// abi=x86 triple=i686-linux-android api_level=21
      #|supported_targets = "native"
      #|options(
      #|  link: {
      #|    "native": {
      #|      "cc": "/opt/android-ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/i686-linux-android21-clang",
      #|      "cc-flags": "--target=i686-linux-android21",
      #|      "cc-link-flags": "-llog -landroid",
      #|      "stub-cc": "/opt/android-ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/i686-linux-android21-clang",
      #|    },
      #|  },
      #|)
    ) +
    "\n"
  assert_eq(
    @moon_abi.render(@moon_abi.generate(unix_profile(21), @moon_abi.Abi::X86)),
    expected_x86,
  )
  let expected_x64 = (
      #|// generated by moon_abi; do not edit by hand
      #|// abi=x86_64 triple=x86_64-linux-android api_level=21
      #|supported_targets = "native"
      #|options(
      #|  link: {
      #|    "native": {
      #|      "cc": "/opt/android-ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android21-clang",
      #|      "cc-flags": "--target=x86_64-linux-android21",
      #|      "cc-link-flags": "-llog -landroid",
      #|      "stub-cc": "/opt/android-ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android21-clang",
      #|    },
      #|  },
      #|)
    ) +
    "\n"
  assert_eq(
    @moon_abi.render(
      @moon_abi.generate(unix_profile(21), @moon_abi.Abi::X86_64),
    ),
    expected_x64,
  )
}

///|
/// render：高 API level golden 快照（arm64-v8a / API 35）。
test "render: golden API 35" {
  let expected = (
      #|// generated by moon_abi; do not edit by hand
      #|// abi=arm64-v8a triple=aarch64-linux-android api_level=35
      #|supported_targets = "native"
      #|options(
      #|  link: {
      #|    "native": {
      #|      "cc": "/opt/android-ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android35-clang",
      #|      "cc-flags": "--target=aarch64-linux-android35",
      #|      "cc-link-flags": "-llog -landroid",
      #|      "stub-cc": "/opt/android-ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android35-clang",
      #|    },
      #|  },
      #|)
    ) +
    "\n"
  assert_eq(
    @moon_abi.render(
      @moon_abi.generate(unix_profile(35), @moon_abi.Abi::Arm64V8a),
    ),
    expected,
  )
}

///|
/// render：Windows 路径风格 golden 快照（`\` 在 DSL 字符串内转义为 `\\`）。
test "render: golden Windows 路径风格" {
  let expected = (
      #|// generated by moon_abi; do not edit by hand
      #|// abi=x86_64 triple=x86_64-linux-android api_level=24
      #|supported_targets = "native"
      #|options(
      #|  link: {
      #|    "native": {
      #|      "cc": "C:\\android-ndk\\toolchains\\llvm\\prebuilt\\windows-x86_64\\bin\\x86_64-linux-android24-clang",
      #|      "cc-flags": "--target=x86_64-linux-android24",
      #|      "cc-link-flags": "-llog -landroid",
      #|      "stub-cc": "C:\\android-ndk\\toolchains\\llvm\\prebuilt\\windows-x86_64\\bin\\x86_64-linux-android24-clang",
      #|    },
      #|  },
      #|)
    ) +
    "\n"
  assert_eq(
    @moon_abi.render(@moon_abi.generate(win_profile(24), @moon_abi.Abi::X86_64)),
    expected,
  )
}

///|
/// render：同一输入两次渲染逐字相等（确定性）。
test "render: 双次渲染确定性" {
  for abi in all_abis() {
    let cfg = @moon_abi.generate(unix_profile(28), abi)
    assert_eq(@moon_abi.render(cfg), @moon_abi.render(cfg))
    let cfg_win = @moon_abi.generate(win_profile(28), abi)
    assert_eq(@moon_abi.render(cfg_win), @moon_abi.render(cfg_win))
  }
}

///|
/// render：Windows 含空格路径提前拒绝（`PathContainsSpace`，不自动加引号）。
test "render: 空格路径抛 PathContainsSpace" {
  let p = profile("C:\\Program Files\\android-ndk", "r27", 21, true)
  let cfg = @moon_abi.generate(p, @moon_abi.Abi::Arm64V8a)
  let e = @test.expect_error(() => @moon_abi.render(cfg))
  assert_true(
    e
    is @moon_abi.MoonAbiError::PathContainsSpace(
      "C:\\Program Files\\android-ndk\\toolchains\\llvm\\prebuilt\\windows-x86_64\\bin\\aarch64-linux-android21-clang"
    ),
  )
}

///|
/// render：flag 含空格同样拒绝。
test "render: flag 含空格抛 PathContainsSpace" {
  let cfg = @moon_abi.LinkNativeConfig::{
    cc: "/opt/ndk/bin/clang",
    cc_flags: ["-IC:\\Program Files\\inc"],
    cc_link_flags: [],
    stub_cc: None,
    supported_targets: "native",
    triple: @moon_abi.TargetTriple::Aarch64LinuxAndroid,
    abi: @moon_abi.Abi::Arm64V8a,
    api_level: @moon_abi.ApiLevel::{ level: 21, },
  }
  let e = @test.expect_error(() => @moon_abi.render(cfg))
  assert_true(
    e is @moon_abi.MoonAbiError::PathContainsSpace("-IC:\\Program Files\\inc"),
  )
}

///|
/// render：cc 缺失报 `MissingClang`。
test "render: 空 cc 抛 MissingClang" {
  let cfg = @moon_abi.LinkNativeConfig::{
    cc: "  ",
    cc_flags: [],
    cc_link_flags: [],
    stub_cc: None,
    supported_targets: "native",
    triple: @moon_abi.TargetTriple::Aarch64LinuxAndroid,
    abi: @moon_abi.Abi::Arm64V8a,
    api_level: @moon_abi.ApiLevel::{ level: 21, },
  }
  let e = @test.expect_error(() => @moon_abi.render(cfg))
  assert_true(e is @moon_abi.MoonAbiError::MissingClang("  "))
}

///|
/// render：triple 与 abi 不一致报 `InvalidTriple(triple)`（非法 ABI 组合）。
test "render: 非法 ABI 组合抛 InvalidTriple" {
  let cfg = @moon_abi.LinkNativeConfig::{
    cc: "/opt/ndk/bin/i686-linux-android21-clang",
    cc_flags: [],
    cc_link_flags: [],
    stub_cc: None,
    supported_targets: "native",
    triple: @moon_abi.TargetTriple::I686LinuxAndroid,
    abi: @moon_abi.Abi::X86_64,
    api_level: @moon_abi.ApiLevel::{ level: 21, },
  }
  let e = @test.expect_error(() => @moon_abi.render(cfg))
  assert_true(e is @moon_abi.MoonAbiError::InvalidTriple("i686-linux-android"))
}

///|
/// render：`stub_cc` 为 `None` 时省略 `stub-cc` 行，为 `Some` 时渲染该行。
test "render: stub_cc 分支" {
  let base = @moon_abi.LinkNativeConfig::{
    cc: "/opt/ndk/bin/clang",
    cc_flags: ["--target=aarch64-linux-android21"],
    cc_link_flags: ["-llog", "-landroid"],
    stub_cc: None,
    supported_targets: "native",
    triple: @moon_abi.TargetTriple::Aarch64LinuxAndroid,
    abi: @moon_abi.Abi::Arm64V8a,
    api_level: @moon_abi.ApiLevel::{ level: 21, },
  }
  let out_none = @moon_abi.render(base)
  assert_false(out_none.contains("stub-cc"))
  let out_some = @moon_abi.render({
    ..base,
    stub_cc: Some("/opt/ndk/bin/clang"),
  })
  assert_true(out_some.contains("\"stub-cc\": \"/opt/ndk/bin/clang\","))
}

///|
/// validate：合法 profile 全绿（ok、无警告、无错误）。
test "validate: 合法 profile 全绿" {
  let report = @moon_abi.validate(unix_profile(21), @moon_abi.Abi::Arm64V8a)
  assert_true(report.ok)
  assert_eq(report.errors.length(), 0)
  assert_eq(report.warnings.length(), 0)
}

///|
/// validate：硬问题进 `errors` 并阻断（ok = false）。
test "validate: 硬错误进 errors 且阻断" {
  let p = profile("", "r21", 16, false)
  let report = @moon_abi.validate(p, @moon_abi.Abi::Arm64V8a)
  assert_false(report.ok)
  assert_eq(report.errors.length(), 3)
  assert_true(report.errors[0].contains("MissingNdkRoot"))
  assert_true(report.errors[1].contains("UnsupportedApiLevel"))
  assert_true(report.errors[2].contains("VersionMismatch"))
  let spaced = @moon_abi.validate(
    profile("C:\\Program Files\\ndk", "r27", 21, true),
    @moon_abi.Abi::Arm64V8a,
  )
  assert_false(spaced.ok)
  assert_true(spaced.errors[0].contains("PathContainsSpace"))
}

///|
/// validate：警告不阻断（ok 保持 true，warnings 非空）。
test "validate: 警告不阻断" {
  let p = @moon_abi.NdkProfile::{
    ndk_root: "/opt/android-ndk",
    ndk_version: "r27",
    api_level: @moon_abi.ApiLevel::{ level: 21, },
    extra_link_libs: ["log"],
    extra_cc_flags: [""],
    windows_path_style: true,
  }
  let report = @moon_abi.validate(p, @moon_abi.Abi::X86)
  assert_true(report.ok)
  assert_eq(report.errors.length(), 0)
  assert_eq(report.warnings.length(), 3)
  assert_true(report.warnings[0].contains("empty_entry"))
  assert_true(report.warnings[1].contains("duplicate_link_lib"))
  assert_true(report.warnings[2].contains("path_style_mismatch"))
}
