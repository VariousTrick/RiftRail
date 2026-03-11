local CS2 = {}

local State = nil
local log_debug = function(_) end

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
    storage.rr_cs2_route_cache = storage.rr_cs2_route_cache or { by_surface = {} }
    if storage.rr_cs2_route_cache_dirty == nil then
        storage.rr_cs2_route_cache_dirty = true
    end
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

-- 读取当前时刻表最后一个站名。
-- 对 CS2 车组列车来说，这个站通常就是基础车库站。
local function get_last_station_name(luatrain)
    if not (luatrain and luatrain.valid) then
        return nil
    end

    local schedule = luatrain.get_schedule()
    if not schedule then
        return nil
    end

    local record_count = schedule.get_record_count()
    if record_count < 1 then
        return nil
    end

    local last_record = schedule.get_record({ schedule_index = record_count })
    if last_record and last_record.station and last_record.station ~= "" then
        return last_record.station
    end

    return nil
end

local function is_cs2_enabled_entry(portaldata)
    return portaldata and portaldata.mode == "entry" and portaldata.cs2_enabled and portaldata.shell and portaldata.shell.valid and portaldata.target_ids
end

local function is_cs2_enabled_exit(portaldata)
    return portaldata and portaldata.mode == "exit" and portaldata.cs2_enabled and portaldata.shell and portaldata.shell.valid
end

local function get_or_create_route_bucket(cache, from_surface_index, to_surface_index)
    cache.by_surface[from_surface_index] = cache.by_surface[from_surface_index] or {}
    local by_to_surface = cache.by_surface[from_surface_index]
    by_to_surface[to_surface_index] = by_to_surface[to_surface_index] or {
        -- 入口抽屉：按 entry_id 分组，便于调试/维护。
        by_entry = {},
        -- 平铺边列表：高频查询时直接遍历，避免多层展开。
        flat_edges = {},
    }
    return by_to_surface[to_surface_index]
end

local function append_edge_to_cache(cache, entry, exit_portal)
    local from_surface_index = entry.surface.index
    local to_surface_index = exit_portal.surface.index
    local bucket = get_or_create_route_bucket(cache, from_surface_index, to_surface_index)

    local entry_drawer = bucket.by_entry[entry.id]
    if not entry_drawer then
        entry_drawer = {
            entry_id = entry.id,
            entry_surface_index = from_surface_index,
            entry_x = entry.shell.position.x,
            entry_y = entry.shell.position.y,
            exits = {},
        }
        bucket.by_entry[entry.id] = entry_drawer
    end

    -- 注意：同一出口可以被多个入口引用，必须按 (entry_id, exit_id) 保留边，不能只按 exit_id 去重。
    local edge = {
        entry_id = entry.id,
        exit_id = exit_portal.id,
        entry_x = entry.shell.position.x,
        entry_y = entry.shell.position.y,
        exit_x = exit_portal.shell.position.x,
        exit_y = exit_portal.shell.position.y,
    }

    table.insert(entry_drawer.exits, edge)
    table.insert(bucket.flat_edges, edge)
end

local function append_enabled_edges_for_entry(cache, entry)
    if not is_cs2_enabled_entry(entry) then
        return
    end

    for target_id, _ in pairs(entry.target_ids) do
        local exit_portal = State.get_portaldata_by_id(target_id)
        if is_cs2_enabled_exit(exit_portal) then
            append_edge_to_cache(cache, entry, exit_portal)
        end
    end
end

-- 重建 CS2 路由缓存。
-- 规则：入口和出口都必须开启 cs2 开关，否则不写入缓存。
local function rebuild_route_cache()
    ensure_storage()

    local cache = { by_surface = {} }

    if not storage.rift_rails then
        storage.rr_cs2_route_cache = cache
        storage.rr_cs2_route_cache_dirty = false
        return
    end

    for _, entry in pairs(storage.rift_rails) do
        if is_cs2_enabled_entry(entry) then
            append_enabled_edges_for_entry(cache, entry)
        end
    end

    storage.rr_cs2_route_cache = cache
    storage.rr_cs2_route_cache_dirty = false
