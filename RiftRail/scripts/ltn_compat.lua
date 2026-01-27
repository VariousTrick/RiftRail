-- scripts/ltn_compat.lua
-- 【Rift Rail - LTN 兼容模块】
-- 作用：在玩家开启 LTN 跨面开关时，向 LTN 注册/撤销跨地表连接；
--       仅做“连接关系”的维护，实际列车传送由 RiftRail 自身完成。

local LTN = {}
local State = nil
local log_debug = function() end

-- 日志：遵循全局调试开关（不再绕过）
local function ltn_log(msg)
    if RiftRail and RiftRail.DEBUG_MODE_ENABLED then
        if log_debug then
            log_debug("[LTN] " .. msg)
        else
            log("[RiftRail:LTN] " .. msg)
            if game then
                game.print("[RiftRail:LTN] " .. msg)
            end
        end
    end
end

LTN.BUTTON_NAME = "rift_rail_ltn_switch" -- GUI按钮名

-- 从 RiftRail 结构体提取内部站实体
local function get_station(portaldata)
    if portaldata.children then
        for _, child_data in pairs(portaldata.children) do
            local child = child_data.entity
            if child and child.valid and child.name == "rift-rail-station" then
                return child
            end
        end
    end
    return nil
end

-- 写入路由表的核心函数
local function register_route(portal_data, partner_data)
    if not (portal_data and partner_data and portal_data.mode == "entry") then
        return
    end

    local source_surface = portal_data.surface.index
    local dest_surface = partner_data.surface.index
    local unit_number = portal_data.unit_number
    local station = get_station(portal_data)

    if not station then
        return
    end

    local table = storage.rift_rail_ltn_routing_table
    if not table[source_surface] then
        table[source_surface] = {}
    end
    if not table[source_surface][dest_surface] then
        table[source_surface][dest_surface] = {}
    end

    table[source_surface][dest_surface][unit_number] = {
        station_name = station.backer_name,
        position = portal_data.shell.position,
        unit_number = unit_number,
    }
    if RiftRail.DEBUG_MODE_ENABLED then
        ltn_log("[LTNCompat] 已注册路由: " .. source_surface .. " -> " .. dest_surface .. " via Portal ID " .. portal_data.id)
    end
end

-- 从路由表删除的核心函数
local function unregister_route(portal_data, partner_data)
    if not (portal_data and partner_data) then
        return
    end

    local source_surface = portal_data.surface.index
    local dest_surface = partner_data.surface.index
    local unit_number = portal_data.unit_number

    local table = storage.rift_rail_ltn_routing_table
    if table and table[source_surface] and table[source_surface][dest_surface] and table[source_surface][dest_surface][unit_number] then
        table[source_surface][dest_surface][unit_number] = nil
        if RiftRail.DEBUG_MODE_ENABLED then
            ltn_log("[LTNCompat] 已注销路由: " ..
                source_surface .. " -> " .. dest_surface .. " via Portal ID " .. portal_data.id)
        end
    end
end

-- 供外部调用的模式切换处理函数
function LTN.on_portal_mode_changed(portal_data, old_mode)
    if not portal_data or not portal_data.ltn_enabled or not portal_data.paired_to_id then
        return
    end

    local partner_data = State.get_portaldata_by_id(portal_data.paired_to_id)
    if not partner_data then
        return
    end

    -- 之前是入口，现在不是了 -> 删除
    if old_mode == "entry" and portal_data.mode ~= "entry" then
        unregister_route(portal_data, partner_data)
    end

    -- 之前不是入口，现在是了 -> 注册
    if old_mode ~= "entry" and portal_data.mode == "entry" then
        register_route(portal_data, partner_data)
    end
end

local function is_ltn_active()
    return remote.interfaces["logistic-train-network"] ~= nil
end

-- 计算稳定的 network_id：使用较小的 unit_number，或使用配对 id
local function compute_network_id(a, b, override)
    if type(override) == "number" then
        return override
    end
    local ua = a.unit_number or 0
    local ub = b.unit_number or 0
    if ua > 0 and ub > 0 then
        return math.min(ua, ub)
    end
    return (a.id or 0)
end

function LTN.init(dependencies)
    State = dependencies.State
    if dependencies.log_debug then
        log_debug = dependencies.log_debug
    end
    ltn_log("[LTNCompat] 模块已加载 (运行时检测 LTN 接口)。")
