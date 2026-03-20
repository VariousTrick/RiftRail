-- scripts/teleport.lua
-- 【Rift Rail - 传送核心模块】
-- 功能：处理火车传送的完整运行时逻辑
---@diagnostic disable: need-check-nil, param-type-mismatch

local Teleport = {}

Teleport.STATE = {
    DORMANT = 0,
    QUEUED = 1,
    TELEPORTING = 2,
    REBUILDING = 3,
}
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
        train = train_to_depart,       -- 老车实体
        train_id = train_to_depart.id, -- 老车 ID
        source_teleporter = shell,
        source_teleporter_id = shell.unit_number,
        source_surface = surface,
        source_surface_index = surface.index,
    })
end

--- 负责触发“传送开始”事件 (给需要交接 ID 的 LTN 专属环节使用)
---@see doc/API(CN).md#remote.call("RiftRail", "get_train_teleport_transfer_event")
---@see doc/API(EN).md#How-to-Get-Rift-Rail-Custom-Event-IDs
local function raise_teleport_transfer_event(old_train_id, new_train)
    if not Events or not Events.TrainTeleportTransfer then
        return
    end
    script.raise_event(Events.TrainTeleportTransfer, {
        old_train_id = old_train_id,
        new_train_id = new_train.id,
        new_train = new_train
    })
end

-- 负责触发“抵达”事件
---@see doc/API(CN).md#remote.call("RiftRail", "get_train_arrived_event")
---@see doc/API(EN).md#How-to-Get-Rift-Rail-Custom-Event-IDs
local function raise_arrived_event(entry_portaldata, exit_portaldata, final_train, restored_guis)
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
        restored_guis = restored_guis, -- 成功恢复GUI的玩家和对应新车厢列表
    })
end

-- =================================================================================
-- 依赖与日志系统
-- =================================================================================
---@type StateModule
local State = nil
---@type UtilModule
local Util = nil
---@type ScheduleModule
local Schedule = nil
---@type AwCompatModule
local AwCompat = nil
---@type table
local Math = nil
---@type table
local Factory = nil

-- 1. 定义一个空的日志函数占位符
local log_debug = function(...) end

-- 2. 在 init 函数中接收来自 control.lua 的 log_debug 函数
function Teleport.init(deps)
    State = deps.State
    Util = deps.Util
    Schedule = deps.Schedule
    Math = deps.Math
    Factory = deps.Factory
    if deps.log_debug then
        log_debug = deps.log_debug
    end
    -- 接收兼容模块
    AwCompat = deps.AwCompat
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
-- 统一列车时刻表索引读取函数（直接读取真实指针）
-- =================================================================================
---@param train LuaTrain 要读取的列车 / The train to read
---@return integer|nil 当前时刻表索引 / Current schedule index
local function read_train_schedule_index(train)
    if not (train and train.valid) then
        return nil
    end

    local schedule = train.schedule
    if not schedule then
        return nil
    end

    local records = schedule.records
    if not records then
        return nil
    end

    local current = schedule.current
    if not current then
        return nil
    end

    if type(records) ~= "table" or #records == 0 then
        return nil
    end

    if type(current) ~= "number" or current < 1 or current > #records then
        return nil
    end

    return current
end

-- GEOMETRY 常量已迁移至 scripts/teleport_system/teleport_math.lua (TeleportMath.GEOMETRY)

-- =================================================================================
-- 活跃列表管理辅助函数 (GC 优化)
-- =================================================================================

-- 添加到活跃列表
-- 【性能重构】使用二分查找插入，替换 table.sort
local function add_to_active(portaldata)
    if not portaldata or not portaldata.unit_number then
        return
    end
-- 将传送门加入活跃列表
if storage.active_teleporters[portaldata.unit_number] then
    return -- 已经在列表中，无需重复添加
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

    -- 如果表是空的，返回 nil，而不是空表
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


