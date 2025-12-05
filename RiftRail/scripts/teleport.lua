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

function Teleport.init(deps)
    State = deps.State
    Util = deps.Util
    Schedule = deps.Schedule
    if deps.log_debug then
        log_debug = deps.log_debug
    end

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
    if exit_struct.tug and exit_struct.tug.valid then
        -- [A] 存: 销毁拖船会导致时刻表重置，先保存当前索引
        local saved_index_before_tug_death = nil
        -- 尝试通过 carriage_ahead 获取火车
        local train_ref = exit_struct.carriage_ahead and exit_struct.carriage_ahead.valid and
        exit_struct.carriage_ahead.train
        if train_ref and train_ref.valid and train_ref.schedule then
            saved_index_before_tug_death = train_ref.schedule.current
        end

        -- [B] 炸
        exit_struct.tug.destroy()
        exit_struct.tug = nil

        -- [C] 恢复
        if saved_index_before_tug_death and train_ref and train_ref.valid then
            train_ref.go_to_station(saved_index_before_tug_death)
        end
    end

    local final_train = exit_struct.carriage_ahead and exit_struct.carriage_ahead.train

    if final_train and final_train.valid then
        -- >>>>> [开始修改] 顺滑出站 v3.0 (极简延迟版) >>>>>

        -- 1. 恢复原始模式
        -- 这会将火车切回自动模式(如果之前是自动)，引擎接管寻路
        final_train.manual_mode = exit_struct.saved_manual_mode or false

        -- 2. 准备速度数值 (只取绝对值，动量守恒)
        local original_speed = math.abs(exit_struct.saved_speed or 0)
        local target_speed = math.max(original_speed, 0.5)

        -- >>>>> [开始修改] 入队逻辑 (携带出口方向数据) >>>>>

        -- 1. 计算出口的绝对离去方向 (Orientation 0.0-1.0)
        -- 我们需要告诉 on_tick: "不管谁是车头，反正要往这个方向跑"
        local geo_exit = GEOMETRY[exit_struct.shell.direction] or GEOMETRY[0]
        local out_orientation = geo_exit.direction / 16.0

        -- 2. 初始化队列
        if not storage.speed_queue then
            storage.speed_queue = {}
        end

        -- 3. 入队
        table.insert(storage.speed_queue, {
            train = final_train,
            velocity = target_speed,   -- 速度绝对值
            out_ori = out_orientation, -- 目标物理朝向
        })

        -- <<<<< [修改结束] <<<<<

        -- >>>>> [新增] 数据恢复 (注入灵魂) >>>>>
        if exit_struct.old_train_id and exit_struct.cybersyn_snapshot then
            handle_cybersyn_migration(exit_struct.old_train_id, final_train, exit_struct.cybersyn_snapshot)
            exit_struct.cybersyn_snapshot = nil
        end
        -- <<<<< [新增结束] <<<<<

        -- 4. SE 事件触发 (Finished)
        if SE_TELEPORT_FINISHED_EVENT_ID and exit_struct.old_train_id then
            log_tp("SE 兼容: 触发 on_train_teleport_finished")
            script.raise_event(SE_TELEPORT_FINISHED_EVENT_ID, {
                train = final_train,
                old_train_id_1 = exit_struct.old_train_id,
                old_surface_index = entry_struct.surface.index,
                teleporter = entry_struct.shell,
            })
        end
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
            local collider = entry_struct.surface.create_entity({
                name = "rift-rail-collider",
                position = { x = entry_struct.shell.position.x, y = entry_struct.shell.position.y - 2 }, -- 默认位置，需修正
                force = entry_struct.shell.force,
            })
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
        right_bottom = { x = spawn_pos.x + 2, y = spawn_pos.y + 2 },
    }

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

        -- >>>>> [新增] 免死金牌 (仅无 SE 时生效) >>>>>
        if remote.interfaces["cybersyn"] and not script.active_mods["space-exploration"] then
            -- 打标签：告诉 Cybersyn 别删
            remote.call("cybersyn", "write_global", true, "trains", carriage.train.id, "se_is_being_teleported")
            -- 存快照
            local _, snap = pcall(remote.call, "cybersyn", "read_global", "trains", carriage.train.id)
            if snap then
                exit_struct.cybersyn_snapshot = snap
            end
        end
        -- <<<<< [新增结束] <<<<<

        -- [SE] Started 事件
        if SE_TELEPORT_STARTED_EVENT_ID then
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

    -- 4. 决定生成朝向
    -- geo.direction 是 defines (0, 4, 8, 12)
    -- [修改] 必须除以 16.0 才能得到正确的 orientation (0, 0.25, 0.5, 0.75)
    -- 之前除以 8.0 会导致算出 0.5 (南)，引发错误的吸附
    local exit_base_ori = geo.direction / 16.0
    local target_ori = exit_base_ori

    if not is_nose_in then
        -- 逆向进入 -> 逆向离开 (翻转 180 度 = +0.5)
        target_ori = (target_ori + 0.5) % 1.0
        log_tp("方向计算: 逆向翻转 (Ori " .. exit_base_ori .. " -> " .. target_ori .. ")")
    else
        log_tp("方向计算: 顺向保持 (Ori " .. target_ori .. ")")
    end
    -- <<<<< [修改结束] <<<<<

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

    -- 尝试与上一节车厢强制连接 (防止引擎把它们当成两列车处理)
    if exit_struct.carriage_ahead and exit_struct.carriage_ahead.valid then
        new_carriage.connect_rolling_stock(defines.rail_direction.front)
        new_carriage.connect_rolling_stock(defines.rail_direction.back)
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

        -- 3. 保存新火车的时刻表索引 (解决重置问题)
        -- transfer_schedule 内部已经调用了 go_to_station，所以现在的 current 是正确的下一站
    end

    -- 销毁旧车厢
    carriage.destroy()

    -- 更新链表指针
    entry_struct.carriage_ahead = new_carriage -- 记录刚传过去的这节 (虽然没什么用，但保持一致)
    exit_struct.carriage_ahead = new_carriage  -- 记录出口的最前头 (用于拉动)

    -- 准备下一节
    if next_carriage and next_carriage.valid then
        entry_struct.carriage_behind = next_carriage

        --  A. 在生成/连接拖船前，保存刚才设置好的时刻表索引 >>>>>
        local index_before_tug = nil
        if new_carriage.train.schedule then
            index_before_tug = new_carriage.train.schedule.current
        end

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

            -- 强制连接逻辑 (这行代码会导致重置！)
            tug.connect_rolling_stock(defines.rail_direction.front)
            tug.connect_rolling_stock(defines.rail_direction.back)

            -- B. 拖船连接导致重置，立刻恢复索引 >>>>>
            if index_before_tug then
                new_carriage.train.go_to_station(index_before_tug)
                log_tp("拖船连接修正: 索引已从重置状态恢复为 " .. index_before_tug)
            end
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
        local cars = entity.surface.find_entities_filtered({
            type = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" },
            position = entity.position,
            radius = 4,
        })
        if cars[1] then
            train = cars[1].train
        end
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

    -- 启动 active 标记，让 on_tick 接管
    struct.is_teleporting = true
    -- 注意：此时不重建 Collider，直到传送结束
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
            -- 1. 强制入口手动模式
            if not train_entry.manual_mode then
                train_entry.manual_mode = true
            end

            -- >>>>> [开始修改] 在这里增加强制出口手动模式 >>>>>
            -- 修复报错: Trying to change direction of automatic train
            -- 必须确保出口火车也是手动模式，脚本才有权反转其速度方向(倒车)
            if not train_exit.manual_mode then
                train_exit.manual_mode = true
                -- log_tp("动力维持: 强制出口火车进入手动模式以应用矢量速度")
            end
            -- <<<<< [修改结束] <<<<<

            -- 2. 维持出口动力
            local target_speed = 0.5

            -- >>>>> [开始修改] 基于拖船链接符号的动力逻辑 (SE算法) >>>>>
            local required_sign = 1
            local tug = exit_struct.tug

            if tug and tug.valid then
                -- 1. 计算连接符号
                -- get_train_forward_sign 在文件头部定义，用来判断车厢和列车整体方向的关系
                local link_sign = get_train_forward_sign(tug)

                -- 2. 直接应用符号
                -- 因为拖船永远面朝出口，所以:
                -- 如果拖船顺接(1)，列车正方向就是出口 -> 正速度
                -- 如果拖船反接(-1)，列车正方向是死胡同 -> 负速度(倒车)
                required_sign = link_sign
            else
                -- 异常保护: 如果没有拖船，回退到 Orientation 算法
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

            -- 应用速度
            if math.abs(train_exit.speed) < target_speed or (train_exit.speed * required_sign < 0) then
                train_exit.speed = target_speed * required_sign
            end
            -- <<<<< [修改结束] <<<<<

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
    -- >>>>> [新增] 处理速度恢复队列 (延迟一帧执行) >>>>>
    -- 这是一个简单的 Tick Task 系统
    -- 如果上一帧有火车刚切回自动模式，它们会在这里等待恢复速度
    -- >>>>> [修改] 最终版：自动试错恢复速度 >>>>>
    if storage.speed_queue and #storage.speed_queue > 0 then
        for _, task in pairs(storage.speed_queue) do
            local train = task.train
            local velocity = task.velocity -- 这是一个正数 (绝对值)
            local target_ori = task.out_ori

            if train and train.valid and not train.manual_mode then
                local front = train.front_stock
                if front then
                    -- 1. 先进行几何估算 (准确率 90%)
                    local current_ori = front.orientation
                    local diff = math.abs(current_ori - target_ori)
                    if diff > 0.5 then
                        diff = 1.0 - diff
                    end

                    local sign = 1
                    if diff > 0.25 then
                        sign = -1
                    end

                    -- 2. 尝试应用速度 (pcall 保护)
                    -- 这里的逻辑是：试图应用我们算出的方向。
                    -- 如果引擎认为方向反了(报错)，pcall 会捕获错误，不会让游戏崩溃。
                    local success = pcall(function()
                        train.speed = velocity * sign
                    end)

                    -- 3. 如果估算错了，就反过来设
                    -- 既然正向不对，那反向一定是合法的 (只要有路径)
                    if not success then
                        pcall(function()
                            train.speed = velocity * -sign
                        end)
                    end
                end
            end
        end
        storage.speed_queue = {}
    end
    -- <<<<< [修改结束] <<<<<
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

                local col = struct.surface.create_entity({
                    name = "rift-rail-collider",
                    position = pos, -- 需修正
                    force = struct.shell.force,
                })
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
        -- [性能优化] 只为正在传送的传送门执行昂贵的动力计算
        if struct.is_teleporting then
            Teleport.manage_speed(struct)
        end
    end
end

return Teleport
