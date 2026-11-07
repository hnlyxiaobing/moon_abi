# hnlyxiaobing/moon_abi

> 实现轮完成 · 2026-11-06。本包提供配置值类型、`ConfigRenderer` trait 与 `generate` / `render` / `validate` / `clang_name` 4 个纯函数实现，**无 I/O、无 CLI**。`moon check --deny-warn` / `moon build` / `moon test`：全绿（30 tests）。

Android 交叉编译 `link.native` 配置生成器：按 ABI + API level 产出确定性配置值与文本片段。与骨架 CLI 定位的差异见同目录 `README.md`「定位修正」。

完整文档见同目录 `README.md`、`DESIGN.md`、`API.md`；总体架构与决策见 `../docs/architecture.md`、`../docs/adr/`。

**当前状态：实现完成，测试全绿，等待集成。**
