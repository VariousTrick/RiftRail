# Rift Rail - 裂隙铁路

<details open>
<summary><strong>🌐 Language / 语言</strong></summary>

- [中文](#中文) 
- [English](#english)

</details>

---

<details>
<summary><strong>📖 中文文档 (Chinese Documentation)</strong></summary>

## 中文

### 简介

**裂隙铁路 (Rift Rail)** 是 Factorio 的一个模组，提供一种**非对称、单向的跨地表火车传送系统**。

它允许玩家在不同的地表（Surface）之间传送火车，完美支持 **Space Exploration** 和 **Cybersyn** 物流网络。

### 核心特性

✨ **跨地表传送**
- 火车可以在不同的地表间瞬间传送
- 支持与 Space Exploration (SE) 的飞船集成
- 完全兼容 Cybersyn 物流调度系统

🎯 **灵活的模式控制**
- **入口模式**：火车驶入并被传送到配对的出口
- **出口模式**：火车驶出并继续前进
- **待机模式**：暂停所有操作

🔗 **配对系统**
- 传送门可以与其他传送门配对
- 支持自定义名称和图标
- 跨地表配对提示和验证

📡 **Cybersyn 兼容**
- 手动启用 Cybersyn 连接
- 支持跨地表物流路由
- 可独立配置显示全局消息

🛠️ **调试与管理**
- 完整的调试日志系统
- 紧急碰撞器重置工具
- 详细的模组设置选项

### 视频演示

<div align="center">

<video width="640" height="360" controls>
  <source src="https://github.com/VariousTrick/RiftRail/releases/download/video/_20251216_182942.webm" type="video/webm">
  您的浏览器不支持视频播放
</video>

</div>

### 安装

1. 从 [Factorio 模组门户](https://mods.factorio.com/) 搜索 "Rift Rail" 下载
2. 或者从 [GitHub Release](https://github.com/VariousTrick/RiftRail/releases) 手动下载
3. 解压到 `~/.factorio/mods/` 目录
4. 重启 Factorio 游戏

### 快速开始

1. **放置传送门**
   - 在物品栏中找到 "裂隙铁路" 物品
   - 放置第一个传送门作为 **入口**
   - 放置第二个传送门作为 **出口**

2. **配对传送门**
   - 左键点击传送门打开控制台
   - 从下拉菜单选择要配对的目标
   - 点击 "配对" 按钮

3. **切换模式**
   - 使用中间的三态开关选择 [入口]、[出口] 或 [待机]
   - 配对的传送门会自动同步模式

4. **启用 Cybersyn**（可选）
   - 配对后，勾选 "物流网络" 复选框
   - 传送门将自动注册到 Cybersyn 网络

### 兼容性

| 模组 | 支持情况 |
|------|--------|
| Space Exploration | ✅ 完全兼容 |
| Cybersyn | ✅ 完全兼容 |
| Factorio 2.0+ | ✅ 支持 |

### 常见问题

**Q: 火车进入传送门后不传送？**
- A: 检查传送门是否已配对，以及是否设置为 [入口] 模式。如问题持续，尝试在模组设置中点击 "重置所有碰撞器"。

**Q: 如何在不同地表间传送物品？**
- A: 使用 Cybersyn 物流网络。为两个地表上的传送门都启用 Cybersyn，系统会自动建立跨地表路线。

**Q: 可以传送玩家吗？**
- A: 是的！在传送门控制台中有 "传送玩家" 按钮。

### 设置选项

- **显示 Cybersyn 状态通知** - 在聊天栏显示 Cybersyn 连接状态（个人设置）
- **显示 Cybersyn 全局提示** - 是否看到全局 Cybersyn 通知（个人设置）
- **开启调试日志** - 启用详细日志用于故障排查（全局设置）
- **重置所有碰撞器** - 紧急修复碰撞失效（全局设置）

### 反馈与报告

如发现问题或有建议，请在 [GitHub Issues](https://github.com/VariousTrick/RiftRail/issues) 中提交报告。

---

</details>

<details>
<summary><strong>📖 English Documentation</strong></summary>

## English

### Introduction

**Rift Rail** is a Factorio mod that provides an **asymmetric, single-way cross-surface train teleportation system**.

It enables players to teleport trains between different surfaces, with perfect support for **Space Exploration** and **Cybersyn** logistics networks.

### Core Features

✨ **Cross-Surface Teleportation**
- Teleport trains between different surfaces instantly
- Seamless integration with Space Exploration spaceship mechanics
- Full compatibility with Cybersyn logistics scheduling

🎯 **Flexible Mode Control**
- **Entry Mode**: Train enters and teleports to paired exit
- **Exit Mode**: Train exits and continues forward
- **Standby Mode**: Pause all operations

🔗 **Pairing System**
- Link portals together for bidirectional routes
- Customize names and icons for each portal
- Cross-surface pairing notifications and validation

📡 **Cybersyn Compatible**
- Manually enable Cybersyn connection
- Support for cross-surface logistics routing
- Per-player configurable global message display

🛠️ **Debug & Management Tools**
- Comprehensive debug logging system
- Emergency collider reset utility
- Detailed mod settings and configuration

### Video Demo

<div align="center">

<video width="640" height="360" controls>
  <source src="https://github.com/VariousTrick/RiftRail/releases/download/video/_20251216_182942.webm" type="video/webm">
  Your browser does not support video playback
</video>

</div>

### Installation

1. Search for "Rift Rail" on [Factorio Mod Portal](https://mods.factorio.com/) and download
2. Or manually download from [GitHub Release](https://github.com/VariousTrick/RiftRail/releases)
3. Extract to `~/.factorio/mods/` directory
4. Restart Factorio

### Quick Start

1. **Place Portals**
   - Find "Rift Rail" in your inventory
   - Place the first portal as the **Entry**
   - Place the second portal as the **Exit**

2. **Pair Portals**
   - Left-click on a portal to open the control panel
   - Select the target portal from the dropdown menu
   - Click "Pair" button

3. **Switch Modes**
   - Use the middle three-state switch to select [Entry], [Exit], or [Standby]
   - Paired portals automatically sync their modes

4. **Enable Cybersyn** (Optional)
   - After pairing, check the "Logistics Network" checkbox
   - Portal will auto-register with Cybersyn network

### Compatibility

| Mod | Support |
|-----|---------|
| Space Exploration | ✅ Fully Compatible |
| Cybersyn | ✅ Fully Compatible |
| Factorio 2.0+ | ✅ Supported |

### FAQ

**Q: Train doesn't teleport after entering the portal?**
- A: Check if the portal is paired and set to [Entry] mode. If the issue persists, try clicking "Reset All Colliders" in mod settings.

**Q: How to transport items between surfaces?**
- A: Use the Cybersyn logistics network. Enable Cybersyn on portals on both surfaces and the system will auto-establish cross-surface routes.

**Q: Can I teleport players?**
- A: Yes! There's a "Teleport Player" button in the portal control panel.

### Configuration Options

- **Show Cybersyn Status Notifications** - Display Cybersyn connection status in chat (Per-player)
- **Show Cybersyn Global Messages** - Show global Cybersyn notifications (Per-player)
- **Enable Debug Logging** - Show detailed logs for troubleshooting (Global)
- **Reset All Colliders** - Emergency fix for collision issues (Global)

### Feedback & Bug Reports

Found a bug or have suggestions? Please submit an issue on [GitHub Issues](https://github.com/VariousTrick/RiftRail/issues).

---

</details>

---

<div align="center">

**Made with ❤️ for Factorio Community**

</div>

