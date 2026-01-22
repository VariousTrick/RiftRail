-- scripts/teleport.lua
-- 【Rift Rail - 传送核心模块】
-- 功能：处理火车传送的完整运行时逻辑
-- 包含：堵车检测、内容转移、引导车机制、Cybersyn/SE/LTN 兼容

local Teleport = {}

-- =================================================================================
-- 依赖与日志系统
-- =================================================================================
local State = nil
local Util = nil
local Schedule = nil
local CybersynCompat = nil
local LtnCompat = nil

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
    -- 接收兼容模块
    CybersynCompat = deps.CybersynCompat
    LtnCompat = deps.LtnCompat
end

-- 3. 定义本模块专属的、带 if 判断的日志包装器
local function log_tp(msg)
    if RiftRail.DEBUG_MODE_ENABLED then
        log_debug("[RiftRail:Teleport] " .. msg) -- 调用全局 log_debug, 并加上自己的模块名
    end
end

-- =================================================================================
-- 统一列车时刻表索引读取函数（处理不同列车状态）
-- =================================================================================
local function read_train_schedule_index(train, phase_name)
    if not (train and train.valid and train.schedule) then
        return nil
    end

    local index
    local state = train.state

    if state == defines.train_state.wait_station then
        -- 列车正在等待，读取下一个索引
        index = train.schedule.current + 1
        if index > #train.schedule.records then
            index = 1
        end
    elseif state == defines.train_state.on_the_path or state == defines.train_state.wait_signal or state == defines.train_state.arrive_signal or state == defines.train_state.arrive_station then
        -- 这些状态都使用当前索引
        index = train.schedule.current
    end

    return index
end

-- SE 事件 ID (初始化时获取)
local SE_TELEPORT_STARTED_EVENT_ID = nil
local SE_TELEPORT_FINISHED_EVENT_ID = nil

-- =================================================================================
-- 【Rift Rail 专用几何参数】
-- =================================================================================
-- 将偏移量调整为偶数 (0)，对准铁轨中心，防止生成失败
-- 基于 "车厢生成在建筑中心 (y=0)" 的设定
local GEOMETRY = {
    [0] = { -- North (出口在下方 Y+)
        spawn_offset = { x = 0, y = 0 },
        direction = defines.direction.south,
        leadertrain_offset = { x = 0, y = 4.0 },
        velocity_mult = { x = 0, y = 1 },
        collider_offset = { x = 0, y = -2 },
        check_area_rel = { lt = { x = -1, y = 0 }, rb = { x = 1, y = 10 } },
    },
    [4] = { -- East (出口在左方 X-)
        spawn_offset = { x = 0, y = 0 },
        direction = defines.direction.west,
        leadertrain_offset = { x = -4.0, y = 0 },
        velocity_mult = { x = -1, y = 0 },
        collider_offset = { x = 2, y = 0 },
        check_area_rel = { lt = { x = -10, y = -1 }, rb = { x = 0, y = 1 } },
    },
    [8] = { -- South (出口在上方 Y-)
        spawn_offset = { x = 0, y = 0 },
        direction = defines.direction.north,
        leadertrain_offset = { x = 0, y = -4.0 },
        velocity_mult = { x = 0, y = -1 },
        collider_offset = { x = 0, y = 2 },
        check_area_rel = { lt = { x = -1, y = -10 }, rb = { x = 1, y = 0 } },
    },
    [12] = { -- West (出口在右方 X+)
        spawn_offset = { x = 0, y = 0 },
        direction = defines.direction.east,
        leadertrain_offset = { x = 4.0, y = 0 },
        velocity_mult = { x = 1, y = 0 },
        collider_offset = { x = -2, y = 0 },
        check_area_rel = { lt = { x = 0, y = -1 }, rb = { x = 10, y = 1 } },
    },
}

-- =================================================================================
-- 活跃列表管理辅助函数 (GC 优化)
-- =================================================================================

-- 添加到活跃列表
-- 【性能重构】使用二分查找插入，替换 table.sort
local function add_to_active(portaldata)
    if not portaldata or not portaldata.unit_number then
        return
    end

    if not storage.active_teleporters then
        storage.active_teleporters = {}
    end
    if not storage.active_teleporter_list then
        storage.active_teleporter_list = {}
    end

    if storage.active_teleporters[portaldata.unit_number] then
        return
    end

    storage.active_teleporters[portaldata.unit_number] = portaldata
    local list = storage.active_teleporter_list
    local unit_number = portaldata.unit_number

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
    table.insert(list, pos, portaldata)
end
-- =================================================================================
-- 通用查找子实体函数
-- =================================================================================
local function find_child_entity(portaldata, name_to_find)
    if not (portaldata and portaldata.children) then
        return nil
    end
    for _, child_data in pairs(portaldata.children) do
        local entity = child_data.entity
        if entity and entity.valid and entity.name == name_to_find then
            return entity
        end
    end
    return nil
