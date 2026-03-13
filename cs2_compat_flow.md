# RiftRail 兼容 Cybersyn2 流程（实施版）

> 目标：给 RiftRail 增加对 `cybersyn2` 的稳定兼容。
> 范围：流程设计与落地顺序，不涉及本文件内直接改代码。

## 1. 设计目标

1. 只在安装 `cybersyn2` 时显示 CS2 开关。
2. 以每个传送门为粒度控制“是否参与 CS2 路由”。
3. 通过 CS2 route plugin 机制实现跨地表列车接管与归还。
4. 在门网络变化后主动重建 CS2 拓扑，避免陈旧路由。
5. 保证失败可回退，不让 delivery 长时间卡在 `plugin_handoff`。

---

## 2. 先统一的心智模型

1. `topology` 负责“分区/可服务范围”。
2. `reachable_callback` 负责“这单是否允许派发”（提前 veto）。
3. `route_callback` 负责“当前路段是否接管”（handoff 开关）。
4. RiftRail 传送完成后，调用 `route_plugin_handoff` 把控制权还给 CS2。

---

## 3. 实施阶段（建议按顺序）

## 阶段A：UI 与状态链路（无侵入）

1. 在 GUI 增加 CS2 按钮
- 位置：放在 LTN 区块上方。
- 显示条件：`script.active_mods["cybersyn2"]` 为真时显示。
- 启用条件：和 LTN 一致，至少有一个连接时可用。
- 字段建议：`portaldata.cs2_enabled`（默认 `false`）。

2. 打通调用链
- `GUI`：新增 `rift_rail_cs2_switch`，切换后 `remote.call("RiftRail", "set_cs2_enabled", ...)`。
- `scripts/remote.lua`：增加 `set_cs2_enabled` 接口转发到 `Logic`。
- `scripts/logic.lua`：实现 `Logic.set_cs2_enabled`，并在连接变化时通知 CS2 兼容模块同步。

3. 连接归零时自动复位
- 沿用现有逻辑：连接数为 0 时自动关闭物流开关。
- 新增同步关闭 `cs2_enabled`，避免“无连接但开关还亮”。

---

## 阶段B：注册 route plugin（data 阶段）

1. 在 data 阶段把 RiftRail 注册进 CS2 route plugins
- 不是 runtime remote 注册。
- 目标是写入 `mod-data["cybersyn2"].data.route_plugins["riftrail"]`。

2. 注册三个回调
- `train_topology_callback`
- `reachable_callback`
- `route_callback`

3. control 阶段提供回调接口
- `remote.add_interface("riftrail", { ...callbacks... })`
- 回调实现放 `scripts/compat/cs2.lua`。

---

## 阶段C：实现 compat 模块边界（核心）

建议新增 `scripts/compat/cs2.lua`，职责如下：

1. `init(deps)`
- 注入 `State`、`log_debug`、必要工具函数。
- 初始化内存表（handoff 上下文、旧新 train 映射等）。

2. `train_topology_callback(origin_surface_index)`
- 返回 `SET<table<uint, true>>`。
- 只基于“当前已启用 CS2 且有效连接”的门对来计算可达 surface。

3. `reachable_callback(...)`
- 对 CS2 即将派发的匹配做提前否决。
- 返回 `true` 表示 veto（拒绝这次匹配）。
- 用于拦截单向不可回、目标门无效、关门中等风险场景。

4. `route_callback(delivery_id, action, topology_id, train_id, luatrain, train_stock, train_home_surface_index, stop_id?, stop_entity?)`
- 只在“本路段跨地表且可处理”时返回 truthy 接管。
- 同时记录 handoff 上下文（见第 4 节）。

5. `on_train_arrived(event)`
- 监听 RiftRail `TrainArrived` 自定义事件。
- 通过 `event.old_train_id -> delivery_id` 找到待归还 delivery。
- 调用 `remote.call("cybersyn2", "route_plugin_handoff", delivery_id, event.train)`。

