-- scripts/teleport.lua
-- 【Rift Rail - 传送核心模块】
-- 功能：处理火车传送的完整运行时逻辑

local Teleport = {}
-- =================================================================================
-- 【事件广播模块】 - 集中处理自定义API事件的触发
-- =================================================================================
local Events = nil
-- 负责触发“出发”事件
---@see doc/API(CN).md#remote.call("RiftRail", "get_train_departing_event")
---@see doc/API(EN).md#How-to-Get-Rift-Rail-Custom-Event-IDs
local function raise_departing_event(entry_portaldata, train_to_depart)
    if not (entry_portaldata and entry_portaldata.shell and train_to_depart and train_to_depart.valid) then
        return
    end

    local shell = entry_portaldata.shell
    local surface = entry_portaldata.surface

    -- 通过依赖注入的 Events 获取事件ID
    if not Events or not Events.TrainDeparting then
        return
    end
    script.raise_event(Events.TrainDeparting, {
        train = train_to_depart,
        train_id = train_to_depart.id,
        source_teleporter = shell,
        source_teleporter_id = shell.unit_number,
        source_surface = surface,
        source_surface_index = surface.index,
    })
end

-- 负责触发“抵达”事件
---@see doc/API(CN).md#remote.call("RiftRail", "get_train_arrived_event")
---@see doc/API(EN).md#How-to-Get-Rift-Rail-Custom-Event-IDs
local function raise_arrived_event(entry_portaldata, exit_portaldata, final_train)
    if not (entry_portaldata and exit_portaldata and exit_portaldata.shell and final_train and final_train.valid) then
        return
    end

    local exit_shell = exit_portaldata.shell
    local exit_surface = exit_portaldata.surface
    local entry_surface = entry_portaldata.surface

    -- 通过依赖注入的 Events 获取事件ID
    if not Events or not Events.TrainArrived then
        return
    end
    script.raise_event(Events.TrainArrived, {
        train = final_train,
        train_id = final_train.id,
        old_train_id = exit_portaldata.old_train_id,

        source_surface = entry_surface,
        source_surface_index = entry_surface.index,

        destination_teleporter = exit_shell,
        destination_teleporter_id = exit_shell.unit_number,
        destination_surface = exit_surface,
        destination_surface_index = exit_surface.index,
    })
end

-- =================================================================================
-- 依赖与日志系统
-- =================================================================================
local State = nil
local Util = nil
local Schedule = nil
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
    LtnCompat = deps.LtnCompat
    -- 接收事件ID表
    if deps.Events then
        Events = deps.Events
    end
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
---@param train LuaTrain 要读取的列车 / The train to read
---@param phase_name string 阶段名（可选）/ Phase name (optional)
---@return integer|nil 当前时刻表索引 / Current schedule index
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
---@param portaldata PortalData 传送门数据 / Portal data
---@param name_to_find string 要查找的实体名 / Entity name to find
---@return LuaEntity|nil 匹配的子实体 / Matched child entity
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
---@param portaldata PortalData 传送门数据 / Portal data
---@return string 真实车站名称 / Real station name
local function get_real_station_name(portaldata)
    -- 适配 children 结构 {entity=..., relative_pos=...}
    local station = find_child_entity(portaldata, "rift-rail-station")
    if station then
        return station.backer_name
    end
    return portaldata.name
end
-- =================================================================================
-- 精准记录查看具体车厢的玩家（映射表模式）
-- =================================================================================
---@param train LuaTrain 要查找的列车 / The train to search
---@return table|nil 车厢ID到玩家列表映射 / Map<UnitNumber, Player[]>  { [carriage ID] = {PlayerA, PlayerB} }
local function collect_gui_watchers(train)
    local map = {}

    if not settings.global["rift-rail-train-gui-track"].value then
        return nil -- 如果功能被全局禁用，直接返回 nil
    end

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
-- 精准恢复 GUI 到指定车厢实体
-- =================================================================================