-- =========================================================================
-- 入口速度控制：施加"脉冲推力" (事件驱动核心)
-- =========================================================================
---@param entry_portaldata PortalData 入口数据 / Entry portal data
---@param exit_portaldata PortalData 出口数据 / Exit portal data
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
    local target_speed = (exit_portaldata and exit_portaldata.cached_teleport_speed) or
    settings.global["rift-rail-teleport-speed"].value

    -- 2. 重新计算当前入口列车应该进入入口的方向（正向/反向），并将其转化为速度符号
    local entry_sign = -1 * Math.calculate_speed_sign(train, entry_portaldata)

    -- 3. 施加 10 速度迫使列车"靠近/吸入"传送门
    train.speed = target_speed * 10 * entry_sign

    if RiftRail.DEBUG_MODE_ENABLED then
        log_tp("入口脉冲已施加: 速度=" .. train.speed)
    end
end

-- =================================================================================
-- 【辅助函数】确保几何数据缓存有效 (去重逻辑)
-- =================================================================================
---@param portaldata PortalData 传送门数据 / Portal data
---@return table|nil 有效的几何配置表 / Valid geometry config
local function ensure_geometry_cache(portaldata)
    if not (portaldata and portaldata.shell and portaldata.shell.valid) then
        return nil
    end

    local geo = portaldata.cached_geo
    -- 检查缓存是否存在，且包含最新的字段 check_area_rel
    if not geo or not geo.check_area_rel then
        geo = Math.GEOMETRY[portaldata.shell.direction] or Math.GEOMETRY[0]
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
-- 辅助函数：从入口电路网络读取目标ID信号 (riftrail-go-to-id)
-- =================================================================================
---@param entry_portaldata PortalData 入口数据 / Entry portal data
---@return integer|nil 目标传送门ID / Target portal ID
local function get_entry_circuit_go_to_id(entry_portaldata)
    if not entry_portaldata then
        return nil
    end

    local signal_source = find_child_entity(entry_portaldata, "rift-rail-station")
    if not (signal_source and signal_source.valid) then
        signal_source = entry_portaldata.shell
    end

    if not (signal_source and signal_source.valid and signal_source.get_signal) then
        return nil
    end

    local signal_id = {
        type = "virtual",
        name = "riftrail-go-to-id",
    }

    local value = signal_source.get_signal(signal_id, defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green)
    if value and value ~= 0 then
        return value
    end

    return nil
end

---@param entry_portaldata PortalData 入口数据 / Entry portal data
---@param target_id integer|nil 目标出口ID / Target exit id
---@return PortalData|nil 目标出口数据 / Target exit portal data
local function resolve_valid_target(entry_portaldata, target_id)
    if not (entry_portaldata and target_id) then
        return nil
    end

    local targets = entry_portaldata.target_ids
    if not (targets and targets[target_id]) then
        return nil
    end

    local target_portal = State.get_portaldata_by_id(target_id)
    if not (target_portal and target_portal.shell and target_portal.shell.valid) then
        return nil
    end

    return target_portal