end
-- =================================================================================
-- 辅助函数：从子实体中获取真实的车站名称 (带图标)
-- =================================================================================
local function get_real_station_name(portaldata)
    -- 适配 children 结构 {entity=..., relative_pos=...}
    local station = find_child_entity(portaldata, "rift-rail-station")
    if station then
        return station.backer_name
    end
    return portaldata.name
end
-- =================================================================================
-- 【重构】精准记录查看具体车厢的玩家（映射表模式）
-- =================================================================================
-- 参数：train (LuaTrain 对象)
-- 返回：Map<UnitNumber, Player[]>  { [车厢ID] = {玩家A, 玩家B} }
local function collect_gui_watchers(train)
    local map = {}
    if not (train and train.valid) then
        return nil
    end

    -- 遍历所有玩家，寻找正在查看该列车实体的玩家
    for _, p in pairs(game.connected_players) do
        local opened = p.opened
        -- 仅处理 LuaEntity 类型（精准对应车厢），暂不处理 LuaTrain（时刻表）
        if opened and opened.valid and opened.object_name == "LuaEntity" then
            if opened.train == train then
                local uid = opened.unit_number
                if not map[uid] then
                    map[uid] = {}
                end
                table.insert(map[uid], p)
            end
        end
    end

    -- 【关键修改】如果表是空的，返回 nil，而不是空表
    -- next(map) 是 Lua 判断表是否为空最高效的方法
    if next(map) == nil then
        return nil
    end

    return map
end
-- =================================================================================
-- 【重构】精准恢复 GUI 到指定车厢实体
-- =================================================================================
-- 参数：watchers (玩家对象列表), entity (新生成的车厢实体)
local function reopen_car_gui(watchers, entity)
    -- 如果没人看这节车，或者实体无效，直接返回
    if not (watchers and entity and entity.valid) then
        return
    end

    for _, p in ipairs(watchers) do
        if p.valid then
            -- [关键] 立即将玩家界面重定向到新车厢
            p.opened = entity
        end
    end
end

-- =================================================================================
-- 速度方向计算函数 (基于铁轨端点距离)
-- =================================================================================
--- 计算列车相对于一个参考点的逻辑方向。
-- @param train (LuaTrain) 要计算的列车。
-- @param origin_pos (Position) 参考点坐标 (通常是传送门出口)。
-- @return (number) 1 代表逻辑正向 (Front更远), -1 代表逻辑反向 (Back更远)。
local function calculate_speed_sign(train, select_portal)
    -- 安全检查：如果输入无效，默认返回正向
    if not (train and train.valid and select_portal) then
        return 1
    end

    -- [核心逻辑] 使用缓存，并为旧存档/克隆体提供懒加载
    local origin_pos = select_portal.blocker_position

    -- 如果缓存不存在 (旧存档)，则计算一次并写回
    if not origin_pos then
        local shell = select_portal.shell
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
        select_portal.blocker_position = origin_pos -- 将计算结果写回缓存
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
-- =================================================================================
-- 【克隆工厂】生成替身车厢并转移所有属性
-- =================================================================================
-- 参数：
--   old_entity: 原车厢实体
--   surface:    目标地表
--   position:   目标坐标
--   orientation:目标朝向 (0.0-1.0)
-- 返回：新创建的车厢实体 (失败返回 nil)
local function spawn_cloned_car(old_entity, surface, position, orientation)
    if not (old_entity and old_entity.valid) then
        return nil
    end

    -- 1. 创建实体 (Factorio 2.0 API: 支持 quality 和 orientation)
    local new_entity = surface.create_entity({
        name = old_entity.name,
        position = position,
        orientation = orientation,
        force = old_entity.force,
        quality = old_entity.quality,
        snap_to_train_stop = false, -- 建议设为 false 以提高位置精确度
        raise_built = true,
    })

    if not new_entity then
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("克隆工厂: 创建实体失败 " .. old_entity.name)
        end
        return nil
    end

    -- 使用 copy_settings 一键同步配置 (颜色、名字、过滤器、红叉、中断等)
    new_entity.copy_settings(old_entity)

    -- 2. 基础属性同步
    new_entity.health = old_entity.health

    -- 3. 内容转移 (调用 Util)
    Util.clone_all_inventories(old_entity, new_entity)
    Util.clone_fluid_contents(old_entity, new_entity)
    Util.clone_grid(old_entity, new_entity)

    -- 4. 司机转移 (特殊处理)
    local driver = old_entity.get_driver()
    if driver then
        -- 必须先从旧车“下车”，防止被留在旧世界
        old_entity.set_driver(nil)

        if driver.object_name == "LuaPlayer" then
            -- 玩家直接上新车 (引擎自动处理坐标跨越)
            new_entity.set_driver(driver)
        elseif driver.valid and driver.teleport then
            -- NPC/AAI 矿车司机需要手动传送物理坐标
            driver.teleport(new_entity.position, new_entity.surface)
            new_entity.set_driver(driver)
        end
    end

    return new_entity
