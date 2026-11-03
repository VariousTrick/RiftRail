![Version](https://img.shields.io/badge/dynamic/json?url=https://raw.githubusercontent.com/VariousTrick/RiftRail/main/RiftRail/info.json&query=$.version&label=Version&color=blue) ![Downloads](https://img.shields.io/badge/dynamic/json?url=https://mods.factorio.com/api/mods/RiftRail&query=$.downloads_count&label=Downloads&color=orange)

# Rift Rail - 裂隙铁路

<details open>
<summary><strong>🌐 Language / 语言</strong></summary>

- [中文](#中文)
- [English](#english)

</details>

---

<details open>
<summary><strong>📖 中文文档 (Chinese Documentation)</strong></summary>

## 裂隙铁路

Rift Rail 是一个跨地表、跨空间平台的列车传送系统。它通过入口和出口连接不同位置的铁路网络，让列车可以在不同地表之间快速通行。

[观看演示录像](https://github.com/user-attachments/assets/71ac7154-dcad-40d2-93ed-dec77c9c3791)

### 🚂 主要功能

- 🌌 支持地表之间以及 Space Exploration 太空平台之间的列车传送。
- 🔀 通过入口、出口和待机模式配置传送门。
- 🕸️ 支持多个入口连接一个出口，也支持一个入口连接多个出口。
- 🚆 支持机车、货运车厢、流体车厢和炮车。
- 👤 乘坐列车的玩家会随列车一起传送。
- 🛡️ 控制核心支持可配置权限的手动玩家传送。
- 🎨 支持自定义传送门名称和图标。
- 📦 支持 LTN 和 Cybersyn 2 跨地表物流调度。
- ⚙️ 提供多种模组集成与配方进程选项。

### 🛠️ 基本用法

1. 建造两个 Rift Rail 传送门。
2. 打开传送门的控制核心。
3. 将一个传送门设置为入口，另一个设置为出口。
4. 在连接界面中完成配对。
5. 将铁路连接到传送门内部的轨道。
6. 让列车驶入入口传送门。

列车会从已连接的出口传送门出现，并继续运行。

### 📦 物流集成

#### 🚚 Logistic Train Network

支持 LTN 跨地表物流调度。

#### 🤖 Cybersyn 2

自 v0.12 起原生支持 Cybersyn 2，通过 CS2 的 route plugin 接口实现跨地表调度。

#### 🚀 Space Exploration

支持在太空平台上建造和使用 Rift Rail，并进行跨地表列车传送。

### 🧩 模组集成与配方进程

可以在模组设置中选择以下选项：

- 无集成
- 简单模式
- Space Age
- Krastorio 2
- Space Exploration
- Space Exploration + Krastorio 2

修改启动设置后需要重新启动游戏。

### 📚 详细文档

- [常见问题](./FAQ.md)
- [中文 API 文档](./doc/API_CN.md)
- [English API Documentation](./doc/API_EN.md)

### ❤️ 致谢

- **Ldmf**：配方、科技和模组集成方面的贡献。
- **Harag**：跨地表物流设计方面的启发。
- **Cybersyn**、**LTN** 和 **Space Exploration** 的作者：感谢你们提供的框架和工具。
- 感谢所有参与测试、报告问题和提出建议的玩家。

</details>

<details open>
<summary><strong>📖 English Documentation</strong></summary>

## Rift Rail

Rift Rail is a train teleportation system for transporting trains across surfaces and Space Exploration space platforms. It connects railway networks through entry and exit portals.

[Watch the demonstration video](https://github.com/user-attachments/assets/71ac7154-dcad-40d2-93ed-dec77c9c3791)

### 🚂 Features

- 🌌 Train teleportation between surfaces and Space Exploration space platforms.
- 🔀 Entry, Exit, and Standby portal modes.
- 🕸️ Multiple Entry portals connected to one Exit, or one Entry connected to multiple Exits.
- 🚆 Support for locomotives, cargo wagons, fluid wagons, and artillery wagons.
- 👤 Players inside trains travel with the train.
- 🛡️ Configurable manual player teleportation from the control core.
- 🎨 Custom portal names and icons.
- 📦 Logistic Train Network and Cybersyn 2 integration.
- ⚙️ Multiple mod integration and recipe progression options.

### 🛠️ Basic Usage

1. Build two Rift Rail portals.
2. Open a portal's control core.
3. Set one portal to Entry mode and the other to Exit mode.
4. Pair the portals through the connection interface.
5. Connect your railway to the internal portal tracks.
6. Send a train through the Entry portal.

The train will appear at the connected Exit portal and continue its journey.

### 📦 Logistics Integrations

#### 🚚 Logistic Train Network

Rift Rail supports LTN cross-surface logistics.

#### 🤖 Cybersyn 2

Native Cybersyn 2 support was added in v0.12 through the CS2 route plugin interface.

#### 🚀 Space Exploration

Rift Rail supports building and using portals on Space Exploration space platforms.

### 🧩 Mod Integrations and Recipe Progression

The mod provides the following options:

- None
- Easy Mode
- Space Age
- Krastorio 2
- Space Exploration
- Space Exploration + Krastorio 2

Changing the startup setting requires restarting the game.

### 📚 Documentation

- [FAQ](./FAQ.md)
- [中文 API 文档](./doc/API_CN.md)
- [English API Documentation](./doc/API_EN.md)

### ❤️ Thanks

- **Ldmf** for contributions to recipes, technologies, and mod integrations.
- **Harag** for the inspiration behind the cross-surface logistics design.
- The creators of **Cybersyn**, **LTN**, and **Space Exploration** for providing the frameworks that make this mod possible.
- Everyone who tested the mod, reported issues, and provided feedback.

</details>


<div align="center">

**Made with ❤️ for Factorio Community**

</div>