end
-- =================================================================================
-- 目标选择器 (v4.0 - 统一使用 riftrail-go-to-id 信号)
-- =================================================================================
-- 优先级 1: 列车时刻表中的 go-to-id 信号
-- 优先级 2: 入口电路网络中的 go-to-id 信号
-- 优先级 3: 默认返回第一个可用出口 (兜底)
---@param entry_portaldata PortalData 入口数据 / Entry portal data
---@return PortalData|nil 目标出口数据 / Target exit portal data
local function select_target_exit(entry_portaldata)

    -- [防御性检查 1] 确保入口数据存在
    if not entry_portaldata then
        return nil
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
        return resolve_valid_target(entry_portaldata, first_id)
    end

    -- 多出口优先使用缓存出口
    local cached_target = resolve_valid_target(entry_portaldata, entry_portaldata.waiting_target_exit_id)
    if cached_target then
        return cached_target
    end

    -- A. 获取列车对象
    local train = nil
    if entry_portaldata.waiting_car and entry_portaldata.waiting_car.valid then
        train = entry_portaldata.waiting_car.train
    end
    if not train and entry_portaldata.entry_car and entry_portaldata.entry_car.valid then
        train = entry_portaldata.entry_car.train
    end

    -- [优先级 1] 列车时刻表信号
    local train_target_id = nil
    local train_target_portal = nil
    if train then
        train_target_id = get_circuit_go_to_id(train)
        train_target_portal = resolve_valid_target(entry_portaldata, train_target_id)
        if train_target_portal then
            if RiftRail.DEBUG_MODE_ENABLED and entry_portaldata.waiting_car then
                log_tp("智能路由: 识别到信号 riftrail-go-to-id = " .. train_target_id .. "，精准导向出口。")
            end
            return train_target_portal
        end

        if train_target_id then
            game.print({ "messages.rift-rail-error-invalid-go-to-id-train", train_target_id, entry_portaldata.id })
        end
    end

    -- [优先级 2] 入口电路信号（列车信号不存在或无效时尝试）
    local entry_target_id = nil
    if not train_target_portal then
        entry_target_id = get_entry_circuit_go_to_id(entry_portaldata)
    end

    local entry_target_portal = resolve_valid_target(entry_portaldata, entry_target_id)
    if entry_target_portal then
        if RiftRail.DEBUG_MODE_ENABLED and entry_portaldata.waiting_car then
            log_tp("智能路由: 列车信号无效，命中入口信号 riftrail-go-to-id = " .. entry_target_id .. "，导向对应出口。")
        end
        return entry_target_portal
    end

    if entry_target_id then
        game.print({ "messages.rift-rail-error-invalid-go-to-id-entry", entry_target_id, entry_portaldata.id })
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
            default_valid = resolve_valid_target(entry_portaldata, def_id) ~= nil
        end
    end

    -- 3. 返回默认出口
    if default_valid then
        return resolve_valid_target(entry_portaldata, def_id)
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

    -- 直接把出口的物理身份证写死在记事本上
    entry_portal.locked_exit_unit_number = exit_portal.unit_number

    -- 2. 迁移车厢引用
    entry_portal.entry_car = entry_portal.waiting_car
    entry_portal.cached_entry_radius = Math.get_carriage_radius(entry_portal.entry_car)
    entry_portal.waiting_car = nil
    entry_portal.waiting_target_exit_id = nil

    -- 3. 激活传送状态
    entry_portal.state = Teleport.STATE.TELEPORTING

    if RiftRail.DEBUG_MODE_ENABLED then
        log_tp("会话启动: 入口 " .. entry_portal.id .. " 锁定出口 " .. exit_portal.id)
    end

    -- 触发“出发”事件
    raise_departing_event(entry_portal, entry_portal.entry_car.train)
end

