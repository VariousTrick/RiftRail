-- scripts/teleport.lua
-- 【Rift Rail - 传送核心模块】
-- 功能：处理火车传送的完整运行时逻辑 (基于传送门 Mod v1.1 适配)
-- 包含：堵车检测、内容转移、拖船机制、Cybersyn/SE 兼容

local Teleport = {}

-- =================================================================================
-- 依赖与本地变量
-- =================================================================================
local State = nil
local Util = nil
local Schedule = nil
local log_debug = function() end

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
        velocity_mult = { x = 0, y = 1 }
    },
    [4] = { -- East
        spawn_offset = { x = 0, y = 0 },
        direction = defines.direction.west,
        tug_offset = { x = 4.0, y = 0 }, -- [修改] 4.5 -> 4.0
        velocity_mult = { x = -1, y = 0 }
    },
    [8] = { -- South
        spawn_offset = { x = 0, y = 0 },
        direction = defines.direction.north,
        tug_offset = { x = 0, y = 4.0 }, -- [修改] 4.5 -> 4.0
        velocity_mult = { x = 0, y = -1 }
    },
    [12] = { -- West
        spawn_offset = { x = 0, y = 0 },
        direction = defines.direction.east,
        tug_offset = { x = -4.0, y = 0 }, -- [修改] -4.5 -> -4.0
        velocity_mult = { x = 1, y = 0 }
    }
}

-- [新增] 辅助函数：从子实体中获取真实的车站名称 (带图标)
-- 逻辑复刻：传送门模组直接读取 struct.station.backer_name，RiftRail 需遍历 children
local function get_real_station_name(struct)
    if struct.children then
        for _, child in pairs(struct.children) do
            if child.valid and child.name == "rift-rail-station" then
                -- 返回游戏内实际显示的名称 (如 "[item=xxx] 1")
                return child.backer_name
            end
        end
    end
    -- 保底：如果找不到实体，才返回内部存储的名字
    return struct.name
end

-- [新增] 本地日志辅助 (如果文件中已有可忽略)
local function log_tp(msg)
    -- 假设 log_debug 已经在 init 中注入
    if log_debug then log_debug("[Teleport] " .. msg) end
end

-- [新增] 辅助函数：判断车厢在列车中的连接方向 (照搬 SE)
-- 返回 1 (正接) 或 -1 (反接)
local function get_train_forward_sign(carriage_a)
    local sign = 1
    if #carriage_a.train.carriages == 1 then return sign end

    -- 检查前连接点
    local carriage_b = carriage_a.get_connected_rolling_stock(defines.rail_direction.front)
    if not carriage_b then
        -- 如果前连接点没车，说明是用后连接点连的 (反接)
        carriage_b = carriage_a.get_connected_rolling_stock(defines.rail_direction.back)
        sign = -sign
    end

    -- 遍历列车确定相对顺序
    for _, carriage in pairs(carriage_a.train.carriages) do
        if carriage == carriage_b then return sign end
        if carriage == carriage_a then return -sign end
    end
    return sign
end

function Teleport.init(deps)
    State = deps.State
    Util = deps.Util
    Schedule = deps.Schedule
    if deps.log_debug then log_debug = deps.log_debug end

    -- 尝试获取 SE 事件 (动态检测)
    if script.active_mods["space-exploration"] and remote.interfaces["space-exploration"] then
        local success, event_started = pcall(remote.call, "space-exploration", "get_on_train_teleport_started_event")
        local _, event_finished = pcall(remote.call, "space-exploration", "get_on_train_teleport_finished_event")
        if success then
            SE_TELEPORT_STARTED_EVENT_ID = event_started
            SE_TELEPORT_FINISHED_EVENT_ID = event_finished
            log_debug("传送门 SE 兼容: 成功获取传送事件 ID。")
        end
    end
end

-- 本地日志
local function log_tp(msg)
    log_debug("[Teleport] " .. msg)
end