end

local function ensure_route_cache()
    ensure_storage()
    if storage.rr_cs2_route_cache_dirty then
        rebuild_route_cache()
    end
end

local function rebuild_drawers_from_flat_edges(bucket, from_surface_index)
    local by_entry = {}

    for _, edge in ipairs(bucket.flat_edges) do
        local entry_drawer = by_entry[edge.entry_id]
        if not entry_drawer then
            entry_drawer = {
                entry_id = edge.entry_id,
                entry_surface_index = from_surface_index,
                entry_x = edge.entry_x,
                entry_y = edge.entry_y,
                exits = {},
            }
            by_entry[edge.entry_id] = entry_drawer
        end

        table.insert(entry_drawer.exits, edge)
    end

    bucket.by_entry = by_entry
end

-- 精准清理：仅删除与指定 portal 相关的边与抽屉。
local function remove_portal_edges_from_cache(cache, portal_id)
    local empty_from_surfaces = {}

    for from_surface_index, by_to_surface in pairs(cache.by_surface) do
        local empty_to_surfaces = {}

        for to_surface_index, bucket in pairs(by_to_surface) do
            for idx = #bucket.flat_edges, 1, -1 do
                local edge = bucket.flat_edges[idx]
                if edge.entry_id == portal_id or edge.exit_id == portal_id then
                    table.remove(bucket.flat_edges, idx)
                end
            end

            if #bucket.flat_edges > 0 then
                rebuild_drawers_from_flat_edges(bucket, from_surface_index)
            else
                table.insert(empty_to_surfaces, to_surface_index)
            end
        end

        for _, to_surface_index in ipairs(empty_to_surfaces) do
            by_to_surface[to_surface_index] = nil
        end

        if not next(by_to_surface) then
            table.insert(empty_from_surfaces, from_surface_index)
        end
    end

    for _, from_surface_index in ipairs(empty_from_surfaces) do
        cache.by_surface[from_surface_index] = nil
    end
end

local function append_enabled_edges_for_exit(cache, exit_portal)
    if not is_cs2_enabled_exit(exit_portal) then
        return
    end

    local seen_entry = {}

    if exit_portal.source_ids then
        for source_id, _ in pairs(exit_portal.source_ids) do
            local entry = State.get_portaldata_by_id(source_id)
            if is_cs2_enabled_entry(entry) and entry.target_ids[exit_portal.id] then
                append_edge_to_cache(cache, entry, exit_portal)
                seen_entry[source_id] = true
            end
        end
    end

    -- 兜底：若 source_ids 不完整，再从全量入口补齐，避免漏边。
    if storage.rift_rails then
        for _, entry in pairs(storage.rift_rails) do
            if is_cs2_enabled_entry(entry) and (not seen_entry[entry.id]) and entry.target_ids[exit_portal.id] then
                append_edge_to_cache(cache, entry, exit_portal)
            end
        end
    end
end

local function refresh_cache_for_toggled_portal(portal_id)
    ensure_route_cache()

    local cache = storage.rr_cs2_route_cache
    remove_portal_edges_from_cache(cache, portal_id)

    local portal = State.get_portaldata_by_id(portal_id)
    if is_cs2_enabled_entry(portal) then
        -- 入口开启：重建该入口抽屉及其边。
        append_enabled_edges_for_entry(cache, portal)
    elseif is_cs2_enabled_exit(portal) then
        -- 出口开启：重建所有指向该出口的边。
        append_enabled_edges_for_exit(cache, portal)
    end

    storage.rr_cs2_route_cache_dirty = false
end

local function request_cs2_topology_rebuild()
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

