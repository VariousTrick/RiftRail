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
            ltn_log("[LTNCompat] 已建立跨面连接 network_id=" .. nid)
        else
            remote.call("logistic-train-network", "disconnect_surfaces", station1, station2)
            ltn_log("[LTNCompat] 已断开跨面连接")
        end
    end)
    if not ok then
        ltn_log("[LTNCompat] 调用失败: " .. tostring(err))
        if player then
            player.print({ "messages.rift-rail-error-ltn-call-failed", tostring(err) })
        end
        return
    end

    select_portal.ltn_enabled = connect
    target_portal.ltn_enabled = connect

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
    if not is_ltn_active() then
        return
    end
    if select_portal and select_portal.ltn_enabled then
        local opp = State.get_portaldata_by_id(select_portal.paired_to_id)
        if opp then
            LTN.update_connection(select_portal, opp, false, nil)
        else
            -- 无对端时无需显式断开，LTN在实体删除时不要求调用
            ltn_log("[LTNCompat] 仅标记断开，无需显式清理")
        end
    end
end

-- =====================================================================================
-- 事件处理：缓存 stops 与在调度完成后插入中转站
-- =====================================================================================

-- 选择匹配目标地表的裂隙站
local function pick_station_for_surface(conn, surface)
    if not conn then
        return nil
    end
    local e1 = conn.entity1
    local e2 = conn.entity2
    if e1 and e1.valid and e1.surface == surface then
        return e1
    end
    if e2 and e2.valid and e2.surface == surface then
        return e2
    end
    return nil
end

-- 将指定站点名称插入到列车时刻表
local function add_station_to_schedule(train, station_entity, insert_index)
    if not (train and train.valid and station_entity and station_entity.valid) then
        return
    end

    -- 身份验证
    -- 只处理 Rift Rail 自己的车站。
    -- 如果是 SE 太空电梯 (se-ltn-elevator-connector) 或其他模组的实体，直接忽略。
    -- 这既防止了报错 (因为那些实体可能没有 backer_name)，
    -- 也防止了功能冲突 (把处理权交给 se-ltn-glue)。
    if station_entity.name ~= "rift-rail-station" then
        return
    end

    local schedule = train.get_schedule()
    if not schedule then
        return
    end
    --[[     -- 防重：若目标站名已在时刻表中，则不再重复插入
    local station_name = station_entity.backer_name
    if station_name and schedule.get_record then
        -- 简单线性扫描当前日程，若存在同名站点则跳过插入
        -- 说明：Factorio 2.0 的 TrainSchedule 提供 get_record 接口，但未暴露枚举器；
        --       这里保守地从 1 开始尝试读取，遇到 nil 则停止。
        local i = 1
        while true do
            local rec = schedule.get_record({ schedule_index = i })
            if not rec then
                break
            end
            if rec.station == station_name then
                return
            end
            i = i + 1
        end
    end ]]
    -- 1. 插入传送门站点
    schedule.add_record({
        station = station_entity.backer_name,
        index = { schedule_index = insert_index },
    })

    -- 2. 插入防堵塞清理站 (Cleared Station)
    -- 逻辑：如果开关开启，在传送门站点之后 (insert_index + 1) 插入一个临时站
    if settings.global["rift-rail-ltn-use-teleported"].value then
        local clearance_name = settings.global["rift-rail-ltn-teleported-name"].value
        schedule.add_record({
            station = clearance_name,
            index = { schedule_index = insert_index + 1 },      -- 紧跟在传送门之后
            temporary = true,                                   -- 临时站
            wait_conditions = { { type = "time", ticks = 0 } }, -- 0秒等待，到站即走
        })
    end

    -- 3. 更新列车目标
    -- 如果当前索引已经在插入点之后，说明列车已经过了这个阶段，不用回退
    -- 否则确保列车指向正确的下一站（即刚才插入的传送门站）
    if schedule.current > insert_index then
        schedule.go_to_station(insert_index)
    end
end

function LTN.on_stops_updated(e)
    -- e.logistic_train_stops: map[id] = { entity = stop-entity, ... }
    storage.ltn_stops = e.logistic_train_stops or {}
end

-- 专门处理单条交付任务的函数 (提取自原来的循环体)
-- 使用 return 代替 goto continue，逻辑更清晰
local function process_single_delivery(train_id, deliveries, stops)
    local d = deliveries and deliveries[train_id]
    if not d then
        return
    end

    local train = d.train
    if not (train and train.valid) then
        return
    end

    -- 仅处理跨地表的交付
    local from_stop_data = d.from_id and stops[d.from_id]
    local to_stop_data = d.to_id and stops[d.to_id]
    local from_entity = from_stop_data and from_stop_data.entity
    local to_entity = to_stop_data and to_stop_data.entity

    if not (from_entity and from_entity.valid and to_entity and to_entity.valid) then
        return
    end

    local loco = train.locomotives and train.locomotives.front_movers and train.locomotives.front_movers[1]
    if loco and loco.valid then
        -- 检查是否跨面
        local cross_surface = (from_entity.surface ~= to_entity.surface) or (loco.surface ~= from_entity.surface)
        if not cross_surface then
            return -- 不跨面，直接退出
        end
    end

    -- 找到当前交付关联的裂隙连接
    local conns = d.surface_connections or {}
    if not next(conns) then
        return
    end

    -- 计算 provider/requester 索引
    local p_index, _, p_type = remote.call("logistic-train-network", "get_next_logistic_stop", train)
    local r_index, r_type
    if p_type == "provider" then
        r_index, _, r_type = remote.call("logistic-train-network", "get_next_logistic_stop", train, (p_index or 0) + 1)
    else
        -- 若第一站不是 provider，尝试直接获取 requester
        r_index, _, r_type = remote.call("logistic-train-network", "get_next_logistic_stop", train)
        if r_type ~= "requester" then
            r_index, _, r_type = remote.call("logistic-train-network", "get_next_logistic_stop", train,
                (r_index or 0) + 1)
        end
    end

    -- 按逻辑插入中转站：

    -- 1. 在 requester 后插入目标面中转站
    if r_index and to_entity.surface ~= (loco and loco.valid and loco.surface or to_entity.surface) then
        for _, conn in pairs(conns) do
            local station = pick_station_for_surface(conn, to_entity.surface)
            if station then
                add_station_to_schedule(train, station, r_index + 1)
            end
            break
        end
    end

    -- 2. 在 requester 前插入来源面中转站（当跨面时）
    if r_index and from_entity.surface ~= to_entity.surface then
        for _, conn in pairs(conns) do
            local station = pick_station_for_surface(conn, from_entity.surface)
            if station then
                add_station_to_schedule(train, station, r_index)
            end
            break
        end
    end

    -- 3. 在 provider 前插入来源面中转站（当机车不在来源面时）
    if p_index and loco and loco.valid and loco.surface ~= from_entity.surface then
        for _, conn in pairs(conns) do
            local station = pick_station_for_surface(conn, loco.surface)
            if station then
                add_station_to_schedule(train, station, p_index)
            end
            break
        end
    end
end

function LTN.on_dispatcher_updated(e)
    if not is_ltn_active() then
        return
    end

    local deliveries = e.deliveries
    local stops = storage.ltn_stops or {}

    -- 遍历所有新任务，逐个调用处理函数
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
        ltn_log("LTN兼容模式: 启用手动重指派")
    else
        -- 否则 (有 SE 且有 Glue) -> Glue 会处理，我们躺平
        LTN.on_teleport_end = noop
        ltn_log("LTN兼容模式: SE-Glue 托管")
    end
end

return LTN