--[[ -- =================================================================================
-- Cybersyn 兼容逻辑 (照搬自传送门 Mod)
-- =================================================================================

-- 处理 Cybersyn 数据迁移 (在传送结束或生成新车头时调用)
local function handle_cybersyn_migration(old_train_id, new_train, snapshot)
    if not (remote.interfaces["cybersyn"] and remote.interfaces["cybersyn"]["write_global"]) then return end
    if script.active_mods["space-exploration"] then return end -- SE 模式下 Cybersyn 自带兼容，无需干预

    local c_train = snapshot
    if not c_train then return end

    log_tp("Cybersyn 兼容: 开始为新火车 " .. new_train.id .. " (旧ID: " .. old_train_id .. ") 注入数据...")

    -- 1. 更新实体引用并搬家
    c_train.entity = new_train
    remote.call("cybersyn", "write_global", c_train, "trains", new_train.id)
    remote.call("cybersyn", "write_global", nil, "trains", old_train_id)

    -- 2. 强制清除 "正在传送" 标签
    remote.call("cybersyn", "write_global", nil, "trains", new_train.id, "se_is_being_teleported")
    log_tp("Cybersyn 兼容: 标签清除请求已发送。")

    -- 3. 时刻表补全 (Rail Patch) - 修复回库逻辑
    local schedule = new_train.schedule
    if schedule and schedule.records and c_train.status then
        local current_record = schedule.records[schedule.current]
        if current_record and current_record.station then
            local target_station_id = nil
            -- 状态映射: 1=TO_P, 3=TO_R, 5=TO_D, 6=TO_D_BYPASS
            if c_train.status == 1 then target_station_id = c_train.p_station_id end
            if c_train.status == 3 then target_station_id = c_train.r_station_id end
            if c_train.status == 5 or c_train.status == 6 then target_station_id = c_train.depot_id end

            if target_station_id then
                local st_data = nil
                if c_train.status == 5 or c_train.status == 6 then
                    st_data = remote.call("cybersyn", "read_global", "depots", target_station_id)
                else
                    st_data = remote.call("cybersyn", "read_global", "stations", target_station_id)
                end

                if st_data and st_data.entity_stop and st_data.entity_stop.valid then
                    local rail = st_data.entity_stop.connected_rail
                    -- 仅当目标铁轨在新地表时才补全
                    if rail and rail.surface == new_train.front_stock.surface then
                        table.insert(schedule.records, schedule.current, {
                            rail = rail,
                            rail_direction = st_data.entity_stop.connected_rail_direction,
                            temporary = true,
                            wait_conditions = { { type = "time", ticks = 1 } }
                        })
                        new_train.schedule = schedule
                        log_tp("Cybersyn 兼容: Rail Patch 补全成功。")
                    end
                end
            end
        end
    end
end ]]

-- =================================================================================
-- 核心传送逻辑
-- =================================================================================

