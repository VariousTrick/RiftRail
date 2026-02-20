# Rift Rail - 模组兼容性与API指南

欢迎！本文档旨在帮助其他模组开发者与 Rift Rail 进行兼容。

## 核心机制：销毁与再创造

理解 Rift Rail 的核心机制至关重要：当一列火车通过传送门时，它并非被“移动”，而是**旧的列车实体被逐节销毁，新的列车实体在出口被逐节重新创建**。

这意味着，任何直接引用旧列车实体（`LuaEntity`）的变量或数据表，在传送后都会失效。


## 事件监听建议与自定义事件说明

Rift Rail 在不同传送实现下会分别触发 Factorio 的 `on_built_entity` 和 `on_entity_cloned` 标准事件：

- 这两类事件会为每一节新生成的车厢单独触发，适合需要逐节处理列车数据的场景。

此外，Rift Rail 还会在整列列车传送的“开始”和“结束”节点，额外触发自定义事件（通过 remote.call 获取事件ID），事件参数包含整车的关键信息，适合需要整体把控传送流程或跨模组交互的场景。

### 监听方式建议

- 需要逐节车厢详细数据 → 监听标准事件（on_built_entity/on_entity_cloned）
- 需要整体传送信息或跨模组交互 → 监听 Rift Rail 自定义事件
- 也可以两者同时监听，获得最完整的兼容性和信息

### 如何获取 Rift Rail 自定义事件ID

通过 remote.call 获取事件ID：

```lua
-- 获取“列车开始传送”事件ID
remote.call("RiftRail", "get_train_departing_event")

-- 获取“列车传送完成”事件ID
remote.call("RiftRail", "get_train_arrived_event")
```

拿到事件ID后，用 script.on_event 监听即可。

### 自定义事件参数说明

事件参数为 table，常见字段如下：

- `train`：LuaTrain，传送中的列车对象
- `train_id`：number，列车ID
- `source_teleporter` / `destination_teleporter`：LuaEntity，入口/出口传送门
- `source_surface` / `destination_surface`：LuaSurface，入口/出口地表
- `source_surface_index` / `destination_surface_index`：number，地表索引
- `tick`：number，事件发生时刻
- `old_train_id`：number，仅到达事件有，表示原始列车ID

### 说明

Rift Rail 的自定义事件只会在整列列车传送的关键节点触发一次，参数包含整车的关键信息。标准事件则会为每节车厢单独触发。开发者可根据自身需求选择监听方式，两者可同时使用。

如有任何问题，欢迎在我们的模组页面上提出。