-- 排队逻辑处理器
---@param portaldata PortalData 传送门数据 / Portal data
local function process_waiting_logic(portaldata)
    -- 车厢无效 -> 清理并退出
    if not (portaldata.waiting_car and portaldata.waiting_car.valid) then
        portaldata.waiting_car = nil
        portaldata.waiting_target_exit_id = nil
        portaldata.state = Teleport.STATE.DORMANT
        return
    end

    -- 出口数据丢失 -> 清理并退出
    -- 使用目标选择器来寻找一个可用的出口
    local exit_portal = select_target_exit(portaldata)
    if not exit_portal then
        portaldata.waiting_car = nil
        portaldata.waiting_target_exit_id = nil
        portaldata.state = Teleport.STATE.DORMANT
        return
    end
    portaldata.waiting_target_exit_id = exit_portal.id

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
---@param preferred_index integer|nil 优先恢复索引 / Preferred index
local function restore_train_state(train, portaldata, apply_speed, preferred_index)
    if not (train and train.valid) then
        return
    end

    if RiftRail.DEBUG_MODE_ENABLED then
        log_tp("状态恢复: TrainID=" .. train.id .. ", 恢复进度=" .. tostring(portaldata.saved_schedule_index ~= nil))
    end

    -- A. 恢复时刻表索引 (副作用：列车变为自动模式)
    -- 优先使用传入的 preferred_index，其次使用 saved_schedule_index
    local index_to_restore = preferred_index or portaldata.saved_schedule_index
    if index_to_restore then
        train.go_to_station(index_to_restore)
    end

    -- B. 恢复手动/自动模式
    train.manual_mode = portaldata.saved_manual_mode or false

    -- C. (可选) 恢复速度
    if apply_speed then
        local speed_mag = settings.global["rift-rail-teleport-speed"].value
        local sign = Math.calculate_speed_sign(train, portaldata)
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
---@param exit_portaldata PortalData|nil 出口数据 / Exit portal data
local function finalize_sequence(entry_portaldata, exit_portaldata)
    if RiftRail.DEBUG_MODE_ENABLED then
        local exit_id = exit_portaldata and exit_portaldata.id or "N/A(已摧毁)"
        log_tp("传送结束: 清理状态 (入口ID: " .. entry_portaldata.id .. ", 出口ID: " .. exit_id .. ")")
    end

    -- 1. 在销毁引导车前读取列车索引
    if exit_portaldata then
        local final_train = nil
        local actual_index_before_cleanup = nil
        if exit_portaldata.exit_car and exit_portaldata.exit_car.valid then
            final_train = exit_portaldata.exit_car.train
            if final_train and final_train.valid then
                actual_index_before_cleanup = read_train_schedule_index(final_train)
            end
        end

        -- 2. 销毁引导车（会导致列车对象失效并重新创建）
        local leader_destroyed = false
        if exit_portaldata.leadertrain and exit_portaldata.leadertrain.valid then
            exit_portaldata.leadertrain.destroy()
            exit_portaldata.leadertrain = nil
            leader_destroyed = true -- 标记：列车已经被物理截断
        end

        -- 仅当引导车被销毁，导致旧火车对象失效时，才重新获取！
        if leader_destroyed and exit_portaldata.exit_car and exit_portaldata.exit_car.valid then
            final_train = exit_portaldata.exit_car.train
        end

        if final_train and final_train.valid then
            if RiftRail.DEBUG_MODE_ENABLED then
                log_tp("【销毁后】准备恢复: actual_index=" .. tostring(actual_index_before_cleanup) .. ", saved_index=" .. tostring(exit_portaldata.saved_schedule_index))
            end
            -- 使用统一函数恢复状态 (参数 true 代表同时恢复速度)
            restore_train_state(final_train, exit_portaldata, true, actual_index_before_cleanup)

            -- 触发“抵达”事件
            raise_arrived_event(entry_portaldata, exit_portaldata, final_train, entry_portaldata.restored_guis)
        end

        -- 5. 重置状态变量

        -- 注意：exit_portaldata 不维护 entry_car，避免写入无效字段
        exit_portaldata.exit_car = nil                -- 清理出口车厢引用，防止 on_tick 中的过期访问
        exit_portaldata.old_train_id = nil            -- 清理旧车ID缓存
        exit_portaldata.cached_teleport_speed = nil   -- 清理缓存速度
        exit_portaldata.cached_speed_sign = nil       -- 清理速度方向缓存
        exit_portaldata.cached_exit_drive_sign = nil  -- 清理新的出口意图方向缓存
        exit_portaldata.saved_schedule_index = nil    -- 清理时刻表索引缓存
        exit_portaldata.locking_entry_id = nil        -- 释放互斥锁,允许其他入口使用
        exit_portaldata.saved_manual_mode = nil       -- 清理手动/自动模式缓存
        exit_portaldata.cached_exit_radius = nil      -- 清除外接圆半径缓存
        exit_portaldata.cached_destination_stop = nil -- 清理缓存的目的地站点数据
        exit_portaldata.cached_intent_vector = nil    -- 清理缓存的意图向量
    end

    if entry_portaldata then
        entry_portaldata.entry_car = nil               -- 清理入口车厢引用，防止 on_tick 中的过期访问
        entry_portaldata.exit_car = nil                -- 清理入口侧“上一节已生成替身”标记，供下一次会话重新判定首节
        entry_portaldata.locked_exit_unit_number = nil -- 清理物理死锁，允许下次传送重新排队选择
        entry_portaldata.gui_map = nil                 -- 清理 GUI 观看者映射表
        entry_portaldata.restored_guis = nil           -- 阅后即焚，清理恢复名单
        entry_portaldata.placement_interval = nil      -- 清理入口放置间隔缓存（process_teleport_sequence 读取入口侧）
        entry_portaldata.cached_entry_radius = nil     -- 兼容性清理旧版预缓存逻辑产生的无用字段
        entry_portaldata.last_car_name = nil           -- 阅后即焚，销毁列车类型的短时记忆
        entry_portaldata.last_car_radius = nil         -- 阅后即焚，销毁列车尺寸的短时记忆

    -- 6. 标记需要重建入口碰撞器
    -- 我们不在这里直接创建，而是交给 on_tick 去计算正确的坐标并创建
        entry_portaldata.state = Teleport.STATE.REBUILDING
        -- 确保它在活跃列表中，这样 on_tick 才会去处理它
        add_to_active(entry_portaldata)
    end