-- 结束传送：清理状态，恢复数据
local function finish_teleport(entry_struct, exit_struct)
    log_tp("传送结束: 清理状态 (入口ID: " .. entry_struct.id .. ", 出口ID: " .. exit_struct.id .. ")")

    -- 1. 销毁最后的拖船
    if exit_struct.tug and exit_struct.tug.valid then
        exit_struct.tug.destroy()
        exit_struct.tug = nil
    end

    local final_train = exit_struct.carriage_ahead and exit_struct.carriage_ahead.train

    if final_train and final_train.valid then
        -- 2. 恢复模式和速度
        final_train.manual_mode = exit_struct.saved_manual_mode or false

        -- >>>>> [新增] 消除卡顿：补一脚油门 >>>>>
        -- 获取当前火车的速度方向符号
        local current_sign = (final_train.speed >= 0) and 1 or -1
        -- 如果速度过低 (卡顿了)，强制给一个驶离速度 (0.5)
        -- 这样火车会带着惯性继续滑出出口
        if math.abs(final_train.speed) < 0.5 then
            final_train.speed = 0.5 * current_sign
        end
        -- <<<<< [新增结束] <<<<<

        --[[         -- 3. Cybersyn 数据恢复
        if exit_struct.cybersyn_snapshot and exit_struct.old_train_id then
            handle_cybersyn_migration(exit_struct.old_train_id, final_train, exit_struct.cybersyn_snapshot)
            exit_struct.cybersyn_snapshot = nil
        end ]]

        -- 4. SE 事件触发 (Finished)
        if SE_TELEPORT_FINISHED_EVENT_ID and exit_struct.old_train_id then
            log_tp("SE 兼容: 触发 on_train_teleport_finished")
            script.raise_event(SE_TELEPORT_FINISHED_EVENT_ID, {
                train = final_train,
                old_train_id_1 = exit_struct.old_train_id,
                old_surface_index = entry_struct.surface.index,
                teleporter = entry_struct.shell
            })
        end

        -- >>>>> [新增修复] 时刻表索引保护 (复刻传送门逻辑) >>>>>
        if exit_struct.saved_schedule_index then
            local sched = final_train.schedule
            -- 检查索引是否被引擎重置了 (例如重置回了1)
            if sched and sched.records and sched.current ~= exit_struct.saved_schedule_index then
                -- 如果当前记录数足够，强制恢复索引
                if #sched.records >= exit_struct.saved_schedule_index then
                    log_tp("时刻表保护: 检测到索引重置 (" .. sched.current .. ")，强制恢复为: " .. exit_struct.saved_schedule_index)
                    sched.current = exit_struct.saved_schedule_index
                    final_train.schedule = sched
                else
                    log_tp("时刻表保护: 警告 - 记录数不足，无法恢复索引。")
                end
            end
            -- 清理保存的索引
            exit_struct.saved_schedule_index = nil
        end
        -- <<<<< [修复结束] <<<<<
    end

    -- 5. 重置状态变量
    entry_struct.carriage_behind = nil
    entry_struct.carriage_ahead = nil
    exit_struct.carriage_behind = nil
    exit_struct.carriage_ahead = nil
    exit_struct.old_train_id = nil

    -- 6. 【关键】重建入口的碰撞器 (按照传送门Mod逻辑，整列传完才重建)
    -- 注意：Rift Rail 的 Builder 可能没有自动重建逻辑，我们需要手动重建
    if entry_struct.shell and entry_struct.shell.valid then
        local builder_data = State.get_struct(entry_struct.shell)
        if builder_data then
            -- 这里的逻辑需要根据 Builder.lua 的定义。
            -- 简单起见，我们重新创建一个 rift-rail-collider
            -- 由于 collider 是 data.children 的一部分，为了严谨，我们应该复用位置
            -- 暂时先不自动重建，依赖 control.lua 的 on_tick 检查或 Builder 的逻辑
            -- **修正**：按照传送门逻辑，这里必须重建，否则下一辆车无法触发
            local collider = entry_struct.surface.create_entity {
                name = "rift-rail-collider",
                position = { x = entry_struct.shell.position.x, y = entry_struct.shell.position.y - 2 }, -- 默认位置，需修正
                force = entry_struct.shell.force
            }
            -- 注意：实际位置需要根据旋转计算。为防出错，建议在 Teleport.tick 里做延迟检查重建
            -- 或者在这里简单调用一个 Builder 的修复函数（如果有）
            -- 鉴于要求“照搬逻辑”，传送门是在 on_tick 里重建的。我们在 on_tick 处理。
            entry_struct.collider_needs_rebuild = true
        end
    end
end