end

-- 切换连接状态
function LTN.update_connection(select_portal, target_portal, connect, player)
    if not is_ltn_active() then
        if player then
            player.print({ "messages.rift-rail-error-ltn-not-found" })
        end
        return
    end

    local station1 = get_station(select_portal)
    local station2 = get_station(target_portal)
    if not (station1 and station1.valid and station2 and station2.valid) then
        if player then
            player.print({ "messages.rift-rail-error-ltn-no-station" })
        end
        return
    end

    local ok, err = pcall(function()
        if connect then
            local nid = compute_network_id(station1, station2, tonumber(select_portal.ltn_network_id) or -1)
            remote.call("logistic-train-network", "connect_surfaces", station1, station2, nid)
            if RiftRail.DEBUG_MODE_ENABLED then
                ltn_log("[LTNCompat] 已建立跨面连接 network_id=" .. nid)
            end

            -- 分别检查每一方是否为 Entry，只注册合法路径
            register_route(select_portal, target_portal)
            register_route(target_portal, select_portal)
        else
            remote.call("logistic-train-network", "disconnect_surfaces", station1, station2)
            if RiftRail.DEBUG_MODE_ENABLED then
                ltn_log("[LTNCompat] 已断开跨面连接")
            end

            -- 注销时同样分别处理
            unregister_route(select_portal, target_portal)
            unregister_route(target_portal, select_portal)
        end
    end)
    if not ok then
        if RiftRail.DEBUG_MODE_ENABLED then
            ltn_log("[LTNCompat] 调用失败: " .. tostring(err))
        end
        if player then
            player.print({ "messages.rift-rail-error-ltn-call-failed", tostring(err) })
        end
        return
    end

    --[[     select_portal.ltn_enabled = connect
    target_portal.ltn_enabled = connect ]]

    -- 玩家通知（带双向 GPS 标签，受设置控制）
    local name1 = select_portal.name or "RiftRail"
    local pos1 = select_portal.shell.position
    local surface1 = select_portal.shell.surface.name
    local gps1 = "[gps=" .. pos1.x .. "," .. pos1.y .. "," .. surface1 .. "]"

    local name2 = target_portal.name or "RiftRail"
    local pos2 = target_portal.shell.position
    local surface2 = target_portal.shell.surface.name
    local gps2 = "[gps=" .. pos2.x .. "," .. pos2.y .. "," .. surface2 .. "]"

    for _, p in pairs(game.connected_players) do
        local setting = settings.get_player_settings(p)["rift-rail-show-logistics-notifications"]
        if setting and setting.value then
            if connect then
                p.print({ "messages.rift-rail-info-ltn-connected", name1, gps1, name2, gps2 })
            else
                p.print({ "messages.rift-rail-info-ltn-disconnected", name1, gps1, name2, gps2 })
            end
        end
    end
end

function LTN.on_portal_destroyed(select_portal)
    -- 优先清理路由表
    if select_portal and select_portal.ltn_enabled and select_portal.mode == "entry" and select_portal.paired_to_id then
        local partner = State.get_portaldata_by_id(select_portal.paired_to_id)
        if partner then
            unregister_route(select_portal, partner)
        end
    end
    if not is_ltn_active() then
        return
    end
    if select_portal and select_portal.ltn_enabled then
        local opp = State.get_portaldata_by_id(select_portal.paired_to_id)
        if opp then
            LTN.update_connection(select_portal, opp, false, nil)
        else
            -- 无对端时无需显式断开，LTN在实体删除时不要求调用
            if RiftRail.DEBUG_MODE_ENABLED then
                ltn_log("[LTNCompat] 仅标记断开，无需显式清理")
            end
        end
    end
end

-- =====================================================================================
-- 事件处理：缓存 stops 与在调度完成后插入中转站
-- =====================================================================================

function LTN.on_stops_updated(e)
    -- e.logistic_train_stops: map[id] = { entity = stop-entity, ... }
    storage.ltn_stops = e.logistic_train_stops or {}
end

