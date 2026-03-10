local CS2 = {}

local State = nil
local log_debug = function() end

local REBUILD_DEBOUNCE_TICKS = 120

local function cs2_active()
    return (script.active_mods["cybersyn2"] ~= nil) and (remote.interfaces["cybersyn2"] ~= nil)
end

local function cs2_log(msg)
    if RiftRail and RiftRail.DEBUG_MODE_ENABLED then
        log_debug("[CS2] " .. msg)
    end
end

local function ensure_storage()
    storage.rr_cs2_handoff_by_old_train_id = storage.rr_cs2_handoff_by_old_train_id or {}
    storage.rr_cs2_old_train_by_delivery_id = storage.rr_cs2_old_train_by_delivery_id or {}
    -- 保存跨地表卸货站信息（station名称、轨道坐标等）
    storage.rr_cs2_dropoff_info_by_train_id = storage.rr_cs2_dropoff_info_by_train_id or {}
end

local function get_station(portaldata)
    if not (portaldata and portaldata.children) then
        return nil
    end
    for _, child_data in pairs(portaldata.children) do
        local child = child_data.entity
        if child and child.valid and child.name == "rift-rail-station" then
            return child
        end
    end
    return nil
end

local function get_train_surface_and_position(train_stock, luatrain)
    if train_stock and train_stock.valid and train_stock.surface then
        return train_stock.surface.index, train_stock.position
    end

    if not (luatrain and luatrain.valid) then
        return nil, nil
    end

    local stock = luatrain.front_stock or luatrain.back_stock or luatrain.carriages[1]
    if stock and stock.valid and stock.surface then
        return stock.surface.index, stock.position
    end

    return nil, nil
end

local function is_cs2_enabled_entry(portaldata)
    return portaldata
        and portaldata.mode == "entry"
        and portaldata.cs2_enabled
        and portaldata.shell
        and portaldata.shell.valid
        and portaldata.target_ids
end

local function is_cs2_enabled_exit(portaldata)
    return portaldata
        and portaldata.mode == "exit"
        and portaldata.cs2_enabled
        and portaldata.shell
        and portaldata.shell.valid
end

local function has_direct_route(from_surface_index, to_surface_index)
    if not (from_surface_index and to_surface_index and storage.rift_rails) then
        return false
    end

    for _, entry in pairs(storage.rift_rails) do
        if is_cs2_enabled_entry(entry) and entry.surface.index == from_surface_index then
            for target_id, _ in pairs(entry.target_ids) do
                local exit_portal = State.get_portaldata_by_id(target_id)
                if is_cs2_enabled_exit(exit_portal)
                    and exit_portal.surface.index == to_surface_index
                then
                    return true
                end
            end
        end
    end

    return false
end

local function find_best_route(from_surface_index, to_surface_index, start_pos)
    if not (from_surface_index and to_surface_index and storage.rift_rails) then
        return nil, nil
    end

    local best_entry = nil
    local best_exit = nil
    local best_dist = math.huge

    for _, entry in pairs(storage.rift_rails) do
        if is_cs2_enabled_entry(entry) and entry.surface.index == from_surface_index then
            for target_id, _ in pairs(entry.target_ids) do
                local exit_portal = State.get_portaldata_by_id(target_id)
                if is_cs2_enabled_exit(exit_portal)
                    and exit_portal.surface.index == to_surface_index
                then
                    local dist = 0
                    if start_pos then
                        local dx = start_pos.x - entry.shell.position.x
                        local dy = start_pos.y - entry.shell.position.y
                        dist = (dx * dx) + (dy * dy)
                    end
                    if dist < best_dist then
                        best_dist = dist
                        best_entry = entry
                        best_exit = exit_portal
                    end
                end
            end
        end
    end

    return best_entry, best_exit
end

local function route_train_to_entry(luatrain, station_name, exit_id)
    if not (luatrain and luatrain.valid and station_name) then
        return false
    end

    local schedule = luatrain.get_schedule()
    if not schedule then
        return false
    end

    local wait_conditions = {
        {
            type = "circuit",
            compare_type = "or",
            condition = {
                first_signal = { type = "virtual", name = "riftrail-go-to-id" },
                comparator = "=",
                constant = exit_id,
            },
        },
    }

    local record_count = schedule.get_record_count()
    local insert_index = record_count > 0 and record_count or 1

    local ok = schedule.add_record({
        station = station_name,
        index = { schedule_index = insert_index },
        temporary = true,
        wait_conditions = wait_conditions,
    })

    if not ok then
        return false
    end

    if schedule.current >= insert_index then
        luatrain.go_to_station(insert_index)
    else
        luatrain.go_to_station(insert_index)
    end

    return true
end

function CS2.init(deps)
    State = deps.State
    log_debug = deps.log_debug or log_debug
    ensure_storage()
end

