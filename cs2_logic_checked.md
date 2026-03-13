# RiftRail x Cybersyn2 逻辑校对版（基于当前工作区源码）

> 目的：把 `cs2.md` 讨论过的逻辑做一次“可落地”的技术版总结，避免后续实现踩坑。
> 结论基于当前工作区 `cybersyn2` 代码，而不是口头推断。

## 1. 先说结论（TL;DR）

1. CS2 确实支持把列车控制权交给外部插件（`plugin_handoff`）。
2. 交接不是整单一次，而是按路段触发：`pickup` / `dropoff` / `complete`。
3. 拓扑回调不是“有向图边”接口，而是“从某 surface 可达 surface 的集合（SET）”接口。
4. 仅靠 topology 回调不足以表达单向门约束；应结合 `reachable_callback` / `route_callback` 实现方向性与可达性控制。
5. 交还控制使用 `remote.call("cybersyn2", "route_plugin_handoff", delivery_id, new_luatrain)`。
6. 路由插件注册是 data 阶段写入 `mod-data`，不是运行时 remote 注册。

---

## 2. 关键源码锚点

- `cybersyn2/scripts/logistics/delivery/train.lua`
  - `query_route_plugins(...)`
  - `goto_from()` / `goto_to()` / `complete()` 中触发 handoff
  - `notify_plugin_handoff(new_luatrain)` 处理归还
- `cybersyn2/scripts/vehicle/train/base.lua`
  - `set_volatile()` / `clear_volatile(new_luatrain)`
- `cybersyn2/scripts/api/base.lua`
  - `route_plugin_handoff`
  - `rebuild_train_topologies`
- `cybersyn2/scripts/node/topology.lua`
  - `query_topo_plugins(original_surface_id)`
  - `create_train_topology(surface_index)`
- `cybersyn2/scripts/api/plugins/route.lua`
  - `query_reachable_callbacks(...)`
- `cybersyn2/control.lua`
  - `remote.add_interface("cybersyn2", _G.cs2.remote_api)`
- `cybersyn2/prototypes/custom-event.lua`
  - `mod-data` 中的 `route_plugins = {}`

---

## 3. CS2 的真实交接时序

### 3.1 pickup 阶段（去供货站）

CS2 在 `goto_from()` 里先问插件：

```lua
query_route_plugins(
  delivery_id,
  "pickup",
  topology_id,
  train_id,
  luatrain,
  train_stock,
  train_home_surface_index,
  from_stop_id,
  from_stop_entity
)
```

- 若插件返回 truthy：
  - `handoff_state = "to_from"`
  - `train:set_volatile()`
  - `state = "plugin_handoff"`
  - CS2 本段不再写 schedule
- 若插件不接管：CS2 继续 `train:schedule(...)`

### 3.2 dropoff 阶段（去需求站）

同理，在 `goto_to()` 里问插件，`action = "dropoff"`，并传 `to_stop_id/to_stop_entity`。

- 接管则 `handoff_state = "to_to"` + `plugin_handoff`
- 否则 CS2 自己写本段 schedule

### 3.3 complete 阶段（交付完成）

`complete()` 里也会问插件，`action = "complete"`。

- 接管则 `handoff_state = "completed"` + `plugin_handoff`
- 不接管则直接 `state = "completed"`

### 3.4 插件交还控制

插件完成跨地表处理后调用：

```lua
remote.call("cybersyn2", "route_plugin_handoff", delivery_id, new_luatrain)
```

CS2 在 `notify_plugin_handoff` 中：

1. `train:clear_volatile(new_luatrain)`（可替换 LuaTrain）
2. 根据 `handoff_state` 继续推进：
   - `to_from` -> enqueue `goto_from`
   - `to_to` -> enqueue `goto_to`
   - `completed` -> 直接完成

---

## 4. 关于“空时刻表”的准确说法

不要写成“handoff 时列车一定是空表”。更准确是：