local function add_surface_pair(pairs, pair_set, from_surface_index, to_surface_index)
    if not (from_surface_index and to_surface_index) then
        return
    end
    if from_surface_index == to_surface_index then
        return
    end

    local key = tostring(from_surface_index) .. ">" .. tostring(to_surface_index)
    if pair_set[key] then
        return
    end

    pair_set[key] = true
    table.insert(pairs, {
        from_surface_index = from_surface_index,
        to_surface_index = to_surface_index,
    })
end

-- 收集指定 portal 可能影响到的地表方向对。
-- 用于开关操作后仅做定向提醒，不做全图扫描。
local function collect_impacted_surface_pairs(portal)
    local impacted_pairs = {}
    local pair_set = {}

    if not (portal and portal.surface and portal.surface.index) then
        return impacted_pairs
    end

    local portal_surface_index = portal.surface.index

    if portal.mode == "entry" and portal.target_ids then
        for target_id, _ in pairs(portal.target_ids) do
            local exit_portal = State.get_portaldata_by_id(target_id)
            if exit_portal and exit_portal.surface and exit_portal.surface.index then
                add_surface_pair(impacted_pairs, pair_set, portal_surface_index, exit_portal.surface.index)
            end
        end
    elseif portal.mode == "exit" then
        if portal.source_ids then
            for source_id, _ in pairs(portal.source_ids) do
                local entry = State.get_portaldata_by_id(source_id)
                if entry and entry.surface and entry.surface.index then
                    add_surface_pair(impacted_pairs, pair_set, entry.surface.index, portal_surface_index)
                end
            end
        end

        -- 兜底：某些情况下 source_ids 可能滞后，用全量入口补齐受影响方向。
        if storage.rift_rails then
            for _, entry in pairs(storage.rift_rails) do
                if entry and entry.mode == "entry" and entry.surface and entry.surface.index and entry.target_ids and entry.target_ids[portal.id] then
                    add_surface_pair(impacted_pairs, pair_set, entry.surface.index, portal_surface_index)
                end
            end
        end
    end

    return impacted_pairs
end

local function get_route_bucket(from_surface_index, to_surface_index)
    ensure_route_cache()

    local by_to_surface = storage.rr_cs2_route_cache.by_surface[from_surface_index]
    if not by_to_surface then
        return nil
    end

    return by_to_surface[to_surface_index]
end

local function calc_dist_sq_to_pos(x, y, pos)
    if not pos then
        return 0
    end

    local dx = pos.x - x
    local dy = pos.y - y
    return (dx * dx) + (dy * dy)
end

