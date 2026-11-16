# Rift Rail - 模组兼容性与API指南

欢迎！本文档旨在帮助其他模组开发者与 Rift Rail 进行兼容。

## 核心机制：销毁与再创造

理解 Rift Rail 的核心机制至关重要：当一列火车通过传送门时，它并非被“移动”，而是**旧的列车实体被逐节销毁，新的列车实体在出口被逐节重新创建**。

这意味着，任何直接引用旧列车实体（`LuaEntity`）的变量或数据表，在传送后都会失效。


## 事件监听建议与自定义事件说明

Rift Rail 传送时会触发 Factorio 的 `on_entity_cloned` 标准事件：

- 这两类事件会为每一节新生成的车厢单独触发，适合需要逐节处理列车数据的场景。

此外，Rift Rail 还会在整列列车传送的“开始”和“结束”节点，额外触发自定义事件（通过 remote.call 获取事件ID），事件参数包含整车的关键信息，适合需要整体把控传送流程或跨模组交互的场景。

### 监听方式建议

- 需要逐节车厢详细数据 → 监听标准事件（on_entity_cloned）
- 需要整体传送信息或跨模组交互 → 监听 Rift Rail 自定义事件
- 也可以两者同时监听，获得最完整的兼容性和信息

### 如何获取 Rift Rail 自定义事件ID

通过 remote.call 获取事件ID：

```lua
-- 获取“列车开始传送”事件ID
remote.call("RiftRail", "get_train_departing_event")

-- 获取“列车传送移交”事件ID
remote.call("RiftRail", "get_train_teleport_transfer_event")

-- 获取“列车传送完成”事件ID
remote.call("RiftRail", "get_train_arrived_event")
```

拿到事件ID后，用 script.on_event 监听即可。

### 自定义事件参数说明

事件参数为 table，常见字段如下：

#### `TrainDeparting`
*触发时机：传送会话启动，列车被入口传送门锁定准备传送时触发。此时列车本体完好无损，适合通用模组清空车站状态。*
*   `train`: [LuaTrain] 完整的旧列车实体。
*   `train_id`: [number] 旧列车的ID。
*   `source_teleporter`: [LuaEntity] 出发传送门实体。
*   `source_teleporter_id`: [number] 出发传送门的ID。
*   `source_surface`: [LuaSurface] 出发地表。
*   `source_surface_index`: [number] 出发地表的索引。

#### `TrainTeleportTransfer`
*触发时机：出口第一节新车厢刚刚克隆生成、且入口原车厢尚未被销毁的微秒级瞬间触发。该事件专为外部物流模组（如 LTN/Cybersyn）设计，用于在同一帧内完成新旧列车 ID 的发货单接管。为满足相关模组底层调用约束，本事件不仅传递新老列车的 ID，也特别提供了新生成的列车实体对象。*
*   `old_train_id`: [number] 完整的旧列车 ID。
*   `new_train_id`: [number] 刚刚在出口生成的新列车（此时仅包含首节车厢）的 ID。
*   `new_train`: [LuaTrain] 刚刚在出口生成的新列车实体对象。
*   `entry_unit_number`: [number] 入口传送门的 unit_number。
*   `exit_unit_number`: [number] 出口传送门的 unit_number。

#### `TrainArrived`
*   `train`: [LuaTrain] 完整的、刚刚形成的新列车实体。
*   `train_id`: [number] 新列车的ID。
*   `old_train_id`: [number] **【关键】** 被传送的旧列车的ID，用于关联`TrainDeparting`事件。
*   `source_surface`: [LuaSurface] 起始地表。
*   `source_surface_index`: [number] 起始地表的索引。
*   `destination_teleporter`: [LuaEntity] 到达传送门实体。
*   `destination_teleporter_id`: [number] 到达传送门的ID。
*   `destination_surface`: [LuaSurface] 到达地表。
*   `destination_surface_index`: [number] 到达地表的索引。
*   `entry_unit_number`: [number] 入口（来源）传送门的 unit_number。
*   `exit_unit_number`: [number] 出口（接收）传送门的 unit_number。
*   `restored_guis`: [table] (用于恢复GUI的对象表，内部使用)。

### 说明

Rift Rail 的自定义事件只会在整列列车传送的关键节点触发一次，参数包含整车的关键信息。标准事件则会为每节车厢单独触发。开发者可根据自身需求选择监听方式，两者可同时使用。

---

## 远程接口 (Remote Interface)

除了事件监听，Rift Rail 还提供丰富的 `remote.call` 远程接口，供第三方模组查询拓扑数据或进行协同控制。

### 传送门配对拓扑查询接口

#### 1. `get_paired_portals`
查询指定传送门配对的所有入口与出口信息，返回结构化的纯数据表（ID 居于各元素首位）。

```lua
local data = remote.call("RiftRail", "get_paired_portals", portal_or_id)
```

- **参数 `portal_or_id`** (可选)：
  - `number`: 传送门的数字 ID（例如 `1`）。
  - `string`: 传送门的字符串 ID（例如 `"1"`）。
  - `LuaEntity`: 传送门的实体对象（支持传送门外壳 `rift-rail-entity`、核心 `rift-rail-core` 或任意子实体）。
  - `nil`: 若不传，则默认解析为当前玩家所选中的实体（`game.player.selected`）。
- **返回值**：若未找到返回 `nil`；若找到返回结构如下的 Table：
  ```lua
  {
      id = 1,                                -- [number] 目标传送门的自定义 ID
      name = "主基地站",                      -- [string] 传送门自定义名称（未命名则为空字符串）
      mode = "entry",                        -- [string] 运行模式: "entry" | "exit" | "neutral"
      gps = "[gps=10.5,20.0,nauvis]",        -- [string] 富文本 GPS 坐标超链接
      entries = {                            -- [table] 配对的入口列表（按 ID 升序排列）
          {
              id = 2,
              name = "远端输入",
              mode = "entry",
              gps = "[gps=-50.0,80.0,nauvis]",
          },
      },
      exits = {                              -- [table] 配对的出口列表（按 ID 升序排列）
          {
              id = 3,
              name = "冶炼区出口",
              mode = "exit",
              gps = "[gps=120.0,-35.0,vulcanus]",
          },
      },
  }
  ```

#### 2. `print_paired_portals`
将指定传送门的配对拓扑信息格式化后，通过本地化富文本打印到指定玩家的聊天框或控制台。信息中包含出入口独立计数、分类展示，以及末尾可点击的大地图跳转 GPS 超链接。

```lua
remote.call("RiftRail", "print_paired_portals", portal_or_id, target_player)
-- 亦兼容逆序传参：
-- remote.call("RiftRail", "print_paired_portals", target_player, portal_or_id)
```

- **参数**：
  - `portal_or_id`: 同 `get_paired_portals`，支持数字 ID、字符串 ID、实体对象或已提取的数据表。
  - `target_player` (可选): `LuaPlayer` 对象。若省略或在无玩家环境执行，将安全回退至控制台打印。
- **输出样式示意**：
  ```text
  [RiftRail] ID: 1 · Nauvis 入口站 [入口] -> [gps=10.5,20.0,nauvis]
  ▼ 配对出口 (共 2 处):
    [1] ID: 2 · Vulcanus 铸造出口 -> [gps=-100.0,55.5,vulcanus]
    [2] ID: 3 · Gleba 农场出口 -> [gps=32.0,-80.0,gleba]
  ```

---

如有任何问题，欢迎在我们的模组页面上提出。