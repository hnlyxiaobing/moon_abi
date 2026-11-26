# moon_abi 测试系统设计（第一性原理）

> 建立：2026-11-16 ｜ 状态：设计生效，随开发文档逐包落地 ｜ 适用仓库：本仓库（独立自包含）
> 配套文档：[2026-11-16-ndk-config-fidelity-dev-plan.md](2026-11-16-ndk-config-fidelity-dev-plan.md)（`T-W*-*` 验收 ID 一一对应；B# 证据行出自该文档 §0）
> 现状基线：2026-11-16 实跑 `moon test` 68/68（默认 wasm 目标）、`moon test --target native` 68/68、#skip=0；五门禁全绿、双快照零漂移。
> M0（W1+W2）交付后 2026-11-16 复跑：双目标各 **76/76**（+8，旧用例零改动）、#skip=0；错误簿记 **11/11** 达成；快照 diff 纯加法（resolve_ndk_values）；T-W2-2 防火墙实测通过（resolve 失败路径 stdout/stderr SHA-256 与基线一致）。
> M1（W3）交付后 2026-11-26 复跑：双目标各 **86/86**（+5，旧用例零改动）、#skip=0；快照 diff 空；T-W3-1..5 全绿；新解析路径随包一行接入截断扫描。
> M2（W4）交付后 2026-11-26 复跑：双目标各 **94/94**（+8，旧用例零改动）、#skip=0；快照 diff 纯加法（+3 声明 +1 struct）；T-W4-1..5 全绿；`parse_gen_args_ext` 新解析路径随包一行接入截断扫描；17 场景逐字节防火墙 + 4 个 W4 新场景实跑符合。
> M3（W5）交付后 2026-11-26 复跑：双目标各 **99/99**（+5，旧用例零改动）、#skip=0；快照 diff 纯加法（+4 声明）；T-W5-1..4 全绿；`api_level_advisory` 新解析路径随包一行接入截断扫描；darwin 宿主标签与 NDK major→API 表已联网核实并登记 CHANGELOG。

## 1. 第一性原理：本库的正确性是什么

本库的数学形态：`(NdkProfile, Abi) → (LinkNativeConfig, 渲染文本, 校验结论) | MoonAbiError`，外加两个受控副作用通道：只读探测 `NdkProbeInputs → NdkProbeResult`（事实报告）与受管块幂等写 `(既有文本, 块) → (新文本, 动作)`。

正确性不可约简为以下断言，每条必须有测试层承载：

| # | 断言 | 含义 | 反例（测试必须抓住） |
|---|---|---|---|
| A1 | 寻址忠实 | triple/wrapper 命名、cc 路径拼接、flag 注入顺序与 NDK 规范及声明一致 | `armv7a-linux-androideabi21-clang` 写成 `arm-linux-androideabi21-clang`；`--target=` 后缀漏 API level；extra flag 乱序 |
| A2 | 完整性 fail-closed | 可校验项不一致必被报告；未校验≠通过；损坏标记/空白 token/误命中键不得静默放行 | 多 END 标记被接受（B15）；tab token 渲染出断裂 DSL（B6）；`Pkg.RevisionFoo` 被当版本（B19） |
| A3 | 边界纯净 | 只输出配置值/文本/事实报告；不产出构建执行结论；探测不安装不下载；validate 只报告不决策 | probe 结果里出现「已为你配置/修复」类语义；render 输出含执行指令 |
| A4 | 输入安全 | 任意畸形字符串不 panic/不越界；合并不破坏块外内容；写盘不逃逸受管块；内存有界（全量字符串=文件大小上界） | 截断的 source.properties 致 panic；merge 吞掉用户头部；Unchanged 仍写盘 |
| A5 | 契约稳定 | API 签名/CLI 记录行/退出码 0/1/2 与文档一致；变更只加法；旧 API 语义永不变 | 新函数合入后旧 render 输出变化；退出码 2 变 1；`NDK|…` 字段序漂移 |
| A6 | 平台等价 | wasm 与 native 同输入同输出（纯函数层）；FS 层语义等价（注入通道≡真实通道） | 同一 profile 两目标渲染文本不同；probe_ndk_with 与 probe_ndk 判定分歧 |

