# RiftRail 开发变更记录

> 说明：模组未发布阶段使用本文件记录每一次改动。
> 规则：新改动统一追加到最上方（时间倒序），每次包含日期、改动文件、改动内容。
> 补充：本文件从 v0.11.7 之后开始维护；当前 2026-03-02 的全部条目均归入 v0.11.8 发布内容。

## 2026-03-10（v0.12.0 开发中：CS2 传送流程收敛为 SE 同款闭环）

### 改动摘要
- 将 CS2 跨地表接管逻辑收敛为“入口传送站 + 下一实名站”的过渡调度。
- 移除第一节车厢阶段的临时回填钩子，避免与最终 handoff 流程形成混合路径。
- 保留“传送完成后清理过渡临时站，再 `route_plugin_handoff` 交还 CS2”的闭环，避免重复生成临时站。

### 具体改动
- `RiftRail/scripts/compat/cs2.lua`
  - `route_train_to_entry(...)` 新增 `continuation_station_name` 参数。
  - 接管时按顺序写入：
    - 入口传送站（带 `riftrail-go-to-id` 条件）。
    - 下一实名站（由 CS2 传入 `stop_entity.backer_name`）。
  - 删除 `restore_dropoff_schedule(...)` 与 `rr_cs2_dropoff_info_by_train_id` 缓存路径。
  - `on_train_arrived(...)` 仅执行“先清理临时站，再 handoff”，不再二次补站。

- `RiftRail/scripts/teleport.lua`
  - 移除 `CS2Compat.restore_dropoff_schedule(...)` 的第一节回填调用。
  - 移除 `CS2Compat` 依赖注入接收字段。

- `RiftRail/control.lua`
  - `Teleport.init(...)` 移除 `CS2Compat` 注入参数。

## 2026-03-09（v0.12.0 开发中：CS2 兼容骨架接入）

### 改动摘要
- 接入 Cybersyn2 route plugin 骨架，实现 `topology / reachable / route` 三类回调。
- 增加 RiftRail 传送完成后的 CS2 handback 闭环：在 `TrainArrived` 事件中按旧车 ID 归还 delivery。
- 完成运行时接线：`control -> compat.cs2 -> logic/remote`，并在拓扑变化操作后触发 CS2 拓扑重建（带节流）。
- 完成 data 阶段注册：在检测到 `cybersyn2` 时将 RiftRail 回调写入 `mod-data["cybersyn2"].data.route_plugins`。

### 具体改动
- `RiftRail/scripts/compat/cs2.lua`（新文件）
  - 新增 `CS2.init(...)`。
  - 新增 `train_topology_callback(origin_surface_index)`：按 `cs2_enabled` 的 Entry/Exit 连接返回可达 surface 集合。
  - 新增 `reachable_callback(...)`：对不可跨地表路径执行 veto（返回 `true`）。
  - 新增 `route_callback(...)`：跨地表时接管列车，插入前往入口站的调度并记录 handoff 上下文。
  - 新增 `on_train_arrived(event)`：使用 `old_train_id` 定位待归还 delivery，调用 `remote.call("cybersyn2", "route_plugin_handoff", ...)`。
  - 新增 `on_topology_changed()`：节流调用 `remote.call("cybersyn2", "rebuild_train_topologies")`。

- `RiftRail/control.lua`
  - 新增 `require("scripts.compat.cs2")` 并初始化 `CS2Compat`。
  - 将 `CS2Compat` 注入 `Logic.init(...)` 与 `Remote.init(...)`。
  - 新增 `RiftRail.Events.TrainArrived` 监听并转发至 `CS2Compat.on_train_arrived`。

- `RiftRail/scripts/remote.lua`
  - `RiftRail` remote interface 新增：
    - `cs2_train_topology_callback`
    - `cs2_reachable_callback`
    - `cs2_route_callback`
  - 以上回调均转发到 `CS2Compat`。

- `RiftRail/scripts/logic.lua`
  - `Logic.init(...)` 新增 `CS2` 依赖注入。
  - 在 `set_mode / pair_portals / unpair_portals_specific / set_cs2_enabled` 后触发 `CS2.on_topology_changed()`。

