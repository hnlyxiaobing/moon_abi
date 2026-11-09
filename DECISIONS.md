# moon_abi · 设计决策记录（DECISIONS.md）

> 本文整合自**开发期决策记录**，按「背景 → 决策 → 理由 → 后果」组织，使仓库外读者不依赖任何外部文档即可理解本库的全部设计取舍。外部事实（工具链行为、NDK 命名规则等）在此直接陈述结论与依据；文中不引用仓库外的任何文件。

## 决策一览

1. [纯 MoonBit 自研，不引入 zig-cross](#决策-1纯-moonbit-自研不引入-zig-cross)
2. [CLI 后移组合根，库保持纯值 API](#决策-2cli-后移组合根库保持纯值-api)
3. [与 moon_android 仅以文本契约协作、名义类型隔离](#决策-3与-moon_android-仅以文本契约协作名义类型隔离)
4. [NDK 交叉编译从「硬前置」降级为「上板软依赖」](#决策-4ndk-交叉编译从硬前置降级为上板软依赖)
5. [具体类型用真实定义、函数用真实实现](#决策-5具体类型用真实定义函数用真实实现)
6. [NDK 事实基线（三元组 / wrapper 命名 / 版本下限 / 证伪记录）](#决策-6ndk-事实基线)
7. [风险与待验证（Android native 产物链路未复现）](#决策-7风险与待验证android-native-产物链路未复现)

---

## 决策 1：纯 MoonBit 自研，不引入 zig-cross

**背景**：Android 交叉编译需要一份 `link.native` 的 `cc` / `cc-flags` / `cc-link-flags` 配置。社区存在可复用包 `moonrockz/zig-cross@0.3.2`（Apache-2.0，native + wasm），走的是「用 zig 编译 native」的另一条技术路径。需要判定：复用它，还是纯 MoonBit 自研配置生成器。

**决策**：**纯 MoonBit 自研** `moon_abi` 配置生成器；zig-cross **仅作设计参照**（借鉴其配置结构），不引入为依赖。

**理由**：
- 本库只需产出**确定性配置片段**，不执行外部命令——纯值渲染、可单测，不需要一个编译驱动工具链。
- 引入 zig-cross 会带来 **zig 工具链依赖**，属无依据大型依赖：用途、许可、维护风险均无法收敛到「本库必需」。
- 依赖引入须同时满足五条门槛（用途 / 许可 / 维护 / 平台 / 风险登记），zig-cross 未达「用途必需」门槛。
- 保持可替换性：将来若改走 zig 路线（或换任何交叉编译器），只改 `NdkProfile` 与渲染实现，不改 `generate` / `render` / `validate` / `clang_name` 的签名。

**后果**：
- 本库零依赖（无 `moon add`、未改 `moon.pkg`）、零 FFI、无外部句柄；桌面与 wasm 后端均可直接测试。
- zig-cross 是否值得引入，留待后续轮次按五条门槛重新评估；当前结论是**只参照、不引入**。

### 决策 1 的 R4 复议（2026-11-09）：结论仍为「不引入」

> 触发原因：申报书把「`zig-cross` 引入与否 R4 复议」列为计划项。本节是**书面复议结论**，不改变决策 1 的原有结论，只补充 2026-11-09 的复核证据与判定。

**复核对象与事实**（2026-11-09 查询 mooncakes registry 与 GitHub API，`[已复验-网络]`；外部数据只作事实引用）：

| 项 | 0.3.2（申报书原参照版本） | 0.4.1（查询时 latest） |
|---|---|---|
| 版本状态 | `yanked=false`、`build_status=success` | 同左；`latest_version=0.4.1` |
| 许可 | `Apache-2.0`（registry `metadata.license` 与 GitHub `license.spdx_id` 一致） | 同左 |
| 发布时间 | 2026-10-31 | 2026-11-07 |
| 直接依赖 | `moonbitlang/async@0.22.5`、`moonbitlang/x@0.5.5` | `moonbitlang/async@0.22.7`、`moonbitlang/x@0.5.5` |
| 仓库 | `https://github.com/moonrockz/moonx-tools`（创建 2026-10-17，最后 push 2026-11-07，star=0，fork=0，open issues=2，`archived=false`，language=MoonBit） | 同左 |
| 定位 | 描述 "Cross-compile MoonBit native binaries with zig"；keywords 含 `zig` / `cross-compile` / `command-line` | 同左 |

**收益（若引入）**：
- 可作为「zig 编译 native」路线的现成驱动与配置结构参照（本库只借鉴配置思路，这一点已发生且无需依赖）。
- 若未来交付链正式改用 zig 作为交叉编译器，其驱动代码可能有复用价值。

**成本 / 风险**：
- **依赖面**：直接引入 2 个依赖（`moonbitlang/async`、`moonbitlang/x`，均为版本敏感的 0.x），与 ADR-0002「11 模块零跨模块 import、可独立 `moon check`」和 ADR-0010「零新增依赖」直接冲突；传递依赖未逐项审计，引入即新增版本耦合与升级跟随成本。
- **工具链**：其价值前提是本机安装 zig 工具链；本环境**未安装、未实测** zig，且外部工具链的许可/分发/平台覆盖需另核（`[仍需实测]`），与本库「纯 MoonBit、不执行外部命令」的定位相反。
- **能力不匹配**：本库的交付物是供 **NDK clang** 消费的 `options(link.native…)` 文本；`zig-cross` 是另一条编译路径，**不能**替代本库，也不解决 E3（MoonBit→C→NDK clang 产出可加载 `.so`）的复现验证。
- **维护**：仓库创建于 2026-10-17，star=0 / fork=0、单人/新组织维护、0.x API 未稳定，且一周内从 0.3.2 迭代到 0.4.1；对「只生成确定性文本」的本库而言，收益不抵维护与版本跟随成本。
- **许可**：`zig-cross` 自身 Apache-2.0 与本项目兼容；但其依赖的 zig 工具链及传递依赖的再分发义务未核（`[仅据文档]` / `[仍需实测]`）。**不引入即不产生新增许可义务**。

**复议结论：不引入 `zig-cross`（任何版本），维持 0 依赖。** 仅保留为设计参照。

**重评触发条件**（满足任一才重新评估，且仍须过 ADR-0010 五门槛）：
1. 交付链正式决定用 zig 取代 NDK clang 作为 MoonBit→Android 的交叉编译器；
2. 本库职责扩展到「执行编译驱动」（当前明确非目标）；
3. `zig-cross` 提供本库无法以更小代价覆盖的能力，且其依赖面收敛到可接受范围。

**可逆性**：即使未来引入，`generate` / `render` / `validate` / `clang_name` 的签名保持不变；只改 `NdkProfile` 与渲染实现（决策 1 的可替换性结论仍成立）。

## 决策 2：CLI 后移组合根，库保持纯值 API

**背景**：原始构想是 CLI `moon-abi gen --abi armv7 --api 21`（约 300 行脚本），由脚本探测本机 NDK 并写文件。但本项目家族约定各模块**零跨模块 import、各自独立 `moon check`**，且 CLI 与进程 / 文件 I/O 属于组合根（未来 App 工程里的一段适配代码）而非叶子库职责。

**决策**：
- 本库契约为 **4 个纯函数**：`generate(profile, abi)` / `render(config)` / `validate(profile, abi)` / `clang_name(abi, api)`。
- CLI 包装**没有被删除，只是后移**：由组合根把 `render` 的文本写入 `moon.pkg` 或打印到 stdout。
- `NdkProfile` 由调用方注入，库不探测本机环境。

**理由**：
- 纯值、确定性、可并发、无 I/O 的 API 可以用 golden 快照测试做 CI 门禁（同输入两次渲染逐字相等）。
- 文件 / 进程 I/O 与命令行解析留在组合根，保证本库零 import、可独立 `moon check`，不把主机差异带进单元测试。
- `PathContainsSpace` 只做校验而非自动加引号：引号语义随 shell 变化，提前拒绝更确定。

**后果**：
- 骨架 README 描述的 CLI 形态由组合根承接（写 `moon.pkg` / stdout），本库不含任何 CLI 代码。
- 验收标准「生成片段可直接粘贴进 `moon.pkg` 并被 `moon check` 接受」的**实际粘贴验证属组合根集成**，本库以 golden 快照覆盖文本形态。

### 决策 2 的 R4 更新（2026-11-09）：CLI 已在本模块内落地

> 本节只登记职责边界的变化与理由；决策 2 在 R1–R3 期间的结论（库保持纯值核心）**不被推翻**。

- **R4 交付**：在模块内新增 `cmd/main` CLI（`moon-abi gen` / `moon-abi probe`）与 I/O 层（`sync_config_file` / `probe_ndk`）。CLI 不再是「未来组合根的一段代码」，而是本模块的可执行包。
- **边界仍然成立**：核心配置生成（`generate` / `render` / `validate` / `clang_name`）保持**纯函数、无 I/O、确定性**；全部文件系统/环境变量访问被收敛到 `sync_config_file`、`probe_ndk` 与 `cmd/main` 三个明确入口。
- **为何改变**：R4 任务明确要求 CLI 落地（写文件与只读输出、幂等、退出码契约、NDK 探测）。若继续后移，这些契约无法在模块内测试与复现。新增的 I/O 只依赖 `moonbitlang/core/async/fs` 与 `moonbitlang/core/env`（工具链随附 core，不是外部 mooncakes 依赖），因此**零跨模块 import 的红线不变**。
- **可测试性补偿**：I/O 不是直接写死在业务逻辑里——`write_config_with` 用注入的读/写闭包覆盖权限拒绝、磁盘满、读失败；`probe_ndk_with` 用注入的目录/文件闭包覆盖伪目录；真实文件系统测试只在 `@fs.tmpdir()` 临时目录内进行并递归清理。
- **仍属非目标**：调用 NDK/clang、执行打包/签名、下载 SDK、链接任何 C 库。CLI 只生成文本/写 `moon.pkg`，不验证设备可加载（E3 仍待实测，见决策 7）。

## 决策 3：与 moon_android 仅以文本契约协作、名义类型隔离

**背景**：MoonBit 是**名义类型**系统——两个模块里结构完全相同的 `struct` 也不是同一类型。若 `moon_abi` import `moon_android`（或反向让 `moon_android` 读打包产物、引用本库类型），两个模块会形成**潜在循环依赖**，且破坏「各自独立 `moon check`」的性质。

**决策**：
- `moon_abi` → `moon_android` 之间是**数据契约（`options(link.native…)` 配置片段文本），不是 import**。
- `Abi` 等共享语义的类型在两个模块中**各自定义、结构同构**，由组合根转换；`moon_android` 的构建计划只消费文本，不引用本库任何类型。
- `moon_abi` **不读打包产物**（否则会与 `moon_android` 成环）。
- 本库零 import、零 FFI、零外部句柄；`#external` 句柄永不跨模块传递。

**理由**：名义类型 + 零 import 使两模块可完全并行开发、独立评审；文本契约天然消解潜在循环依赖；结构漂移风险由 `pkg.generated.mbti` API 快照 + 契约测试守住。

**后果**：组合根需要少量显式适配代码（值类型转换）；`moon_android::ToolchainVersions` 等跨模块语义以**文本契约**约定（见决策 6），不构成编译期依赖。

## 决策 4：NDK 交叉编译从「硬前置」降级为「上板软依赖」

**背景**：早期计划把 NDK 交叉编译当作 TFLite / 相机等 FFI 模块桌面验证的硬前置。核对发现 LiteRT `.so` 与插桩 devkit 都是**预编译产物**，桌面验证不需要 NDK；只有最终「上板」（目标 Android 设备安装运行）才需要交叉编译链路。

**决策**：`moon_abi` 的定位从「FFI 硬前置」降级为「**上板软依赖**」——桌面用预编译 `.so` 即可验证 FFI 模块；上板前必须补齐本库产出的 `link.native` 配置，不能省略。

**理由**：解除 NDK 对其他模块并行开发的阻塞；本库仍是所有 Android FFI 项目上板时的**公共配置前置**，但不阻塞桌面验证。

**后果**：各 FFI 模块与本库可完全并行推进；上板集成阶段必须消费本库产出的配置片段（`generate` → `render` → 写入 `moon.pkg`）。

## 决策 5：具体类型用真实定义、函数用真实实现

**背景**：早期要求「用 `declare` 声明数据结构与函数签名、不实现业务逻辑」。工具链实测（moonc v0.10.x 探针）结论：`declare` 只支持函数签名、抽象类型与实现关系；`declare struct` / `declare enum` / `declare trait` / `declare suberror` / `declare type A = B` 均被编译器拒绝（`E4193 Cannot declare a type with concrete definition`）；缺失实现只是 warning `0068`，不是错误。

**决策**：
- **具体数据结构**（`enum` / `struct` / `trait` / `suberror`）使用**真实类型定义**——它们只有类型形状，不含业务逻辑。
- 本库 4 个函数均为 `pub fn` **真实实现**（无 `declare` 占位、无 `0068` 告警），公开 API 配 `///` 文档注释（参数所有权、错误、线程约束、非目标）。
- 无 `#external`、无 `extern "C"`、无 `#borrow` / `#owned`、无回调。

**理由**：语言层面 `declare` 不能声明具体类型定义，只能用真实类型；真实类型定义本身不违反「不实现业务逻辑」的约束，且让 `pkg.generated.mbti` API 快照可直接评审。

**后果**：`moon check --deny-warn` 可开（0 error / 0 warn）；`pkg.generated.mbti` 与源码公开签名逐字对账一致；**冻结后签名变更即破坏性变更**。

## 决策 6：NDK 事实基线

**背景**：生成 `link.native` 配置必须依据统一、可复现的 NDK 命名规则与版本下限；此前流传的个别「NDK 历史行为」说法已被证伪，必须以核实过的事实为准。

**决策**：本库实现与文档统一遵循以下事实基线：

- **clang 目标三元组**（不含 API level 后缀）：
  `armeabi-v7a = armv7a-linux-androideabi`、`arm64-v8a = aarch64-linux-android`、`x86 = i686-linux-android`、`x86_64 = x86_64-linux-android`。
- **统一工具链 wrapper 命名**：clang 驱动名为 `<triple><api>-clang`（如 `armv7a-linux-androideabi21-clang`），完整路径 `<ndk_root>/toolchains/llvm/prebuilt/<host>/bin/<triple><api>-clang`。
- **常用默认链接库**：`-llog`、`-landroid`（`extra_link_libs` 裸库名自动补 `-l` 前缀）。
- **API level 下限**：`MIN_API_LEVEL = 21`（64 位 ABI 的 NDK 最低 API）；**最低 NDK 主版本** `MIN_NDK_MAJOR = 22`（输出面向 NDK r22+），版本低于下限或不可解析报 `VersionMismatch(expected, actual)`。
- **事实证伪（不得引用错误前提）**：「NDK r23 移除 GNU make / standalone toolchain」是**错误前提**；r23 实际移除的是 **GNU binutils（除 GAS）与 GDB 支持**，standalone toolchain 脚本仍在、仅提示不再必要。r23 起 Clang 自动选 sysroot、LLD 为默认链接器。本库文档与实现均不得依据被证伪的说法设计回退路径。
- **Windows 路径空格**：含空格的路径 / flag 会把 cc 命令断裂；统一策略是**提前拒绝（`PathContainsSpace`）、不自动加引号**。
- **版本锁归属**：精确工具链版本（NDK / build-tools / JDK / CMake）由 `moon_android::ToolchainVersions` 持有（文本契约，非 import）；本库只按 `MIN_NDK_MAJOR` 做下限校验。

**理由**：三元组与 wrapper 命名按当前 NDK 文档实现；API ≥ 21 与 r22+ 是全系 NDK 的安全下限；把已证伪的说法写死为回退依据会引入错误设计；空格拒绝策略避免 shell 引号语义差异。

**后果**：NDK 大版本升级时需复核 clang 命名规则；`VersionMismatch` / `InvalidTriple` 错误构造显式化版本与命名不匹配；换 NDK 版本只改 `NdkProfile`，不改 API 签名。

## 决策 7：风险与待验证（Android native 产物链路未复现）

**背景**：平台事实（核实结论）：`moon build --target` 只有 wasm / wasm-gc / js / native / llvm / all，**没有 Android 编译目标**；新 native 后端平台覆盖仅 macOS ARM、Linux x86-64、Windows MSVC；`#export_name` 仅限 `foreign_library` 包；且 native 后端**不能把 `foreign_library` 导出为可链接 `.so/.dll`**。因此 Android 集成必须走「MoonBit → C 源码/对象 → NDK clang + CMake 宿主工程」，任何 FFI 项目都得手写 `link.native` 配置——本库把这一步标准化。

**待验证假设（未复现）**：上述「MoonBit → C 源码/对象 → NDK clang + CMake」链路在 Android 上**能否产出可加载的 `.so`**，尚未在开发环境中复现验证。验证方法：最小 MoonBit 模块 + 一个 C stub，用 NDK clang 编出 `.so`，装入 shell APK，在设备上加载。该项是高优先级待验证项。

**相关资产边界**：开发期引用的一次性打包脚本与真实 APK 样本资产**未随本仓库分发**；集成验证需自备 APK 样本与打包脚本。

**后果**：本库产出配置的最终有效性依赖上述链路验证；在验证完成前，「生成片段可被 `moon check` 接受」（文本形态）已由快照测试覆盖，「设备上可加载」仍属待验证假设。NDK clang 命名已按当前文档锁定为统一工具链 wrapper（`<triple><api>-clang`），NDK 大版本升级时需复核；zig-cross 是否复议见决策 1。

---

## 附：术语对照

| 本文表述 | 含义 |
|---|---|
| 组合根（Composition Root） | 未来 App 工程里的一段适配代码：在模块间用文本 / 中性值转换、注入后端、编排生命周期；不是本仓库内的库 |
| 文本契约 | 跨模块协作只传递 `options(link.native…)` 配置片段文本，不建立编译期依赖 |
| 名义类型隔离 | 同构类型在各模块各自定义（MoonBit 名义类型系统），由组合根转换 |
| 上板 | 在目标 Android 设备上安装并运行产物 |
| golden 快照 | 与期望输出逐字比对的快照测试 |