---@param watchers table 玩家对象列表 / List of player objects
---@param entity LuaEntity 新生成的车厢实体 / Newly created carriage entity
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
---@param train LuaTrain 要计算的列车 / The train to calculate
---@param select_portal PortalData 参考传送门 / Reference portal
---@return integer 1 代表逻辑正向 (Front更远), -1 代表逻辑反向 (Back更远)。/ 1 for forward, -1 for backward
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

-- =========================================================================
-- 入口速度控制：施加“脉冲推力” (事件驱动核心)
-- =========================================================================
---@param entry_portaldata PortalData 入口数据 / Entry portal data
---@param exit_portaldata PortalData 出口数据 / Exit portal data
---@return number 施加的速度值 / Applied speed value
local function apply_entry_pulse(entry_portaldata, exit_portaldata)
    local entry_car = entry_portaldata.entry_car
    if not (entry_car and entry_car.valid) then
        return
    end

    local train = entry_car.train
    if not (train and train.valid) then
        return
    end

    -- 强制入口手动模式。
    if not train.manual_mode then
        train.manual_mode = true
    end

    -- 1. 获取目标速度大小
    local target_speed = (exit_portaldata and exit_portaldata.cached_teleport_speed) or settings.global["rift-rail-teleport-speed"].value

    -- 2. 重新计算当前入口列车应该进入入口的方向（正向/反向），并将其转化为速度符号
    local entry_sign = -1 * calculate_speed_sign(train, entry_portaldata)

    -- 3. 施加 10 速度迫使列车“靠近/吸入”传送门
    train.speed = target_speed * 10 * entry_sign

    game.print("施加入口脉冲: 目标速度=" .. target_speed .. ", 方向=" .. (entry_sign == 1 and "正向" or "反向") .. ", 实际速度=" .. train.speed)
    if RiftRail.DEBUG_MODE_ENABLED then
        log_tp("入口脉冲已施加: 速度=" .. train.speed)
    end
end
-- =================================================================================
-- 【纯函数】计算车厢在出口生成的朝向 (Orientation 0.0-1.0)
-- =================================================================================
---@param entry_shell_dir integer 入口传送门朝向 / Entry portal direction
---@param exit_geo_dir integer 出口传送门朝向 / Exit portal direction
---@param current_ori number 当前车厢朝向 / Current carriage orientation
---@return number 目标朝向 / Target orientation
---@return boolean 是否顺向 / Is nose-in
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
        log_tp("方向计算: 车厢=" .. string.format("%.2f", current_ori) .. ", 入口=" .. entry_shell_ori .. ", 判定=" .. (is_nose_in and "顺向(NoseIn)" or "逆向(TailIn)"))
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
-- 司机转移函数 (处理玩家和NPC两种情况)
-- =================================================================================
local function transfer_driver(old_entity, new_entity)
    if not (old_entity and old_entity.valid and new_entity and new_entity.valid) then
        return
    end

    local driver = old_entity.get_driver()
    if driver then
        old_entity.set_driver(nil)
        if driver.object_name == "LuaPlayer" then
            new_entity.set_driver(driver)
        elseif driver.valid and driver.teleport then
            driver.teleport(new_entity.position, new_entity.surface)
            new_entity.set_driver(driver)
        end
    end
end