end

-- =================================================================================
-- 生成引导车 (Leader)
-- =================================================================================
--- 生成一个不可摧毁的引导车实体
---@param exit_portaldata PortalData 出口传送门数据
---@param geo table 几何设置信息
---@param force LuaForce 新车厢的阵营
local function spawn_leader_train(exit_portaldata, geo, force)
    -- 通过刚刚克隆出来的新车外接圆半径，动态推算最完美的引导车挤压距离
    local exit_radius = exit_portaldata.cached_exit_radius or 2.8
    -- 使用静态的门朝向和动态的安全距离推导向量
    local leader_offset = Math.get_dynamic_leader_offset(exit_portaldata.shell.direction, exit_radius)
    local leadertrain_pos = Util.add_offset(exit_portaldata.shell.position, leader_offset)
    if RiftRail.DEBUG_MODE_ENABLED then
        log_tp("正在创建引导车 (Leader)... 动态坐标偏移: x=" .. leader_offset.x .. ", y=" .. leader_offset.y)
    end
    local leadertrain = exit_portaldata.surface.create_entity({
        name = "rift-rail-leader-train",
        position = leadertrain_pos,
        direction = geo.direction,
        force = force,
    })
    if leadertrain then
        leadertrain.destructible = false
        exit_portaldata.leadertrain = leadertrain
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("引导车创建成功 ID: " .. leadertrain.unit_number)
        end
    end
end

