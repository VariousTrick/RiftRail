-- scripts/teleport.lua
-- 【Rift Rail - 传送核心模块】
-- 功能：处理火车传送的完整运行时逻辑 (基于传送门 Mod v1.1 适配)
-- 包含：堵车检测、内容转移、拖船机制、Cybersyn/SE 兼容

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
-- 定义不同建筑朝向下的：出口生成点、车厢朝向、拖船位置
-- 【Rift Rail 专用几何参数】
-- 修正版：将偏移量调整为偶数 (0)，对准铁轨中心，防止生成失败
-- 基于 "车厢生成在建筑中心 (y=0)" 的设定
local GEOMETRY = {
    [0] = { -- North
        spawn_offset = { x = 0, y = 0 },
        direction = defines.direction.south,
        tug_offset = { x = 0, y = -4.0 }, -- [修改] 拉近距离，从 -4.5 改为 -4.0
        velocity_mult = { x = 0, y = 1 },
    },
    [4] = { -- East
        spawn_offset = { x = 0, y = 0 },
        direction = defines.direction.west,
        tug_offset = { x = 4.0, y = 0 }, -- [修改] 4.5 -> 4.0
        velocity_mult = { x = -1, y = 0 },
    },
    [8] = { -- South
        spawn_offset = { x = 0, y = 0 },
        direction = defines.direction.north,
        tug_offset = { x = 0, y = 4.0 }, -- [修改] 4.5 -> 4.0
        velocity_mult = { x = 0, y = -1 },
    },
    [12] = { -- West
        spawn_offset = { x = 0, y = 0 },
        direction = defines.direction.east,
        tug_offset = { x = -4.0, y = 0 }, -- [修改] -4.5 -> -4.0
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
-- 【性能重构】优化移除逻辑
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

-- [新增] 辅助函数：从子实体中获取真实的车站名称 (带图标)
local function get_real_station_name(struct)
    -- 【修改】适配新的 children 结构 {entity=..., relative_pos=...}
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

-- [新增] 记录/恢复正在查看列车 GUI 的玩家列表（兼容 train 和 entity 打开方式）
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

-- [新增] 辅助函数：判断车厢在列车中的连接方向 (照搬 SE)
-- 返回 1 (正接) 或 -1 (反接)
local function get_train_forward_sign(carriage_a)
    local sign = 1
    if #carriage_a.train.carriages == 1 then
        return sign
    end

    -- 检查前连接点
    local carriage_b = carriage_a.get_connected_rolling_stock(defines.rail_direction.front)
    if not carriage_b then
        -- 如果前连接点没车，说明是用后连接点连的 (反接)
        carriage_b = carriage_a.get_connected_rolling_stock(defines.rail_direction.back)
        sign = -sign
    end

    -- 遍历列车确定相对顺序
    for _, carriage in pairs(carriage_a.train.carriages) do
        if carriage == carriage_b then
            return sign
        end
        if carriage == carriage_a then
            return -sign
        end
    end
    return sign
end

-- [新增] 专门用于在 on_load 中初始化的 SE 事件获取函数
function Teleport.init_se_events()
    -- [关键修复] 确保 on_load 时也能拿到最新的日志函数
    -- if injected_log_debug then log_debug = injected_log_debug end
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
-- -- [新增] Cybersyn 无 SE 模式下的数据迁移与时刻表修复
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
    log_tp("传送结束: 清理状态 (入口ID: " .. entry_struct.id .. ", 出口ID: " .. exit_struct.id .. ")")

    -- 1. 销毁最后的拖船 (带时刻表保护)
    local exit_train_speed_before_tug_death = nil
    if exit_struct.tug and exit_struct.tug.valid then
        -- [A] 存: 销毁拖船会导致时刻表重置，先保存当前索引和速度
        local saved_index_before_tug_death = nil
        -- 尝试通过 carriage_ahead 获取火车
        local train_ref = exit_struct.carriage_ahead and exit_struct.carriage_ahead.valid and exit_struct.carriage_ahead.train
        if train_ref and train_ref.valid then
            if train_ref.schedule then
                saved_index_before_tug_death = train_ref.schedule.current
            end
            -- [关键] 保存出口列车当前的实际速度（传送过程中已加速到的高速）
            exit_train_speed_before_tug_death = train_ref.speed
        end

        -- [B] 炸
        exit_struct.tug.destroy()
        exit_struct.tug = nil

        -- [C] 恢复
        if saved_index_before_tug_death and train_ref and train_ref.valid then
            train_ref.go_to_station(saved_index_before_tug_death)
        end
    end

    -- [修复] 安全获取 train 对象，防止 carriage_ahead 已销毁(invalid)时访问 .train 导致崩溃
    local final_train = nil
    if exit_struct.carriage_ahead and exit_struct.carriage_ahead.valid then
        final_train = exit_struct.carriage_ahead.train
    else
        log_tp("警告: finish_teleport 时出口车厢无效或丢失，跳过列车恢复逻辑。")
    end

    if final_train and final_train.valid then
        -- >>>>> [关键修复] 先恢复时刻表索引，后恢复 manual_mode >>>>>
        -- 注意：go_to_station 会强制设置列车为自动模式，所以必须先调用 go_to_station
        -- 然后立即恢复 manual_mode，这样恢复的值才不会被覆盖
        if exit_struct.saved_schedule_index then
            final_train.go_to_station(exit_struct.saved_schedule_index)
        end

        -- 1. 恢复原始模式
        -- go_to_station 已经把列车改成自动，现在恢复到之前的状态
        final_train.manual_mode = exit_struct.saved_manual_mode or false
        -- <<<<< [修复结束] <<<<<

        -- 2. 恢复速度：优先使用最后保存的出口实际速度，其次拖船销毁前速度，最后才用入口速度
        -- 这样可以保持传送过程中获得的动量，避免结束时骤降
        local restored_speed = exit_struct.final_train_speed or exit_train_speed_before_tug_death or exit_struct.saved_speed or 0
        final_train.speed = restored_speed

        -- >>>>> [新增] 数据恢复 (注入灵魂) >>>>>
        if exit_struct.old_train_id and exit_struct.cybersyn_snapshot then
            handle_cybersyn_migration(exit_struct.old_train_id, final_train, exit_struct.cybersyn_snapshot)
            exit_struct.cybersyn_snapshot = nil
        end
        -- <<<<< [新增结束] <<<<<

        -- 4. SE 事件触发 (Finished)
        if SE_TELEPORT_FINISHED_EVENT_ID and exit_struct.old_train_id then
            -- >>>>> [新增调试日志] >>>>>
            log_tp("【DEBUG】准备触发 FINISHED 事件: new_train_id = " .. tostring(final_train.id) .. ", old_train_id = " .. tostring(exit_struct.old_train_id))
            -- <<<<< [新增结束] <<<<<
            log_tp("SE 兼容: 触发 on_train_teleport_finished")
            script.raise_event(SE_TELEPORT_FINISHED_EVENT_ID, {
                train = final_train,
                old_train_id = exit_struct.old_train_id,
                old_train_id_1 = exit_struct.old_train_id,
                old_surface_index = entry_struct.surface.index,
                teleporter = exit_struct.shell,
            })
        end

        -- [新增] 恢复被记录的 GUI 观察者到最终列车
        local restored = reopen_train_gui(exit_struct.gui_watchers, final_train)
        exit_struct.gui_watchers = nil
        log_tp("恢复 GUI 观察者: " .. tostring(restored) .. " 人, final_train_id=" .. tostring(final_train.id))
    end

    -- 5. 重置状态变量
    entry_struct.carriage_behind = nil
    entry_struct.carriage_ahead = nil
    exit_struct.carriage_behind = nil
    exit_struct.carriage_ahead = nil
    exit_struct.old_train_id = nil

    -- 6. 【关键】标记需要重建入口碰撞器
    -- 我们不在这里直接创建，而是交给 on_tick 去计算正确的坐标并创建
    if entry_struct.shell and entry_struct.shell.valid then
        entry_struct.collider_needs_rebuild = true

        -- [保险措施] 确保它在活跃列表中，这样 on_tick 才会去处理它
        -- [修改] 使用辅助函数
        add_to_active(entry_struct)
    end
end

-- 传送下一节车厢 (由 on_tick 驱动)
function Teleport.teleport_next(entry_struct, exit_struct)
    -- [已删除] local exit_struct = State.get_struct_by_id(entry_struct.paired_to_id)

    -- >>>>> [新增] 在这里记录是否为第一节车 >>>>>
    -- 必须在 entry_struct.carriage_ahead 被后续逻辑更新之前记录下来
    local is_first_carriage = (entry_struct.carriage_ahead == nil)
    -- <<<<< [新增结束] <<<<<

    -- 安全检查 (保持不变)
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

    -- 检查出口是否堵塞 (照搬传送门逻辑)
    local geo = GEOMETRY[exit_struct.shell.direction] or GEOMETRY[0]
    local spawn_pos = Util.vectors_add(exit_struct.shell.position, geo.spawn_offset)

    -- >>>>> [修改] 动态生成出口检测区域 (宽度修正为2) >>>>>
    local check_area = {}
    local dir = exit_struct.shell.direction

    if dir == 0 then -- North (出口在下)
        check_area = {
            left_top = { x = spawn_pos.x - 1, y = spawn_pos.y },
            right_bottom = { x = spawn_pos.x + 1, y = spawn_pos.y + 8 },
        }
    elseif dir == 8 then -- South (出口在上)
        check_area = {
            left_top = { x = spawn_pos.x - 1, y = spawn_pos.y - 8 },
            right_bottom = { x = spawn_pos.x + 1, y = spawn_pos.y },
        }
    elseif dir == 4 then -- East (出口在左)
        check_area = {
            left_top = { x = spawn_pos.x - 8, y = spawn_pos.y - 1 },
            right_bottom = { x = spawn_pos.x, y = spawn_pos.y + 1 },
        }
    elseif dir == 12 then -- West (出口在右)
        check_area = {
            left_top = { x = spawn_pos.x, y = spawn_pos.y - 1 },
            right_bottom = { x = spawn_pos.x + 8, y = spawn_pos.y + 1 },
        }
    end
    -- <<<<< [修改结束] <<<<<

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

    -- 堵塞处理 (SE 方案 - API 调用完全修正版)
    if not is_clear then
        log_tp("出口堵塞，暂停传送...")
        if carriage.train and not carriage.train.manual_mode then
            local sched = carriage.train.get_schedule()
            if not sched then
                return
            end

            local station_entity = nil
            if entry_struct.children then
                for _, child in pairs(entry_struct.children) do
                    if child.valid and child.name == "rift-rail-station" then
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
                -- >>>>> [API 修正] 将所有参数合并到一个表中直接传递 >>>>>
                sched.add_record({
                    -- 描述站点本身的字段
                    rail = station_entity.connected_rail,
                    temporary = true,
                    wait_conditions = { { type = "time", ticks = 9999999 } },

                    -- 描述插入位置的字段
                    index = { schedule_index = sched.current + 1 },
                })
                -- <<<<< [修正结束] <<<<<

                carriage.train.go_to_station(sched.current + 1)

                log_tp("API 调用正确：已插入临时路障站点。")
            end
        end
        return
    end

    -- 动态拼接检测
    -- 询问引擎：当前位置是否已经空出来，可以放置新车厢了？
    -- 如果前车还没被拖船拉远，这里会返回 false
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
    log_tp("正在传送车厢: " .. carriage.name)

    -- [新增] 第一节车时记录正在查看该列车 GUI 的玩家
    if is_first_carriage and carriage.train then
        exit_struct.gui_watchers = collect_gui_watchers(carriage.train.id)
        log_tp("记录 GUI 观察者: " .. tostring(#exit_struct.gui_watchers) .. " 人, old_train_id=" .. tostring(carriage.train.id))
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

        -- >>>>> [修改] 免死金牌 (无条件生效) >>>>>
        if remote.interfaces["cybersyn"] then
            -- 打标签：告诉 Cybersyn 别删
            remote.call("cybersyn", "write_global", true, "trains", carriage.train.id, "se_is_being_teleported")

            -- [优化] 只有在无 SE 时才需要存快照
            if not script.active_mods["space-exploration"] then
                local _, snap = pcall(remote.call, "cybersyn", "read_global", "trains", carriage.train.id)
                if snap then
                    exit_struct.cybersyn_snapshot = snap
                end
            end
        end
        -- <<<<< [新增结束] <<<<<

        -- [SE] Started 事件
        if SE_TELEPORT_STARTED_EVENT_ID then
            -- >>>>> [新增调试日志] >>>>>
            log_tp("【DEBUG】准备触发 STARTED 事件: old_train_id = " .. tostring(carriage.train.id))
            -- <<<<< [新增结束] <<<<<
            script.raise_event(SE_TELEPORT_STARTED_EVENT_ID, {
                train = carriage.train,
                old_train_id_1 = carriage.train.id,
                old_surface_index = entry_struct.surface.index,
                teleporter = entry_struct.shell,
            })
        end
    end

    -- >>>>> [新增 SE 策略] 1. 在变动发生前，保存当前进度 >>>>>
    -- 必须在销毁拖船之前保存！因为销毁拖船会导致 carriage_ahead 的时刻表被重置为 1
    local saved_ahead_index = nil
    if exit_struct.carriage_ahead and exit_struct.carriage_ahead.valid and exit_struct.carriage_ahead.train then
        -- 如果出口已经有火车（说明这不是第一节车），保存它的进度
        if exit_struct.carriage_ahead.train.schedule then
            saved_ahead_index = exit_struct.carriage_ahead.train.schedule.current
        end
    end
    -- <<<<< [新增结束] <<<<<

    -- 销毁旧拖船
    if exit_struct.tug and exit_struct.tug.valid then
        exit_struct.tug.destroy()
        exit_struct.tug = nil
    end

    -- >>>>> [开始修改] 计算车厢生成朝向 (纯 Orientation 版) >>>>>
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

    log_tp("方向计算: 车厢ori=" .. carriage_ori .. ", 建筑ori=" .. entry_shell_ori .. ", 判定=" .. (is_nose_in and "顺向" or "逆向"))

    -- >>>>> [修改] 1. 提前计算目标朝向 (target_ori) >>>>>
    local exit_base_ori = geo.direction / 16.0
    local target_ori = exit_base_ori

    if not is_nose_in then
        -- 逆向进入 -> 逆向离开 (翻转 180 度)
        target_ori = (target_ori + 0.5) % 1.0
        log_tp("方向计算: 逆向翻转 (Ori " .. exit_base_ori .. " -> " .. target_ori .. ")")
    else
        log_tp("方向计算: 顺向保持 (Ori " .. target_ori .. ")")
    end
    -- <<<<< [修改结束] <<<<<

    -- >>>>> [修改] 2. 方案B: 动态偏移生成位置 (基于目标朝向) >>>>>
    -- 判定条件：默认方向建筑(0) + 第一节车 + 机车 + 车头朝向北(0/1)
    local is_facing_dead_end = (target_ori > 0.875 or target_ori < 0.125)

    if exit_struct.shell.direction == 0 and not entry_struct.carriage_ahead and carriage.type == "locomotive" and is_facing_dead_end then
        spawn_pos.y = spawn_pos.y + 2 -- 往出口方向(南)挪2格
        log_tp("几何修正: 检测到车头面朝死胡同，已向外偏移生成坐标以容纳拖车。")
    end
    -- <<<<< [修改结束] <<<<<

    -- [注意] 这里删除了原有的 "-- 4. 决定生成朝向" 那一大段重复代码
    -- 直接使用上面算好的 target_ori 进行生成

    -- 生成新车厢
    local new_carriage = exit_struct.surface.create_entity({
        name = carriage.name,
        position = spawn_pos,
        -- [修改] 不再使用 direction，改用 orientation
        -- 这样引擎会直接接受准确的角度，不再需要猜测是8向还是16向
        orientation = target_ori,
        force = carriage.force,
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

    -- 司机转移逻辑 (严格照搬传送门)
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

    -- [新增修复] 转移时刻表与保存索引
    if not entry_struct.carriage_ahead then
        -- 1. 获取带图标的真实站名 (解决比对失败问题)
        local real_station_name = get_real_station_name(entry_struct)
        log_tp("时刻表转移: 使用真实站名 '" .. real_station_name .. "' 进行比对")

        -- 2. 转移时刻表
        Schedule.transfer_schedule(carriage.train, new_carriage.train, real_station_name)

        -- >>>>> [关键修复] 在被拖船重置前，立刻备份正确的索引！ >>>>>
        if new_carriage.train and new_carriage.train.schedule then
            exit_struct.saved_schedule_index = new_carriage.train.schedule.current
        end
        -- <<<<< [修复结束] <<<<<

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
    if next_carriage and next_carriage.valid then
        entry_struct.carriage_behind = next_carriage

        -- [修改] 只创建拖船，不连接，不恢复索引

        -- 生成新拖船 (Tug)
        local tug_pos = Util.vectors_add(exit_struct.shell.position, geo.tug_offset)
        local tug = exit_struct.surface.create_entity({
            name = "rift-rail-tug",
            position = tug_pos,
            direction = geo.direction,
            force = new_carriage.force,
        })
        if tug then
            tug.destructible = false
            exit_struct.tug = tug
            log_tp("拖船已创建，等待物理吸附或速度管理器接管。")
        end

        -- >>>>> [新增逻辑] 立即恢复出口火车的状态 (模仿 SE) >>>>>
        if new_carriage.train and new_carriage.train.valid then
            -- 1. 恢复时刻表指针
            -- [修正] 这里的变量名是 exit_struct，而不是 struct
            if exit_struct.saved_schedule_index then
                new_carriage.train.go_to_station(exit_struct.saved_schedule_index)
            end

            -- 2. 恢复自动模式 (如果之前是自动)
            -- 直接恢复，相信几何修正已经保证了拖车的存在
            new_carriage.train.manual_mode = exit_struct.saved_manual_mode or false
        end
        -- <<<<< [新增结束] <<<<<
    else
        log_tp("最后一节车厢传送完毕。")
        -- 最后一节车传完时不再更新速度（此时为0），直接使用之前保存的高速
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
        -- 如果是出口模式撞的，忽略 (不复活碰撞器? 或者复活但没反应?)
        -- 按照要求：出口碰撞器不实现效果。
        -- 但如果不复活，下次变成入口就没用了。所以建议还是复活，只是不触发传送。
        -- 既然 entity 已经 died，我们需要在之后某个时刻重建它。
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

    -- [修改] 逻辑分流与入队
    if not train then
        -- 情况 A: 没有火车（被虫子咬了，或者非火车撞击），只需重建
        struct.collider_needs_rebuild = true
    else
        -- 情况 B: 有火车，触发传送逻辑
        log_tp("触发传送！入口ID: " .. struct.id .. " 火车ID: " .. train.id)

        -- [修改] 优先用撞击者作为第一节
        struct.carriage_behind = event.cause or train.front_stock
        struct.is_teleporting = true
    end

    -- [修改] 使用辅助函数添加到活跃列表
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

            -- [修改] 移除了强制出口火车 (train_exit) 手动模式的代码
            -- 允许出口火车保持自动模式，以便引擎能够检测红绿灯信号

            -- 2. 维持出口动力
            local target_speed = 0.5

            -- [保留] 基于拖船链接符号的动力逻辑 (SE算法)
            local required_sign = 1
            local tug = exit_struct.tug

            if tug and tug.valid then
                local link_sign = get_train_forward_sign(tug)
                required_sign = link_sign
            else
                local geo_exit = GEOMETRY[exit_struct.shell.direction] or GEOMETRY[0]
                local out_orientation = geo_exit.direction / 16.0
                local head_orientation = train_exit.front_stock.orientation
                local diff = math.abs(head_orientation - out_orientation)
                if diff > 0.5 then
                    diff = 1.0 - diff
                end
                if diff > 0.25 then
                    required_sign = -1
                end
            end

            -- [修改] 应用速度前增加状态检查
            -- 只有当火车处于手动模式，或者自动模式下的“正在行驶”/“无路径”状态时，才施加动力
            -- 如果是 wait_signal (红灯) 或 destination_full (终点满)，则不推，让其自然停下
            local should_push = train_exit.manual_mode or (train_exit.state == defines.train_state.on_the_path) or (train_exit.state == defines.train_state.no_path)

            if should_push then
                if math.abs(train_exit.speed) < target_speed or (train_exit.speed * required_sign < 0) then
                    train_exit.speed = target_speed * required_sign
                end
            end

            -- [关键修复] 在速度管理过程中持续保存出口列车速度
            -- 这样传送结束时使用的就是被维持的高速，而不是刚生成时的 0 速度
            exit_struct.final_train_speed = train_exit.speed

            -- 3. [终极修正] 太空电梯三方符号算法 (保持不变)
            local dir = struct.shell.direction
            local portal_sign = -1
            if dir == 0 or dir == 4 then
                portal_sign = 1
            end

            local ori = carriage_entry.orientation
            local car_sign = (ori < 0.5) and 1 or -1
            local link_sign = get_train_forward_sign(carriage_entry)

            local final_sign = portal_sign * car_sign * link_sign
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
                    -- 1. 根据建筑方向计算偏移量 (North: y-2, East: x+2, South: y+2, West: x-2)
                    local dir = struct.shell.direction
                    local offset = { x = 0, y = 0 }

                    if dir == 0 then
                        offset = { x = 0, y = -2 } -- North
                    elseif dir == 4 then
                        offset = { x = 2, y = 0 } -- East
                    elseif dir == 8 then
                        offset = { x = 0, y = 2 } -- South
                    elseif dir == 12 then
                        offset = { x = -2, y = 0 } -- West
                    end

                    -- 2. 计算绝对坐标
                    local final_pos = {
                        x = struct.shell.position.x + offset.x,
                        y = struct.shell.position.y + offset.y,
                    }

                    -- 3. 创建实体
                    struct.surface.create_entity({
                        name = "rift-rail-collider",
                        position = final_pos,
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

            -- [修改] 出队检查 (使用辅助函数移除)
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
