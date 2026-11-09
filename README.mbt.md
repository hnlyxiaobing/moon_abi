# hnlyxiaobing/moon_abi

> 实现完成 · **API 冻结前对账（2026-11-07）**。本包提供配置值类型、`ConfigRenderer` trait 与 `generate` / `render` / `validate` / `clang_name` 4 个纯函数的**真实实现**，**无 I/O、无 CLI**。四道门禁 `moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check`：全绿（30 tests）。**冻结后签名变更即破坏性变更。**

Android 交叉编译 `link.native` 配置生成器：按 ABI + API level 产出确定性配置值与文本片段。与骨架 CLI 定位的差异见同目录 `README.md`「定位修正」。

完整文档见同目录 `README.md`、`DESIGN.md`、`API.md`；设计决策记录见同目录 `DECISIONS.md`。

**当前状态：实现完成，四道门禁全绿，等待集成。**