end
-- =================================================================================
-- 【纯函数】计算车厢在出口生成的朝向 (Orientation 0.0-1.0)
-- =================================================================================
-- 参数：
--   entry_shell_dir: 入口传送门的朝向 (0, 4, 8, 12)
--   exit_geo_dir:    出口传送门的目标朝向 (0, 4, 8, 12)
--   current_ori:     车厢当前的朝向 (0.0 - 1.0)
local function calculate_arrival_orientation(entry_shell_dir, exit_geo_dir, current_ori)
    -- 1. 将入口建筑朝向转为 Orientation (0-1)
    local entry_shell_ori = entry_shell_dir / 16.0

    -- 2. 判断车厢是“顺着进”还是“倒着进”
    -- 计算角度差 (处理 0.0/1.0 的环形边界)
    local diff = math.abs(current_ori - entry_shell_ori)
    if diff > 0.5 then
        diff = 1.0 - diff
    end

    -- 判定阈值 (0.125 = 45度，小于45度夹角视为顺向)
    local is_nose_in = diff < 0.125

    if RiftRail.DEBUG_MODE_ENABLED then
        log_tp("方向计算: 车厢=" ..
        string.format("%.2f", current_ori) ..
        ", 入口=" .. entry_shell_ori .. ", 判定=" .. (is_nose_in and "顺向(NoseIn)" or "逆向(TailIn)"))
    end

    -- 3. 计算出口基准朝向
    local exit_base_ori = exit_geo_dir / 16.0
    local target_ori = exit_base_ori

    -- 4. 根据进出关系修正最终朝向
    if not is_nose_in then
        -- 逆向进入 -> 逆向离开 (翻转 180 度即 +0.5)
        target_ori = (target_ori + 0.5) % 1.0
    end

    if RiftRail.DEBUG_MODE_ENABLED and not is_nose_in then
        log_tp("方向计算: 执行逆向翻转 -> " .. target_ori)
    end

    -- 增加第二个返回值 is_nose_in
    return target_ori, is_nose_in
end
-- =================================================================================
-- 【辅助函数】确保几何数据缓存有效 (去重逻辑)
-- =================================================================================
-- 参数：portaldata (传送门数据)
-- 返回：有效的 geo 配置表
local function ensure_geometry_cache(portaldata)
    if not (portaldata and portaldata.shell and portaldata.shell.valid) then
        return nil
    end

    local geo = portaldata.cached_geo
    -- 检查缓存是否存在，且包含最新的字段 check_area_rel
    if not geo or not geo.check_area_rel then
        geo = GEOMETRY[portaldata.shell.direction] or GEOMETRY[0]
        portaldata.cached_geo = geo
    end
    return geo
end
-- =================================================================================
-- 【业务逻辑】尝试启动传送流程
-- =================================================================================
-- 参数：entry_portaldata (入口数据), car (触发的车厢实体)
-- 返回：bool (是否成功启动)
local function try_start_teleport(entry_portaldata, car)
    -- 1. 模式检查
    if entry_portaldata.mode ~= "entry" then
        return false
    end

    -- 2. 配对检查
    if not entry_portaldata.paired_to_id then
        game.print({ "messages.rift-rail-error-unpaired-or-collider" })
        return false
    end

    -- 3. 启动逻辑
    if RiftRail.DEBUG_MODE_ENABLED then
        log_tp("触发传送: 入口ID=" .. entry_portaldata.id .. ", 车厢=" .. car.name)
    end

    entry_portaldata.entry_car = car
    entry_portaldata.is_teleporting = true

    -- 启动时不再预计算出口缓存，交由 process_transfer_step 处理
    -- 也不再设置 collider_needs_rebuild
    return true
end
-- =================================================================================
-- 新增辅助函数 (代码提纯)
-- =================================================================================
-- =================================================================================
-- 统一列车状态恢复函数
-- =================================================================================
local function restore_train_state(train, portaldata, apply_speed, target_index)
    if not (train and train.valid) then
        return
    end

    if RiftRail.DEBUG_MODE_ENABLED then
        log_tp("状态恢复: TrainID=" .. train.id .. ", 恢复进度=" .. tostring(portaldata.saved_schedule_index ~= nil))
    end

    -- A. 恢复时刻表索引 (副作用：列车变为自动模式)
    -- 优先使用传入的 target_index，其次使用 saved_schedule_index
    local index_to_restore = target_index or portaldata.saved_schedule_index
    if index_to_restore then
        train.go_to_station(index_to_restore)
    end

    -- B. 恢复手动/自动模式
    train.manual_mode = portaldata.saved_manual_mode or false

    -- C. (可选) 恢复速度
    if apply_speed then
        local speed_mag = settings.global["rift-rail-teleport-speed"].value
        local sign = calculate_speed_sign(train, portaldata)
        train.speed = speed_mag * sign

        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("状态恢复: 速度重置为 " .. train.speed)
        end
    end