-- 专门处理单条交付任务的函数 (提取自原来的循环体)
-- 使用 return 代替 goto continue，逻辑更清晰
-- 使用路由表进行精准、高效的站点插入
-- 辅助函数：查表并在表中寻找离 reference_pos 最近的传送门名称
local function find_best_route_station(from_surface_idx, to_surface_idx, reference_pos)
    local routing_table = storage.rift_rail_ltn_routing_table
    -- 1. 查表
    local available_portals = routing_table[from_surface_idx] and routing_table[from_surface_idx][to_surface_idx]

    if not (available_portals and next(available_portals)) then
        return nil
    end

    -- 2. 表内寻找最近 (Find Closest in Table)
    local best_station_name = nil
    local min_dist_sq = math.huge

    for _, portal_info in pairs(available_portals) do
        -- 简单的欧几里得距离比较
        local dist_sq = (reference_pos.x - portal_info.position.x) ^ 2 + (reference_pos.y - portal_info.position.y) ^ 2
        if dist_sq < min_dist_sq then
            min_dist_sq = dist_sq
            best_station_name = portal_info.station_name
        end
    end

    return best_station_name
end

-- 辅助函数：插入传送门站点序列 (含清理站逻辑)
local function insert_portal_sequence(train, station_name, insert_index)
    local schedule = train.get_schedule()
    if not schedule then
        return
    end

    if settings.global["rift-rail-ltn-use-teleported"].value then
        -- === 情况 A: 开启了清理站 ===
        local teleported_name = settings.global["rift-rail-ltn-teleported-name"].value

        -- 1. 先插清理站 (它目前在 insert_index)
        schedule.add_record({
            station = teleported_name,
            index = { schedule_index = insert_index },
            temporary = true,
            wait_conditions = { { type = "time", ticks = 0 } },
        })

        -- 2. 再插传送门 (把清理站挤下去到 insert_index + 1)
        schedule.add_record({
            station = station_name,
            index = { schedule_index = insert_index },
        })
    else
        -- === 情况 B: 没开清理站 ===
        -- 仅插入传送门
        schedule.add_record({
            station = station_name,
            index = { schedule_index = insert_index },
        })
    end

    -- 3. 如果列车当前目标在这个索引之后，更新目标
    if schedule.current >= insert_index then
        train.go_to_station(insert_index)
    end
end

-- 结合查表 + 三段式路径规划的处理函数
local function process_single_delivery(train_id, deliveries, stops)
    local d = deliveries and deliveries[train_id]
    if not (d and d.train and d.train.valid) then
        return
    end

    local train = d.train
    -- 获取主要车头用于定位地表
    local loco = train.locomotives and train.locomotives.front_movers and train.locomotives.front_movers[1]
    if not (loco and loco.valid) then
        return
    end

    local from_stop_data = d.from_id and stops[d.from_id]
    local to_stop_data = d.to_id and stops[d.to_id]

    local from_entity = from_stop_data and from_stop_data.entity
    local to_entity = to_stop_data and to_stop_data.entity

    if not (from_entity and from_entity.valid and to_entity and to_entity.valid) then
        return
    end

    -- 1. 获取 LTN 关键索引 (Provider 和 Requester)
    local p_index, _, p_type = remote.call("logistic-train-network", "get_next_logistic_stop", train)
    local r_index, r_type

    if p_type == "provider" then
        -- 正常情况：Next 是 Provider，再下一个是 Requester
        r_index, _, r_type = remote.call("logistic-train-network", "get_next_logistic_stop", train, p_index + 1)
    else
        -- 异常情况：第一站不是 Provider (可能是 Depot?)，尝试找 Requester
        r_index, _, r_type = remote.call("logistic-train-network", "get_next_logistic_stop", train)
        if r_type ~= "requester" then
            r_index, _, r_type = remote.call("logistic-train-network", "get_next_logistic_stop", train,
                (r_index or 0) + 1)
        end
    end

    -- 2. 执行三段式插入 (倒序执行，防止索引偏移)

    -- [阶段 C] Requester -> Loco Surface (回程/去往下一站)
    if r_index and to_entity.surface.index ~= loco.surface.index then
        local station = find_best_route_station(to_entity.surface.index, loco.surface.index, to_entity.position)
        if station then
            insert_portal_sequence(train, station, r_index + 1)
            if RiftRail.DEBUG_MODE_ENABLED then
                ltn_log("插入回程路由: " .. to_entity.surface.name .. " -> " .. loco.surface.name)
            end
        end
    end

    -- [阶段 B] Provider -> Requester (送货)
    if r_index and from_entity.surface.index ~= to_entity.surface.index then
        local station = find_best_route_station(from_entity.surface.index, to_entity.surface.index, from_entity.position)
        if station then
            insert_portal_sequence(train, station, r_index)
            if RiftRail.DEBUG_MODE_ENABLED then
                ltn_log("插入送货路由: " .. from_entity.surface.name .. " -> " .. to_entity.surface.name)
            end
        end
    end

    -- [阶段 A] Loco -> Provider (取货)
    if p_index and loco.surface.index ~= from_entity.surface.index then
        local station = find_best_route_station(loco.surface.index, from_entity.surface.index, loco.position)
        if station then
            insert_portal_sequence(train, station, p_index)
            if RiftRail.DEBUG_MODE_ENABLED then
                ltn_log("插入取货路由: " .. loco.surface.name .. " -> " .. from_entity.surface.name)
            end
        end
    end
