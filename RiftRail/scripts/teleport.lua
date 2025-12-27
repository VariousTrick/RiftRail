-- scripts/teleport.lua
-- 【Rift Rail - 传送核心模块】
-- 功能：处理火车传送的完整运行时逻辑 (基于传送门 Mod v1.1 适配)
-- 包含：堵车检测、内容转移、引导车机制、Cybersyn/SE 兼容

local Teleport = {}

-- =================================================================================
-- 依赖与日志系统
-- =================================================================================
local State = nil
local Util = nil
local Schedule = nil

-- 1. 定义一个空的日志函数占位符
local log_debug = function() end

-- 2. 在 init 函数中接收来自 control.lua 的 log_debug 函数
function Teleport.init(deps)
    State = deps.State
    Util = deps.Util
    Schedule = deps.Schedule
    if deps.log_debug then
        log_debug = deps.log_debug
    end
end

-- 3. 定义本模块专属的、带 if 判断的日志包装器
local function log_tp(msg)
    if RiftRail.DEBUG_MODE_ENABLED then
        log_debug("[RiftRail:Teleport] " .. msg) -- 调用全局 log_debug, 并加上自己的模块名
    end
end

-- SE 事件 ID (初始化时获取)
local SE_TELEPORT_STARTED_EVENT_ID = nil
local SE_TELEPORT_FINISHED_EVENT_ID = nil

-- 【Rift Rail 专用几何参数】
-- 修正版：将偏移量调整为偶数 (0)，对准铁轨中心，防止生成失败
-- 基于 "车厢生成在建筑中心 (y=0)" 的设定
local GEOMETRY = {
    [0] = { -- North (出口在下方 Y+)
        spawn_offset = { x = 0, y = 0 },
        direction = defines.direction.south,
        -- 坐标反转：从 -4.0 (后方) 改为 4.0 (前方，即出口方向)
        -- 这样 Leader Train 会生成在车厢和下方红绿灯(y=5)之间
        leadertrain_offset = { x = 0, y = 4.0 },
        velocity_mult = { x = 0, y = 1 },
    },
    [4] = { -- East (出口在左方 X-)
        spawn_offset = { x = 0, y = 0 },
        direction = defines.direction.west,
        -- 坐标反转：从 4.0 (后方) 改为 -4.0 (前方，即出口方向)
        -- 这样 Leader Train 会生成在车厢和左侧红绿灯(x=-5)之间
        leadertrain_offset = { x = -4.0, y = 0 },
        velocity_mult = { x = -1, y = 0 },
    },
    [8] = { -- South (出口在上方 Y-)
        spawn_offset = { x = 0, y = 0 },
        direction = defines.direction.north,
        -- 坐标反转：从 4.0 (后方) 改为 -4.0 (前方，即出口方向)
        -- 这样 Leader Train 会生成在车厢和上方红绿灯(y=-5)之间
        leadertrain_offset = { x = 0, y = -4.0 },
        velocity_mult = { x = 0, y = -1 },
    },
    [12] = { -- West (出口在右方 X+)
        spawn_offset = { x = 0, y = 0 },
        direction = defines.direction.east,
        -- 坐标反转：从 -4.0 (后方) 改为 4.0 (前方，即出口方向)
        -- 这样 Leader Train 会生成在车厢和右侧红绿灯(x=5)之间
        leadertrain_offset = { x = 4.0, y = 0 },
        velocity_mult = { x = 1, y = 0 },
    },
}

-- =================================================================================
-- 活跃列表管理辅助函数 (GC 优化)
-- =================================================================================

-- 添加到活跃列表
-- 【性能重构】使用二分查找插入，替换 table.sort
local function add_to_active(struct)
    if not struct or not struct.unit_number then
        return
    end

    if not storage.active_teleporters then
        storage.active_teleporters = {}
    end
    if not storage.active_teleporter_list then
        storage.active_teleporter_list = {}
    end

    if storage.active_teleporters[struct.unit_number] then
        return
    end

    storage.active_teleporters[struct.unit_number] = struct
    local list = storage.active_teleporter_list
    local unit_number = struct.unit_number

    -- 二分查找确定插入位置
    local low, high = 1, #list
    local pos = #list + 1
    while low <= high do
        local mid = math.floor((low + high) / 2)
        if list[mid].unit_number > unit_number then
            pos = mid
            high = mid - 1
        else
            low = mid + 1
        end
    end
    table.insert(list, pos, struct)
end

-- 从活跃列表移除
-- 优化移除逻辑
local function remove_from_active(struct)
    if not struct or not struct.unit_number then
        return
    end
    if not storage.active_teleporters or not storage.active_teleporters[struct.unit_number] then
        return
    end

    storage.active_teleporters[struct.unit_number] = nil
    local list = storage.active_teleporter_list
    local unit_number = struct.unit_number

    -- 二分查找确定移除位置
    local low, high = 1, #list
    while low <= high do
        local mid = math.floor((low + high) / 2)
        local mid_val = list[mid].unit_number
        if mid_val == unit_number then
            table.remove(list, mid)
            return
        elseif mid_val < unit_number then
            low = mid + 1
        else
            high = mid - 1
        end
    end
end