end
-- =================================================================================
-- 专门用于在 on_load 中初始化的 SE 事件获取函数
-- =================================================================================
function Teleport.init_se_events()
    -- 确保 on_load 时也能拿到最新的日志函数
    if script.active_mods["space-exploration"] and remote.interfaces["space-exploration"] then
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("Teleport: 正在尝试从 SE 获取传送事件 ID (on_load)...")
        end
        local success, event_started = pcall(remote.call, "space-exploration", "get_on_train_teleport_started_event")
        local _, event_finished = pcall(remote.call, "space-exploration", "get_on_train_teleport_finished_event")

        if success and event_started then
            SE_TELEPORT_STARTED_EVENT_ID = event_started
            SE_TELEPORT_FINISHED_EVENT_ID = event_finished
            if RiftRail.DEBUG_MODE_ENABLED then
                log_tp("Teleport: SE 传送事件 ID 获取成功！")
            end
        else
            if RiftRail.DEBUG_MODE_ENABLED then
                log_tp("Teleport: 警告 - 无法从 SE 获取传送事件 ID。")
            end
        end
    end
end

-- =================================================================================
-- 核心传送逻辑
-- =================================================================================

-- =================================================================================
-- 结束传送：清理状态，恢复数据
-- =================================================================================
local function finalize_sequence(entry_portaldata, exit_portaldata)
    if RiftRail.DEBUG_MODE_ENABLED then
        log_tp("传送结束: 清理状态 (入口ID: " .. entry_portaldata.id .. ", 出口ID: " .. exit_portaldata.id .. ")")
    end

    -- 1. 在销毁引导车前读取列车索引
    local final_train = nil
    local actual_index_before_cleanup = nil
    if exit_portaldata.exit_car and exit_portaldata.exit_car.valid then
        final_train = exit_portaldata.exit_car.train
        if final_train and final_train.valid then
            actual_index_before_cleanup = read_train_schedule_index(final_train)
        end
    else
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("警告: finalize_sequence 时出口车厢无效或丢失，跳过列车恢复逻辑。")
        end
    end

    -- 2. 销毁引导车（会导致列车对象失效并重新创建）
    if exit_portaldata.leadertrain and exit_portaldata.leadertrain.valid then
        exit_portaldata.leadertrain.destroy()
        exit_portaldata.leadertrain = nil
    end

    -- 3. 销毁后重新获取新的列车对象
    if exit_portaldata.exit_car and exit_portaldata.exit_car.valid then
        final_train = exit_portaldata.exit_car.train
    end

    if final_train and final_train.valid then
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("【销毁后】准备恢复: actual_index=" ..
            tostring(actual_index_before_cleanup) .. ", saved_index=" .. tostring(exit_portaldata.saved_schedule_index))
        end
        -- 使用统一函数恢复状态 (参数 true 代表同时恢复速度)
        restore_train_state(final_train, exit_portaldata, true, actual_index_before_cleanup)

        -- 触发 Cybersyn 完成钩子 (自动处理数据恢复)
        if CybersynCompat and exit_portaldata.old_train_id then
            CybersynCompat.on_teleport_end(final_train, exit_portaldata.old_train_id, exit_portaldata.cybersyn_snapshot)
            exit_portaldata.cybersyn_snapshot = nil
        end

        -- 4. SE 事件触发 (Finished)
        if SE_TELEPORT_FINISHED_EVENT_ID and exit_portaldata.old_train_id then
            if RiftRail.DEBUG_MODE_ENABLED then
                log_tp("SE兼容触发 on_train_teleport_finished 事件: new_train_id = " ..
                tostring(final_train.id) .. ", old_train_id = " .. tostring(exit_portaldata.old_train_id))
            end
            script.raise_event(SE_TELEPORT_FINISHED_EVENT_ID, {
                train = final_train,
                old_train_id = exit_portaldata.old_train_id,
                old_train_id_1 = exit_portaldata.old_train_id,
                old_surface_index = entry_portaldata.surface.index,
                teleporter = exit_portaldata.shell,
            })
        end

        -- 清理残留的 GUI 映射表（如果有）
        if entry_portaldata.gui_map then
            entry_portaldata.gui_map = nil
        end
    end

    -- 5. 重置状态变量
    entry_portaldata.entry_car = nil
    entry_portaldata.exit_car = nil
    exit_portaldata.entry_car = nil
    exit_portaldata.exit_car = nil
    exit_portaldata.old_train_id = nil
    exit_portaldata.cached_geo = nil
    exit_portaldata.final_train_speed = nil

    -- 6. 【关键】标记需要重建入口碰撞器
    -- 我们不在这里直接创建，而是交给 on_tick 去计算正确的坐标并创建
    if entry_portaldata.shell and entry_portaldata.shell.valid then
        entry_portaldata.collider_needs_rebuild = true

        -- [保险措施] 确保它在活跃列表中，这样 on_tick 才会去处理它
        -- 使用辅助函数
        add_to_active(entry_portaldata)
    end