- `RiftRail/data-updates.lua`
  - 新增 `has_cs2 = mods["cybersyn2"]` 检测。
  - 在 `has_RiftRail and has_cs2` 时加载 `updates.cs2`。

- `RiftRail/updates/cs2.lua`（新文件）
  - 向 `cybersyn2` 的 `route_plugins` 注册 RiftRail 三个回调：
    - `train_topology_callback = { "RiftRail", "cs2_train_topology_callback" }`
    - `reachable_callback = { "RiftRail", "cs2_reachable_callback" }`
    - `route_callback = { "RiftRail", "cs2_route_callback" }`

## 2026-03-09（v0.12.0 开发中：旧存档 CS2 字段补齐迁移）

### 改动摘要
- 为旧存档中的传送门数据补充 `cs2_enabled` 字段，默认值为 `false`。
- 迁移为一次性任务，在 `on_configuration_changed` 路径执行并写入完成标记，避免重复运行。

### 具体改动
- `RiftRail/scripts/migrations.lua`
  - 新增 `Migrations.patch_cs2_enabled_default()`。
  - 遍历 `storage.rift_rails`，对缺失 `cs2_enabled` 的旧数据补齐 `false`。
  - 新增标志位 `storage.rift_rail_cs2_toggle_migrated`。
  - 在 `Migrations.run_all()` 中接入该迁移任务。

## 2026-03-09（v0.12.0 开发中：新增 CS2 按钮与本地开关链路）

### 改动摘要
- 在传送门 GUI 中新增 CS2 开关，位置位于 LTN 开关上方，仅在安装 `cybersyn2` 时显示。
- 打通 CS2 开关的本地状态链路：`GUI -> Remote -> Logic`，用于保存 `cs2_enabled` 并刷新界面。
- 新增英/日/简中本地化条目，覆盖 CS2 开关标签、状态与提示文案。
- 本次不包含 CS2 路由/拓扑/handoff 兼容逻辑，仅实现按钮与按钮功能。

### 具体改动
- `RiftRail/scripts/gui.lua`
  - 新增 `rift_rail_cs2_switch` 开关组件，显示条件为 `script.active_mods["cybersyn2"]`。
  - 将 CS2 区块放置于 LTN 区块上方。
  - 在 `handle_switch_state_changed` 中新增 `rift_rail_cs2_switch` 分支，调用 `remote.call("RiftRail", "set_cs2_enabled", ...)`。

- `RiftRail/scripts/remote.lua`
  - `RiftRail` remote interface 新增 `set_cs2_enabled(player_index, portal_id, enabled)`，转发到 `Logic.set_cs2_enabled`。

- `RiftRail/scripts/logic.lua`
  - 新增 `Logic.set_cs2_enabled(...)`，负责保存 `portaldata.cs2_enabled` 并刷新 GUI。
  - 在连接归零自动复位逻辑中加入 `portaldata.cs2_enabled = false`。

- `RiftRail/scripts/builder.lua`
  - 新建传送门数据时新增默认字段 `cs2_enabled = false`。

- `RiftRail/locale/en/strings.cfg`
  - 新增 `rift-rail-cs2-label / connected / disconnected / tooltip`。

- `RiftRail/locale/ja/strings.cfg`
  - 新增 `rift-rail-cs2-label / connected / disconnected / tooltip`。

- `RiftRail/locale/zh-CN/strings.cfg`
  - 新增 `rift-rail-cs2-label / connected / disconnected / tooltip`。

## 2026-03-06（v0.11.10 开发中：入口拆除时的出口锁泄漏修复）

### 改动摘要
- 修复入口传送门在传送中被拆除后，出口 `locking_entry_id` 可能残留导致后续长期无法抢锁的问题。
- 采用最小改动策略：仅在 `on_tick` 的“无效 portal 清理”分支增加一次临终解锁。

### 具体改动
- `RiftRail/scripts/teleport.lua`
  - `Teleport.on_tick(event)`：当活跃列表中的入口 `portaldata` 已失效时，若其记录了 `locked_exit_unit_number`，则尝试定位出口并在 `locking_entry_id == 该入口unit_number` 时释放锁，随后再执行原有活跃列表清理。

## 2026-03-06（v0.11.10 开发中：修正放置间隔缓存读写对象不一致）

