# CHANGELOG（加法性变更簿记）

> 口径：每工作包登记「日期 / 工作包 / 新增 pub 声明 / 快照 diff 结论 / 测试增量」；
> 快照由 `moon info` 生成（禁手编）；#skip/SKIPPED 永不计入通过。
> 配套设计文档：[2026-11-16-ndk-config-fidelity-dev-plan.md](2026-11-16-ndk-config-fidelity-dev-plan.md)。

## 2026-11-16 · M0（W1 + W2，用户裁决 W2-A / W6-A 后落地）

### W1 漂移清理与文档自包含（纯文档/注释/CI 文案）

- 新增 pub 声明：无。快照 diff：空。测试增量：0。
- ci.yml：Gate5 失败消息 `docs/API.md`（已删文件）→ README.md API 索引 + docs/CHANGELOG.md；`.r1` 存档注释改为历史说明（文件已于 d4b18a8 删除）；删除 `bobzhang/zip@0.1.2` 误植示例（本模块零第三方依赖）。
- copilot-setup-steps.yml：同步删除 bobzhang/zip 误植示例。
- moon_abi.mbt：MIN_API_LEVEL 注释删除跨仓库符号引用（`moon_android::ToolchainVersions`），改自足表述。
- README.md：「唯一说明文档」→「入口文档」+ docs/ 索引；API 索引补齐 4 条漏抽 pub 声明（probe_ndk / sync_config_file / MoonAbiError::to_repr / ConfigRenderer），抽取口径改为全部 pub 声明（含 async/方法/trait）；依赖口径补 debug/env/test 注记；§6 补 probe 文本记录行 `|`/换行歧义局限声明与提交数实测口径。
- 新建 docs/ 开发文档与测试系统设计文档（2026-11-16）、本 CHANGELOG。
- 历史口径修正（实测推翻，详见开发文档 §0 B#）：提交数 15→16；pub(all) 值类型 8→16；错误显式簿记「全覆盖」→9/11（W2 前）。

### W2 错误簿记补齐与 NdkNotFound 接线（裁决 A）

- 新增 pub 声明：`pub fn resolve_ndk_values(GenCommand, NdkProbeResult) -> (String, String) raise MoonAbiError`（纯加法）。
- 快照 diff：pkg.generated.mbti +2 行（上述声明）；cmd/main/pkg.generated.mbti 零漂移。
- 测试增量：+8（68→76；wasm 与 native 双目标各 76/76，旧用例零改动全绿，#skip=0）。
  - gen_cli_test.mbt +1：CliUsage 显式变体断言 6 例。
  - ndk_resolve_test.mbt +6：resolve_ndk_values 注入式行为样例（含 NdkNotFound 两条失败路径的确定性触发与消息冻结断言）。
  - ndk_resolve_wbtest.mbt +1：NdkNotFound 构造级 exit/message 断言（whitebox，见下方语言约束）。
- 行为变更：无对外契约变更。NdkNotFound 由死变体转为库内 raise（resolve_ndk_values）；CLI resolve_ndk 委托库纯函数，失败路径 stderr 单行文案与退出码 1 逐字节不变（T-W2-2：改动前后 stdout/stderr SHA-256 一致，2026-11-16 实测）；17 场景 CLI 冒烟复跑全符合契约。错误显式簿记 9/11 → **11/11**。
- 语言约束登记（实测发现，设计偏差已回写开发文档 W2）：
  1. MoonBit `pub suberror` 变体在定义包外只读（错误 4036）：cmd/main 无法构造 NdkNotFound，故 raise 点必须落库内（新增纯函数承载）；构造级测试只能落库包内 whitebox（`_wbtest.mbt`）。
  2. `moon check --deny-warn` 的 result_error_return lint 禁止 `Result[T, MoonAbiError]` 返回形态：CLI 维持 `Result[T, String]` 归一。
  3. 主包（executable）黑盒测试（`_test.mbt`）触发未来弃用警告：cmd/main 不落黑盒测试文件。

### 待落地（已裁决/已排期）

- W3 fail-closed 输入加固（M1）：合入时须在此登记「以前静默放行的损坏/不安全输入现在拒绝」条目与受影响样本清单。
- W4 CLI extra/多 ABI（M2）、W5 宿主/API 矩阵（M3，数据表先联网核实）、W6-A 外部 oracle runner（M4，脚本层零 API）。