-- =================================================================================
-- 【克隆工厂 v3.0 - 旋转克隆】 - 统一处理所有平行传送
-- =================================================================================
---@param old_entity LuaEntity 原车厢实体 / Old carriage entity
---@param surface LuaSurface 目标地表 / Target surface
---@param position Position 目标坐标 / Target position
---@param needs_rotation boolean 是否需要在克隆前进行原地180度旋转 / Whether needs rotation
---@return LuaEntity|nil 新车厢实体 / New carriage entity
local function spawn_via_clone(old_entity, surface, position, needs_rotation)
    if not (old_entity and old_entity.valid) then
        return nil
    end

    -- 步骤 1: 如果需要，执行“断开->旋转”
    if needs_rotation then
        -- 物理隔离，为旋转做准备
        old_entity.disconnect_rolling_stock(defines.rail_direction.front)
        old_entity.disconnect_rolling_stock(defines.rail_direction.back)

        -- 尝试原地掉头
        local rotated_successfully = old_entity.rotate()

        if not rotated_successfully then
            -- 极端情况：由于铁轨扭曲等原因，原地旋转失败。
            -- 优雅地失败，让主逻辑降级到 create_entity。
            if RiftRail.DEBUG_MODE_ENABLED then
                log_tp("警告：车厢在入口原地旋转失败，将尝试使用 create_entity 降级处理。")
            end
            return nil -- 返回 nil，主逻辑会知道需要使用备用方案
        end
    end

    -- 步骤 2: 极速克隆
    -- 无论是旋转过的还是没旋转的，都直接克隆
    local new_entity = old_entity.clone({
        surface = surface,
        position = position,
        force = old_entity.force,
        create_build_effect_smoke = false,
    })

    if not new_entity then
        -- 克隆失败，可能是出口在最后一刻被堵住
        -- 不需要做任何回滚，主逻辑会在下一tick重新尝试
        return nil
    end

    -- 步骤 3: 手动转移司机 (clone 唯一不复制的东西)
    transfer_driver(old_entity, new_entity)

    return new_entity
end

-- =================================================================================
-- 【克隆工厂】生成替身车厢并转移所有属性
-- =================================================================================
---@param old_entity LuaEntity 原车厢实体 / Old carriage entity
---@param surface LuaSurface 目标地表 / Target surface
---@param position Position 目标坐标 / Target position
---@param orientation number 目标朝向(0.0-1.0) / Target orientation (0.0-1.0)
---@return LuaEntity|nil 新车厢实体 / New carriage entity
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
        snap_to_grid = false,
        create_build_effect_smoke = false,
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
    transfer_driver(old_entity, new_entity)

    return new_entity
end

-- =================================================================================
-- 【智能生成决策 v4.0】 - 封装所有创建逻辑的主函数
-- =================================================================================
-- 这个函数是传送的核心大脑，它会决定使用最高效的方式创建下一节车厢。
---@param car LuaEntity 要传送的旧车厢 / Old carriage to teleport
---@param entry_portaldata PortalData 入口数据 / Entry portal data
---@param exit_portaldata PortalData 出口数据 / Exit portal data
---@param spawn_pos Position 出口生成坐标 / Spawn position
---@param geo table 几何数据 / Geometry data
---@return LuaEntity|nil 新车厢实体 / New carriage entity
local function spawn_next_car_intelligently(car, entry_portaldata, exit_portaldata, spawn_pos, geo)
    local new_car = nil

    -- 首先，判断入口和出口铁轨是否平行
    local entry_dir = entry_portaldata.shell.direction
    local exit_dir = exit_portaldata.shell.direction
    local is_parallel = (entry_dir == exit_dir) or ((entry_dir + 8) % 16 == exit_dir)

    if is_parallel then
        -- 【高性能路径】铁轨平行，尝试使用 clone
        local needs_rotation = (entry_dir == exit_dir) -- 建筑同向时，需要旋转
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("优化: 铁轨平行，尝试使用 clone()。" .. (needs_rotation and " (需要旋转)" or " (无需旋转)"))
        end
        new_car = spawn_via_clone(car, exit_portaldata.surface, spawn_pos, needs_rotation)
    end

    -- 【降级/备用路径】如果不是平行，或者 clone 失败（比如旋转失败），则使用传统方法
    if not new_car then
        if is_parallel and RiftRail.DEBUG_MODE_ENABLED then
            log_tp("Clone 路径失败，降级至 create_entity 进行传送。")
        end
        local target_ori, is_nose_in = calculate_arrival_orientation(entry_dir, geo.direction, car.orientation)
        new_car = spawn_cloned_car(car, exit_portaldata.surface, spawn_pos, target_ori)
    end

    return new_car
end

