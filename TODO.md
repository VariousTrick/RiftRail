# Rift Rail Development Plan

---

## ⏳ To Do (Unfinished Tasks)

-   [ ] Add a "Select Target" interface to replace the old "Link" button.
-   [ ] Research and implement technology unlocks for Many-to-One and One-to-Many features.
-   [ ] Add sound and visual effects for teleportation events.
-   [ ] Add an optional setting to make teleportation consume electricity.
-   [ ] Add a statistics counter for "Total Trains Teleported" in the GUI.
-   [ ] (Advanced) Draw connection lines between portals on the map view.
-   [ ] (Advanced) Display the portal network topology on the minimap.

---

## ✅ Done (Completed Tasks)

-   [x] Overhauled the core architecture to support Many-to-Many (N-to-M) connections.
-   [x] Implemented Many-to-One (Convergence) support.
-   [x] Implemented One-to-Many (Divergence) support.
-   [x] Built a smart routing system (LTN auto-routing & player signal control).
-   [x] Redesigned the GUI with a dual-mode interface (Management/Addition).
-   [x] Created a dedicated module for all save game migrations.
-   [x] Removed Cybersyn compatibility.
-   [x] Removed the `cybersyn_scheduler.lua` module.
-   [x] Updated the Mod Portal description and FAQ.
-   [x] Added in-game migration notification messages.
-   [x] Cleaned up all deprecated comments and debug logs from the code.
-   [x] Standardized version numbers in file headers.

---

## 🛠️ Ongoing (Continuous Maintenance)

-   [ ] Keep English and Chinese localizations synchronized.
-   [ ] Add support for additional languages (multi-language localization).
-   [ ] Respond to community feedback and fix bugs.
-   [ ] Continuously monitor UPS impact.

# Rift Rail 开发计划

---

## ⏳ 未完成 (To Do)

-   [ ] 新增“选择目标”界面，以取代旧的“配对”按钮。
-   [ ] 研究并实装用于解锁“多对一”和“一对多”功能的科技。
-   [ ] 为传送事件添加音效和视觉特效。
-   [ ] 添加一个可选设置，使传送消耗电力。
-   [ ] 在 GUI 中为“累计传送列车”添加一个统计计数器。
-   [ ] (高级) 在地图视图上绘制已连接传送门之间的连线。
-   [ ] (高级) 在小地图上显示传送网络拓扑。

---

## ✅ 已完成 (Done)

-   [x] 重构了核心架构以支持多对多 (N-to-M) 连接。
-   [x] 实现了多对一 (汇流) 功能。
-   [x] 实现了一对多 (分流) 功能。
-   [x] 构建了智能路由系统（LTN 自动路由 & 玩家信号控制）。
-   [x] 重新设计了具有双模式（管理/添加）的 GUI 交互界面。
-   [x] 创建了专用模块来处理所有存档的自动迁移。
-   [x] 移除了 Cybersyn 兼容性。
-   [x] 移除了 `cybersyn_scheduler.lua` 模块。
-   [x] 更新了 Mod Portal 描述和 FAQ。
-   [x] 添加了游戏内的迁移提示消息。
-   [x] 清理了代码中所有废弃的注释和调试日志。
-   [x] 统一了文件头部的版本号注释。

---

## 🛠️ 持续维护 (Ongoing)

-   [ ] 保持中英文本地化的同步。
-   [ ] 新增对其他语言的支持（多语言本地化）。
-   [ ] 响应社区反馈并修复 Bug。
-   [ ] 持续监控 UPS 消耗。