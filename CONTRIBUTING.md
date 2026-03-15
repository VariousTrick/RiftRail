# Contributing to Rift Rail

First of all, thank you for your interest in contributing to Rift Rail!
To ensure the stability and performance of the mod, as well as to keep the codebase clean and maintainable, please briefly review the following development guidelines before submitting a Pull Request.

## 1. Core Philosophy: Performance First
Rift Rail involves complex hardcore mechanisms such as cross-surface/cross-planet real-time train teleportation. Therefore, **UPS (Updates Per Second) performance is our highest priority**.
When writing logic, especially in high-frequency loops like `on_tick`, always try to minimize Lua GC (Garbage Collection) pressure and redundant engine API calls. It is acceptable to sacrifice some code simplicity if it leads to performance gains.

## 2. Global Data Lifecycle Management
We have implemented a strict separation between "New Game Initialization" and "Old Save Migration" for global data (`storage`). Please try to follow this paradigm:
* **Creating New Tables**: If you need to add a new global root table (e.g., `storage.my_new_feature`), please declare it unconditionally in `State.setup_new_game()` in `state.lua`.
* **Patching Old Saves**: To ensure old saves inherit the new table, add an initialization check (`if not storage.my_new_feature then ... end`) in `State.patch_missing_root_tables()`.
* **Avoiding Lazy Initialization**: Please try to **avoid** writing lazy defensive code like `storage.xxx = storage.xxx or {}` inside business logic (e.g., `teleport.lua`, `builder.lua`). Let `state.lua` act as the single source of truth for the data structure.
* **Adding Fields to Existing Entities**: If you need to add a new internal state field to existing portals, try to write a dedicated migration task in `migrations.lua` instead of checking it at runtime.

## 3. Compatibility Modules (Compat) Design
When writing compatibility code for third-party mods (like LTN, Cybersyn 2):
* **Stub Module Pattern**: We highly recommend using the "Stub Module" pattern. Check if the mod is installed at the very top of your compat file. If not, directly return an empty shell of functions.
* **Reduce Defensive Programming**: Thanks to the stub pattern, you should minimize redundant `is_mod_active()` checks inside the actual execution functions. This squeezes out maximum performance, especially for high-frequency event callbacks (like dispatcher updates).

## 4. High-Frequency Loops and Event Optimization
* **Encourage Caching**: When looking up entities, try to use `unit_number` as a dictionary key for O(1) lookups. Traversal searches are acceptable only as a fallback when `unit_number` is strictly unavailable.
* **Event Filtering**: When registering native events (e.g., `on_entity_died`, `on_player_mined_entity`), it is **strongly recommended** to attach `filters`. We must strictly prevent irrelevant global events (like biters dying) from triggering our logic.

## 5. Development Log (Optional)
* If your PR includes logic changes, it is **encouraged** (but not strictly required) to add a brief description of your changes at the top of the `DEV_CHANGES.md` file. You can write this log in English, Chinese, or any language you are comfortable with—others can simply use translation tools to read it.

---
---

# 参与 Rift Rail 贡献指南

首先，非常感谢你有兴趣为 Rift Rail 贡献代码！
为了保证模组的绝对稳定与极速性能，同时也为了保持代码库的整洁与可维护性，在提交 Pull Request 之前，请花一点时间阅读以下的开发指南。

## 1. 核心理念：性能第一优先 (Performance First)
Rift Rail 涉及跨星系实时列车传送等硬核机制。因此在编写任何逻辑时，**UPS（游戏每秒更新次数）开销是我们最优先考量的指标**。
在编写高频循环（特别是 `on_tick`）时，请尽量减少 Lua GC（垃圾回收）压力和冗余的底层 API 调用。只要能提升核心性能，适度牺牲一些代码的精简度是完全可以接受的。

## 2. 全局数据生命周期管理
我们对全局数据（`storage`）实行了严格的“新档创世”与“旧档兜底”分离的规范。请尽量遵循此范式：
* **新增根表**：如果你需要新增一个全局表（如 `storage.my_new_feature`），请在 `state.lua` 的 `State.setup_new_game()` 中无条件地声明它。
* **兼容旧档**：为了让旧存档也能获得这个新表，请在 `State.patch_missing_root_tables()` 中添加兜底判断（`if not storage.my_new_feature then ... end`）。
* **拒绝懒加载**：请**尽量避免**在业务代码（如 `teleport.lua`, `builder.lua`）的循环里写 `storage.xxx = storage.xxx or {}` 这样的懒加载防卫代码。让 `state.lua` 成为数据结构的唯一“户口本”。
* **新增内部字段**：如果需要给旧建筑补充新的状态字段，请尽量在 `migrations.lua` 中写成独立的迁移任务，而不是在运行时去动态判断。

## 3. 兼容性模块（Compat）的设计倾向
在编写针对第三方模组（如 LTN, Cybersyn 2）的兼容代码时：
* **推荐空壳模式（Stub Module）**：建议在文件最顶部检测是否安装了该模组。如果没有安装，请直接返回一个包含空函数的壳模块。
* **减少防卫式编程**：依托于空壳模式，在实际的业务函数内部，请尽量减少冗余的 `is_mod_active()` 检查。这能进一步压榨高频事件（如调度器派单更新）的回调性能。

## 4. 高频循环与事件优化
* **鼓励缓存查找**：在进行实体查询时，尽量使用 `unit_number` 作为字典键来进行 O(1) 查找。但在确实无法获取 `unit_number` 的特殊场景下，遍历查找也可作为兜底方案。
* **强制事件过滤**：注册原生事件（如 `on_entity_died`, `on_player_mined_entity`）时，**强烈建议**带上 `filters` 过滤器。坚决不能让全图无关实体（如杀虫子、砍树）的事件卡进我们的逻辑处理流中。

## 5. 开发日志记录（可选）
* 如果你的 PR 包含逻辑变动，我们**鼓励**（但不强制）你在 `DEV_CHANGES.md` 文件的最顶部添加一段简短的改动说明。记录语言不限（中英文皆可），其他开发者可以通过翻译工具自行阅读。