-- =================================================================================
-- 【辅助函数】确保几何数据缓存有效 (去重逻辑)
-- =================================================================================
---@param portaldata PortalData 传送门数据 / Portal data
---@return table 有效的几何配置表 / Valid geometry config
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
-- 辅助函数：从列车时刻表中读取目标ID信号 (riftrail-go-to-id)
-- =================================================================================
---@param train LuaTrain 要读取的列车 / The train to read
---@return integer|nil 目标传送门ID / Target portal ID
local function get_circuit_go_to_id(train)
    if not (train and train.valid and train.schedule) then
        return nil
    end
    local current_sched = train.schedule
    local records = current_sched.records
    if not records then
        return nil
    end

    -- 读取当前站点的等待条件
    local current_record = records[current_sched.current]
    if current_record and current_record.wait_conditions then
        for _, cond in pairs(current_record.wait_conditions) do
            -- 读取 riftrail-go-to-id 信号的值
            -- LTN兼容模块或玩家手动设置都会使用这个信号
            if cond.type == "circuit" and cond.condition then
                local signal = cond.condition.first_signal
                if signal and signal.name == "riftrail-go-to-id" then
                    return cond.condition.constant -- 返回目标传送门的自定义ID
                end
            end
        end
    end
    return nil
end
-- =================================================================================
-- 目标选择器 (v4.0 - 统一使用 riftrail-go-to-id 信号)
-- =================================================================================
-- 优先级 1: go-to-id 信号 (无论来自LTN还是玩家手动设置)
-- 优先级 2: 默认返回第一个可用出口 (兜底)
---@param entry_portaldata PortalData 入口数据 / Entry portal data
---@return PortalData|nil 目标出口数据 / Target exit portal data
local function select_target_exit(entry_portaldata)
    -- [防御性检查 1] 确保入口数据存在
    if not entry_portaldata then
        return nil
    end

    -- 如果已缓存出口，优先使用 (这是正在传送中的状态，必须保持锁定)
    if entry_portaldata.selected_exit_id then
        local cached_portal = State.get_portaldata_by_id(entry_portaldata.selected_exit_id)
        if cached_portal and cached_portal.shell and cached_portal.shell.valid then
            return cached_portal
        end
    end

    -- [防御性检查 2] 确保 target_ids 是一个有效的表
    local targets = entry_portaldata.target_ids
    if type(targets) ~= "table" then
        return nil
    end

    -- [防御性检查 3] 确保表不为空 (使用 next 前再次确认)
    local first_id, _ = next(targets)
    if not first_id then
        return nil -- 列表是空的
    end

    -- [极速通道] 检查是否只有一个目标
    -- 此时 first_id 必定存在，我们检查是否有第二个
    if not next(targets, first_id) then
        local target_portal = State.get_portaldata_by_id(first_id)
        if target_portal and target_portal.shell and target_portal.shell.valid then
            return target_portal
        else
            return nil
        end
    end

    -- A. 获取列车对象
    local train = nil
    if entry_portaldata.waiting_car and entry_portaldata.waiting_car.valid then
        train = entry_portaldata.waiting_car.train
    elseif entry_portaldata.entry_car and entry_portaldata.entry_car.valid then
        train = entry_portaldata.entry_car.train
    end

    -- [优先级 1] riftrail-go-to-id 信号 (无论来自LTN还是玩家)
    if train then
        local target_id = get_circuit_go_to_id(train)
        if target_id and targets[target_id] then
            local target_portal = State.get_portaldata_by_id(target_id)
            if target_portal and target_portal.shell and target_portal.shell.valid then
                if RiftRail.DEBUG_MODE_ENABLED and entry_portaldata.waiting_car then
                    log_tp("智能路由: 识别到信号 riftrail-go-to-id = " .. target_id .. "，精准导向出口。")
                end
                return target_portal
            end
        end
    end

    -- 2. [优先级 中] 默认出口 (含老存档自动迁移)
    local def_id = entry_portaldata.default_exit_id

    -- 验证默认ID是否有效 (存在且还在连接列表中)
    local default_valid = false
    if def_id and targets[def_id] then
        local p = State.get_portaldata_by_id(def_id)
        if p and p.shell and p.shell.valid then
            default_valid = true
        end
    end

    -- [懒加载] 如果默认值无效/不存在，自动提拔列表中的第一个为默认
    if not default_valid then
        local first_id, _ = next(targets)
        if first_id then
            entry_portaldata.default_exit_id = first_id
            def_id = first_id
            default_valid = true
        end
    end

    -- 3. 返回默认出口
    if default_valid then
        return State.get_portaldata_by_id(def_id)
    end

    return nil