### 改动摘要
- 修正 `placement_interval` 缓存写在出口、读取在入口导致缓存不命中的问题。
- 保持现有流程不变，仅统一为“入口侧写入 + 入口侧读取 + 会话结束清理”。

### 具体改动
- `RiftRail/scripts/teleport.lua`
  - `process_transfer_step(...)`：首节车时将 `placement_interval` 写入 `entry_portaldata`（与 `process_teleport_sequence(...)` 读取对象一致）。
  - `finalize_sequence(...)`：将 `placement_interval` 清理从 `exit_portaldata` 调整为 `entry_portaldata`。

## 2026-03-06（v0.11.10 开发中：出口速度方向缓存更新时机优化）

### 改动摘要
- 将出口速度方向计算从 `maintain_exit_speed` 的每 tick 重算，调整为“拼接成功后更新缓存，tick 内直接读取缓存”。
- 结合实测结论（拼接会触发 `train_id` 变化），采用单一触发点策略，不再引入额外的 `train_id` 变化判断分支。
- 保留“缓存缺失时兜底重算”以覆盖极端首帧/异常路径，保证稳定性。

### 具体改动
- `RiftRail/scripts/teleport.lua`
  - `process_transfer_step(...)`：在新车厢创建并拼接完成后，写入 `exit_portaldata.cached_speed_sign`。
  - `maintain_exit_speed(...)`：优先读取 `cached_speed_sign`，不再每 tick 调用 `calculate_speed_sign(...)`；仅在缓存为空时兜底计算一次并回填。
  - `finalize_sequence(...)`：新增 `exit_portaldata.cached_speed_sign = nil` 清理，避免跨会话残留。

## 2026-03-04（v0.11.9 开发中：Kux-SlimInserters 兼容修复）

### 改动摘要
- 修复与 `Kux-SlimInserters` 并用时，`rift-rail-core` 可选区域被缩小导致核心点击困难、GUI 难以打开的问题。
- 在 `data-final-fixes` 中增加条件恢复逻辑：仅当检测到 `Kux-SlimInserters` 时恢复核心 `selection_box`。

### 具体改动
- `RiftRail/data-final-fixes.lua`
  - 新增 `KUX_SLIM_INSERTERS_INSTALLED` 检测（`mods["Kux-SlimInserters"]`）。
  - 若已安装该模组，则将 `data.raw["container"]["rift-rail-core"].selection_box` 恢复为 `{{-2,-2},{2,2}}`。
  - 保留调试日志输出，便于在启用 `rift-rail-debug-mode` 时追踪兼容修复是否生效。

## 2026-03-04（v0.11.9 开发中：日语本地化首版与术语修正）

### 改动摘要
- 新增 `ja` 本地化目录并完成首版文本，覆盖 `strings / informatron / tips` 三类文件。
- 日语文案保持 `Rift Rail` 英文名不变，同时统一保留原有占位符与富文本标记格式。
- 根据审阅反馈修正术语自然度与残留拼写问题（如 `Entry（送信）/Exit（受信）` 改为 `入口/出口`）。

### 具体改动
- `RiftRail/locale/ja/strings.cfg`
  - 新建日语版 `strings` 文案（与 `en` 键集合保持一致）。
  - 调整模式命名：`rift-rail-mode-entry=入口`、`rift-rail-mode-exit=出口`。
  - 清理错误拼接残留：`rift-rail-error-station-missing` 行内重复脏串已移除。

- `RiftRail/locale/ja/informatron.cfg`
  - 新建日语版 Informatron 页面文案。

- `RiftRail/locale/ja/tips.cfg`
  - 新建日语版 Tips 文案。

- `doc/unused-locale-keys-2026-03-04.md`
  - 生成未使用本地化键扫描报告（用于清理决策与后续审查）。

## 2026-03-04（v0.11.9 开发中：索引命名可读性整理）

### 改动摘要
- 不改动任何传送逻辑，仅优化索引参数命名，降低“目标索引/回退索引”语义歧义。
- 保持调用链与行为完全一致，仅在函数签名和注释层面做可读性增强。
- `read_train_schedule_index(...)` 改为仅读取真实 `schedule.current`，不再按列车状态分支推断索引。