设计推论：A1/A2 → 性质测试+穷举扫描；A2 语义 → 恒等式断言+错误簿记；A4 → 截断扫描+变异语料+边界值；A5/A6 → 门禁与差分；真实符合性（配置真能被 moon+NDK 消费）→ 外部 oracle 层（W6，许可约束下本地可选）。

## 2. 测试分层

```text
L0 单元与程序化 fixture（每个 pub fn 行为样例）——现状主体，76 条（M0 后）
L1 性质与变异（变形律/截断扫描/位翻转/边界值）——现状仅确定性/幂等点状覆盖，待建系统化
L2 受控黄金差分（内嵌 golden 文本 + 逐字段黄金记录）——现状 render golden 6 组，待扩 probe/merge
L3 外部 oracle 差分（moon build + 真实 NDK，本地可选，SKIPPED 纪律）——未实现（W6 已裁决 A，待 M4 落地）
L4 CLI 场景 E2E（预期场景 + 安全拒绝语料 + 退出码矩阵）——现状 17 场景手工实跑基线，待脚本固化
L5 元契约门禁（快照/错误簿记/双目标等价/变异自检/引用实存性）——快照门禁已在 CI，其余待建
R  真实样本本地 runner（仓库外 NDK 路径 + SHA-256 门禁 + 显式 SKIPPED）——未实现（W6）
```

断言×层承载表：

| 断言 | 主承载层 | 辅助层 |
|---|---|---|
| A1 寻址忠实 | L0（golden 逐字段） | L2、L3（oracle 消费验证） |
| A2 fail-closed | L0（负例变体断言） | L1（截断/变异）、L5（簿记门禁） |
| A3 边界纯净 | L0（输出形态断言） | L4（CLI 只读/写盘范围）、L5（防火墙） |
| A4 输入安全 | L1（截断/变异/边界值） | L0（错误注入）、L4（安全拒绝场景） |
| A5 契约稳定 | L5（快照/簿记/引用扫描） | L4（退出码矩阵）、L2（记录行 golden） |
| A6 平台等价 | L5（双目标 moon test） | L0（双通道一致律） |

## 3. fixture 体系