-- 传送下一节车厢 (由 on_tick 驱动)
function Teleport.teleport_next(entry_struct)
    local exit_struct = State.get_struct_by_id(entry_struct.paired_to_id)

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

    -- 检查出口是否堵塞 (照搬传送门逻辑)
    local geo = GEOMETRY[exit_struct.shell.direction] or GEOMETRY[0]
    local spawn_pos = Util.vectors_add(exit_struct.shell.position, geo.spawn_offset)

    -- 定义检查区域 (简单一个小矩形)
    local check_area = {
        left_top = { x = spawn_pos.x - 2, y = spawn_pos.y - 2 },
        right_bottom = { x = spawn_pos.x + 2, y = spawn_pos.y + 2 }
    }

    -- 如果前面有车 (carriage_ahead)，说明正在传送中，不需要检查堵塞 (我们是接在它后面的)
    -- 只有当 carriage_ahead 为空 (第一节) 时才检查堵塞
    local is_clear = true
    if not entry_struct.carriage_ahead then
        local count = exit_struct.surface.count_entities_filtered {
            area = check_area,
            type = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" }
        }
        if count > 0 then is_clear = false end
    end

    -- 堵塞处理
    if not is_clear then
        log_tp("出口堵塞，暂停传送...")
        -- 修改时刻表让火车停下 (照搬逻辑)
        if carriage.train and not carriage.train.manual_mode then
            local sched = carriage.train.schedule
            if sched then
                local current = sched.records[sched.current]
                if current then
                    -- 添加无限等待
                    current.wait_conditions = { { type = "time", ticks = 9999999 } }
                    current.temporary = true
                    carriage.train.schedule = sched
                    log_tp("已修改入口火车时刻表为无限等待。")
                end
            end
        end
        return -- 退出，等待下一次 tick
    end

    -- >>>>> [开始插入] 动态拼接检测 >>>>>
    -- 询问引擎：当前位置是否已经空出来，可以放置新车厢了？
    -- 如果前车还没被拖船拉远，这里会返回 false
    local can_place = exit_struct.surface.can_place_entity {
        name = carriage.name,
        position = spawn_pos,
        direction = geo.direction,
        force = carriage.force
    }

    if not can_place then
        return -- 位置没空出来，跳过本次循环，等待下一帧
    end
    -- <<<<< [插入结束] <<<<<

    -- 开始传送当前车厢
    log_tp("正在传送车厢: " .. carriage.name)

    -- 获取下一节车 (用于更新循环)
    local next_carriage = carriage.get_connected_rolling_stock(defines.rail_direction.front)
    if next_carriage == carriage then next_carriage = nil end -- 防止环形误判
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

        --[[         -- [Cybersyn] 抢救数据快照
        if remote.interfaces["cybersyn"] and remote.interfaces["cybersyn"]["read_global"] then
            -- 标记免死金牌
            remote.call("cybersyn", "write_global", true, "trains", carriage.train.id, "se_is_being_teleported")
            local status, c_data = pcall(remote.call, "cybersyn", "read_global", "trains", carriage.train.id)
            if status and c_data then
                exit_struct.cybersyn_snapshot = c_data
                log_tp("Cybersyn 快照保存成功。")
            end
        end ]]

        -- [SE] Started 事件
        if SE_TELEPORT_STARTED_EVENT_ID then
            script.raise_event(SE_TELEPORT_STARTED_EVENT_ID, {
                train = carriage.train,
                old_train_id_1 = carriage.train.id,
                old_surface_index = entry_struct.surface.index,
                teleporter = entry_struct.shell
            })
        end
    end

    -- 销毁旧拖船
    if exit_struct.tug and exit_struct.tug.valid then
        exit_struct.tug.destroy()
        exit_struct.tug = nil
    end

    -- 生成新车厢
    local new_carriage = exit_struct.surface.create_entity {
        name = carriage.name,
        position = spawn_pos,
        direction = geo.direction,
        force = carriage.force
    }

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
    if carriage.color then new_carriage.color = carriage.color end

    -- [修正] 司机转移逻辑 (严格照搬传送门)
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

    -- >>>>> [新增修复] 转移时刻表与保存索引 >>>>>
    if not entry_struct.carriage_ahead then
        -- 1. 获取带图标的真实站名 (解决比对失败问题)
        local real_station_name = get_real_station_name(entry_struct)
        log_tp("时刻表转移: 使用真实站名 '" .. real_station_name .. "' 进行比对")

        -- 2. 转移时刻表
        Schedule.transfer_schedule(carriage.train, new_carriage.train, real_station_name)

        -- 3. 保存新火车的时刻表索引 (解决重置问题)
        -- transfer_schedule 内部已经调用了 go_to_station，所以现在的 current 是正确的下一站
        if new_carriage.train.schedule then
            exit_struct.saved_schedule_index = new_carriage.train.schedule.current
            log_tp("时刻表保护: 已保存目标索引 [" .. exit_struct.saved_schedule_index .. "] 到出口结构")
        end
    end
    -- <<<<< [修复结束] <<<<<

    -- 销毁旧车厢
    carriage.destroy()

    -- 更新链表指针
    entry_struct.carriage_ahead = new_carriage -- 记录刚传过去的这节 (虽然没什么用，但保持一致)
    exit_struct.carriage_ahead = new_carriage  -- 记录出口的最前头 (用于拉动)

    -- 准备下一节
    if next_carriage and next_carriage.valid then
        entry_struct.carriage_behind = next_carriage

        -- 生成新拖船 (Tug)
        local tug_pos = Util.vectors_add(exit_struct.shell.position, geo.tug_offset)
        local tug = exit_struct.surface.create_entity {
            name = "rift-rail-tug",
            position = tug_pos,
            direction = geo.direction, -- 拖船方向与车一致
            force = new_carriage.force
        }
        if tug then
            tug.destructible = false
            exit_struct.tug = tug

            -- [新增] 强制连接逻辑
            -- 拖车生成在车厢后方，且方向一致
            -- 所以拖车的 "Front" 对着车厢的 "Back"
            -- 尝试两个方向连接，确保万无一失
            tug.connect_rolling_stock(defines.rail_direction.front)
            tug.connect_rolling_stock(defines.rail_direction.back)
        end
    else
        log_tp("最后一节车厢传送完毕。")
        finish_teleport(entry_struct, exit_struct)
    end