end

-- 主入口函数：仅负责循环调用
function LTN.on_dispatcher_updated(e)
    if not is_ltn_active() then
        return
    end

    local deliveries = e.deliveries
    local stops = storage.ltn_stops or {}

    -- 主循环
    for _, train_id in pairs(e.new_deliveries or {}) do
        process_single_delivery(train_id, deliveries, stops)
    end
end

-- ============================================================================
-- 传送生命周期钩子
-- ============================================================================

-- 具体的重指派逻辑
local function logic_reassign(new_train, old_id)
    if not (new_train and new_train.valid and old_id) then
        return
    end

    if remote.interfaces["logistic-train-network"] then
        -- 调用 LTN 接口将旧列车的任务指派给新列车
        local ok, has_delivery = pcall(remote.call, "logistic-train-network", "reassign_delivery", old_id, new_train)

        if ok and has_delivery then
            if RiftRail.DEBUG_MODE_ENABLED then
                ltn_log("任务迁移: 已重指派交付给新列车 " .. new_train.id)
            end

            -- LTN 特性: 插入临时站以确保状态更新
            local insert_index = remote.call("logistic-train-network", "get_or_create_next_temp_stop", new_train)
            if insert_index then
                local sched = new_train.schedule
                if sched and (sched.current > insert_index) then
                    new_train.go_to_station(insert_index)
                end
            end
        end
    end
end

local function noop() end

-- 策略分发
LTN.on_teleport_end = noop

if script.active_mods["logistic-train-network"] then
    local has_se = script.active_mods["space-exploration"]
    local has_glue = script.active_mods["se-ltn-glue"]

    -- 如果 (没装 SE) 或者 (装了 SE 但没装 Glue) -> 我们必须兜底
    if (not has_se) or (has_se and not has_glue) then
        LTN.on_teleport_end = logic_reassign
        if RiftRail.DEBUG_MODE_ENABLED then
            ltn_log("LTN兼容模式: 启用手动重指派")
        end
    else
        -- 否则 (有 SE 且有 Glue) -> Glue 会处理，我们躺平
        LTN.on_teleport_end = noop
        if RiftRail.DEBUG_MODE_ENABLED then
            ltn_log("LTN兼容模式: SE-Glue 托管")
        end
    end
end

-- 供迁移脚本调用的函数，用于从旧数据重建整个路由表
function LTN.rebuild_routing_table_from_storage()
    if RiftRail.DEBUG_MODE_ENABLED then
        ltn_log("重建 LTN 路由表...")
    end

    -- 1. 先清空，防止重复执行时数据污染
    if storage.rift_rail_ltn_routing_table then
        for k in pairs(storage.rift_rail_ltn_routing_table) do
            storage.rift_rail_ltn_routing_table[k] = nil
        end
    else
        storage.rift_rail_ltn_routing_table = {}
    end

    -- 2. 遍历所有传送门
    if storage.rift_rails then
        for _, portaldata in pairs(storage.rift_rails) do
            -- 3. 检查是否满足注册条件：已开启LTN、是入口模式、已配对
            if portaldata.ltn_enabled and portaldata.mode == "entry" and portaldata.paired_to_id then
                local partner = State.get_portaldata_by_id(portaldata.paired_to_id)
                if partner then
                    -- 4. 调用我们已有的注册函数
                    register_route(portaldata, partner)
                end
            end
        end
    end
    if RiftRail.DEBUG_MODE_ENABLED then
        ltn_log("LTN 路由表重建完成。")
    end
end

return LTN