-- =================================================================================
-- JIT 动态半径会话级缓存获取器 (O(1) 极速命中)
-- =================================================================================
local function get_memoized_radius(portaldata, car)
    -- O(1) 极速命中同类型车厢的短时记忆
    if portaldata.last_car_name == car.name and portaldata.last_car_radius then
        return portaldata.last_car_radius
    end
    -- 缓存未命中（首节车，或更换了异形车厢类型），重新穿透引擎跨层算并更新短时记忆
    local r = Math.get_carriage_radius(car)
    portaldata.last_car_name = car.name
    portaldata.last_car_radius = r
    return r
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
        finalize_sequence(entry_portaldata, nil) -- 自身清理
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

    -- =========================================================================
    -- 基于外接圆与重叠距离的刚体碰撞验证
    -- 用于确认出生点坐标已经安全让出空间
    -- =========================================================================
    local entry_radius = get_memoized_radius(entry_portaldata, car)
    local exit_radius = exit_portaldata.cached_exit_radius or 2.8

    if not Math.is_spawn_clear_math(spawn_pos, entry_radius, entry_portaldata.exit_car, exit_radius) then
        return -- 距离护盾未通过，等待前车驶离
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
        exit_portaldata.cached_teleport_speed = settings.global["rift-rail-teleport-speed"].value       -- 缓存设定中的列车速度，供 maintain_exit_speed 使用
        entry_portaldata.placement_interval = settings.global["rift-rail-placement-interval"].value     -- 缓存设定中的放置间隔，供 process_teleport_sequence 使用（入口侧读取）
    end

    -- 计算目标朝向
    -- 参数：入口方向, 出口几何预设方向, 车厢当前方向
    -- 接收 target_ori 和 is_nose_in 两个返回值
    local _, is_nose_in = Math.calculate_arrival_orientation(entry_portaldata.shell.direction, geo.direction, car.orientation)

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
    -- 根据入口和出口的朝向决定使用哪种生成方式
    -- =========================================================================
    local new_car = Factory.spawn_next_car_intelligently(car, entry_portaldata, exit_portaldata, spawn_pos, geo)

    if not new_car then
        if RiftRail.DEBUG_MODE_ENABLED then
            log_tp("严重错误: 无法在出口创建车厢！")
        end
        -- finalize_sequence(entry_portaldata, exit_portaldata)
        return
    end

    if AwCompat and AwCompat.on_car_replaced then
        AwCompat.on_car_replaced(car, new_car)
    end

    -- 转移时刻表与保存索引
    if not entry_portaldata.exit_car then
        -- 1. 获取带图标的真实站名 (解决比对失败问题)
        local real_station_name = get_real_station_name(entry_portaldata)

        -- 2. 转移时刻表
        Schedule.copy_schedule(car.train, new_car.train, real_station_name, exit_portaldata.saved_schedule_index, exit_portaldata.saved_manual_mode)

        -- 在被引导车重置前，立刻备份正确的索引！
        if new_car.train and new_car.train.schedule then
            exit_portaldata.saved_schedule_index = new_car.train.schedule.current
        end

        -- 新旧实体物理交接完毕，触发移交事件（除了传递ID，必须传递 new_train 实体供 LTN 使用）
        raise_teleport_transfer_event(car.train.id, new_car.train)
    end

    -- 立即恢复查看这节车厢的玩家界面
    if entry_portaldata.gui_map then
        local watchers = entry_portaldata.gui_map[old_car_id]
        if watchers then
            reopen_car_gui(watchers, new_car)

            -- 记录成功恢复的玩家和对应的新车厢
            entry_portaldata.restored_guis = entry_portaldata.restored_guis or {}
            for _, p in ipairs(watchers) do
                if p.valid then
                    table.insert(entry_portaldata.restored_guis, { player = p, entity = new_car })
                end
            end

            -- 恢复后从表中移除，释放内存
            entry_portaldata.gui_map[old_car_id] = nil
        end
    end

    -- 销毁旧车厢
    car.destroy()

    -- 更新链表指针
    entry_portaldata.exit_car = new_car                                    -- 记录入口侧最近生成的出口替身（用于首节判定与流程状态）
    exit_portaldata.exit_car = new_car                                     -- 记录出口的最前头 (用于拉动)
    exit_portaldata.cached_exit_radius = entry_radius                      -- 物理数据完美接力：从入口复制准确的几何半径给出口，无需重算

    -- 准备下一节
    -- =========================================================================
    -- 引导车 (Leader) 生成逻辑：只在第一节车时生成，且不再销毁
    -- =========================================================================
    -- 1. 如果是第一节车并且需要引导车，生成引导车 (Leader)
    if need_leader then
        spawn_leader_train(exit_portaldata, geo, new_car.force)
    end

    -- =========================================================================
    -- 状态一致性维护：每次拼接后恢复索引和模式
    -- 使用创建前读取的索引（如果有），否则用 saved_schedule_index
    -- =========================================================================
    if exit_portaldata.exit_car and exit_portaldata.exit_car.valid then
        local merged_train = exit_portaldata.exit_car.train
        if merged_train and merged_train.valid then
            -- 在每次拼接后，清空方向和目的地的双重缓存
            -- 这将强制 maintain_exit_speed 在下一帧进行完整的重新验证和计算
            exit_portaldata.cached_exit_drive_sign = nil  -- 清理出口意图方向缓存
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
        -- 旧版冗余预计算 cached_entry_radius 这里已被删除，交由下周期的 get_memoized_radius 推演
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

    -- 过滤传送中产生的多余碰撞器销毁事件
    -- 传送流程由内部链表接管，不应被后续碰撞中断
    if portaldata.state == Teleport.STATE.TELEPORTING then
        return
    end

    -- 2. 尝试捕获肇事车辆
    local car = nil
    if event.cause and event.cause.train then
        -- 如果是火车撞的，直接取肇事车厢
        car = event.cause
    end

    -- 3. 根据是否有车，决定下一步任务
    if not car then
        portaldata.state = Teleport.STATE.REBUILDING
        add_to_active(portaldata)
        return
    end
    -- 必须是入口模式
    if portaldata.mode ~= "entry" then
        portaldata.state = Teleport.STATE.REBUILDING
        add_to_active(portaldata)
        return
    end
    -- 必须配对才能传送，否则直接重建碰撞器并报错
    if not (portaldata.target_ids and next(portaldata.target_ids)) then
        portaldata.state = Teleport.STATE.REBUILDING
        add_to_active(portaldata)
        game.print({ "messages.rift-rail-error-unpaired-or-collider" })
        return
    end
    -- 不再立即传送，而是挂入等待队列
    portaldata.waiting_car = car
    portaldata.state = Teleport.STATE.QUEUED
    local preselected_exit = select_target_exit(portaldata)
    portaldata.waiting_target_exit_id = preselected_exit and preselected_exit.id or nil
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
function Teleport.maintain_exit_speed(portaldata)

    -- 直接从入口的记事本里读取锁定的出口 ID
    local exit_unit_number = portaldata.locked_exit_unit_number
    if not exit_unit_number then
        return
    end

    local exit_portaldata = State.get_portaldata_by_unit_number(exit_unit_number)

    -- 检查出口是否还有效
    if not (exit_portaldata and exit_portaldata.shell and exit_portaldata.shell.valid) then
        return
    end

    local car_exit = exit_portaldata.exit_car
    if not (car_exit and car_exit.valid) then
        return
    end

    local train_exit = car_exit.train
    if not (train_exit and train_exit.valid) then
        return
    end

    -- 1. 维持出口动力 (已重构为距离比对法)
    -- 直接锁定为设定速度
    -- 这是一个强制行为，确保列车不会因为传送而掉速或超速。
    -- 同时这会产生“弹射/吸入”效果，最大化吞吐量。
    local target_speed = exit_portaldata.cached_teleport_speed or settings.global["rift-rail-teleport-speed"].value

    -- 获取或计算纯物理几何的推离方向（算一次管一节）
    local phys_sign = exit_portaldata.cached_speed_sign
    if not phys_sign then
        phys_sign = Math.calculate_speed_sign(train_exit, exit_portaldata)
        exit_portaldata.cached_speed_sign = phys_sign
    end

    -- 【第一层判断：处理手动模式列车】
    if train_exit.manual_mode then
        -- 手动车直接使用缓存好的物理方向，不再每 tick 跨界调用！
        train_exit.speed = target_speed * phys_sign
        return
    end

    -- 【第二层判断：处理就绪的自动模式列车】
    if train_exit.state == defines.train_state.on_the_path then
        -- 1. 获取列车当前真正的目的地
        local current_destination = train_exit.path_end_stop

        -- 2. 【昂贵层】检查列车意图是否已改变 (玩家修改了时刻表 / 第一次生成)
        if current_destination ~= exit_portaldata.cached_destination_stop then
            exit_portaldata.cached_intent_vector = Math.get_ai_intent_vector(train_exit)
            exit_portaldata.cached_destination_stop = current_destination
            exit_portaldata.cached_exit_drive_sign = nil -- 强制重算符号
        end

        -- 3. 【廉价层】执行极速符号计算
        local required_sign = exit_portaldata.cached_exit_drive_sign
        if not required_sign then
            -- 仅在缓存为空时 (首次、每次拼接后、或时刻表改变后) 执行简单的点积
            required_sign = Math.calculate_sign_from_intent(train_exit, exit_portaldata.cached_intent_vector, exit_portaldata)
            exit_portaldata.cached_exit_drive_sign = required_sign
        end

        -- 4. 施加速度
        train_exit.speed = target_speed * required_sign
        return
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
    local geo = Math.GEOMETRY[portaldata.shell.direction] or Math.GEOMETRY[0]

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
    portaldata.state = Teleport.STATE.DORMANT
