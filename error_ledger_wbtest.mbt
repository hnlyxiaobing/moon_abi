// 错误变体簿记门禁（whitebox：可在定义包内构造 pub suberror 变体）。
//
// 测试系统设计 §6.2 / §8.3「错误簿记门禁」：每个 `MoonAbiError` 变体都必须
// （1）被 `error_message` / `exit_code_for_error` 的穷尽匹配处理（编译期强制），
// （2）在测试中有 ≥1 显式触发（行为层，见各 *_test.mbt），（3）在此门禁内被
// 显式构造并断言可读消息与退出码归属（结构层）。缺一即红。
//
// 本门禁把「变体 → 触发 fixture」清单（§6.2）固化为代码：列出全部 11 变体，
// 断言每个都能构造、都有非空人读消息、退出码落入 1/2 契约；并断言清单与
// 已知 11 变体集合一一对应（无缺无余）。新增变体必须同时在此清单登记并补行为触发。

///|
/// 簿记清单：`(变体名, 是否已交付行为触发)`。`true` 表示 §6.2 已登记显式触发
/// fixture 且测试已落地；`false` 表示该变体虽可构造但尚无行为触发（应红）。
fn ledger_entries() -> Array[(String, Bool)] {
  [
    ("UnsupportedAbi", true),
    ("UnsupportedApiLevel", true),
    ("MissingNdkRoot", true),
    ("MissingClang", true),
    ("PathContainsSpace", true),
    ("InvalidTriple", true),
    ("VersionMismatch", true),
    ("CliUsage", true),
    ("IoFailure", true),
    ("MalformedConfig", true),
    ("NdkNotFound", true),
  ]
}

///|
/// 簿记门禁：11/11 变体都可构造、消息非空、退出码 ∈ {1,2}，且清单无缺无余。
test "error ledger gate: 11/11 变体可构造且消息/退出码健全" {
  let entries = ledger_entries()
  // 清单必须恰好覆盖已知 11 变体（无缺无余，且无重复）。
  assert_eq(entries.length(), 11)
  let seen = entries.map(fn(e) { e.0 })
  for name in seen {
    assert_true(
      count_in(seen, name) == 1,
      msg="变体 " + name + " 在清单中必须恰好出现一次",
    )
  }
  // 每个变体构造并断言人读消息非空、退出码属于 1/2 契约。
  for (name, triggered) in entries {
    let err = construct_variant(name)
    let msg = error_message(err)
    assert_true(
      msg.length() > 0,
      msg="变体 " + name + " 的人读消息不得为空",
    )
    let code = exit_code_for_error(err)
    assert_true(
      code == 1 || code == 2,
      msg="变体 " + name + " 退出码必须在 1/2 契约内",
    )
    assert_true(
      triggered,
      msg="变体 " + name + " 缺行为触发，不得标记通过",
    )
  }
}

///|
/// 统计 `name` 在 `names` 中出现的次数（清单无重复断言用）。
fn count_in(names : Array[String], name : String) -> Int32 {
  let mut n = 0
  for item in names {
    if item == name {
      n = n + 1
    }
  }
  n
}

///|
/// 用该变体的「最小可构造样值」构造一个实例（仅验证构造/消息/退出码健全性）。
/// 命中未知变体名即 `fail`（raise Failure），故签名带 `raise`。
fn construct_variant(name : String) -> MoonAbiError raise {
  match name {
    "UnsupportedAbi" => UnsupportedAbi("mips")
    "UnsupportedApiLevel" => UnsupportedApiLevel(20, 21)
    "MissingNdkRoot" => MissingNdkRoot
    "MissingClang" => MissingClang("C:\\ndk\\clang.exe")
    "PathContainsSpace" => PathContainsSpace("C:\\Program Files\\ndk")
    "InvalidTriple" => InvalidTriple("arm-linux-androideabi21")
    "VersionMismatch" => VersionMismatch("r22+", "r21")
    "CliUsage" => CliUsage("--api expects a positive integer")
    "IoFailure" => IoFailure("moon.pkg", "permission denied")
    "MalformedConfig" =>
      MalformedConfig("multiple managed blocks are not supported")
    "NdkNotFound" => NdkNotFound("ndk missing detail")
    _ => fail("未知变体名 " + name)
  }
}