end

-- =================================================================================
-- 传送下一节车厢 (由 on_tick 驱动)
-- =================================================================================
function Teleport.process_transfer_step(entry_portaldata, exit_portaldata)
    -- 必须在 entry_portaldata.exit_car 被后续逻辑更新之前记录下来
    local is_first_car = (entry_portaldata.exit_car == nil)

    -- 安全检查
    if not (exit_portaldata and exit_portaldata.shell and exit_portaldata.shell.valid) then
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("错误: 出口失效，传送中断。")
        end
        finalize_sequence(entry_portaldata, entry_portaldata) -- 自身清理
        return
    end

    -- 检查入口车厢
    local car = entry_portaldata.entry_car
    if not (car and car.valid) then
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("入口车厢失效或丢失，结束传送。")
        end
        finalize_sequence(entry_portaldata, exit_portaldata)
        return
    end

    -- 检查出口是否堵塞
    -- 使用统一函数获取缓存
    local geo = ensure_geometry_cache(exit_portaldata)
    if not geo then
        return
    end -- 保护性检查
    local spawn_pos = Util.add_offset(exit_portaldata.shell.position, geo.spawn_offset)

    -- 动态生成出口检测区域 (使用配置表)
    local check_area = {
        left_top = Util.add_offset(spawn_pos, geo.check_area_rel.lt),
        right_bottom = Util.add_offset(spawn_pos, geo.check_area_rel.rb),
    }

    -- 如果前面有车 (exit_car)，说明正在传送中，不需要检查堵塞 (我们是接在它后面的)
    -- 只有当 exit_car 为空 (第一节) 时才检查堵塞
    local is_clear = true
    if not entry_portaldata.exit_car then
        local count = exit_portaldata.surface.count_entities_filtered({
            area = check_area,
            type = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" },
        })
        if count > 0 then
            is_clear = false
        end
    end

    -- 堵塞处理
    if not is_clear then
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("出口堵塞，暂停传送...")
        end

        return -- 必须返回，中断传送
    end

    -- 动态拼接检测
    -- 询问引擎：当前位置是否已经空出来，可以放置新车厢了？
    -- 如果前车还没被引导车拉远，这里会返回 false
    local can_place = exit_portaldata.surface.can_place_entity({
        name = car.name,
        position = spawn_pos,
        direction = geo.direction,
        force = car.force,
    })

    if not can_place then
        return -- 位置没空出来，跳过本次循环，等待下一帧
    end

    -- 开始传送当前车厢
    if RiftRail.DEBUG_MODE_ENABLED then
        log_tp("正在传送车厢: " .. car.name)
    end

    -- 第一节车时记录正在查看该列车 GUI 的玩家
    if is_first_car and car.train then
        -- 构建 GUI 映射表，存入 entry_portaldata (因为要在传送循环中用)
        entry_portaldata.gui_map = collect_gui_watchers(car.train)
    end

    -- 获取下一节车 (用于更新循环)
    local next_car = car.get_connected_rolling_stock(defines.rail_direction.front)
    if next_car == car then
        next_car = nil
    end -- 防止环形误判
    -- 简单查找另一端
    if not next_car then
        next_car = car.get_connected_rolling_stock(defines.rail_direction.back)
    end
    -- 排除掉刚刚传送过去的那节 (entry_portaldata.exit_car 记录的是上一节在新表面的替身，这里我们需要在旧表面找)
    -- 此处简化逻辑：因为是单向移除，旧车厢会被销毁，所以 get_connected 应该只能找到还没传的

    -- 保存第一节车的数据 (用于 Cybersyn / 恢复)
    if not entry_portaldata.exit_car then
        exit_portaldata.saved_manual_mode = car.train.manual_mode
        exit_portaldata.saved_speed = car.train.speed
        exit_portaldata.old_train_id = car.train.id

        -- 触发模组开始钩子 (自动处理标签和快照)
        if CybersynCompat then
            exit_portaldata.cybersyn_snapshot = CybersynCompat.on_teleport_start(car.train)
        end

        -- [SE] Started 事件
        if SE_TELEPORT_STARTED_EVENT_ID then
            if RiftRail.DEBUG_MODE_ENABLED then
                log_tp("【DEBUG】准备触发 STARTED 事件: old_train_id = " .. tostring(car.train.id))
            end
            script.raise_event(SE_TELEPORT_STARTED_EVENT_ID, {
                train = car.train,
                old_train_id_1 = car.train.id,
                old_surface_index = entry_portaldata.surface.index,
                teleporter = entry_portaldata.shell,
            })
        end
    end

    -- 计算目标朝向
    -- 参数：入口方向, 出口几何预设方向, 车厢当前方向
    -- 接收 target_ori 和 is_nose_in 两个返回值
    local target_ori, is_nose_in = calculate_arrival_orientation(entry_portaldata.shell.direction, geo.direction,
        car.orientation)

    -- 判断是否需要引导车 (如果是正向车头则不需要)
    local need_leader = is_first_car and (car.type ~= "locomotive" or not is_nose_in)

    -- 【关键】在创建新车厢前，读取当前出口列车的实际索引
    -- 因为 create_entity 时新车厢会立即拼接，索引会回退到1
    local index_before_spawn = nil
    if not is_first_car and exit_portaldata.exit_car and exit_portaldata.exit_car.valid then
        local current_train = exit_portaldata.exit_car.train
        if current_train and current_train.valid then
            index_before_spawn = read_train_schedule_index(current_train)
        end
    end

    -- 必须先保存旧车ID用于查表
    local old_car_id = car.unit_number

    -- 使用克隆工厂一键生成
    local new_car = spawn_cloned_car(car, exit_portaldata.surface, spawn_pos, target_ori)

    if not new_car then
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("严重错误: 无法在出口创建车厢！")
        end
        finalize_sequence(entry_portaldata, exit_portaldata)
        return
    end

    --[[     -- =========================================================================
    -- 强制连接逻辑：防止高速传送断裂
    -- =========================================================================
    -- 获取上一节传送过去的车厢 (也就是 A)
    local prev_car = entry_portaldata.exit_car

    -- 只有当上一节车存在时，才需要连接 (第一节车不需要连谁)
    if prev_car and prev_car.valid then
        -- 盲连策略：让新车厢 (B) 向前后两个方向尝试抓取
        -- 只要抓到了 prev_car，引擎会自动合并列车
        local connected_front = new_car.connect_rolling_stock(defines.rail_direction.front)
        local connected_back = new_car.connect_rolling_stock(defines.rail_direction.back)

        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("强制连接: 新车(ID" .. new_car.unit_number .. ") -> 前车(ID" .. prev_car.unit_number .. ") | 前向结果:" .. tostring(connected_front) .. " 后向结果:" .. tostring(connected_back))
        end
    end ]]

    -- 转移时刻表与保存索引
    if not entry_portaldata.exit_car then
        -- 1. 获取带图标的真实站名 (解决比对失败问题)
        local real_station_name = get_real_station_name(entry_portaldata)
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("时刻表转移: 使用真实站名 '" .. real_station_name .. "' 进行比对")
        end
        -- 2. 转移时刻表
        Schedule.copy_schedule(car.train, new_car.train, real_station_name)

        -- 关键修复: 在被引导车重置前，立刻备份正确的索引！
        if new_car.train and new_car.train.schedule then
            exit_portaldata.saved_schedule_index = new_car.train.schedule.current
        end
        -- 3. 保存新火车的时刻表索引 (解决重置问题)
        -- copy_schedule 内部已经调用了 go_to_station，所以现在的 current 是正确的下一站

        -- 触发 LTN 到达钩子 (自动处理重指派)
        -- 注意：LTN 比较特殊，通常需要在生成第一节车后立刻指派，以支持后续的时刻表操作
        if LtnCompat then
            LtnCompat.on_teleport_end(new_car.train, exit_portaldata.old_train_id)
        end
    end

    -- 立即恢复查看这节车厢的玩家界面
    if entry_portaldata.gui_map then
        -- 查表：O(1) 复杂度
        local watchers = entry_portaldata.gui_map[old_car_id]
        if watchers then
            reopen_car_gui(watchers, new_car)
            -- 恢复后从表中移除，释放内存
            entry_portaldata.gui_map[old_car_id] = nil
        end
    end

    -- 销毁旧车厢
    car.destroy()

    -- 更新链表指针
    entry_portaldata.exit_car = new_car -- 记录刚传过去的这节 (虽然没什么用，但保持一致)
    exit_portaldata.exit_car = new_car  -- 记录出口的最前头 (用于拉动)

    -- 准备下一节
    -- =========================================================================
    -- 引导车 (Leader) 生成逻辑：只在第一节车时生成，且不再销毁
    -- =========================================================================
    -- 1. 如果是第一节车，生成引导车 (Leader)
    if need_leader then
        -- 计算位于前方的引导车坐标 (leadertrain_offset 已改为前方)
        local leadertrain_pos = Util.add_offset(exit_portaldata.shell.position, geo.leadertrain_offset)
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("正在创建引导车 (Leader)... 坐标偏移: x=" .. geo.leadertrain_offset.x .. ", y=" .. geo.leadertrain_offset.y)
        end
        local leadertrain = exit_portaldata.surface.create_entity({
            name = "rift-rail-leader-train",
            position = leadertrain_pos,
            direction = geo.direction,
            force = new_car.force,
        })

        if leadertrain then
            leadertrain.destructible = false
            exit_portaldata.leadertrain = leadertrain
            if RiftRail.DEBUG_MODE_ENABLED then
                log_tp("引导车创建成功 ID: " .. leadertrain.unit_number)
            end
        else
            if RiftRail.DEBUG_MODE_ENABLED then
                log_tp("错误：引导车创建失败！")
            end
        end
        -- 如果是第一节车但不需要引导车时的日志
    elseif is_first_car then
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("优化：首节为正向车头，跳过引导车生成。")
        end
    end

    -- =========================================================================
    -- 状态一致性维护：每次拼接后恢复索引和模式
    -- 使用创建前读取的索引（如果有），否则用 saved_schedule_index
    -- =========================================================================
    if exit_portaldata.exit_car and exit_portaldata.exit_car.valid then
        local merged_train = exit_portaldata.exit_car.train
        if merged_train and merged_train.valid then
            local target_index = index_before_spawn or exit_portaldata.saved_schedule_index
            if RiftRail.DEBUG_MODE_ENABLED then
                log_tp("【创建后】准备恢复: index_before_spawn=" ..
                tostring(index_before_spawn) ..
                ", saved_index=" ..
                tostring(exit_portaldata.saved_schedule_index) .. ", 使用target=" .. tostring(target_index))
            end
            restore_train_state(merged_train, exit_portaldata, false, target_index)
        end
    end

    -- 2. 准备下一节 (简化版：只更新指针，不再生成引导车)
    if next_car and next_car.valid then
        entry_portaldata.entry_car = next_car
    else
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("最后一节车厢传送完毕。")
        end
        -- 传送结束，调用 finalize_sequence 进行收尾 (销毁引导车，恢复最终速度)
        finalize_sequence(entry_portaldata, exit_portaldata)
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
    -- 或者更简单：在 Builder.lua 里我们记录了 portaldata，我们可以遍历查找
    -- 但遍历太慢。更好的方法是：on_entity_died 传入的 entity 我们去 State 查
    -- 但 State.get_portaldata 主要是查 Shell 或 Core。
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

    local portaldata = State.get_portaldata(shell)
    if not portaldata then
        return
    end

    -- 2. 尝试捕获肇事车辆
    local car = nil
    if event.cause and event.cause.train then
        -- 如果是火车撞的，直接取肇事车厢
        car = event.cause
    else
        -- 否则搜索附近的火车车厢 (半径3)
        local cars = entity.surface.find_entities_filtered({
            type = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" },
            position = entity.position,
            radius = 3,
            limit = 1,
        })
        if cars[1] then
            car = cars[1]
        end
    end

    -- 3. 根据是否有车，决定下一步任务
    if car then
        -- 情况 A: 有车 -> 尝试启动传送流程
        local success = try_start_teleport(portaldata, car)

        -- 如果启动失败 (例如未配对)，则降级为只重建碰撞器
        if not success then
            portaldata.collider_needs_rebuild = true
        end
    else
        -- 情况 B: 无车 (被虫子咬了等) -> 只需标记重建
        portaldata.collider_needs_rebuild = true
    end
    -- 4. 入队 (无论是重建还是传送，都需要 tick 驱动)
    add_to_active(portaldata)