### 具体改动
- `RiftRail/scripts/teleport.lua`
  - `read_train_schedule_index(train)`：
    - 移除 `wait_station / on_the_path / wait_signal / arrive_*` 的状态分支。
    - 统一返回真实时刻表指针 `train.schedule.current`。
    - 增加记录表与索引范围校验，异常时返回 `nil`。
  - `restore_train_state(train, portaldata, apply_speed, ...)`：
    - 参数名由 `target_index` 调整为 `preferred_index`。
    - 对应注释同步更新为“优先恢复索引”。
    - 函数内部变量计算保持不变：仍为“优先参数，其次 `saved_schedule_index`”。

## 2026-03-04（v0.11.9 开发中：传送缓存与出口速度维护重构）

### 改动摘要
- 删除传送结束阶段的两处冗余/误导清理：`exit_portaldata.entry_car` 与 `exit_portaldata.cached_geo`。
- 保留 `cached_place_query` 的运行期复用，并在建筑克隆后强制失效，避免深拷贝带入旧坐标查询参数。
- 修正文案注释，明确 `cached_place_query` 只在当前门坐标/朝向下有效。
- 修正 `entry_portaldata.exit_car` 的注释语义，明确其用于入口侧流程状态判定。
- 将出口速度函数改为卫语句结构并重命名为 `maintain_exit_speed`，同时移除每 60 tick 的调试打印。

### 具体改动
- `RiftRail/scripts/teleport.lua`
  - `finalize_sequence(...)`：
    - 删除 `exit_portaldata.entry_car = nil`（exit 侧无该活跃字段）。
    - 删除 `exit_portaldata.cached_geo = nil`（几何缓存由懒加载维护）。
    - 更新 `entry_portaldata.exit_car` 清理注释，明确是“上一节已生成替身”状态标记。
  - `process_transfer_step(...)`：
    - 更新 `cached_place_query` 初始化注释，明确克隆/重建后需失效再懒加载。
    - 更新 `entry_portaldata.exit_car = new_car` 注释，去除“没什么用”的误导描述。
    - 将出口速度缓存注释中的函数名更新为 `maintain_exit_speed`。
  - `sync_momentum(...)` -> `maintain_exit_speed(...)`：
    - 重构为卫语句，提前返回无效 `exit_portal/car/train` 分支，减少嵌套。
    - 删除每 60 tick 调试日志打印，保留核心速度维护逻辑。

- `RiftRail/scripts/builder.lua`
  - `on_cloned(event)`：
    - 在重建 `cached_spawn_pos/cached_check_area` 后，新增 `new_data.cached_place_query = nil`，防止深拷贝脏缓存。

## 2026-03-02（v0.11.8：多出口路由逻辑更新，加入入口信号与缓存优先）

### 改动摘要
- 多出口路由优先级更新为：列车时刻表信号 > 入口电路信号 > 默认出口（默认失效则首个可用出口）。
- 在碰撞触发时预选出口并写入缓存，等待阶段优先命中缓存，缓存失效时再重选。
- 新增无效 `go-to-id` 提示（列车信号 / 入口信号），用于提示“信号存在但目标出口无效”的情况。

### 具体改动
- `RiftRail/scripts/teleport.lua`
  - 新增 `get_entry_circuit_go_to_id(entry_portaldata)`：读取入口侧电路网络 `riftrail-go-to-id`。
  - 新增 `resolve_valid_target(entry_portaldata, target_id)`：统一目标出口有效性校验。
  - 更新 `select_target_exit(entry_portaldata)`：
    - 单出口快速通道保持不变；
    - 多出口场景先尝试缓存 `waiting_target_exit_id`；
    - 列车信号无效时继续尝试入口信号；
    - 信号均无效时回退默认出口/首个可用出口。
  - 更新 `Teleport.on_collider_died(event)`：入队时预选出口并缓存。
  - 更新 `process_waiting_logic(portaldata)`：每 tick 优先使用缓存目标，失效后重选并回写缓存。
  - 更新 `initialize_teleport_session(...)`：会话启动后清理 `waiting_target_exit_id`。

- `RiftRail/locale/zh-CN/strings.cfg`
  - 新增：
    - `rift-rail-error-invalid-go-to-id-train`
    - `rift-rail-error-invalid-go-to-id-entry`