end
-- =================================================================================
-- 【业务逻辑】尝试启动传送流程
-- =================================================================================
---@param entry_portal PortalData 入口数据 / Entry portal data
---@param exit_portal PortalData 出口数据 / Exit portal data
local function initialize_teleport_session(entry_portal, exit_portal)
    -- 1. 抢占互斥锁
    exit_portal.locking_entry_id = entry_portal.unit_number

    -- 缓存出口，后续车厢不再重新选择
    entry_portal.selected_exit_id = exit_portal.id

    -- 2. 迁移车厢引用
    entry_portal.entry_car = entry_portal.waiting_car
    entry_portal.waiting_car = nil

    -- 3. 激活传送状态
    entry_portal.is_teleporting = true

    if RiftRail.DEBUG_MODE_ENABLED then
        log_tp("会话启动: 入口 " .. entry_portal.id .. " 锁定出口 " .. exit_portal.id)
    end

    -- 触发“出发”事件
    raise_departing_event(entry_portal, entry_portal.entry_car.train)

    -- 给予入口列车起步的脉冲推力
    -- apply_entry_pulse(entry_portal, exit_portal)
end

-- 排队逻辑处理器
---@param portaldata PortalData 传送门数据 / Portal data
local function process_waiting_logic(portaldata)
    -- 车厢无效 -> 清理并退出
    if not (portaldata.waiting_car and portaldata.waiting_car.valid) then
        portaldata.waiting_car = nil
        return
    end

    -- 出口数据丢失 -> 清理并退出
    -- 使用目标选择器来寻找一个可用的出口
    local exit_portal = select_target_exit(portaldata)
    if not exit_portal then
        portaldata.waiting_car = nil
        return
    end

    -- 互斥锁繁忙 -> 退出 (等待下一帧)
    -- 规则: 锁不为空 且 锁不是我
    if exit_portal.locking_entry_id ~= nil and exit_portal.locking_entry_id ~= portaldata.unit_number then
        return
    end

    -- 通过所有检查 -> 执行初始化
    initialize_teleport_session(portaldata, exit_portal)
end
-- =================================================================================
-- 统一列车状态恢复函数
-- =================================================================================
---@param train LuaTrain 要恢复的列车 / Train to restore
---@param portaldata PortalData 传送门数据 / Portal data
---@param apply_speed boolean 是否恢复速度 / Whether to restore speed
---@param target_index integer|nil 目标索引 / Target index
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
-- 核心传送逻辑
-- =================================================================================