local function select_best_edge(bucket, start_pos, target_pos)
    if not (bucket and bucket.flat_edges and #bucket.flat_edges > 0) then
        return nil
    end

    local best_edge = nil
    local best_total_dist = math.huge
    local best_exit_dist = math.huge
    local best_entry_dist = math.huge

    for _, edge in ipairs(bucket.flat_edges) do
        local entry_dist_sq = calc_dist_sq_to_pos(edge.entry_x, edge.entry_y, start_pos)
        local exit_dist_sq = calc_dist_sq_to_pos(edge.exit_x, edge.exit_y, target_pos)
        local total_dist_sq = entry_dist_sq + exit_dist_sq

        local is_better = total_dist_sq < best_total_dist
        if (not is_better) and total_dist_sq == best_total_dist then
            -- 平分时固定比较顺序，避免路线在等价候选之间抖动。
            if exit_dist_sq < best_exit_dist then
                is_better = true
            elseif exit_dist_sq == best_exit_dist then
                if entry_dist_sq < best_entry_dist then
                    is_better = true
                elseif entry_dist_sq == best_entry_dist then
                    if best_edge then
                        if edge.entry_id < best_edge.entry_id then
                            is_better = true
                        elseif edge.entry_id == best_edge.entry_id and edge.exit_id < best_edge.exit_id then
                            is_better = true
                        end
                    end
                end
            end
        end

        if is_better then
            best_edge = edge
            best_total_dist = total_dist_sq
            best_exit_dist = exit_dist_sq
            best_entry_dist = entry_dist_sq
        end
    end

    return best_edge
end

local function has_direct_route(from_surface_index, to_surface_index)
    if not (from_surface_index and to_surface_index) then
        return false
    end

    local bucket = get_route_bucket(from_surface_index, to_surface_index)
    return bucket ~= nil and bucket.flat_edges ~= nil and #bucket.flat_edges > 0
end

local function find_best_route(from_surface_index, to_surface_index, start_pos, target_pos)
    if not (from_surface_index and to_surface_index) then
        return nil, nil
    end

    local bucket = get_route_bucket(from_surface_index, to_surface_index)
    local best_edge = select_best_edge(bucket, start_pos, target_pos)
    if not best_edge then
        return nil, nil
    end

    local best_entry = State.get_portaldata_by_id(best_edge.entry_id)
    local best_exit = State.get_portaldata_by_id(best_edge.exit_id)
    if is_cs2_enabled_entry(best_entry) and is_cs2_enabled_exit(best_exit) then
        return best_entry, best_exit
    end

    -- 缓存可能在拓扑变化边缘瞬间过期，强制重建后再做一次选择。
    rebuild_route_cache()
    bucket = get_route_bucket(from_surface_index, to_surface_index)
    best_edge = select_best_edge(bucket, start_pos, target_pos)
    if not best_edge then
        return nil, nil
    end

    best_entry = State.get_portaldata_by_id(best_edge.entry_id)
    best_exit = State.get_portaldata_by_id(best_edge.exit_id)
    if is_cs2_enabled_entry(best_entry) and is_cs2_enabled_exit(best_exit) then
        return best_entry, best_exit
    end

    return nil, nil
end

local function route_train_to_entry(luatrain, station_name, exit_id, continuation_station_name)
    if not (luatrain and luatrain.valid and station_name) then
        return false
    end

    if not continuation_station_name or continuation_station_name == "" then
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

    -- 对齐 SE 方案：接管时直接覆盖为两站过渡调度（入口 -> 下一实名站）。
    luatrain.schedule = {
        records = {
            {
                station = station_name,
                temporary = true,
                wait_conditions = wait_conditions,
            },
            {
                station = continuation_station_name,
                temporary = true,
            },
        },
        current = 1,
    }

    return true
end

function CS2.init(deps)
    State = deps.State
    log_debug = deps.log_debug or log_debug
    ensure_storage()
    rebuild_route_cache()
end

-- Returns a SET<table<uint, boolean>> of surfaces reachable from origin surface.
function CS2.train_topology_callback(origin_surface_index)
    if not cs2_active() then
        return nil
    end

    ensure_route_cache()

    local result = {}
    local by_to_surface = storage.rr_cs2_route_cache.by_surface[origin_surface_index]
    if not by_to_surface then
        return nil
    end

    for to_surface_index, bucket in pairs(by_to_surface) do
        if bucket.flat_edges and #bucket.flat_edges > 0 then
            result[to_surface_index] = true
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

    if train_home_surface_index and train_home_surface_index ~= to_surface_index and not has_direct_route(to_surface_index, train_home_surface_index) then
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
    local target_pos = nil
    if action == "complete" then
        target_surface_index = train_home_surface_index
    elseif stop_entity and stop_entity.valid then
        target_surface_index = stop_entity.surface.index
        target_pos = stop_entity.position
    end

    if not target_surface_index or target_surface_index == current_surface_index then
        return nil
    end

    local entry, exit_portal = find_best_route(current_surface_index, target_surface_index, start_pos, target_pos)
    if not (entry and exit_portal) then
        return nil
    end

    local station = get_station(entry)
    if not (station and station.valid) then
        return nil
    end

    local exit_station = get_station(exit_portal)

    local continuation_station_name = nil
    if stop_entity and stop_entity.valid then
        continuation_station_name = stop_entity.backer_name
    elseif action == "complete" then
        -- complete 场景无 stop_entity：优先使用时刻表末站（通常是车库）作为过渡 continuation。
        continuation_station_name = get_last_station_name(luatrain)

        -- 兜底：如果异常读不到车库名，回退到出口站，避免直接中断接管。
        if not continuation_station_name and exit_station and exit_station.valid then
            continuation_station_name = exit_station.backer_name
            cs2_log("complete 未读到车库站名，回退使用出口站 continuation=" .. tostring(continuation_station_name))
        end
    end

    if not continuation_station_name then
        return nil
    end

    local previous_group = luatrain.group
    if previous_group then
        luatrain.group = nil
    end

    if not route_train_to_entry(luatrain, station.backer_name, exit_portal.id, continuation_station_name) then
        if previous_group then
            luatrain.group = previous_group
        end
        return nil
    end

    local old_train_id = luatrain.id

    ensure_storage()

    storage.rr_cs2_handoff_by_old_train_id[old_train_id] = {
        delivery_id = delivery_id,
        action = action,
        previous_group = previous_group,
        tick = game and game.tick or 0,
    }
    storage.rr_cs2_old_train_by_delivery_id[delivery_id] = old_train_id

    cs2_log("接管 delivery=" .. delivery_id .. " action=" .. tostring(action) .. " old_luatrain=" .. tostring(old_train_id) .. " cstrain=" .. tostring(train_id) .. " route=" .. entry.id .. "->" .. exit_portal.id .. (continuation_station_name and (" -> " .. continuation_station_name) or ""))

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

    -- 对齐 SE 方案：传送完毕先清空过渡调度，再恢复原车组，然后交还 CS2。
    new_train.schedule = nil
    if handoff.previous_group then
        new_train.group = handoff.previous_group
    end

    cs2_log("传送完成：已清空过渡调度并恢复车组 old_train=" .. old_train_id .. " new_train=" .. new_train.id .. " delivery=" .. handoff.delivery_id)

    storage.rr_cs2_handoff_by_old_train_id[old_train_id] = nil
    storage.rr_cs2_old_train_by_delivery_id[handoff.delivery_id] = nil

    -- 第二步：调用route_plugin_handoff将列车归还给CS2
    local ok, err = pcall(remote.call, "cybersyn2", "route_plugin_handoff", handoff.delivery_id, new_train)

    if not ok then
        cs2_log("handoff 归还失败 delivery=" .. handoff.delivery_id .. " err=" .. tostring(err))
        pcall(remote.call, "cybersyn2", "fail_delivery", handoff.delivery_id, "RIFTRAIL_HANDOFF_FAILED")
        return
    end

    cs2_log("handoff 归还成功 delivery=" .. handoff.delivery_id .. " old_train=" .. old_train_id .. " new_train=" .. new_train.id)
end

function CS2.on_topology_changed()
    if not cs2_active() then
        return
    end

    ensure_storage()
    storage.rr_cs2_route_cache_dirty = true
    rebuild_route_cache()

    request_cs2_topology_rebuild()
end

-- 返回指定 portal 当前受影响方向中的“仅单向”路径列表：A->B 存在且 B->A 不存在。
function CS2.get_one_way_pairs_for_portal(portal_id)
    if not cs2_active() then
        return {}
    end
    if not portal_id then
        return {}
    end

    ensure_route_cache()

    local portal = State.get_portaldata_by_id(portal_id)
    if not portal then
        return {}
    end

    local impacted_pairs = collect_impacted_surface_pairs(portal)
    local result = {}

    for _, pair in ipairs(impacted_pairs) do
        local has_forward = has_direct_route(pair.from_surface_index, pair.to_surface_index)
        local has_return = has_direct_route(pair.to_surface_index, pair.from_surface_index)
        if has_forward and not has_return then
            table.insert(result, pair)
        end
    end

    return result
end

function CS2.on_portal_cs2_toggle(portal_id)
    if not cs2_active() then
        return
    end

    if not portal_id then
        return
    end

    ensure_storage()
    refresh_cache_for_toggled_portal(portal_id)
    request_cs2_topology_rebuild()
end

return CS2