end

-- =================================================================================
-- 持续动力 (每 tick 调用)
-- =================================================================================

function Teleport.sync_momentum(portaldata)
    if not portaldata.paired_to_id then
        return
    end
    local exit_portaldata = State.get_portaldata_by_id(portaldata.paired_to_id)
    if not (exit_portaldata and exit_portaldata.shell and exit_portaldata.shell.valid) then
        return
    end

    local car_entry = portaldata.entry_car
    local car_exit = exit_portaldata.exit_car

    if car_entry and car_entry.valid and car_exit and car_exit.valid then
        local train_entry = car_entry.train
        local train_exit = car_exit.train

        if train_entry and train_entry.valid and train_exit and train_exit.valid then
            -- 1. 强制入口手动模式 (保持不变，入口必须完全接管)
            if not train_entry.manual_mode then
                train_entry.manual_mode = true
            end

            -- 移除了强制出口火车 (train_exit) 手动模式的代码
            -- 允许出口火车保持自动模式，以便引擎能够检测红绿灯信号

            -- 2. 维持出口动力 (已重构为距离比对法)
            -- 直接锁定为设定速度
            -- 这是一个强制行为，确保列车不会因为传送而掉速或超速。
            -- 同时这会产生“弹射/吸入”效果，最大化吞吐量。
            local target_speed = settings.global["rift-rail-teleport-speed"].value

            -- 计算出口列车所需的速度方向
            -- 以出口传送门的位置为参考点
            local required_sign = calculate_speed_sign(train_exit, exit_portaldata)

            -- 每60tick(1秒)打印一次，监控计算结果
            if RiftRail.DEBUG_MODE_ENABLED then
                if game.tick % 60 == portaldata.unit_number % 60 then
                    log_tp("【Speed Exit】ReqSign=" .. required_sign .. " | TrainSpeed=" .. train_exit.speed)
                end
            end

            -- 应用速度前增加状态检查 (保持不变)
            local should_push = train_exit.manual_mode or (train_exit.state == defines.train_state.on_the_path)

            if should_push then
                -- 直接赋值，不管它现在是快了还是慢了
                -- 这样既解决了掉速卡顿，也解决了超速断裂
                train_exit.speed = target_speed * required_sign
            end

            -- 3. 入口动力 (已重构为距离比对法)
            -- 使用新函数计算入口列车的逻辑方向
            -- 以入口传送门的位置为参考点
            local entry_sign = calculate_speed_sign(train_entry, portaldata)

            -- [关键] 反转符号
            -- calculate_speed_sign 计算的是"远离"的方向 (1 或 -1)
            -- 对于入口，我们需要的是"靠近"，所以将结果乘以 -1
            local final_sign = entry_sign * -1

            -- 每60tick打印一次
            if RiftRail.DEBUG_MODE_ENABLED then
                if game.tick % 60 == portaldata.unit_number % 60 then
                    log_tp("【Speed Entry】CalcSign=" .. entry_sign .. " -> FinalSign=" .. final_sign)
                end
            end

            -- 应用与出口速度大小同步的、方向修正后的速度
            train_entry.speed = math.abs(train_exit.speed) * final_sign
        end
    end