1. CS2 在 handoff 分支不会给该路段追加临时记录。
2. CS2 的 schedule 管理主要操作 temporary 记录。
3. 列车可能保留 depot 等非 temporary 记录，因此不是严格意义的“空表”。

---

## 5. 关于拓扑：为什么不能简单等同“有向图”

`train_topology_callback` 返回的是“从 origin surface 可达的 surface SET”。
CS2 将这个 SET 合并后映射到同一 topology。

这意味着：

1. 拓扑层本身更像“同一可服务域”的分组，而非逐边方向图。
2. 单向门、阶段可达性、条件可达性等细节，不能只靠 topology 表达。
3. 方向性约束应落在 `reachable_callback` 与 `route_callback`。

---

## 6. 路由插件注册方式（容易写错）

不是 runtime `remote` 注册，而是 data 阶段写入 `mod-data`。

示意（放在你的 data 阶段文件里）：

```lua
local cs2_md = data.raw["mod-data"] and data.raw["mod-data"]["cybersyn2"]
if cs2_md and cs2_md.data and cs2_md.data.route_plugins then
  cs2_md.data.route_plugins["riftrail"] = {
    train_topology_callback = {"riftrail", "cs2_train_topology_callback"},
    reachable_callback = {"riftrail", "cs2_reachable_callback"},
    route_callback = {"riftrail", "cs2_route_callback"},
  }
end
```

然后在 control 阶段由 RiftRail 提供 `remote.add_interface("riftrail", {...})` 实现上述回调。

---

## 7. 给 RiftRail 的最小接入方案（建议）

1. `train_topology_callback(origin_surface_index)`
- 返回 `SET<table<uint, true>>`：从该 surface 能到达的 surface。
- 当门网络变化（建造/拆除/重配）后，调用：
  - `remote.call("cybersyn2", "rebuild_train_topologies")`

2. `reachable_callback(...)`
- 用于提前 veto 不可达组合（返回 `true` 表示拒绝本次匹配）。
- 这里可做“单向门无法完成全流程”的快速剪枝。

3. `route_callback(delivery_id, action, ..., stop_entity?)`
- 在 `pickup/dropoff/complete` 时按 action 判断是否接管。
- 若接管：执行你现有的传送流程。
- 结束后必须 handback：
  - `remote.call("cybersyn2", "route_plugin_handoff", delivery_id, new_luatrain)`

4. 健壮性
- 传送失败时可调用：
  - `remote.call("cybersyn2", "fail_delivery", delivery_id, reason)`
- 防止 delivery 长时间卡在 `plugin_handoff`。

---

## 8. 实现时最容易踩的坑

1. 把接口名写成 `"cs2"`（当前源码里是 `"cybersyn2"`）。
2. 只做 topology，不做 reachable/route 约束。
3. handoff 后忘记回调 `route_plugin_handoff`。
4. 没有在门网络变化后触发 `rebuild_train_topologies`。
5. 假设 train_id 永远不变，忽略 `new_luatrain` 替换场景。

---

## 9. 可执行检查清单

- [ ] data 阶段成功写入 `route_plugins["riftrail"]`
- [ ] control 阶段 `riftrail` remote interface 可调用
- [ ] `train_topology_callback` 在 A/B surface 返回预期 SET
- [ ] 门网络变化后已触发 `rebuild_train_topologies`
- [ ] `pickup/dropoff/complete` 至少一段能触发 handoff
- [ ] 插件 handoff 后能调用 `route_plugin_handoff`
- [ ] 跨地表重建列车后 `new_luatrain` 交还成功
- [ ] 异常路径可 `fail_delivery`

---

## 10. 一句话定位

RiftRail 对接 CS2 的正确心智模型是：

- topology 负责“分区范围”；
- reachable/route 负责“是否可走、何时接管”；
- handoff API 负责“跨地表接力后的控制权归还”。