-- 在新地表的列车上恢复卸货站时刻表。
-- 这个函数由 teleport.lua 在第一节车厢生成并恢复状态之后调用。
-- 插入顺序：临时轨道坐标（首位）→ 卸货站实名（第二位）→ 车库仍在末尾。
-- 返回新的时刻表目标索引（1），如果没有需要恢复的信息则返回 nil。
function CS2.restore_dropoff_schedule(new_train, old_train_id)
    if not (new_train and new_train.valid and old_train_id) then
        return nil
    end

    ensure_storage()
    local dropoff_info = storage.rr_cs2_dropoff_info_by_train_id[old_train_id]
    if not dropoff_info then
        return nil
    end

    local schedule = new_train.get_schedule()
    if not schedule then
        cs2_log("警告：restore_dropoff_schedule 无法获取时刻表 old_train=" .. old_train_id)
        return nil
    end

    -- 先插入实名车站到第1位（随后临时轨道插到第1位会把它推到第2位）
    if dropoff_info.station_name then
        local ok = schedule.add_record({
            station = dropoff_info.station_name,
            index = { schedule_index = 1 },
            temporary = true,
            wait_conditions = {
                { type = "empty", compare_type = "and" },
            },
        })
        if ok then
            cs2_log("恢复卸货站实名 station=" .. dropoff_info.station_name .. " old_train=" .. old_train_id)
        else
            cs2_log("警告：恢复卸货站实名失败 station=" .. dropoff_info.station_name .. " old_train=" .. old_train_id)
        end
    end

    -- 再插入临时轨道坐标到第1位（把实名车站推到第2位）
    if dropoff_info.connected_rail and dropoff_info.connected_rail.valid then
        local ok = schedule.add_record({
            rail = dropoff_info.connected_rail,
            rail_direction = dropoff_info.connected_rail_direction,
            index = { schedule_index = 1 },
            temporary = true,
        })
        if ok then
            cs2_log("恢复卸货站临时轨道 old_train=" .. old_train_id)
        else
            cs2_log("警告：恢复卸货站临时轨道失败 old_train=" .. old_train_id)
        end
    end

    -- 跳转到第1位（临时轨道），让列车立即开往卸货站
    schedule.go_to_station(1)

    -- 清理已使用的信息
    storage.rr_cs2_dropoff_info_by_train_id[old_train_id] = nil

    cs2_log("卸货站时刻表恢复完成，已跳转到索引1 old_train=" .. old_train_id)
    return 1
end

-- Returns a SET<table<uint, boolean>> of surfaces reachable from origin surface.
function CS2.train_topology_callback(origin_surface_index)
    if not cs2_active() then
        return nil
    end

    local result = {}
    if not storage.rift_rails then
        return nil
    end

    for _, entry in pairs(storage.rift_rails) do
        if is_cs2_enabled_entry(entry) and entry.surface.index == origin_surface_index then
            for target_id, _ in pairs(entry.target_ids) do
                local exit_portal = State.get_portaldata_by_id(target_id)
                if is_cs2_enabled_exit(exit_portal) then
                    result[exit_portal.surface.index] = true
                end
            end
        end
    end

    if next(result) then
        return result
    end

    return nil
end

-- Return true to veto reachability.
function CS2.reachable_callback(_, _, _, _, train_home_surface_index, from_stop_entity, to_stop_entity)
    if not cs2_active() then
        return nil
    end

    if not (from_stop_entity and from_stop_entity.valid and to_stop_entity and to_stop_entity.valid) then
        return nil
    end

    local from_surface_index = from_stop_entity.surface.index
    local to_surface_index = to_stop_entity.surface.index

    if from_surface_index == to_surface_index then
        return nil
    end

    if not has_direct_route(from_surface_index, to_surface_index) then
        return true
    end

    if train_home_surface_index
        and train_home_surface_index ~= to_surface_index
        and not has_direct_route(to_surface_index, train_home_surface_index)
    then
        return true
    end

    return nil
end

