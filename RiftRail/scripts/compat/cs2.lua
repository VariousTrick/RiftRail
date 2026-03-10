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

local function route_train_to_entry(luatrain, station_name, exit_id, continuation_station_name)
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

    -- 在传送入口下方追加“下一实名站”，让第一节车厢到出口后有明确下一站可走，
    -- 避免在整列尚未传送完成前出现车头堵住出口的问题。
    if continuation_station_name and continuation_station_name ~= "" then
        local continuation_ok = schedule.add_record({
            station = continuation_station_name,
            index = { schedule_index = insert_index + 1 },
            temporary = true,
        })
        if not continuation_ok then
            return false
        end
    end

    if schedule.current >= insert_index then
        luatrain.go_to_station(insert_index)
    else
        luatrain.go_to_station(insert_index)
    end

    return true
end

-- 清理列车时刻表中的临时站点。
-- 用于在最终 handoff 前移除 RiftRail 过渡阶段添加的临时记录，
-- 让 CS2 在 handoff 后只重建一套临时调度，避免重复。
local function clear_temporary_records(luatrain)
    if not (luatrain and luatrain.valid) then
        return 0
    end

    local schedule = luatrain.get_schedule()
    if not schedule then
        return 0
    end

    local removed = 0
    local record_count = schedule.get_record_count()
    for i = record_count, 1, -1 do
        local rec = schedule.get_record({ schedule_index = i })
        if rec and rec.temporary then
            if schedule.remove_record({ schedule_index = i }) then
                removed = removed + 1
            end
        end
    end

    return removed
end

function CS2.init(deps)
    State = deps.State
    log_debug = deps.log_debug or log_debug
    ensure_storage()
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

    local continuation_station_name = nil
    if stop_entity and stop_entity.valid then
        continuation_station_name = stop_entity.backer_name
    end

    if not route_train_to_entry(luatrain, station.backer_name, exit_portal.id, continuation_station_name) then
        return nil
    end

    local old_train_id = luatrain.id

    ensure_storage()

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
                .. (continuation_station_name and (" -> " .. continuation_station_name) or "")
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

    -- 第一步：清理过渡时刻表中的临时站，避免 handoff 后和 CS2 新建的临时站叠加。
    local removed = clear_temporary_records(new_train)
    if removed > 0 then
        cs2_log(
            "传送完成：已清理过渡临时站 count=" .. removed
                .. " old_train=" .. old_train_id
                .. " new_train=" .. new_train.id
                .. " delivery=" .. handoff.delivery_id
        )
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
