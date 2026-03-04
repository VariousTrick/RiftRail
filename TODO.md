# Rift Rail Development Plan

---

## ⏳ To Do (Unfinished Tasks)

-   [ ] Develop a complete GUI overhaul (Targeting v1.0.0).
-   [ ] Research and implement technology unlocks for Many-to-One and One-to-Many features.
-   [ ] Add sound and visual effects for teleportation events.
-   [ ] Add an optional setting to make teleportation consume electricity.
-   [ ] Add a statistics counter for "Total Trains Teleported" in the GUI.
-   [ ] (Advanced) Draw connection lines between portals on the map view.
-   [ ] (Advanced) Display the portal network topology on the minimap.
-   [ ] Add blueprint support for links to auto-restore connections when pasting paired portals.
-   [ ] Add a debug/performance profiling mode to display the current "active list" count for UPS monitoring.
-   [ ] Add in-game Tips & Tricks/Factoriopedia entries for the "UPS Optimization Guide".
-   [ ] Add visual status indicators (e.g., lights) for portals to show idle/active states.
-   [ ] Apply different textures, building coatings, or core styles based on the current planet (Space Age integration).
-   [ ] Replace current AI-generated textures with high-quality custom art (Milestone for v1.0.0 release).
-   [ ] Introduce technology upgrades to increase the maximum allowed paired targets (currently hardcoded to 5).


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
-   [x] Expanded native Clone API activation conditions (Same-Axis Optimization) to further reduce UPS consumption.
-   [x] Adjusted the portal recipe balance for the Space Age (SA) environment.
-   [x] Added a second dedicated demo scenario to explain pairing logic and workflow.
-   [x] Optimized the file structure and recipe balancing across various mod environments (SA, SE, K2, SE+K2) - Special thanks to Ldmf for this contribution!

---

## 🛠️ Ongoing (Continuous Maintenance)

-   [ ] Keep English and Chinese localizations synchronized.
-   [ ] Add support for additional languages (multi-language localization).
-   [ ] Respond to community feedback and fix bugs.
-   [ ] Continuously monitor UPS impact.

# Rift Rail 开发计划

---

## ⏳ 未完成 (To Do)

-   [ ] 制作一套全新的 GUI（迈向 1.0.0 版本）。
-   [ ] 研究并实装用于解锁“多对一”和“一对多”功能的科技。
-   [ ] 为传送事件添加音效和视觉特效。
-   [ ] 添加一个可选设置，使传送消耗电力或其他资源。
-   [ ] 在 GUI 中为“累计传送列车”添加一个统计计数器。
-   [ ] (高级) 在地图视图上绘制已连接传送门之间的连线。
-   [ ] (高级) 在小地图上显示传送网络拓扑。
-   [ ] 新增蓝图保存配对关系功能，支持在复制粘贴时自动恢复传送门之间的连接。
-   [ ] 添加调试/性能监控模式，在界面上显示当前“活跃列表”中的传送门数量，方便监控 UPS 状态。
-   [ ] 为传送门添加工作状态指示灯（如空闲、激活等视觉反馈）。
-   [ ] 在不同的星球使用不同的贴图、建筑涂装或核心样式（支持 SA 太空时代）。
-   [ ] 用高质量的自定义贴图替换目前的 AI 生成贴图（完成此项即可发布 1.0.0 正式版）。
-   [ ] 引入科技升级，用于提升建筑可配对的目标数量上限（目前硬编码限制为 5）。

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
-   [x] 扩展了原生 Clone API 的触发条件（同向放置优化），进一步降低列车传送时的 UPS 消耗。
-   [x] 针对 Space Age (SA) 环境调整了传送门配方平衡（卫星数量增加至 2 个）。
-   [x] 新增了第二个演示场景，专门用于演示传送门的配对逻辑与操作流程。
-   [x] 优化了文件结构以及各模组环境（SA, SE, K2, SE+K2）的配方平衡（特别感谢 Ldmf 提交的代码与贡献！）。
-   [x] 添加了对信息稽器人模组的支持，可以在其中查看模组使用说明。
-   [x] 添加了游戏原生的“提示与技巧 (Tips & Tricks)”系统集成。

---

## 🛠️ 持续维护 (Ongoing)

-   [ ] 保持本地化文件的同步。
-   [ ] 新增对其他语言的支持（多语言本地化）。
-   [ ] 响应社区反馈并修复 Bug。
-   [ ] 持续监控 UPS 消耗。