- `RiftRail/locale/en/strings.cfg`
  - 新增：
    - `rift-rail-error-invalid-go-to-id-train`
    - `rift-rail-error-invalid-go-to-id-entry`

## 2026-03-02（v0.11.8：路由文案与高级用法说明同步）

### 改动摘要
- 将路由说明统一为实际实现：列车时刻表信号 > 入口电路信号 > 默认出口（默认不可用则首个可用出口）。
- 更新高级用法中的路由优先级描述，移除旧的 LTN 自动路由描述。

### 具体改动
- `RiftRail/locale/zh-CN/informatron.cfg`
  - 更新 `page_routing_text_2` 路由优先级与兜底行为。

- `RiftRail/locale/en/informatron.cfg`
  - 更新 `page_routing_text_2` 路由优先级与兜底行为。

- `RiftRail/locale/zh-CN/tips.cfg`
  - 更新 `item-description-advanced` 的路由优先级说明。

- `RiftRail/locale/en/tips.cfg`
  - 更新 `item-description-advanced` 的路由优先级说明。

## 2026-03-01（AW桥接参数改为实体对象）

### 改动摘要
- 将 AW 兼容桥接调用参数从 `unit_number` 改为 `LuaEntity`，以支持 AW 侧完整更新反向映射。

### 具体改动
- `scripts/compat/aw.lua`
  - `remote.call("AssemblyWagon", "transfer_binding", ...)` 参数由
    - `old_car.unit_number, new_car.unit_number`
    改为
    - `old_car, new_car`。

### 备注
- 该调整用于配合 AssemblyWagon 新增的 `transfer_binding(old_wagon, new_wagon)` 接口实现。

## 2026-03-01（Informatron兼容文件归档到compat）

### 改动摘要
- 将 Informatron 适配脚本移动到 `scripts/compat` 目录，统一兼容模块结构。
- 同步更新 `control.lua` 中的加载路径，保持运行逻辑不变。

### 具体改动
- `scripts/compat/informatron.lua`
  - 由原 `scripts/informatron.lua` 迁移而来（仅路径调整）。

- `control.lua`
  - `require("scripts.informatron")` 改为 `require("scripts.compat.informatron")`。

## 2026-03-01（compat目录重构 + AW兼容接入）

### 改动摘要
- 在 `scripts` 下建立 `compat` 目录，统一管理兼容模块。
- 将 LTN 兼容模块迁移到 `scripts/compat/ltn.lua`。
- 新增 AssemblyWagon 兼容模块 `scripts/compat/aw.lua`，用于车厢传送后 old/new 映射桥接。
- 在传送主流程中加入单点兼容调用，统一覆盖 clone/create 两种创建路径。

### 具体改动
- `scripts/compat/ltn.lua`
  - 由原 `scripts/ltn_compat.lua` 迁移而来（文件路径调整）。

- `scripts/compat/aw.lua`（新文件）
  - 新增 `AW.init(deps)`：缓存 `script.active_mods["AssemblyWagon"]` 状态。
  - 新增 `AW.on_car_replaced(old_car, new_car)`：
    - 仅在 AssemblyWagon 已启用且 `old/new` 均为 `assembly-wagon` 时执行。
    - 检查 `remote.interfaces["AssemblyWagon"].transfer_binding` 是否存在。
    - 使用 `pcall(remote.call, ...)` 调用接口并在调试模式下记录失败日志。

- `control.lua`
  - `require("scripts.ltn_compat")` 改为 `require("scripts.compat.ltn")`。
  - 新增 `local AWCompat = require("scripts.compat.aw")`。
  - 启动时调用 `AWCompat.init({ log_debug = log_debug })`。
  - 向 `Teleport.init(...)` 注入 `AwCompat = AWCompat`。

- `scripts/teleport.lua`
  - 新增依赖字段 `AwCompat` 并在 `Teleport.init(deps)` 中接收。
  - 在 `new_car` 创建成功后、`car.destroy()` 前调用：
    - `AwCompat.on_car_replaced(car, new_car)`
  - 该调用点统一适配 clone/create 路径，无需在多处分支重复判断。

### 备注
- 目前仅完成 RiftRail 侧兼容桥接；AssemblyWagon 侧 `remote interface` 后续再接。
