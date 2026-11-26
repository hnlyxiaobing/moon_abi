// 截断/变异扫描驱动（whitebox：可访问包内私有 parser）。
//
// 目的（测试系统设计 §4「截断扫描」；技能 §3 M0 必做项 3）：对每个已登记的
// parser 遍历其输入的全前缀（0..n 字符边界，天然覆盖全部结构边界点），断言每次
// 调用要么返回合法输出、要么抛 `MoonAbiError`（11 变体之一），**绝不允许出现
// 与 MoonAbiError 无关的 panic**（越界/溢出/其他错误通道）。
//
// 用法：新解析路径（W3 空白/多 END/键名变体、W4 新选项、W5 宿主）随能力同一
// 提交，在文件底部以「一行 `register_*`」接入本扫描。这保证 DoD「新解析路径随包
// 进入扫描」成立，而不是在收尾时批量补写。

///|
/// 对单个前缀做一次解析：合法输出或 `MoonAbiError` 均接受；
/// 任何非 `MoonAbiError` 的错误/panic 会从这里逃逸，从而让整个测试失败。
/// `catch { _ => () }` 只吞 `MoonAbiError`（由 parse 的 raise 签名固定错误通道）；
/// 越界/溢出等其它错误类型不属该通道，会直接传播并导致测试失败。
fn scan_one_prefix(
  prefix : String,
  parse : (String) -> Unit raise MoonAbiError,
) -> Unit {
  let _ = parse(prefix) catch { _ => () }
}

///|
/// 通用截断扫描驱动：对 `seed` 的每个字符边界前缀 `0..i`（i 从 0 到 len）调用
/// `parse`。调用方以闭包把具体 parser 适配为 `(String) -> Unit raise MoonAbiError`。
/// 纯函数、确定性；无 panic 断言即本函数的通过条件。
fn run_truncation_scan(
  seed : String,
  parse : (String) -> Unit raise MoonAbiError,
) -> Unit {
  let len = seed.length()
  let mut i = 0
  while i <= len {
    scan_one_prefix(seed[:i].to_owned(), parse)
    i = i + 1
  }
}

///|
/// 参数序列截断扫描驱动：对 `args` 的每个前缀 `0..i`（i 从 0 到 len）调用 `parse`。
/// 覆盖 `parse_gen_args` 这类 Array[String] 输入的截断路径。
fn run_truncation_scan_args(
  args : ArrayView[String],
  parse : (ArrayView[String]) -> Unit raise MoonAbiError,
) -> Unit {
  let len = args.length()
  let mut i = 0
  while i <= len {
    let _ = parse(args[0:i]) catch { _ => () }
    i = i + 1
  }
}

///|
/// 测试用受管块（无空格 token，`managed_block` 可安全渲染）；whitebox 就地构造，
/// 不依赖其它测试文件内的 helper。
fn scan_block_or_fail() -> String raise MoonAbiError {
  let cfg : LinkNativeConfig = {
    cc: "C:\\android-ndk\\toolchains\\llvm\\prebuilt\\windows-x86_64\\bin\\aarch64-linux-android21-clang",
    cc_flags: ["--target=aarch64-linux-android21"],
    cc_link_flags: ["-llog", "-landroid"],
    stub_cc: None,
    supported_targets: "native",
    triple: TargetTriple::Aarch64LinuxAndroid,
    abi: Abi::Arm64V8a,
    api_level: ApiLevel::{ level: 21, },
  }
  managed_block(cfg)
}

///|
/// 截断扫描：`merge_link_config` 既有文本（受管块标记解析）。
test "truncation scan: merge_link_config 既有文本全前缀无 panic" {
  let seed = [
    "// >>> moon_abi gen:managed (do not edit this block) >>>", "some user content",
    "// <<< moon_abi gen:managed <<<",
  ].join("\n")
  run_truncation_scan(seed, existing => {
    let block = scan_block_or_fail()
    ignore(merge_link_config(existing, block))
  })
}

///|
/// 截断扫描：`merge_link_config` 畸形标记边界（多 begin / 孤儿 end 等）。
test "truncation scan: merge_link_config 畸形标记全前缀无 panic" {
  let seeds : Array[String] = [
    "// >>> moon_abi gen:managed (do not edit this block) >>>", "// <<< moon_abi gen:managed <<<",
    "// >>> moon_abi gen:managed (do not edit this block) >>>\n// <<< moon_abi gen:managed <<<",
    "a\n// >>> moon_abi gen:managed (do not edit this block) >>>\nb\n// <<< moon_abi gen:managed <<<",
    // W3：单 begin + 多 end（旧 B15 孤儿 end）必须进扫描，全前缀不得 panic。
     "// >>> moon_abi gen:managed (do not edit this block) >>>\n// <<< moon_abi gen:managed <<<\n// <<< moon_abi gen:managed <<<",
    "\n", "// >>>\n// <<<",
  ]
  for seed in seeds {
    run_truncation_scan(seed, existing => {
      let block = scan_block_or_fail()
      ignore(merge_link_config(existing, block))
    })
  }
}

///|
/// 截断扫描：`parse_pkg_revision` source.properties 内容全前缀无 panic。
/// W3：种子覆盖标准键（带空格/紧邻 `=`）与误命中键（`Pkg.RevisionFoo`）。
test "truncation scan: parse_pkg_revision source.properties 全前缀无 panic" {
  let seeds : Array[String] = [
    "Pkg.Revision = 27.0.12077973\nPkg.Desc = Android NDK 27\n", "Pkg.Revision=27.0.12077973",
    "Pkg.RevisionFoo = 27.0.12077973\nPkg.Desc = x\n",
  ]
  for seed in seeds {
    run_truncation_scan(seed, text => ignore(parse_pkg_revision(text)))
  }
}

///|
/// 截断扫描：`render` / `check_no_space` 对含空白 token 的输入全前缀无 panic。
/// W3 新解析路径：任一空白字符（tab/CR/LF/VT/FF）出现在 token 中即 fail-closed
/// 拒绝；前缀不含空白时仍为合法输出——两者均属扫描允许通道（MoonAbiError 或合法输出）。
test "truncation scan: render 含空白 token 全前缀无 panic" {
  let seeds : Array[String] = [
    "/opt/ndk/bin/aarch64-linux-android21-clang\tx", "C:\\ndk\t\\bin\\aarch64-linux-android21-clang",
    "/opt/ndk\nbin/aarch64-linux-android21-clang",
  ]
  for seed in seeds {
    run_truncation_scan(seed, cc => {
      let cfg : LinkNativeConfig = {
        cc,
        cc_flags: [],
        cc_link_flags: [],
        stub_cc: None,
        supported_targets: "native",
        triple: TargetTriple::Aarch64LinuxAndroid,
        abi: Abi::Arm64V8a,
        api_level: ApiLevel::{ level: 21, },
      }
      ignore(render(cfg))
    })
  }
}

///|
/// 截断扫描：`parse_gen_args` 参数序列全前缀无 panic。
test "truncation scan: parse_gen_args 参数序列全前缀无 panic" {
  let args : Array[String] = [
    "--abi", "arm64-v8a", "--api", "21", "--ndk-root", "/opt/ndk", "--ndk-version",
    "r27",
  ]
  run_truncation_scan_args(args, argv => ignore(parse_gen_args(argv)))
}
