// Whitebox tests run within the package scope.
// 覆盖内部映射表、版本解析、转义/连接等纯辅助函数与 ConfigRenderer 契约一致性。

///|
/// ndk_major：rXX / rXX 字母 / 点分版本号三种官方写法均可解析。
test "ndk_major: 版本解析" {
  match ndk_major("r22") {
    Some(n) => assert_eq(n, 22)
    None => fail("expected Some(22)")
  }
  match ndk_major("r27c") {
    Some(n) => assert_eq(n, 27)
    None => fail("expected Some(27)")
  }
  match ndk_major("27.0.12077973") {
    Some(n) => assert_eq(n, 27)
    None => fail("expected Some(27)")
  }
  match ndk_major("r22c") {
    Some(n) => assert_eq(n, 22)
    None => fail("expected Some(22)")
  }
}

///|
/// ndk_major：不可解析的版本串返回 `None`。
test "ndk_major: 非法版本返回 None" {
  for v in ["", "banana", "r", "rc"] {
    match ndk_major(v) {
      Some(n) => fail("expected None for " + v + ", got " + n.to_string())
      None => ()
    }
  }
}

///|
/// triple_of_name：非法 ABI 名抛 `UnsupportedAbi(name)`（不可变映射表的防御分支）。
test "triple_of_name: 非法 ABI 名抛 UnsupportedAbi" {
  try {
    ignore(triple_of_name("mips"))
    fail("expected UnsupportedAbi")
  } catch {
    MoonAbiError::UnsupportedAbi(name) => assert_eq(name, "mips")
    _ => fail("expected UnsupportedAbi")
  }
}

///|
/// triple_of_name：映射表覆盖全部 4 种 ABI，且与 triple_name 互逆。
test "triple_of_name: 映射表完整" {
  assert_eq(
    triple_name(triple_of_name("armeabi-v7a")),
    "armv7a-linux-androideabi",
  )
  assert_eq(triple_name(triple_of_name("arm64-v8a")), "aarch64-linux-android")
  assert_eq(triple_name(triple_of_name("x86")), "i686-linux-android")
  assert_eq(triple_name(triple_of_name("x86_64")), "x86_64-linux-android")
}

///|
/// abi_name：规范 Android ABI 名称。
test "abi_name: 规范名称" {
  assert_eq(abi_name(Abi::ArmeabiV7a), "armeabi-v7a")
  assert_eq(abi_name(Abi::Arm64V8a), "arm64-v8a")
  assert_eq(abi_name(Abi::X86), "x86")
  assert_eq(abi_name(Abi::X86_64), "x86_64")
}

///|
/// escape_dsl：转义 `\` 与 `"`，保证 Windows 路径在 moon.pkg 字符串字面量内合法。
test "escape_dsl: 转义反斜杠与引号" {
  assert_eq(escape_dsl("plain"), "plain")
  assert_eq(escape_dsl("C:\\android-ndk\\bin"), "C:\\\\android-ndk\\\\bin")
  assert_eq(escape_dsl("a\"b"), "a\\\"b")
}

///|
/// join_flags / trim_trailing_sep / clang_driver：纯字符串辅助函数。
test "字符串辅助函数" {
  assert_eq(join_flags([]), "")
  assert_eq(join_flags(["-a"]), "-a")
  assert_eq(join_flags(["-a", "-b", "-c"]), "-a -b -c")
  assert_eq(trim_trailing_sep("/opt/ndk"), "/opt/ndk")
  assert_eq(trim_trailing_sep("/opt/ndk/"), "/opt/ndk")
  assert_eq(trim_trailing_sep("C:\\ndk\\"), "C:\\ndk")
  assert_eq(trim_trailing_sep("/"), "/")
  assert_eq(
    clang_driver("aarch64-linux-android", 21),
    "aarch64-linux-android21-clang",
  )
}

///|
/// cc_path：分隔符与 prebuilt 宿主标签由 windows_path_style 决定。
test "cc_path: 分隔符与宿主标签" {
  assert_eq(
    cc_path("/opt/ndk", false, "i686-linux-android", 24),
    "/opt/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/i686-linux-android24-clang",
  )
  assert_eq(
    cc_path("C:\\ndk", true, "x86_64-linux-android", 21),
    "C:\\ndk\\toolchains\\llvm\\prebuilt\\windows-x86_64\\bin\\x86_64-linux-android21-clang",
  )
}

///|
/// ConfigRenderer 契约：trait 渲染与 `render` 自由函数逐字一致。
test "ConfigRenderer 渲染与 render 一致" {
  let cfg = LinkNativeConfig::{
    cc: "/opt/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang",
    cc_flags: ["--target=aarch64-linux-android21"],
    cc_link_flags: ["-llog", "-landroid"],
    stub_cc: None,
    supported_targets: "native",
    triple: TargetTriple::Aarch64LinuxAndroid,
    abi: Abi::Arm64V8a,
    api_level: ApiLevel::{ level: 21, },
  }
  assert_eq(ConfigRenderer::render(cfg), render(cfg))
  assert_false(ConfigRenderer::render(cfg).contains("stub-cc"))
}