| 类 | 形态 | 入库 | 许可 | 现状 |
|---|---|---|---|---|
| F-A 程序化构造 | 测试代码内 profile/config/伪目录闭包 builder | 是 | 随仓库 | 主体（B36）：profile()/sample_config()/no_inputs()/注入闭包 |
| F-B 受控文件 fixture | tests/fixtures/* | 是 | 哈希登记 | **不存在**（B36）：本模块无需二进制 fixture，维持零文件 fixture；临时目录伪 NDK 用后即焚 |
| F-C 生成器资产 | 确定性脚本产出（变异语料/截断前缀） | 是（种子+算法入库，语料不入库） | 自产 | 待建（L1 系统化，W3/W4 随包） |
| F-D 真实第三方样本 | 仓库外本地 NDK 安装 | 否（红线） | 许可不明 | R runner（W6-A，M4）；永不入库 |

红线：F-D 永不入库；临时目录测试必须递归清理（现有 gen_cli_fs_test/ndk_probe_fs_test 模式延续）；未来若引入文件 fixture，哈希变更须同步登记+黄金记录。

builder 能力清单（现有 + 待扩）：
- 现有：NdkProfile 四参 builder（root/version/level/windows）、LinkNativeConfig 直构、NdkProbeInputs 六字段直构、伪目录三闭包（exists/list/read）、ReadOutcome 三态注入、write 失败注入（权限拒绝/磁盘满）。
- 待扩（W3/W4）：空白字符变体（tab/CR/LF/VT/FF 逐类）、多 END/孤儿标记变体、source.properties 键名变体（Pkg.RevisionFoo/大小写/无=/多行）、GenCommandExt 多 ABI/extra 序列、截断前缀生成器（固定种子）、变异算子（替换/插入/删除，固定种子 ≥1000 变异体/轮）。

## 4. L1 性质与变异

- 变形律 P#：
  - P1 渲染确定性律：`render(c) == render(c)` 逐字节（现有，扩至 generate_with_host/多 ABI 输出）。
  - P2 合并幂等律：`merge(merge(x,b).content, b).action == Unchanged` 且 content 不变（现有，扩至变异语料全集）。
  - P3 块外保留律：merge 前后受管块区间外的前缀/后缀逐字保留（现有，固化为恒等式）。
  - P4 探测去重律：重复路径输入（explicit≡ndk_home≡sdk 展开）候选去重、selected 不变（现有）。
  - P5 版本排序稳定律：版本目录名任意排列输入 → 排序输出唯一（待建：排列穷举 3!×样本）。
  - P6 双通道一致律：同一事实表下 `probe_ndk_with ≡ probe_ndk` 判定；`write_config_with ≡ sync_config_file` 动作与内容（现有人类等价论证，待建自动化差分）。
  - P7 防火墙律：任一 W# 合入后，旧函数在全部既有语料上输出逐字节不变、旧用例零改动全绿（W2-A/W3/W4/W5 合入前置断言）。
  - P8 JSON 结构律：ndk_probe_json 输出单行、无裸控制字符、引号/反斜杠全转义、字段序固定（现有，扩至含 `|`/换行/Unicode 路径样本）。
- 位翻转：**格式依赖口径**——配置文本/properties 无 checksum，翻转后可能仍是合法输入；断言口径为「要么报声明的错误类型（MoonAbiError 11 变体之一），要么输出与翻转前不同」，**不得断言全部必错**。关键字段（triple 前缀、API 数字、Pkg.Revision 值）单 bit 翻转须满足该口径。
- 边界值矩阵：API level {0,20,21,22,35,100000,100001}；NDK 版本 {"", "r", "rc", "r21", "r22", "r22c", "27.0.12077973", "banana", 超长串}；路径 {"", "/", "C:", "C:\\", 尾分隔符×3, 含空格/tab/换行, 含引号/反斜杠, 含 `|`}；merge 既有文本 {空, 无尾换行, CRLF, 1begin+2end, 2begin, end 先于 begin}；--api 累加器溢出边界 100000/100001。
- 截断扫描：merge 既有文本与 source.properties 内容的全前缀（大样本抽样+全部结构边界点：标记行中间、`=` 两侧、版本号中间）；parse_gen_args 参数序列全前缀；只允许声明的错误类型或合法输出，不允许 panic/挂起。
- 变异语料：固定种子随机替换/插入/删除，每轮 ≥1000 变异体，作用于 merge 既有文本与 properties 文本；断言 A2/A4 口径。

## 5. L3 oracle 矩阵 + R runner

| oracle | 差分对象 | 规范化口径 |
|---|---|---|
| moon build --target native + 真实 NDK（W6-A） | 生成片段作为 moon.pkg 是否可被工具链消费（退出码/诊断） | 只比「构建成功与否+错误类别」，不比产物字节（产物属组合根）；临时项目确定性自产 |
| moon check（W6-B 降级） | 生成片段 DSL 语法可解析性 | 只比 check 退出码与诊断文本规范化 |
| NDK 官方目录结构（只读核对） | cc 路径模板/prebuilt 宿主标签/source.properties 键名 | 与本地真实 NDK 目录逐项核对，报告差异；不执行任何构建 |

纪律：oracle 缺失 → 显式 SKIPPED+原因（退出码 78 口径），不得写成通过；oracle 版本（moon/NDK Pkg.Revision）随结果登记。
R runner：样本路径+登记哈希 → 哈希不符拒绝执行 → 规范化差分 → 报告「本地已差分+哈希+日期」；入库 #skip 占位用例保留不删，真实结论永不进入通过计数。

## 6. 覆盖矩阵与错误簿记

### 6.1 能力×场景×安全 覆盖矩阵

现状列来自 2026-11-16 实测（B# 见开发文档 §0）；✓=已有用例，◐=点状/间接覆盖，✗=待建。

| ID | 能力/场景 | L0 | L1 | L2 | L3 | L4 | 现状（P4） | 缺口→W# |
|---|---|---|---|---|---|---|---|---|
| F1 | ABI/triple/wrapper 命名 | ✓ | ✗ | ✓ | ✗ | ✓ | 4 ABI×多 level golden（B2） | 位翻转口径→W3 随包 |
| F2 | generate 配置值 | ✓ | ✗ | ✓ | ✗ | ✓ | 逐字段+extra 顺序（B4）；三宿主 golden（W5） | 多 ABI 已落地(W4)；宿主已落地(W5) |
| F3 | render 确定性/转义 | ✓ | ◐ | ✓ | ✗ | ✓ | golden 6 组+双次渲染（B5） | 空白变体已落地(W3) |
| F4 | validate 报告 | ✓ | ✗ | ✗ | ✗ | ✗ | 三例（B7）；API 上限 advisory 边界三态（W5） | 空白已落地(W3)；advisory 已落地(W5) |
| F5 | CLI 解析/退出码 | ✓ | ◐ | ✗ | ✗ | ◐ | 14+5 负例、17 场景手工实跑（B11/B13） | extra/多 ABI 已落地(W4)；脚本固化仍待 W6 |
| F6 | 受管块合并 | ✓ | ◐ | ✓ | ✗ | ✓ | 三态+CRLF+畸形（B14） | 多 END 已落地(W3)；变异全集→W3 |
| F7 | 写配置双通道 | ✓ | ✗ | ✗ | ✗ | ✓ | 注入三失败+FS 三例（B16/B17） | 双通道自动差分→W3 随包 |
| F8 | NDK 探测 | ✓ | ◐ | ◐ | ✗ | ✓ | 纯核心 7+FS 3+边界 4（B18/B20） | 键名变体已落地(W3)；排序律→W3 随包 |
| F9 | 错误模型 | ✓ | ✗ | ✗ | ✗ | ✓ | 显式簿记 11/11（W2 已交付，原 B9/B10 缺口已闭） | — |
| F10 | 路径风格推断 | ✓ | ✗ | ✗ | ✗ | ✓ | 盘符/反斜杠/空串（B12 相关）；三宿主显式标签/分隔符（W5） | 混合分隔符样本已覆盖(W5) |
| S1 | 预期场景端到端（gen 打印/写盘/幂等、probe 文本/JSON） | | | | | ◐ | 17 场景手工基线（B13）；W4 新增多 ABI stdout/多 ABI+--out 两场景 | 脚本固化仍待 W6 |
| S2 | 安全拒绝场景（空格/畸形/越界先于写盘整体拒绝） | ✓ | | | | ✓ | 实跑 malformed 时原文件未被改写（B13/B14） | 多 END/空白已落地(W3)；越界→W3；多 ABI+--out 已落地(W4) |
| C1 | 输入安全（畸形不 panic/内存有界） | ◐ | ◐ | | | | 错误注入覆盖+W3 截断扫描（render 空白 token 全前缀） | 变异体→W3/W4 随包 |
| C2 | 防火墙（新函数不改旧语义） | ◐ | ✗ | | | ◐ | T-W2-2 已过（W2 失败路径逐字节差分）；T-W4-4 17 场景逐字节（W4）；T-W5-2 win/linux 逐字节（W5）；其余未固化 | P7→后续 |
| C3 | 许可红线（F-D 零入库） | ✓ | | | | | 临时目录自产+用后即焚（B36） | R runner 哈希门禁→W6 |
| C4 | 契约稳定（快照/记录行/退出码） | ✓ | | ✓ | | ✓ | CI 快照门禁+实跑矩阵（B24） | 簿记/引用扫描门禁→W1/W2 |

### 6.2 错误变体触发簿记（11/11 强制）

| 变体 | 触发 fixture（现状） | 新增触发（待建） |
|---|---|---|
| UnsupportedAbi | ✓ abi_from_name("mips") 等 4 名 + wbtest triple_of_name | 无 |
| UnsupportedApiLevel | ✓ clang_name(20/0)、generate(16)、parse(--api 20) | 无 |
| MissingNdkRoot | ✓ generate("" / "   ") | 无 |
| MissingClang | ✓ render(cc="  ") | 无 |
| PathContainsSpace | ✓ render 空格路径/空格 flag；render 全空白字符 token（W3）+ validate 含 tab（W3） | 已落地(W3) |
| InvalidTriple | ✓ render(triple≠abi) | 无 |
| VersionMismatch | ✓ generate(r21/banana/"") | 无 |
| CliUsage | ✓ 显式 `CliUsage(_)` 6 例 + 退出码 2（W2 已交付） | 无 |
| IoFailure | ✓ write_config_with 权限/磁盘满/读失败 + sync FS 父目录缺失/空路径 | 无 |
| MalformedConfig | ✓ 不成对/多 begin/end 先于 begin/空块；多 END 标记（W3） | 已落地(W3) |
| NdkNotFound | ✓ resolve_ndk_values 触发 2 例（not-found/version-unknown，消息冻结断言）+ 构造级 1 例（W2 已交付，死变体状态消除） | 无 |

显式簿记 **11/11**（W2 已交付，2026-11-16 实测；原基线 9/11），门禁化（§8.3）。注：pub suberror 变体在定义包外只读，构造级断言只能落库包内 whitebox 测试（ndk_resolve_wbtest.mbt）；黑盒侧用 expect_error 匹配变体名。

### 6.3 恒等式断言（语义契约，全路径成立）

- `validate(...).ok ⇔ errors.is_empty()`（所有构造点）。
- `generate` 产物：`stub_cc == Some(cc)`、`supported_targets == "native"`、`cc_flags[0] == "--target=" + triple_name + level`、`cc_link_flags` 前两项恒 `["-llog","-landroid"]`。
- `probe`：`found=true ⇒ selected ≠ None`；`candidate.usable ⇒ candidate.exists`；`found=false ⇒ selected=None ∧ version=None ∧ warnings 非空`。
- `merge`：`action=Unchanged ⇒ content == existing ∧ write 不被调用`；块外前缀/后缀逐字保留（P3）。
- `render`：同输入两次逐字节相等（P1）；`ConfigRenderer::render ≡ render`（现有 wbtest）。
- 双通道：同一事实表下 probe_ndk_with ≡ probe_ndk；write_config_with ≡ sync_config_file（P6）。
- **防火墙恒等式：任一 W# 合入后，旧函数全部既有用例零改动全绿；旧 CLI 场景 stdout/stderr/退出码/落盘内容逐字节不变。**

### 6.4 #skip 清单（显式单列，永不计入通过）

| 用例 | 位置 | 原因 |
|---|---|---|
| （无） | — | 当前基线零 #skip（2026-11-26 M3/W5 后实测：源码 Grep #skip=0，moon test 99/99） |

计数口径：99 条声明 − 0 条 #skip = 99 执行（2026-11-26 M3/W5 后，wasm 与 native 双目标各 99/99；M2 后 94；M1 后 86；M0 后基线 76；M0 前基线 68）；`--include-skipped` 结果单独报告。W6 若落地，R 层占位用例以 #skip 入库并在此表单列。

### 6.5 验收 ID 双向追溯表

| T-W*-* | W#（开发文档） | 矩阵缺口行 | 断言/层 |
|---|---|---|---|
| T-W1-1 引用实存性扫描零失效 | W1 | C4 | A5/L5 |
| T-W1-2 README 索引 ↔ mbti 逐条一致（19 fn+to_repr+16 类型+trait，M0 后） | W1 | C4、F9 | A5/L5 |
| T-W1-3 五门禁绿+快照 diff 空 | W1 | C4 | A5/L5 |
| T-W1-4 CHANGELOG 建立并登记 | W1 | C4 | A5/L5 |
| T-W2-1 错误簿记 11/11 显式变体断言 | W2（已交付 ✓） | F9 | A2/L0+L5 |
| T-W2-2 选项 A：CLI 失败路径 stderr/退出码逐字节一致 | W2（已交付 ✓） | C2 | A5/L4 防火墙 |
| T-W2-3 NdkNotFound 触发/构造用例 | W2（已交付 ✓） | F9 | A2/L0 |
| T-W3-1 tab/换行 token → PathContainsSpace（render+validate） | W3（已交付 ✓） | F3、F4、C1 | A2/L0 |
| T-W3-2 多 END → MalformedConfig | W3（已交付 ✓） | F6、S2 | A2/L0 |
| T-W3-3 Pkg.RevisionFoo 不误命中 | W3（已交付 ✓） | F8 | A2/L0 |
| T-W3-4 防火墙回归：旧 68 用例零改动全绿 | W3（已交付 ✓） | C2 | A5/L5 |
| T-W3-5 截断/变异扫描无 panic | W3（已交付 ✓） | C1 | A4/L1 |
| T-W4-1 parse_gen_args_ext 新选项+旧参数 base 等价 | W4（已交付 ✓） | F5 | A1/A5/L0 |
| T-W4-2 generate_multi 顺序/确定性/空数组错误 | W4（已交付 ✓） | F2 | A1/L0+L1 |
| T-W4-3 --out+多 ABI → CliUsage 退出码 2 | W4（已交付 ✓） | F5、S2 | A5/L4 |
| T-W4-4 旧 CLI 17 场景逐字节防火墙 | W4（已交付 ✓） | C2、S1 | A5/L4 |
| T-W4-5 快照 diff 纯加法+CHANGELOG | W4（已交付 ✓） | C4 | A5/L5 |
| T-W5-1 三宿主 golden 路径/标签 | W5（已交付 ✓） | F2、F10 | A1/L2 |
| T-W5-2 旧 generate 输出逐字节不变 | W5（已交付 ✓） | C2 | A5/L5 |
| T-W5-3 api_level_advisory 边界三态 | W5（已交付 ✓） | F4 | A2/L0 |
| T-W5-4 快照 diff 纯加法+CHANGELOG | W5（已交付 ✓） | C4 | A5/L5 |
| T-W6-1 有 NDK→差分报告；无 NDK→显式 SKIPPED | W6 | F2 纵深、L3/R | A1/L3 |
| T-W6-2 哈希不符拒绝执行 | W6 | C3 | A4/R |
| T-W6-3 SKIPPED 不进通过计数 | W6 | C3、C4 | A5/L5 |

## 7. L4 CLI 场景 E2E

退出码矩阵基线（2026-11-16 native 实跑，17 场景；W4 已新增 2 场景并实跑通过，固化为仓库内脚本仍待 W6）：

| 场景 | 命令序列 | 断言要点（退出码+输出+落盘） | 状态 |
|---|---|---|---|
| 无参数 | `moon-abi` | 2；usage 首行 `moon-abi 0.1.0` | ✓ |
| 帮助/版本 | `--help` / `--version` | 0；版本串 `moon-abi 0.1.0` | ✓ |
| 未知子命令 | `bogus` | 2；stderr `unknown subcommand` | ✓ |
| 非法 ABI | `gen --abi mips --api 21` | 2；`unsupported ABI: mips` | ✓ |
| API 越界 | `gen --abi arm64 --api 20` | 2；`below minimum 21` | ✓ |
| 缺必选项 | `gen --api 21` | 2；`missing required option --abi` | ✓ |
| 只读打印 | `gen --abi arm64 --api 21 --ndk-root /opt/ndk --ndk-version r27` | 0；stdout=受管块（trim 尾换行）；零落盘 | ✓ |
| 空格路径 | 同上 `--ndk-root "C:\Program Files\ndk"` | 1；`path contains a space`；**写盘前整体拒绝** | ✓ |
| 旧 NDK | 同上 `--ndk-version r21` | 1；`expected NDK r22+, got r21` | ✓ |
| probe 非法选项 | `probe --bogus` | 2 | ✓ |
| probe 未找到 | `probe` / `probe --json`（无 NDK 环境） | 1；`NDK|found=false` / JSON `"found":false`；记录行字段序冻结 | ✓ |
| 首次写盘 | `gen … --out <tmp>/moon.pkg` | 0；`<path>: appended`；落盘=块 | ✓ |
| 幂等写盘 | 重复上条 | 0；`<path>: unchanged`；落盘哈希不变 | ✓ |
| 畸形既有文件 | `--out` 指向含孤儿 BEGIN 的文件 | 1；`malformed managed config`；**原文件逐字节未被改写** | ✓ |
| 父目录缺失 | `--out <tmp>/nodir/moon.pkg` | 1；`I/O failure` | ✓ |
| 多 END 既有文件（W3） | `--out` 指向单 begin+多 end 的文件 | 1；`malformed managed config`；原文件逐字节未被改写 | ✓ |
| （W4 新增）多 ABI stdout | `gen --abi arm64 --abi x86_64 …` | 0；两个受管块按序、块间单空行 | ✓ |
| （W4 新增）多 ABI+--out | 同上 `--out` | 2；CliUsage 明示单块契约；零落盘 | ✓ |
| （W4 新增）extra 落到 flags | `gen … --extra-lib foo --extra-cc-flag=-DNDEBUG` | 0；cc-flags 尾含 `-DNDEBUG`、cc-link-flags 尾含 `-lfoo` | ✓ |
| （W4 新增）extra 空值 | `gen … --extra-lib ""` / `--extra-lib=` | 2；`CliUsage` 空值消息 | ✓ |

记录行/JSON 契约冻结口径：`NDK|found=..|selected=..|version=..`、`CAND|source=..|exists=..|usable=..|version=..|path=..|note=..`、`WARN|..`；JSON 单行字段序 `tool/found/selected/version/candidates/warnings`；`<path>: appended|replaced|unchanged`。变更即破坏。已知局限（W1 文档化）：路径含 `|`/换行时文本记录行歧义，JSON 通道无此问题。退出码矩阵 0/1/2 逐例断言；78 仅用于 R 层 SKIPPED 口径，不出现在 CLI 契约。

## 8. L5 元契约门禁

1. 快照门禁：`moon info` + `git diff --exit-code -- pkg.generated.mbti cmd/main/pkg.generated.mbti`（纯加法；已在 CI，维持）。
2. 双目标等价：`moon test`（默认 wasm）与 `moon test --target native` 同计数全绿（基线 68/68×2）；纯函数层同 fixture 值输出逐字节 diff=0（W4 起对 generate_multi/新函数同样执行）。
3. 错误簿记门禁：§6.2 与测试代码双向核对（每变体 ≥1 显式变体名断言），缺一即红；W2 合入后启用 11/11 硬门禁。
4. 变异自检：注入 3 类缺陷——①跳过 check_no_space 校验 ②merge 放行多 END ③篡改 `ok` 恒等式（ok=true 硬编码）——套件必须变红后还原复绿；每包合入前跑一次。
5. 计数纪律：#skip/SKIPPED/78 不计通过；测试过滤串以 `*` 结尾防空转假绿；计数一律实跑重测（B25/B26 先例）。
6. 引用实存性扫描：注释/帮助文本/ci.yml/脚本引用的仓库内路径全部实存（覆盖 .mbt/.md/.yml/.ps1）；README API 索引与快照逐条一致（含 async fn/方法/trait，B27 先例）；跨仓库符号引用零容忍（B32 先例）。

## 9. CI 集成与执行入口

五门禁不变（check --deny-warn → build → test → fmt --check → info+双快照 diff）；L0/L1/L2 挂 `moon test`；L3/L4/R/parity/mutation 为脚本层可选 job，缺失显式 SKIPPED。ci.yml 文案漂移由 W1 清理后，引用实存性扫描纳入门禁脚本。

复验命令（本仓库自包含，PowerShell 用 `;` 分隔）：

```powershell
moon clean ; moon check --deny-warn ; moon build ; moon test ; moon fmt --check ; moon info ; git diff --exit-code -- pkg.generated.mbti cmd/main/pkg.generated.mbti
moon test --target native   # 双目标等价
moon build --target native  # CLI E2E 前置
```

## 10. 维护规则与验收清单

1. 新增 pub API ⇒ 同提交附 L0 样例+L1 性质+矩阵/簿记更新；无测试不合入。
2. 新增解析路径（W3 空白/多 END、W4 新选项、W5 宿主）⇒ 进截断扫描 fixture 集。
3. fixture 哈希变更 ⇒ 登记+黄金同提交更新（本模块当前零文件 fixture，规则预置）。
4. 每包合入 ⇒ 开发文档 DoD 勾选+矩阵现状刷新+CHANGELOG 测试增量。
5. 「通过」须可复验：命令+日期+计数；SKIPPED 永远单列。

落地验收（逐层勾选）：

- [x] L0：99 条全绿（M3/W5 后，原 94/86/76/68 基线经 W3→W4→W5 递进零改动）；簿记 11/11 已达成（W2）；W5 新函数（NdkHost/host_tag/generate_with_host/api_level_advisory）已附样例。
- [◐] L1：P1-P8 变形律自动化；截断扫描（W3 新解析路径已一行接入：render 空白 token/merge 多 END/键名变体；W4 parse_gen_args_ext 参数序列；W5 api_level_advisory ndk_version）；≥1000 变异体/轮仍待后续
- [ ] L2：render golden 维持；probe 记录行/merge 三态 golden 扩充（后续）
- [ ] L3/R：未实现（W6 已裁决 A，M4 落地；不得预写通过）
- [ ] L4：17 场景基线脚本固化（脚本层 W6；W4 已实跑全部 17+4 场景并登记）；新增多 ABI 两场景已实跑通过
- [ ] L5：快照门禁已在 CI；簿记/变异自检/引用扫描/双目标等价随 W1/W2 落地