end

-- =================================================================================
-- 【独立任务】处理传送序列步进
-- =================================================================================
---@param portaldata PortalData 传送门数据 / Portal data
---@param tick integer 当前tick / Current tick
local function process_teleport_sequence(portaldata, tick)
    -- 频率控制从游戏设置中读取间隔值
    local interval = portaldata.placement_interval or settings.global["rift-rail-placement-interval"].value
    -- 只有当间隔大于1时，才启用频率控制，以获得最佳性能
    if interval > 1 and tick % interval ~= portaldata.unit_number % interval then
        return
    end

    if portaldata.entry_car then
        -- 直接通过物理 ID 拿数据
        local exit_unit_number = portaldata.locked_exit_unit_number
        local exit_portaldata = nil

        if exit_unit_number then
            exit_portaldata = State.get_portaldata_by_unit_number(exit_unit_number)
        end

        -- 如果在传送中途，出口实体没了
        if not (exit_portaldata and exit_portaldata.shell and exit_portaldata.shell.valid) then
            if RiftRail.DEBUG_MODE_ENABLED then
                log_tp("🚨 致命警告: 传送中途出口被摧毁！强行切断传送！")
            end
            -- 强行中断，清理现场，把剩下的车厢留在入口
            -- 注意，这里 exit_portaldata 可能是 nil，finalize_sequence 会安全处理
            finalize_sequence(portaldata, exit_portaldata)
            return
        end

        -- 还有车厢，且出口安全，继续传送
        Teleport.process_transfer_step(portaldata, exit_portaldata)
    end