6. `on_topology_changed()`
- 门配对/解绑/模式变化/拆除后调用：
- `remote.call("cybersyn2", "rebuild_train_topologies")`。

7. `fail_safe(delivery_id, reason)`
- 无法完成交接时调用：
- `remote.call("cybersyn2", "fail_delivery", delivery_id, reason)`。

---

## 4. 最小状态表设计（建议）

1. `storage.rr_cs2_handoff_by_old_train_id[old_train_id] = { delivery_id, action, tick, portal_id, expected_surface }`
- 作用：传送后根据 `old_train_id` 找回 delivery 并归还。

2. `storage.rr_cs2_delivery_lock[delivery_id] = true`
- 作用：避免同一 delivery 重复接管或重复 handback。

3. `storage.rr_cs2_last_topology_rebuild_tick`
- 作用：节流拓扑重建，避免频繁调用。

---

## 5. 关键交互时序（实际执行）

1. CS2 在 `pickup/dropoff/complete` 触发 `route_callback`。
2. RiftRail 判断该路段跨地表且可处理 -> 返回 truthy，CS2 进入 `plugin_handoff`。
3. RiftRail 执行传送，旧车被销毁，新车在出口重建。
4. RiftRail 在 `TrainArrived` 事件拿到 `old_train_id` 与新 `LuaTrain`。
5. RiftRail 调用 `route_plugin_handoff(delivery_id, new_luatrain)`。
6. CS2 清除 volatile 状态并继续后续状态机。

---

## 6. 与现有 LTN 兼容共存

1. LTN 与 CS2 开关互相独立，默认都可同时存在。
2. 不建议互斥，除非后续发现特定边界冲突。
3. 在传送结束钩子中，先执行现有 LTN `on_teleport_end`，再执行 CS2 handback（或明确固定顺序并记录）。
4. 若两个兼容层都可能改时刻表，必须在模块内定义优先级并防重入。

---

## 7. 回退策略（防卡单）

1. handoff 超时（例如 N 秒未完成）：`fail_delivery`。
2. 传送目标失效：`fail_delivery`。
3. 新车无效或无法映射 delivery：记录日志并 `fail_delivery`。
4. 所有失败路径都要清理 `storage.rr_cs2_*` 临时状态。

---

## 8. 测试清单（从易到难）

1. 单地表普通单（不应触发 handoff）。
2. 双地表 `pickup` 跨地表（触发 1 次 handoff）。
3. 双地表 `dropoff` 跨地表（触发 1 次 handoff）。
4. `complete` 回库跨地表（触发 handoff 或被 reachable veto，取决于阶段实现）。
5. 单向门场景（应被 reachable 拒绝，不能派发死单）。
6. 传送中拆门/拆站（应 fail_delivery，不可无限挂起）。
7. 门连接频繁变化（拓扑应重建，且无明显性能抖动）。

---

## 9. 推荐里程碑

1. M1：GUI + 状态链路 + 占位 compat 模块（不接管）。
2. M2：`train_topology_callback` + `rebuild_train_topologies`。
3. M3：`route_callback` + `TrainArrived` handback（先支持 pickup/dropoff）。
4. M4：`reachable_callback` 精细化规则。
5. M5：`complete` 路段与失败回退完善。

---

## 10. 常见错误提醒

1. 把接口名写成 `"cs2"`（当前应为 `"cybersyn2"`）。
2. 只做 topology，不做 reachable/route。
3. handoff 后忘记调用 `route_plugin_handoff`。
4. 门网络变化后不调用 `rebuild_train_topologies`。
5. 未处理 train id 变化，仍以旧 `LuaTrain` 追踪。

---

## 11. 一句话方案

先做“CS2 开关 + compat 框架 + handoff 闭环”，再做“reachable 策略精细化”，这样可以最快得到可运行、可调试、可扩展的兼容版本。