end

-- =================================================================================
-- 触发入口 (on_entity_died)
-- =================================================================================

function Teleport.on_collider_died(event)
    local entity = event.entity
    if not (entity and entity.valid) then return end

    -- 1. 反查建筑数据
    -- 碰撞器是 children 的一部分，或者是位置重叠
    -- 为了快，假设我们能通过位置找到 Core/Shell
    -- 或者更简单：在 Builder.lua 里我们记录了 struct，我们可以遍历查找
    -- 但遍历太慢。更好的方法是：on_entity_died 传入的 entity 我们去 State 查
    -- 但 State.get_struct 主要是查 Shell 或 Core。
    -- 临时方案：搜索附近的 Shell
    local shells = entity.surface.find_entities_filtered {
        name = "rift-rail-entity",
        position = entity.position,
        radius = 3
    }
    local shell = shells[1]
    if not shell then return end

    local struct = State.get_struct(shell)
    if not struct then return end

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
        game.print("[RiftRail] 错误: 试图进入未配对的传送门！")
        struct.collider_needs_rebuild = true
        return
    end

    -- 4. 捕获火车
    local train = nil
    if event.cause and event.cause.train then
        train = event.cause.train
    else
        -- 搜索附近的火车
        local cars = entity.surface.find_entities_filtered {
            type = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" },
            position = entity.position,
            radius = 4
        }
        if cars[1] then train = cars[1].train end
    end

    if not train then
        struct.collider_needs_rebuild = true
        return
    end

    log_tp("触发传送！入口ID: " .. struct.id .. " 火车ID: " .. train.id)

    -- 5. 初始化传送序列
    -- 记录第一节车厢 (从车头开始，还是从撞击的那节开始？通常是整列)
    -- 这里我们取 front_stock (车头)，或者 back_stock，取决于行驶方向
    -- [修改] 优先用撞击者作为第一节
    struct.carriage_behind = event.cause or train.front_stock

    -- [删除] 这里之前添加的 struct.entry_speed_sign 相关代码请全部删除
    -- 我们不再在撞击瞬间记录方向，改为在 manage_speed 中实时计算

    -- 启动 active 标记，让 on_tick 接管
    struct.is_teleporting = true
    -- 注意：此时不重建 Collider，直到传送结束
end