end
-- =================================================================================
-- 专门用于清理出口互斥锁的辅助函数
-- =================================================================================
--- 释放死锁保护期间占用的出口记录
---@param portaldata PortalData 入口层传送门数据
local function release_exit_lock(portaldata)
    local exit_id = portaldata.locked_exit_unit_number
    local exit_portal = exit_id and State.get_portaldata_by_unit_number(exit_id)
    if exit_portal and exit_portal.locking_entry_id == portaldata.unit_number then
        exit_portal.locking_entry_id = nil
    end
    portaldata.locked_exit_unit_number = nil
end

-- =================================================================================
-- 单个活动传送门的处理 (供 GC 和任务调度使用)
-- =================================================================================
--- 独立处理每个活跃的传送门，消除 else 层级
---@param portaldata PortalData 当前迭代的传送门数据
---@param list table 活跃传送门列表 storage.active_teleporter_list
---@param i integer 当前传送门在列表中的索引（倒序剔除用）
---@param tick integer 当前游戏 tick
local function process_active_portal(portaldata, list, i, tick)
    -- 顶层判断：数据无效直接清理
    if not (portaldata and portaldata.shell and portaldata.shell.valid) then
        if portaldata and portaldata.unit_number then
            release_exit_lock(portaldata)
            storage.active_teleporters[portaldata.unit_number] = nil
        end
        table.remove(list, i)
        return
    end

    -- === 任务调度区 ===
    local state = portaldata.state

    if state == Teleport.STATE.REBUILDING then
        -- 1. 重建碰撞器任务
        process_rebuild_collider(portaldata)
    end

    if state == Teleport.STATE.TELEPORTING then
        -- 2. 传送任务
        process_teleport_sequence(portaldata, tick)
        -- 动力同步需持续进行 (再次检查状态防止序列刚结束)
        if portaldata.state == Teleport.STATE.TELEPORTING then
            Teleport.maintain_exit_speed(portaldata)
        end
    end

    if state == Teleport.STATE.QUEUED then
        -- 3. 排队任务
        process_waiting_logic(portaldata)
    end

    -- 4. 垃圾回收 (GC)
    -- 如果所有任务都空闲，移出活跃列表
    if portaldata.state == Teleport.STATE.DORMANT then
        storage.active_teleporters[portaldata.unit_number] = nil
        table.remove(list, i)
    end
end

-- =================================================================================
-- Tick 调度 (GC 优化版)
-- =================================================================================
---@param event EventData tick事件 / Tick event
function Teleport.on_tick(event)
    local list = storage.active_teleporter_list or {}

    for i = #list, 1, -1 do
        process_active_portal(list[i], list, i, event.tick)
    end
end

return Teleport