-- 辅助函数：从子实体中获取真实的车站名称 (带图标)
local function get_real_station_name(struct)
    -- 适配 children 结构 {entity=..., relative_pos=...}
    if struct.children then
        for _, child_data in pairs(struct.children) do
            local child = child_data.entity
            if child and child.valid and child.name == "rift-rail-station" then
                return child.backer_name
            end
        end
    end
    return struct.name
end

-- 记录/恢复正在查看列车 GUI 的玩家列表（兼容 train 和 entity 打开方式）
local function collect_gui_watchers(train_id)
    local res = {}
    if not train_id then
        return res
    end
    for _, p in pairs(game.players) do
        if p and p.valid then
            local opened = p.opened
            if opened then
                local gt = p.opened_gui_type
                if gt == defines.gui_type.train or gt == defines.gui_type.entity then
                    local typ = opened.object_name
                    local watching = (typ == "LuaTrain" and opened.id == train_id) or (typ == "LuaEntity" and opened.train and opened.train.id == train_id)
                    if watching then
                        res[#res + 1] = p.index
                    end
                end
            end
        end
    end
    return res
end

local function reopen_train_gui(watchers, train)
    if not watchers or #watchers == 0 then
        return 0
    end
    if not (train and train.valid) then
        return 0
    end
    local stock = train.front_stock or train.back_stock
    if not (stock and stock.valid) then
        return 0
    end
    local count = 0
    for _, idx in ipairs(watchers) do
        local player = game.players[idx]
        if player and player.valid then
            player.opened = stock
            count = count + 1
        end
    end
    return count
end

-- =================================================================================
-- 速度方向计算函数 (基于铁轨端点距离)
-- =================================================================================
--- 计算列车相对于一个参考点的逻辑方向。
-- @param train (LuaTrain) 要计算的列车。
-- @param origin_pos (Position) 参考点坐标 (通常是传送门出口)。
-- @return (number) 1 代表逻辑正向 (Front更远), -1 代表逻辑反向 (Back更远)。
local function calculate_speed_sign(train, portal_struct)
    -- 安全检查：如果输入无效，默认返回正向
    if not (train and train.valid and portal_struct) then
        return 1
    end

    -- [核心逻辑] 使用缓存，并为旧存档/克隆体提供懒加载
    local origin_pos = portal_struct.blocker_position

    -- 如果缓存不存在 (旧存档)，则计算一次并写回
    if not origin_pos then
        local shell = portal_struct.shell
        -- 再次安全检查，防止 shell 失效
        if not (shell and shell.valid) then
            return 1
        end

        local shell_pos = shell.position
        local shell_dir = shell.direction
        local blocker_relative_pos = { x = 0, y = -6 }

        local rotated_offset
        if shell_dir == 0 then
            rotated_offset = { x = blocker_relative_pos.x, y = blocker_relative_pos.y }
        elseif shell_dir == 4 then
            rotated_offset = { x = -blocker_relative_pos.y, y = blocker_relative_pos.x }
        elseif shell_dir == 8 then
            rotated_offset = { x = -blocker_relative_pos.x, y = -blocker_relative_pos.y }
        else
            rotated_offset = { x = blocker_relative_pos.y, y = -blocker_relative_pos.x }
        end

        origin_pos = { x = shell_pos.x + rotated_offset.x, y = shell_pos.y + rotated_offset.y }
        portal_struct.blocker_position = origin_pos -- 将计算结果写回缓存
    end

    local rail_front = train.front_end and train.front_end.rail
    local rail_back = train.back_end and train.back_end.rail

    if rail_front and rail_back then
        -- 计算距离平方 (dx^2 + dy^2), 避免开方运算
        local df_x = rail_front.position.x - origin_pos.x
        local df_y = rail_front.position.y - origin_pos.y
        local dist_sq_f = (df_x * df_x) + (df_y * df_y)

        local db_x = rail_back.position.x - origin_pos.x
        local db_y = rail_back.position.y - origin_pos.y
        local dist_sq_b = (db_x * db_x) + (db_y * db_y)

        -- [最终决策]
        -- API定义: 正速度驶向 front_end, 负速度驶向 back_end
        -- 如果后端(Back)离参考点更远，说明列车需要向后端行驶才能“远离”，即需要负速度。
        if dist_sq_b > dist_sq_f then
            return -1 -- 后端更远 -> 逻辑反向
        end
        -- 在所有其他情况下 (前端更远，或两端距离相等)，都判定为逻辑正向。
        -- 这可以完美处理单节车厢(距离相等)时需要正向启动的问题。
        return 1
    end

    -- 异常情况 (无法获取铁轨端点)，返回默认正向
    return 1
end

-- 专门用于在 on_load 中初始化的 SE 事件获取函数
function Teleport.init_se_events()
    -- 确保 on_load 时也能拿到最新的日志函数
    if script.active_mods["space-exploration"] and remote.interfaces["space-exploration"] then
        log_tp("Teleport: 正在尝试从 SE 获取传送事件 ID (on_load)...")
        local success, event_started = pcall(remote.call, "space-exploration", "get_on_train_teleport_started_event")
        local _, event_finished = pcall(remote.call, "space-exploration", "get_on_train_teleport_finished_event")

        if success and event_started then
            SE_TELEPORT_STARTED_EVENT_ID = event_started
            SE_TELEPORT_FINISHED_EVENT_ID = event_finished
            log_tp("Teleport: SE 传送事件 ID 获取成功！")
        else
            log_tp("Teleport: 警告 - 无法从 SE 获取传送事件 ID。")
        end
    end
end

-- =================================================================================
-- Cybersyn 无 SE 模式下的数据迁移与时刻表修复
-- =================================================================================
local function handle_cybersyn_migration(old_train_id, new_train, snapshot)
    -- 如果装了 SE，这步不需要做，直接退出
    if script.active_mods["space-exploration"] then
        return
    end
    if not (snapshot and new_train and new_train.valid) then
        return
    end

    if remote.interfaces["cybersyn"] and remote.interfaces["cybersyn"]["write_global"] then
        -- 1. 更新实体引用
        snapshot.entity = new_train

        -- 2. 注入数据到新 ID
        remote.call("cybersyn", "write_global", snapshot, "trains", new_train.id)

        -- 3. 清除旧 ID 数据 (Cybersyn 会自动清，但手动清更安全)
        remote.call("cybersyn", "write_global", nil, "trains", old_train_id)

        -- 4. 清除 "正在传送" 标签
        remote.call("cybersyn", "write_global", nil, "trains", new_train.id, "se_is_being_teleported")
    end

    -- 5. 时刻表 Rail 补全 (修复异地表 Rail 指向问题)
    local schedule = new_train.schedule
    if schedule and schedule.records then
        local records = schedule.records
        local current_index = schedule.current
        local current_record = records[current_index]

        -- 只有当下一站是真实操作站 (P/R/Depot) 且没有 Rail 时才尝试补全
        if current_record and current_record.station and not current_record.rail then
            local target_id = nil
            -- 状态映射: 1=TO_P, 3=TO_R, 5=TO_D
            if snapshot.status == 1 then
                target_id = snapshot.p_station_id
            end
            if snapshot.status == 3 then
                target_id = snapshot.r_station_id
            end
            if snapshot.status == 5 or snapshot.status == 6 then
                target_id = snapshot.depot_id
            end

            if target_id then
                local table_name = (snapshot.status == 5 or snapshot.status == 6) and "depots" or "stations"
                local st_data = remote.call("cybersyn", "read_global", table_name, target_id)

                -- 如果目标站在当前地表，插入 Rail 导航点
                if st_data and st_data.entity_stop and st_data.entity_stop.valid and st_data.entity_stop.surface == new_train.front_stock.surface then
                    table.insert(records, current_index, {
                        rail = st_data.entity_stop.connected_rail,
                        rail_direction = st_data.entity_stop.connected_rail_direction,
                        temporary = true,
                        wait_conditions = { { type = "time", ticks = 1 } },
                    })
                    schedule.records = records
                    new_train.schedule = schedule
                end
            end
        end
    end
end

-- =================================================================================
-- 核心传送逻辑
-- =================================================================================

-- 结束传送：清理状态，恢复数据
local function finish_teleport(entry_struct, exit_struct)
    if RiftRail.DEBUG_MODE_ENABLED then
        log_tp("传送结束: 清理状态 (入口ID: " .. entry_struct.id .. ", 出口ID: " .. exit_struct.id .. ")")
    end

    -- 1. 直接炸掉引导车
    if exit_struct.leadertrain and exit_struct.leadertrain.valid then
        exit_struct.leadertrain.destroy()
        exit_struct.leadertrain = nil
    end

    -- 安全获取 train 对象，防止 carriage_ahead 已销毁(invalid)时访问 .train 导致崩溃
    local final_train = nil
    if exit_struct.carriage_ahead and exit_struct.carriage_ahead.valid then
        final_train = exit_struct.carriage_ahead.train
    else
        log_tp("警告: finish_teleport 时出口车厢无效或丢失，跳过列车恢复逻辑。")
    end

    if final_train and final_train.valid then
        -- 先恢复时刻表索引，后恢复模式
        -- 注意：go_to_station 会强制设置列车为自动模式，所以必须先调用 go_to_station
        -- 然后立即恢复 manual_mode，这样恢复的值才不会被覆盖
        if exit_struct.saved_schedule_index then
            final_train.go_to_station(exit_struct.saved_schedule_index)
        end

        -- 2. 恢复原始模式
        -- go_to_station 已经把列车改成自动，现在恢复到之前的状态
        final_train.manual_mode = exit_struct.saved_manual_mode or false

        -- 3. 恢复速度 (已重构为距离比对法)
        local raw_speed = exit_struct.final_train_speed or exit_struct.saved_speed or 0
        local speed_mag = math.abs(raw_speed)
        -- 调用新函数，以出口传送门为参考点
        local required_sign = calculate_speed_sign(final_train, exit_struct)
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("【Finish】最终速度判定: ReqSign=" .. required_sign .. " | SpeedMag=" .. speed_mag)
        end
        final_train.speed = speed_mag * required_sign

        -- 数据恢复 (注入灵魂)
        if exit_struct.old_train_id and exit_struct.cybersyn_snapshot then
            handle_cybersyn_migration(exit_struct.old_train_id, final_train, exit_struct.cybersyn_snapshot)
            exit_struct.cybersyn_snapshot = nil
        end

        -- 4. SE 事件触发 (Finished)
        if SE_TELEPORT_FINISHED_EVENT_ID and exit_struct.old_train_id then
            if RiftRail.DEBUG_MODE_ENABLED then
                log_tp("【DEBUG】准备触发 FINISHED 事件: new_train_id = " .. tostring(final_train.id) .. ", old_train_id = " .. tostring(exit_struct.old_train_id))
                log_tp("SE 兼容: 触发 on_train_teleport_finished")
            end
            script.raise_event(SE_TELEPORT_FINISHED_EVENT_ID, {
                train = final_train,
                old_train_id = exit_struct.old_train_id,
                old_train_id_1 = exit_struct.old_train_id,
                old_surface_index = entry_struct.surface.index,
                teleporter = exit_struct.shell,
            })
        end

        -- 恢复被记录的 GUI 观察者到最终列车
        local restored = reopen_train_gui(exit_struct.gui_watchers, final_train)
        exit_struct.gui_watchers = nil
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("恢复 GUI 观察者: " .. tostring(restored) .. " 人, final_train_id=" .. tostring(final_train.id))
        end
    end

    -- 5. 重置状态变量
    entry_struct.carriage_behind = nil
    entry_struct.carriage_ahead = nil
    exit_struct.carriage_behind = nil
    exit_struct.carriage_ahead = nil
    exit_struct.old_train_id = nil
    exit_struct.cached_geo = nil

    -- 6. 【关键】标记需要重建入口碰撞器
    -- 我们不在这里直接创建，而是交给 on_tick 去计算正确的坐标并创建
    if entry_struct.shell and entry_struct.shell.valid then
        entry_struct.collider_needs_rebuild = true

        -- [保险措施] 确保它在活跃列表中，这样 on_tick 才会去处理它
        -- 使用辅助函数
        add_to_active(entry_struct)
    end
end

-- 传送下一节车厢 (由 on_tick 驱动)
function Teleport.teleport_next(entry_struct, exit_struct)
    -- 必须在 entry_struct.carriage_ahead 被后续逻辑更新之前记录下来
    local is_first_carriage = (entry_struct.carriage_ahead == nil)

    -- 安全检查
    if not (exit_struct and exit_struct.shell and exit_struct.shell.valid) then
        log_tp("错误: 出口失效，传送中断。")
        finish_teleport(entry_struct, entry_struct) -- 自身清理
        return
    end

    -- 检查入口车厢
    local carriage = entry_struct.carriage_behind
    if not (carriage and carriage.valid) then
        log_tp("入口车厢失效或丢失，结束传送。")
        finish_teleport(entry_struct, exit_struct)
        return
    end

    -- 检查出口是否堵塞
    -- 优先从缓存读取，如果缓存不存在 (如读档后)，则现场计算一次并存入缓存
    local geo = exit_struct.cached_geo
    if not geo then
        -- 如果 geo 是 nil，说明缓存未命中，立即计算并写入
        geo = GEOMETRY[exit_struct.shell.direction] or GEOMETRY[0]
        exit_struct.cached_geo = geo
    end
    local spawn_pos = Util.vectors_add(exit_struct.shell.position, geo.spawn_offset)

    -- 动态生成出口检测区域 (宽度修正为2)
    local check_area = {}
    local dir = exit_struct.shell.direction

    if dir == 0 then -- North (出口在下)
        check_area = {
            left_top = { x = spawn_pos.x - 1, y = spawn_pos.y },
            right_bottom = { x = spawn_pos.x + 1, y = spawn_pos.y + 10 },
        }
    elseif dir == 8 then -- South (出口在上)
        check_area = {
            left_top = { x = spawn_pos.x - 1, y = spawn_pos.y - 10 },
            right_bottom = { x = spawn_pos.x + 1, y = spawn_pos.y },
        }
    elseif dir == 4 then -- East (出口在左)
        check_area = {
            left_top = { x = spawn_pos.x - 10, y = spawn_pos.y - 1 },
            right_bottom = { x = spawn_pos.x, y = spawn_pos.y + 1 },
        }
    elseif dir == 12 then -- West (出口在右)
        check_area = {
            left_top = { x = spawn_pos.x, y = spawn_pos.y - 1 },
            right_bottom = { x = spawn_pos.x + 10, y = spawn_pos.y + 1 },
        }
    end

    -- 如果前面有车 (carriage_ahead)，说明正在传送中，不需要检查堵塞 (我们是接在它后面的)
    -- 只有当 carriage_ahead 为空 (第一节) 时才检查堵塞
    local is_clear = true
    if not entry_struct.carriage_ahead then
        local count = exit_struct.surface.count_entities_filtered({
            area = check_area,
            type = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" },
        })
        if count > 0 then
            is_clear = false
        end
    end

    -- 堵塞处理
    if not is_clear then
        log_tp("出口堵塞，暂停传送...")
        if carriage.train and not carriage.train.manual_mode then
            local sched = carriage.train.get_schedule()
            if not sched then
                return
            end

            local station_entity = nil
            if entry_struct.children then
                for _, child_data in pairs(entry_struct.children) do
                    -- 从子数据表中取出 entity 对象，因为 children 存的是 {entity=..., ...}
                    local child = child_data.entity
                    if child and child.valid and child.name == "rift-rail-station" then
                        station_entity = child
                        break
                    end
                end
            end

            if not (station_entity and station_entity.connected_rail) then
                return
            end

            local current_record = sched.get_record({ schedule_index = sched.current })

            if not (current_record and current_record.rail and current_record.rail == station_entity.connected_rail) then
                -- 将所有参数合并到一个表中直接传递
                sched.add_record({
                    -- 描述站点本身的字段
                    rail = station_entity.connected_rail,
                    temporary = true,
                    wait_conditions = { { type = "time", ticks = 1111111 } },

                    -- 描述插入位置的字段
                    index = { schedule_index = sched.current + 1 },
                })
                carriage.train.go_to_station(sched.current + 1)

                log_tp("已插入临时路障站点。")
            end
        end
        return
    end

    -- 动态拼接检测
    -- 询问引擎：当前位置是否已经空出来，可以放置新车厢了？
    -- 如果前车还没被引导车拉远，这里会返回 false
    local can_place = exit_struct.surface.can_place_entity({
        name = carriage.name,
        position = spawn_pos,
        direction = geo.direction,
        force = carriage.force,
    })

    if not can_place then
        return -- 位置没空出来，跳过本次循环，等待下一帧
    end

    -- 开始传送当前车厢
    if RiftRail.DEBUG_MODE_ENABLED then
        log_tp("正在传送车厢: " .. carriage.name)
    end

    -- 第一节车时记录正在查看该列车 GUI 的玩家
    if is_first_carriage and carriage.train then
        exit_struct.gui_watchers = collect_gui_watchers(carriage.train.id)
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("记录 GUI 观察者: " .. tostring(#exit_struct.gui_watchers) .. " 人, old_train_id=" .. tostring(carriage.train.id))
        end
    end

    -- 获取下一节车 (用于更新循环)
    local next_carriage = carriage.get_connected_rolling_stock(defines.rail_direction.front)
    if next_carriage == carriage then
        next_carriage = nil
    end -- 防止环形误判
    -- 简单查找另一端
    if not next_carriage then
        next_carriage = carriage.get_connected_rolling_stock(defines.rail_direction.back)
    end
    -- 排除掉刚刚传送过去的那节 (entry_struct.carriage_ahead 记录的是上一节在新表面的替身，这里我们需要在旧表面找)
    -- 此处简化逻辑：因为是单向移除，旧车厢会被销毁，所以 get_connected 应该只能找到还没传的

    -- 保存第一节车的数据 (用于 Cybersyn / 恢复)
    if not entry_struct.carriage_ahead then
        exit_struct.saved_manual_mode = carriage.train.manual_mode
        exit_struct.saved_speed = carriage.train.speed
        exit_struct.old_train_id = carriage.train.id

        -- 免死金牌 (无条件生效)
        if remote.interfaces["cybersyn"] then
            -- 打标签：告诉 Cybersyn 别删
            remote.call("cybersyn", "write_global", true, "trains", carriage.train.id, "se_is_being_teleported")

            -- 只有在无 SE 时才需要存快照
            if not script.active_mods["space-exploration"] then
                local _, snap = pcall(remote.call, "cybersyn", "read_global", "trains", carriage.train.id)
                if snap then
                    exit_struct.cybersyn_snapshot = snap
                end
            end
        end

        -- [SE] Started 事件
        if SE_TELEPORT_STARTED_EVENT_ID then
            if RiftRail.DEBUG_MODE_ENABLED then
                log_tp("【DEBUG】准备触发 STARTED 事件: old_train_id = " .. tostring(carriage.train.id))
            end
            script.raise_event(SE_TELEPORT_STARTED_EVENT_ID, {
                train = carriage.train,
                old_train_id_1 = carriage.train.id,
                old_surface_index = entry_struct.surface.index,
                teleporter = entry_struct.shell,
            })
        end
    end

    -- 计算车厢生成朝向 (纯 Orientation 版)
    -- 1. 获取入口建筑的"深入向量"朝向 (转为 0.0-1.0)
    -- entry_struct.shell.direction 是 0, 4, 8, 12 (16向系统)
    local entry_shell_ori = entry_struct.shell.direction / 16.0

    -- 2. 获取车厢当前的绝对朝向 (0.0 - 1.0)
    local carriage_ori = carriage.orientation

    -- 3. 计算角度差，判断是否"顺向" (头朝死胡同)
    local diff = math.abs(carriage_ori - entry_shell_ori)
    if diff > 0.5 then
        diff = 1.0 - diff
    end
    local is_nose_in = diff < 0.125
    if RiftRail.DEBUG_MODE_ENABLED then
        log_tp("方向计算: 车厢ori=" .. carriage_ori .. ", 建筑ori=" .. entry_shell_ori .. ", 判定=" .. (is_nose_in and "顺向" or "逆向"))
    end
    -- 1. 提前计算目标朝向 (target_ori)
    local exit_base_ori = geo.direction / 16.0
    local target_ori = exit_base_ori

    if not is_nose_in then
        -- 逆向进入 -> 逆向离开 (翻转 180 度)
        target_ori = (target_ori + 0.5) % 1.0
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("方向计算: 逆向翻转 (Ori " .. exit_base_ori .. " -> " .. target_ori .. ")")
        end
    else
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("方向计算: 顺向保持 (Ori " .. target_ori .. ")")
        end
    end

    -- 直接使用上面算好的 target_ori 进行生成
    -- 生成新车厢
    local new_carriage = exit_struct.surface.create_entity({
        name = carriage.name,
        position = spawn_pos,
        -- 不再使用 direction，改用 orientation
        -- 这样引擎会直接接受准确的角度，不再需要猜测是8向还是16向
        orientation = target_ori,
        force = carriage.force,
        quality = carriage.quality,
    })

    if not new_carriage then
        log_tp("严重错误: 无法在出口创建车厢！")
        finish_teleport(entry_struct, exit_struct)
        return
    end

    -- 转移内容 (调用 Util)
    Util.transfer_all_inventories(carriage, new_carriage)
    Util.transfer_fluids(carriage, new_carriage)
    Util.transfer_equipment_grid(carriage, new_carriage)
    new_carriage.health = carriage.health
    new_carriage.backer_name = carriage.backer_name or ""
    if carriage.color then
        new_carriage.color = carriage.color
    end

    -- 如果之前保存了进度，说明这是后续车厢，立刻把被重置的索引改回去
    if saved_ahead_index then
        new_carriage.train.go_to_station(saved_ahead_index)
    end

    -- 司机转移逻辑
    local driver = carriage.get_driver()
    if driver then
        carriage.set_driver(nil) -- 第一步：必须先从旧车“下车”，防止被留在入口

        if driver.object_name == "LuaPlayer" then
            -- 第二步：如果是玩家，直接 Set Driver
            -- 引擎会自动处理物理传送，且不会破坏远程驾驶的视点
            new_carriage.set_driver(driver)
        elseif driver.valid and driver.teleport then
            -- 第三步：如果是 NPC (如 AAI 矿车司机)，需要手动传送坐标
            driver.teleport(new_carriage.position, new_carriage.surface)
            new_carriage.set_driver(driver)
        end
    end

    -- 转移时刻表与保存索引
    if not entry_struct.carriage_ahead then
        -- 1. 获取带图标的真实站名 (解决比对失败问题)
        local real_station_name = get_real_station_name(entry_struct)
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("时刻表转移: 使用真实站名 '" .. real_station_name .. "' 进行比对")
        end
        -- 2. 转移时刻表
        Schedule.transfer_schedule(carriage.train, new_carriage.train, real_station_name)

        -- 关键修复: 在被引导车重置前，立刻备份正确的索引！
        if new_carriage.train and new_carriage.train.schedule then
            exit_struct.saved_schedule_index = new_carriage.train.schedule.current
        end
        -- 3. 保存新火车的时刻表索引 (解决重置问题)
        -- transfer_schedule 内部已经调用了 go_to_station，所以现在的 current 是正确的下一站

        -- [LTN] 在以下任一条件下执行本地重指派与临时站插入：
        --   1) 未安装 SE；或
        --   2) 安装了 SE 但未安装 se-ltn-glue（无第三方接管时需要我们兜底）。
        local need_local_ltn_reassign = remote.interfaces["logistic-train-network"] and exit_struct.old_train_id and (not script.active_mods["space-exploration"] or (script.active_mods["space-exploration"] and not script.active_mods["se-ltn-glue"]))

        if need_local_ltn_reassign then
            local ok, has_delivery = pcall(remote.call, "logistic-train-network", "reassign_delivery", exit_struct.old_train_id, new_carriage.train)
            if ok and has_delivery then
                local insert_index = remote.call("logistic-train-network", "get_or_create_next_temp_stop", new_carriage.train)
                if insert_index ~= nil then
                    local sched = new_carriage.train.get_schedule()
                    if sched and (sched.current > insert_index) then
                        sched.go_to_station(insert_index)
                    end
                end
                log_tp("LTN兼容: 已重指派交付并插入临时站（本地兜底）。")
            end
        end
    end

    -- 销毁旧车厢
    carriage.destroy()

    -- 更新链表指针
    entry_struct.carriage_ahead = new_carriage -- 记录刚传过去的这节 (虽然没什么用，但保持一致)
    exit_struct.carriage_ahead = new_carriage -- 记录出口的最前头 (用于拉动)

    -- 准备下一节
    -- =========================================================================
    -- 引导车 (Leader) 生成逻辑：只在第一节车时生成，且不再销毁
    -- =========================================================================

    -- 1. 如果是第一节车，生成引导车 (Leader)
    if is_first_carriage then
        -- 计算位于前方的引导车坐标 (leadertrain_offset 已改为前方)
        local leadertrain_pos = Util.vectors_add(exit_struct.shell.position, geo.leadertrain_offset)
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("正在创建引导车 (Leader)... 坐标偏移: x=" .. geo.leadertrain_offset.x .. ", y=" .. geo.leadertrain_offset.y)
        end
        local leadertrain = exit_struct.surface.create_entity({
            name = "rift-rail-leader-train",
            position = leadertrain_pos,
            direction = geo.direction,
            force = new_carriage.force,
        })

        if leadertrain then
            leadertrain.destructible = false
            exit_struct.leadertrain = leadertrain
            if RiftRail.DEBUG_MODE_ENABLED then
                log_tp("引导车创建成功 ID: " .. leadertrain.unit_number)
            end
        else
            log_tp("错误：引导车创建失败！")
        end
    end

    -- =========================================================================
    -- 状态一致性维护
    -- 无论是否为第一节车，只要发生了拼接，引擎都会重置列车状态为手动。
    -- 所以必须对每一节新车都执行"先恢复进度，再恢复模式"的操作。
    -- =========================================================================
    if new_carriage.train and new_carriage.train.valid then
        -- 1. 恢复时刻表进度 (副作用：列车会被强制切换为自动模式)
        -- 注意：saved_schedule_index 是在第一节车处理时保存的，后续车厢直接复用
        if exit_struct.saved_schedule_index then
            new_carriage.train.go_to_station(exit_struct.saved_schedule_index)
        end

        -- 2. 恢复原始模式
        -- 如果原来是手动(true)，这里会把它切回手动 -> 引导车强拉
        -- 如果原来是自动(false)，这里保持自动 -> 遵守红绿灯
        new_carriage.train.manual_mode = exit_struct.saved_manual_mode or false
    end

    -- 2. 准备下一节 (简化版：只更新指针，不再生成引导车)
    if next_carriage and next_carriage.valid then
        entry_struct.carriage_behind = next_carriage
    else
        log_tp("最后一节车厢传送完毕。")
        -- 传送结束，调用 finish_teleport 进行收尾 (销毁引导车，恢复最终速度)
        finish_teleport(entry_struct, exit_struct)
    end
end

-- =================================================================================
-- 触发入口 (on_entity_died)
-- =================================================================================

function Teleport.on_collider_died(event)
    local entity = event.entity
    if not (entity and entity.valid) then
        return
    end

    local cause = event.cause -- 撞击者
    if cause and cause.name == "rift-rail-leader-train" then
        cause.destroy()
        game.print({ "messages.rift-rail-error-destroyed-leader" })
        return -- 销毁后直接结束，不执行任何传送逻辑
    end

    -- 1. 反查建筑数据
    -- 碰撞器是 children 的一部分，或者是位置重叠
    -- 为了快，假设我们能通过位置找到 Core/Shell
    -- 或者更简单：在 Builder.lua 里我们记录了 struct，我们可以遍历查找
    -- 但遍历太慢。更好的方法是：on_entity_died 传入的 entity 我们去 State 查
    -- 但 State.get_struct 主要是查 Shell 或 Core。
    -- 临时方案：搜索附近的 Shell
    local shells = entity.surface.find_entities_filtered({
        name = "rift-rail-entity",
        position = entity.position,
        radius = 3,
    })
    local shell = shells[1]
    if not shell then
        return
    end

    local struct = State.get_struct(shell)
    if not struct then
        return
    end

    -- 2. 模式检查
    -- 只有入口模式响应
    if struct.mode ~= "entry" then
        struct.collider_needs_rebuild = true
        return
    end

    -- 3. 配对检查
    if not struct.paired_to_id then
        game.print({ "messages.rift-rail-error-unpaired-or-collider" })
        struct.collider_needs_rebuild = true
        return
    end

    -- 4. 捕获火车
    local train = nil
    if event.cause and event.cause.train then
        train = event.cause.train
    else
        -- 搜索附近的火车
        local cars = entity.surface.find_entities_filtered({
            type = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" },
            position = entity.position,
            radius = 4,
        })
        if cars[1] then
            train = cars[1].train
        end
    end

    -- 逻辑分流与入队
    if not train then
        -- 情况 A: 没有火车（被虫子咬了，或者非火车撞击），只需重建
        struct.collider_needs_rebuild = true
    else
        -- 情况 B: 有火车，触发传送逻辑
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("触发传送检测: 入口ID=" .. struct.id .. ", 火车ID=" .. train.id)
        end

        -- 优先用撞击者作为第一节
        struct.carriage_behind = event.cause or train.front_stock
        struct.is_teleporting = true

        -- 预计算并缓存出口的几何数据，避免在 teleport_next 中重复计算
        -- 仅在触发传送时计算一次
        local exit_struct = State.get_struct_by_id(struct.paired_to_id)
        if exit_struct and exit_struct.shell and exit_struct.shell.valid then
            exit_struct.cached_geo = GEOMETRY[exit_struct.shell.direction] or GEOMETRY[0]
        end
    end

    -- 使用辅助函数添加到活跃列表
    add_to_active(struct)
end

-- =================================================================================
-- 持续动力 (每 tick 调用)
-- =================================================================================

function Teleport.manage_speed(struct)
    if not struct.paired_to_id then
        return
    end
    local exit_struct = State.get_struct_by_id(struct.paired_to_id)
    if not (exit_struct and exit_struct.shell and exit_struct.shell.valid) then
        return
    end

    local carriage_entry = struct.carriage_behind
    local carriage_exit = exit_struct.carriage_ahead

    if carriage_entry and carriage_entry.valid and carriage_exit and carriage_exit.valid then
        local train_entry = carriage_entry.train
        local train_exit = carriage_exit.train

        if train_entry and train_entry.valid and train_exit and train_exit.valid then
            -- 1. 强制入口手动模式 (保持不变，入口必须完全接管)
            if not train_entry.manual_mode then
                train_entry.manual_mode = true
            end

            -- 移除了强制出口火车 (train_exit) 手动模式的代码
            -- 允许出口火车保持自动模式，以便引擎能够检测红绿灯信号

            -- 2. 维持出口动力 (已重构为距离比对法)
            local target_speed = 0.5

            -- 使用新函数计算出口列车所需的速度方向
            -- 以出口传送门的位置为参考点
            local required_sign = calculate_speed_sign(train_exit, exit_struct)

            -- 每60tick(1秒)打印一次，监控计算结果
            if RiftRail.DEBUG_MODE_ENABLED then
                if game.tick % 60 == struct.unit_number % 60 then
                    log_tp("【Speed Exit】ReqSign=" .. required_sign .. " | TrainSpeed=" .. train_exit.speed)
                end
            end

            -- 应用速度前增加状态检查 (保持不变)
            local should_push = train_exit.manual_mode or (train_exit.state == defines.train_state.on_the_path) or (train_exit.state == defines.train_state.no_path)

            if should_push then
                -- 当速度过低或方向错误时，施加动力
                if math.abs(train_exit.speed) < target_speed or (train_exit.speed * required_sign < 0) then
                    train_exit.speed = target_speed * required_sign
                end
            end

            -- 关键修复: 在速度管理过程中持续保存出口列车速度
            -- 这样传送结束时使用的就是被维持的高速，而不是刚生成时的 0 速度
            exit_struct.final_train_speed = train_exit.speed

            -- 3. 入口动力 (已重构为距离比对法)
            -- 使用新函数计算入口列车的逻辑方向
            -- 以入口传送门的位置为参考点
            local entry_sign = calculate_speed_sign(train_entry, struct)

            -- [关键] 反转符号
            -- calculate_speed_sign 计算的是"远离"的方向 (1 或 -1)
            -- 对于入口，我们需要的是"靠近"，所以将结果乘以 -1
            local final_sign = entry_sign * -1

            -- 每60tick打印一次
            if RiftRail.DEBUG_MODE_ENABLED then
                if game.tick % 60 == struct.unit_number % 60 then
                    log_tp("【Speed Entry】CalcSign=" .. entry_sign .. " -> FinalSign=" .. final_sign)
                end
            end

            -- 应用与出口速度大小同步的、方向修正后的速度
            train_entry.speed = math.abs(train_exit.speed) * final_sign
        end
    end
end

-- =================================================================================
-- Tick 调度 (GC 优化版)
-- =================================================================================

function Teleport.on_tick(event)
    -- [优化] 直接遍历有序列表，不再每帧创建表和排序
    -- 使用倒序遍历，这样在循环中安全移除元素不会影响后续索引
    local list = storage.active_teleporter_list or {}

    for i = #list, 1, -1 do
        local struct = list[i]

        -- [保护] 确保数据还在 (防止被其他脚本意外删除)
        if struct and struct.shell and struct.shell.valid then
            -- A. 重建碰撞器逻辑
            if struct.collider_needs_rebuild then
                if struct.shell and struct.shell.valid then
                    -- 优先从缓存读取碰撞器坐标
                    local collider_pos = struct.collider_position

                    -- 如果缓存不存在 (旧存档/克隆体)，则现场计算一次并写回
                    if not collider_pos then
                        local shell = struct.shell
                        local shell_pos = shell.position
                        local shell_dir = shell.direction
                        local col_relative_pos = { x = 0, y = -2 }

                        local rotated_offset
                        if shell_dir == 0 then
                            rotated_offset = { x = col_relative_pos.x, y = col_relative_pos.y }
                        elseif shell_dir == 4 then
                            rotated_offset = { x = -col_relative_pos.y, y = col_relative_pos.x }
                        elseif shell_dir == 8 then
                            rotated_offset = { x = -col_relative_pos.x, y = -col_relative_pos.y }
                        else
                            rotated_offset = { x = col_relative_pos.y, y = -col_relative_pos.x }
                        end

                        collider_pos = { x = shell_pos.x + rotated_offset.x, y = shell_pos.y + rotated_offset.y }
                        struct.collider_position = collider_pos
                    end

                    -- 使用最终坐标创建实体
                    struct.surface.create_entity({
                        name = "rift-rail-collider",
                        position = collider_pos,
                        force = struct.shell.force,
                    })

                    -- 4. 标记完成
                    struct.collider_needs_rebuild = false
                end
            end

            -- B. 执行传送序列
            if struct.is_teleporting then
                -- 频率控制：每 4 tick 一次
                if event.tick % 4 == struct.unit_number % 4 then
                    if struct.carriage_behind then
                        -- [关键] 查找出口并将 exit_struct 作为参数传入
                        local exit_struct = State.get_struct_by_id(struct.paired_to_id)
                        Teleport.teleport_next(struct, exit_struct)
                    else
                        log_tp("传送序列正常结束，关闭状态。")
                        struct.is_teleporting = false
                    end
                end
            end

            -- C. 持续动力
            if struct.is_teleporting then
                Teleport.manage_speed(struct)
            end

            -- 出队检查 (使用辅助函数移除)
            if not struct.is_teleporting and not struct.collider_needs_rebuild then
                remove_from_active(struct)
            end
        else
            -- 结构无效，直接移除
            remove_from_active(struct)
        end
    end
end

return Teleport