function CS2.route_callback(delivery_id, action, _, train_id, luatrain, train_stock, train_home_surface_index, _, stop_entity)
    if not cs2_active() then
        return nil
    end

    if not (delivery_id and train_id and luatrain and luatrain.valid) then
        return nil
    end

    local current_surface_index, start_pos = get_train_surface_and_position(train_stock, luatrain)
    if not current_surface_index then
        return nil
    end

    local target_surface_index = nil
    if action == "complete" then
        target_surface_index = train_home_surface_index
    elseif stop_entity and stop_entity.valid then
        target_surface_index = stop_entity.surface.index
    end

    if not target_surface_index or target_surface_index == current_surface_index then
        return nil
    end

    local entry, exit_portal = find_best_route(current_surface_index, target_surface_index, start_pos)
    if not (entry and exit_portal) then
        return nil
    end

    local station = get_station(entry)
    if not (station and station.valid) then
        return nil
    end

    if not route_train_to_entry(luatrain, station.backer_name, exit_portal.id) then
        return nil
    end

    local old_train_id = luatrain.id

    ensure_storage()
    
    -- 保存卸货站信息：station名称、轨道坐标、轨道方向
    -- 这些信息在on_train_arrived时会被用来在新地表上添加卸货站时刻表
    local dropoff_info = nil
    if stop_entity and stop_entity.valid then
        dropoff_info = {
            station_name = stop_entity.backer_name,
            connected_rail = stop_entity.connected_rail,
            connected_rail_direction = stop_entity.connected_rail_direction,
            surface_index = stop_entity.surface.index,
        }
        storage.rr_cs2_dropoff_info_by_train_id[old_train_id] = dropoff_info
    end

    storage.rr_cs2_handoff_by_old_train_id[old_train_id] = {
        delivery_id = delivery_id,
        action = action,
        tick = game and game.tick or 0,
    }
    storage.rr_cs2_old_train_by_delivery_id[delivery_id] = old_train_id

    cs2_log(
        "接管 delivery=" .. delivery_id
            .. " action=" .. tostring(action)
                .. " old_luatrain=" .. tostring(old_train_id)
                .. " cstrain=" .. tostring(train_id)
            .. " route=" .. entry.id .. "->" .. exit_portal.id
                .. (dropoff_info and (" -> " .. dropoff_info.station_name) or "")
    )

    return true
end

function CS2.on_train_arrived(event)
    if not cs2_active() then
        return
    end

    ensure_storage()

    local old_train_id = event and event.old_train_id
    local new_train = event and event.train
    if not (old_train_id and new_train and new_train.valid) then
        return
    end

    local handoff = storage.rr_cs2_handoff_by_old_train_id[old_train_id]
    if not handoff then
        return
    end

    cs2_log(
        "传送完成：开始恢复卸货站时刻表 old_train=" .. old_train_id
            .. " new_train=" .. new_train.id
            .. " delivery=" .. handoff.delivery_id
    )

    -- 第一步：恢复卸货站的时刻表（临时轨道坐标 + station记录）
    -- 这个步骤必须在新列车到达新地表后进行，不能在传送前做，否则会因为跨地表的轨道而报错
    local dropoff_info = storage.rr_cs2_dropoff_info_by_train_id[old_train_id]
    if dropoff_info then
        local schedule = new_train.get_schedule()
        if schedule then
            -- 添加卸货站的临时轨道坐标记录
            if dropoff_info.connected_rail and dropoff_info.connected_rail.valid then
                local add_record_ok = schedule.add_record({
                    rail = dropoff_info.connected_rail,
                    rail_direction = dropoff_info.connected_rail_direction,
                })
                if add_record_ok then
                    cs2_log("成功添加卸货站轨道坐标 delivery=" .. handoff.delivery_id)
                else
                    cs2_log("警告：添加卸货站轨道坐标失败 delivery=" .. handoff.delivery_id)
                end
            end

            -- 添加卸货站station名称记录
            if dropoff_info.station_name then
                local add_record_ok = schedule.add_record({
                    station = dropoff_info.station_name,
                    wait_conditions = {
                        {
                            type = "empty",
                            compare_type = "and",
                        },
                    },
                })
                if add_record_ok then
                    cs2_log("成功添加卸货站记录 station=" .. dropoff_info.station_name .. " delivery=" .. handoff.delivery_id)
                else
                    cs2_log("警告：添加卸货站记录失败 station=" .. dropoff_info.station_name .. " delivery=" .. handoff.delivery_id)
                end
            end
        end

        storage.rr_cs2_dropoff_info_by_train_id[old_train_id] = nil
    end

    storage.rr_cs2_handoff_by_old_train_id[old_train_id] = nil
    storage.rr_cs2_old_train_by_delivery_id[handoff.delivery_id] = nil

    -- 第二步：调用route_plugin_handoff将列车归还给CS2
    local ok, err = pcall(
        remote.call,
        "cybersyn2",
        "route_plugin_handoff",
        handoff.delivery_id,
        new_train
    )

    if not ok then
        cs2_log("handoff 归还失败 delivery=" .. handoff.delivery_id .. " err=" .. tostring(err))
        pcall(
            remote.call,
            "cybersyn2",
            "fail_delivery",
            handoff.delivery_id,
            "RIFTRAIL_HANDOFF_FAILED"
        )
        return
    end

    cs2_log("handoff 归还成功 delivery=" .. handoff.delivery_id .. " old_train=" .. old_train_id .. " new_train=" .. new_train.id)
end

function CS2.on_topology_changed()
    if not cs2_active() then
        return
    end

    local tick = (game and game.tick) or 0
    local last = storage.rr_cs2_last_topology_rebuild_tick or 0
    if tick - last < REBUILD_DEBOUNCE_TICKS then
        return
    end

    storage.rr_cs2_last_topology_rebuild_tick = tick

    local ok, err = pcall(remote.call, "cybersyn2", "rebuild_train_topologies")
    if not ok then
        cs2_log("重建拓扑失败: " .. tostring(err))
    end
end

return CS2
