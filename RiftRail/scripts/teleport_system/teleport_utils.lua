-- scripts/teleport_system/teleport_utils.lua
-- 【Rift Rail - 传送辅助工具模块】
-- 功能：管理传送过程中涉及 GUI 刷新、列车时刻表读写、状态恢复等低频辅助逻辑
-- 说明：函数均属于低频调用路径（每节车厢完成克隆时触发一次），不在 on_tick 热路径中

---@diagnostic disable: need-check-nil
local TeleportUtils = {}

-- =================================================================================
-- 依赖注入
-- =================================================================================
---@type table
local Math = nil

local log_debug = function(...) end

function TeleportUtils.init(deps)
    Math = deps.Math
    if deps.log_debug then
        log_debug = deps.log_debug
    end
end

local function log_tu(msg)
    if RiftRail.DEBUG_MODE_ENABLED then
        log_debug("[RiftRail:TeleportUtils] " .. msg)
    end
end

-- =================================================================================
-- 统一列车时刻表索引读取函数（直接读取真实指针）
-- =================================================================================
---@param train LuaTrain 要读取的列车 / The train to read
---@return integer|nil 当前时刻表索引 / Current schedule index
function TeleportUtils.read_train_schedule_index(train)
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
TeleportUtils.find_child_entity = find_child_entity

-- =================================================================================
-- 辅助函数：从子实体中获取真实的车站名称 (带图标)
-- =================================================================================
---@param portaldata PortalData 传送门数据 / Portal data
---@return string 真实车站名称 / Real station name
function TeleportUtils.get_real_station_name(portaldata)
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
function TeleportUtils.collect_gui_watchers(train)
    local map = {}

    if not settings.global["rift-rail-train-gui-track"].value then
        return nil
    end

    if not (train and train.valid) then
        return nil
    end

    for _, p in pairs(game.connected_players) do
        local opened = p.opened
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
function TeleportUtils.reopen_car_gui(watchers, entity)
    if not (watchers and entity and entity.valid) then
        return
    end

    for _, p in ipairs(watchers) do
        if p.valid then
            p.opened = entity
        end
    end
end

-- =================================================================================
-- 统一列车状态恢复函数
-- =================================================================================
---@param train LuaTrain 要恢复的列车 / Train to restore
---@param portaldata PortalData 传送门数据 / Portal data
---@param apply_speed boolean 是否恢复速度 / Whether to restore speed
---@param preferred_index integer|nil 优先恢复索引 / Preferred index
function TeleportUtils.restore_train_state(train, portaldata, apply_speed, preferred_index)
    if not (train and train.valid) then
        return
    end

    if RiftRail.DEBUG_MODE_ENABLED then
        log_tu("状态恢复: TrainID=" .. train.id .. ", 恢复进度=" .. tostring(portaldata.saved_schedule_index ~= nil))
    end

    local index_to_restore = preferred_index or portaldata.saved_schedule_index
    if index_to_restore then
        train.go_to_station(index_to_restore)
    end

    train.manual_mode = portaldata.saved_manual_mode or false

    if apply_speed then
        local speed_mag = settings.global["rift-rail-teleport-speed"].value
        local sign = Math.calculate_speed_sign(train, portaldata)
        train.speed = speed_mag * sign

        if RiftRail.DEBUG_MODE_ENABLED then
            log_tu("状态恢复: 速度重置为 " .. train.speed)
        end
    end
end

return TeleportUtils