end

-- =================================================================================
-- 【独立任务】处理碰撞器重建
-- =================================================================================
local function process_rebuild_collider(portaldata)
    if not (portaldata.shell and portaldata.shell.valid) then
        return
    end

    -- 1. 查表获取偏移
    local geo = GEOMETRY[portaldata.shell.direction] or GEOMETRY[0]

    -- 2. 计算绝对坐标
    local final_pos = Util.add_offset(portaldata.shell.position, geo.collider_offset)

    -- 3. 创建实体碰撞器
    local new_collider = portaldata.surface.create_entity({
        name = "rift-rail-collider",
        position = final_pos,
        force = portaldata.shell.force,
    })

    -- 4. 将新碰撞器同步回 children 列表
    if new_collider and portaldata.children then
        -- 清理旧引用 (倒序)
        for i = #portaldata.children, 1, -1 do
            local child_data = portaldata.children[i]
            if child_data and child_data.entity and (not child_data.entity.valid or child_data.entity.name == "rift-rail-collider") then
                table.remove(portaldata.children, i)
            end
        end

        -- 注册新引用
        table.insert(portaldata.children, {
            entity = new_collider,
            relative_pos = geo.collider_offset, -- 直接复用查表结果
        })
    end

    -- 5. 标记完成
    portaldata.collider_needs_rebuild = false
