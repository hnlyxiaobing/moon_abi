// W2：NdkNotFound 构造级簿记（whitebox：pub suberror 变体在定义包外只读，
// 构造级断言只能落在库包内的 whitebox 测试；黑盒触发级用例见
// ndk_resolve_test.mbt 的 resolve_ndk_values 注入测试）。

///|
test "NdkNotFound: 构造级退出码与消息簿记（W2）" {
  let err = MoonAbiError::NdkNotFound("ndk missing detail")
  assert_eq(exit_code_for_error(err), 1)
  assert_eq(error_message(err), "ndk missing detail")
}