-- =================================================================================
-- 结束传送：清理状态，恢复数据
-- =================================================================================
---@param entry_portaldata PortalData 入口数据 / Entry portal data
---@param exit_portaldata PortalData 出口数据 / Exit portal data
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
            log_tp("【销毁后】准备恢复: actual_index=" .. tostring(actual_index_before_cleanup) .. ", saved_index=" .. tostring(exit_portaldata.saved_schedule_index))
        end
        -- 使用统一函数恢复状态 (参数 true 代表同时恢复速度)
        restore_train_state(final_train, exit_portaldata, true, actual_index_before_cleanup)

        -- 触发“抵达”事件
        raise_arrived_event(entry_portaldata, exit_portaldata, final_train)
    end

    -- 5. 重置状态变量
    entry_portaldata.entry_car = nil            -- 清理入口车厢引用，防止 on_tick 中的过期访问
    entry_portaldata.exit_car = nil             -- 清理入口车厢引用，防止 on_tick 中的过期访问
    entry_portaldata.selected_exit_id = nil     -- 清理已选出口缓存，允许下次重新选择
    entry_portaldata.gui_map = nil              -- 清理 GUI 观看者映射表
    exit_portaldata.entry_car = nil             -- 清理入口车厢引用，防止 on_tick 中的过期访问
    exit_portaldata.exit_car = nil              -- 清理出口车厢引用，防止 on_tick 中的过期访问
    exit_portaldata.old_train_id = nil          -- 清理旧车ID缓存
    exit_portaldata.cached_geo = nil            -- 清理几何缓存，强制下次重新计算
    exit_portaldata.cached_teleport_speed = nil -- 清理缓存速度
    exit_portaldata.saved_schedule_index = nil  -- 清理时刻表索引缓存
    exit_portaldata.locking_entry_id = nil      -- 释放互斥锁,允许其他入口使用
    exit_portaldata.placement_interval = nil    -- 清理放置间隔缓存
    exit_portaldata.saved_manual_mode = nil     -- 清理手动/自动模式缓存

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
---@param entry_portaldata PortalData 入口数据 / Entry portal data
---@param exit_portaldata PortalData 出口数据 / Exit portal data
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

    -- 【极限优化】直接从缓存读取绝对世界坐标，0 计算，0 内存分配！
    local spawn_pos = exit_portaldata.cached_spawn_pos
    local check_area = exit_portaldata.cached_check_area

    -- 如果前面有车 (exit_car)，说明正在传送中，不需要检查堵塞 (我们是接在它后面的)
    -- 只有当 exit_car 为空 (第一节) 时才检查堵塞
    local is_clear = true
    if not entry_portaldata.exit_car then
        local count = exit_portaldata.surface.count_entities_filtered({
            area = check_area,
            type = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" },
            limit = 1, -- 只需要知道是否有车，不需要确切数量
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

    -- 保存第一节车的数据
    if is_first_car then
        exit_portaldata.saved_manual_mode = car.train.manual_mode                                       -- 保存手动/自动模式
        exit_portaldata.old_train_id = car.train.id                                                     -- 保存旧车ID
        exit_portaldata.saved_schedule_index = car.train.schedule and car.train.schedule.current or nil -- 保存时刻表索引
        exit_portaldata.cached_teleport_speed = settings.global["rift-rail-teleport-speed"].value       -- 缓存设定中的列车速度，供 sync_momentum 使用
        exit_portaldata.placement_interval = settings.global["rift-rail-placement-interval"].value      -- 缓存设定中的放置间隔，供 process_teleport_sequence 使用
    end

    -- 计算目标朝向
    -- 参数：入口方向, 出口几何预设方向, 车厢当前方向
    -- 接收 target_ori 和 is_nose_in 两个返回值
    local _, is_nose_in = calculate_arrival_orientation(entry_portaldata.shell.direction, geo.direction, car.orientation)

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

    -- =========================================================================
    -- 【动态克隆决策】根据入口和出口的朝向决定使用哪种生成方式
    -- =========================================================================
    -- 【调用我们的新“大脑”函数来完成所有复杂的创建决策】
    local new_car = spawn_next_car_intelligently(car, entry_portaldata, exit_portaldata, spawn_pos, geo)

    if not new_car then
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("严重错误: 无法在出口创建车厢！")
        end
        -- finalize_sequence(entry_portaldata, exit_portaldata)
        return
    end

    -- 转移时刻表与保存索引
    if not entry_portaldata.exit_car then
        -- 1. 获取带图标的真实站名 (解决比对失败问题)
        local real_station_name = get_real_station_name(entry_portaldata)
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("时刻表转移: 使用真实站名 '" .. real_station_name .. "' 进行比对")
        end
        -- 2. 转移时刻表
        Schedule.copy_schedule(car.train, new_car.train, real_station_name, exit_portaldata.saved_schedule_index, exit_portaldata.saved_manual_mode)

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
    exit_portaldata.exit_car = new_car -- 记录出口的最前头 (用于拉动)

    -- 准备下一节
    -- =========================================================================
    -- 引导车 (Leader) 生成逻辑：只在第一节车时生成，且不再销毁
    -- =========================================================================
    -- 1. 如果是第一节车并且需要引导车，生成引导车 (Leader)
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
                log_tp("【创建后】准备恢复: index_before_spawn=" .. tostring(index_before_spawn) .. ", saved_index=" .. tostring(exit_portaldata.saved_schedule_index) .. ", 使用target=" .. tostring(target_index))
            end
            restore_train_state(merged_train, exit_portaldata, false, target_index)
        end
    end

    -- 2. 准备下一节 (简化版：只更新指针，不再生成引导车)
    if next_car and next_car.valid then
        entry_portaldata.entry_car = next_car
        -- 旧车厢消失后，给剩下半截列车补一脚脉冲油门
        apply_entry_pulse(entry_portaldata, exit_portaldata)
        return
    end
    if RiftRail.DEBUG_MODE_ENABLED then
        log_tp("最后一节车厢传送完毕。")
    end
    -- 传送结束，调用 finalize_sequence 进行收尾 (销毁引导车，恢复最终速度)
    finalize_sequence(entry_portaldata, exit_portaldata)
end

-- =================================================================================
-- 触发入口 (on_entity_died)
-- =================================================================================
---@param event EventData 碰撞器死亡事件 / Collider died event
function Teleport.on_collider_died(event)
    local entity = event.entity
    if not (entity and entity.valid) then
        return
    end

    if not (entity.unit_number and storage.collider_to_portal) then
        return
    end

    local cause = event.cause -- 撞击者
    if cause and cause.name == "rift-rail-leader-train" then
        cause.destroy()
        game.print({ "messages.rift-rail-error-destroyed-leader" })
        return -- 销毁后直接结束，不执行任何传送逻辑
    end

    -- 获取传送门 ID
    local portal_unit_number = storage.collider_to_portal[entity.unit_number]
    if not portal_unit_number then
        return -- 不是我们的碰撞器，或者是旧版遗留
    end

    -- 立即清理字典 (人死销户，防止内存泄漏)
    storage.collider_to_portal[entity.unit_number] = nil

    -- 获取传送门数据 (直接用 unit_number 查，最快)
    local portaldata = State.get_portaldata_by_unit_number(portal_unit_number)
    if not portaldata then
        return
    end

    -- 2. 尝试捕获肇事车辆
    local car = nil
    if event.cause and event.cause.train then
        -- 如果是火车撞的，直接取肇事车厢
        car = event.cause
    end
    -- 否则搜索附近的火车车厢 (半径3)
    if not car then
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
    if not car then
        portaldata.collider_needs_rebuild = true
        add_to_active(portaldata)
        return
    end
    -- 必须是入口模式
    if portaldata.mode ~= "entry" then
        portaldata.collider_needs_rebuild = true
        add_to_active(portaldata)
        return
    end
    -- 必须配对才能传送，否则直接重建碰撞器并报错
    if not (portaldata.target_ids and next(portaldata.target_ids)) then
        portaldata.collider_needs_rebuild = true
        add_to_active(portaldata)
        game.print({ "messages.rift-rail-error-unpaired-or-collider" })
        return
    end
    -- 不再立即传送，而是挂入等待队列
    portaldata.waiting_car = car
    if RiftRail.DEBUG_MODE_ENABLED then
        log_tp("排队挂号: 入口 " .. portaldata.id .. " 等待传送车厢 " .. car.unit_number)
    end
    -- 4. 入队 (无论是重建、传送还是排队，都需要 tick 驱动)
    add_to_active(portaldata)
end

-- =================================================================================
-- 持续动力 (每 tick 调用)
-- =================================================================================
---@param portaldata PortalData 传送门数据 / Portal data
function Teleport.sync_momentum(portaldata)
    -- 使用目标选择器
    local exit_portaldata = select_target_exit(portaldata)
    if not (exit_portaldata and exit_portaldata.shell and exit_portaldata.shell.valid) then
        return
    end

    local car_exit = exit_portaldata.exit_car

    if car_exit and car_exit.valid then
        local train_exit = car_exit.train

        if train_exit and train_exit.valid then
            -- 1. 维持出口动力 (已重构为距离比对法)
            -- 直接锁定为设定速度
            -- 这是一个强制行为，确保列车不会因为传送而掉速或超速。
            -- 同时这会产生“弹射/吸入”效果，最大化吞吐量。
            local target_speed = exit_portaldata.cached_teleport_speed or settings.global["rift-rail-teleport-speed"].value

            -- 计算出口列车所需的速度方向
            -- 以出口传送门的位置为参考点
            local required_sign = calculate_speed_sign(train_exit, exit_portaldata)

            -- 每60tick(1秒)打印一次，监控计算结果
            if RiftRail.DEBUG_MODE_ENABLED then
                if game.tick % 60 == portaldata.unit_number % 60 then
                    log_tp("【Speed Exit】ReqSign=" .. required_sign .. " | TrainSpeed=" .. train_exit.speed)
                end
            end

            -- 应用速度前增加状态检查
            local should_push = train_exit.manual_mode or (train_exit.state == defines.train_state.on_the_path)

            if should_push then
                -- 直接赋值，不管它现在是快了还是慢了
                -- 这样既解决了掉速卡顿，也解决了超速断裂
                train_exit.speed = target_speed * required_sign
            end
        end
    end
end

-- =================================================================================
-- 【独立任务】处理碰撞器重建
-- =================================================================================
---@param portaldata PortalData 传送门数据
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

    if not portaldata.children then
        portaldata.children = {}
    end

    -- 4. 将新碰撞器同步回 children 列表
    if new_collider and portaldata.children then

        if new_collider.unit_number then
            storage.collider_to_portal = storage.collider_to_portal or {}
            storage.collider_to_portal[new_collider.unit_number] = portaldata.unit_number
        end

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
---@param portaldata PortalData 传送门数据 / Portal data
---@param tick integer 当前tick / Current tick
local function process_teleport_sequence(portaldata, tick)
    -- 频率控制：从游戏设置中读取间隔值
    local interval = portaldata.placement_interval or settings.global["rift-rail-placement-interval"].value
    -- 只有当间隔大于1时，才启用频率控制，以获得最佳性能
    if interval > 1 and tick % interval ~= portaldata.unit_number % interval then
        return
    end

    if portaldata.entry_car then
        -- 还有车厢，继续传送
        -- 使用目标选择器
        local exit_portaldata = select_target_exit(portaldata)
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
---@param event EventData tick事件 / Tick event
function Teleport.on_tick(event)
    local list = storage.active_teleporter_list or {}

    for i = #list, 1, -1 do
        local portaldata = list[i]

        -- 顶层判断：数据无效直接清理
        if not (portaldata and portaldata.shell and portaldata.shell.valid) then
            if portaldata and portaldata.unit_number then
                storage.active_teleporters[portaldata.unit_number] = nil
            end
            table.remove(list, i)
        else
            -- === 任务调度区 ===

            -- 1. 重建碰撞器任务
            if portaldata.collider_needs_rebuild then
                process_rebuild_collider(portaldata)
            end

            -- 2. 传送任务
            if portaldata.is_teleporting then
                process_teleport_sequence(portaldata, event.tick)
                -- 动力同步需持续进行 (再次检查状态防止序列刚结束)
                if portaldata.is_teleporting then
                    Teleport.sync_momentum(portaldata)
                end
            end

            -- 3. 排队任务 (仅当未传送时)
            if not portaldata.is_teleporting and portaldata.waiting_car then
                process_waiting_logic(portaldata)
            end

            -- 4. 垃圾回收 (GC)
            -- 如果所有任务都空闲，移出活跃列表
            if not portaldata.is_teleporting and not portaldata.waiting_car and not portaldata.collider_needs_rebuild then
                storage.active_teleporters[portaldata.unit_number] = nil
                table.remove(list, i)
            end
        end
    end
end

return Teleport