end

-- =================================================================================
-- 【独立任务】处理传送序列步进
-- =================================================================================
local function process_teleport_sequence(portaldata, tick)
    -- 频率控制：从游戏设置中读取间隔值
    local interval = settings.global["rift-rail-placement-interval"].value
    -- 只有当间隔大于1时，才启用频率控制，以获得最佳性能
    if interval > 1 and tick % interval ~= portaldata.unit_number % interval then
        return
    end

    if portaldata.entry_car then
        -- 还有车厢，继续传送
        local exit_portaldata = State.get_portaldata_by_id(portaldata.paired_to_id)
        Teleport.process_transfer_step(portaldata, exit_portaldata)
    else
        -- 没有后续车厢，传送结束
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("传送序列正常结束，关闭状态。")
        end
        portaldata.is_teleporting = false
    end
end
-- =================================================================================
-- Tick 调度 (GC 优化版)
-- =================================================================================

function Teleport.on_tick(event)
    -- [优化] 直接遍历有序列表
    local list = storage.active_teleporter_list or {}

    for i = #list, 1, -1 do
        local portaldata = list[i]

        -- [保护] 确保数据有效
        if portaldata and portaldata.shell and portaldata.shell.valid then
            -- 任务 A: 重建碰撞器
            if portaldata.collider_needs_rebuild then
                process_rebuild_collider(portaldata)
            end

            -- 任务 B: 传送逻辑
            if portaldata.is_teleporting then
                -- 1. 执行序列步进 (含频率控制)
                process_teleport_sequence(portaldata, event.tick)

                -- 2. 持续动力控制 (每 tick 都要执行，保持吸附力)
                -- 只有当状态依然是 teleporting 时才执行 (防止刚刚 sequence 结束了)
                if portaldata.is_teleporting then
                    Teleport.sync_momentum(portaldata)
                end
            end

            -- 出队检查
            if not portaldata.is_teleporting and not portaldata.collider_needs_rebuild then
                -- 从活跃列表移除
                storage.active_teleporters[portaldata.unit_number] = nil
                table.remove(list, i)
            end
        else
            -- 结构无效，直接清理
            if portaldata and portaldata.unit_number then
                storage.active_teleporters[portaldata.unit_number] = nil
            end
            table.remove(list, i)
        end
    end
end

return Teleport