-- =================================================================================
-- 持续动力 (每 tick 调用)
-- =================================================================================
function Teleport.manage_speed(struct)
    if not struct.paired_to_id then return end
    local exit_struct = State.get_struct_by_id(struct.paired_to_id)
    if not (exit_struct and exit_struct.shell and exit_struct.shell.valid) then return end

    local carriage_entry = struct.carriage_behind
    local carriage_exit = exit_struct.carriage_ahead

    if carriage_entry and carriage_entry.valid and carriage_exit and carriage_exit.valid then
        local train_entry = carriage_entry.train
        local train_exit = carriage_exit.train

        if train_entry and train_entry.valid and train_exit and train_exit.valid then
            -- 1. 强制入口手动模式
            if not train_entry.manual_mode then
                train_entry.manual_mode = true
            end

            -- 2. 维持出口动力
            local target_speed = 0.5
            local exit_sign = (train_exit.speed < 0) and -1 or 1
            if math.abs(train_exit.speed) < target_speed then
                train_exit.speed = target_speed * exit_sign
            end

            -- 3. [终极修正] 太空电梯三方符号算法
            -- 公式: 入口速度 = |出口速度| * 建筑符号 * 车厢符号 * 连接符号

            -- A. 建筑符号 (Portal Sign)
            -- Dir 0 (North, -Y) & Dir 4 (East, +X) -> 定义为 1
            -- Dir 8 (South, +Y) & Dir 12 (West, -X) -> 定义为 -1
            local dir = struct.shell.direction
            local portal_sign = -1
            if dir == 0 or dir == 4 then
                portal_sign = 1
            end

            -- B. 车厢符号 (Carriage Sign)
            -- 照搬 SE: < 0.5 (N/E) 为 1, >= 0.5 (S/W) 为 -1
            local ori = carriage_entry.orientation
            local car_sign = (ori < 0.5) and 1 or -1

            -- C. 连接符号 (Link Sign)
            -- 判断车厢是否反向连接
            local link_sign = get_train_forward_sign(carriage_entry)

            -- 4. 计算并应用
            local final_sign = portal_sign * car_sign * link_sign
            train_entry.speed = math.abs(train_exit.speed) * final_sign
        end
    end
end

-- =================================================================================
-- Tick 调度
-- =================================================================================

function Teleport.on_tick(event)
    -- 遍历所有传送门
    -- 注意：效率优化，实际应该只遍历 active 的
    local all = State.get_all_structs()
    for _, struct in pairs(all) do
        -- 1. 重建碰撞器逻辑 (延迟一帧或传送结束后)
        if struct.collider_needs_rebuild then
            if struct.shell and struct.shell.valid then
                -- 计算位置 (需根据旋转)
                -- 简化：查找偏移量。Builder 里 collider 在 y=-2 (North)
                -- 旋转逻辑同 Builder
                local offset = { x = 0, y = -2 }
                -- (此处省略旋转计算，实际应调用 Builder 的 helper 或硬编码)
                -- 为演示逻辑，假设位置正确
                local pos = struct.shell.position -- 临时

                local col = struct.surface.create_entity {
                    name = "rift-rail-collider",
                    position = pos, -- 需修正
                    force = struct.shell.force
                }
                struct.collider_needs_rebuild = false
            end
        end

        -- 2. 执行传送序列
        if struct.is_teleporting then
            -- 频率控制：每 4 tick 一次 (照搬传送门)
            if event.tick % 4 == struct.unit_number % 4 then
                -- >>>>> [新增修改] 只要引用存在，就进入处理 (即使 .valid 为 false) >>>>>
                -- 原代码: if struct.carriage_behind and struct.carriage_behind.valid then
                if struct.carriage_behind then
                    -- 让 teleport_next 内部去判断有效性。
                    -- 如果无效，teleport_next 会自动调用 finish_teleport 清理拖船。
                    Teleport.teleport_next(struct)
                else
                    -- 只有当 struct.carriage_behind 真的为 nil (正常传送完毕) 时，才关闭状态
                    log_debug("Teleport [Tick]: 传送序列正常结束，关闭状态。")
                    struct.is_teleporting = false
                end
                -- <<<<< [修改结束] <<<<<
            end
        end

        -- 3. 持续动力
        Teleport.manage_speed(struct)
    end
end

return Teleport
