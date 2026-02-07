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

-- 写入路由表的核心函数 (v2.0 - 支持多对多 & 缓存出口信息)
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

    -- [关键修改] 数据结构升级：入口ID -> 出口ID -> 详细数据
    -- 这样同一个入口连接多个出口时，数据不会互相覆盖
    if not table[source_surface][dest_surface][unit_number] then
        table[source_surface][dest_surface][unit_number] = {}
    end

    -- 如果旧数据是残留的非表结构 (旧版本兼容)，先清空
    if type(table[source_surface][dest_surface][unit_number].station_name) == "string" then
        table[source_surface][dest_surface][unit_number] = {}
    end

    -- 写入新数据：包含出口的 ID 和 位置 (用于快速计算距离)
    table[source_surface][dest_surface][unit_number][partner_data.unit_number] = {
        station_name = station.backer_name,
        position = portal_data.shell.position,       -- 入口位置
        unit_number = unit_number,                   -- 入口 ID
        exit_position = partner_data.shell.position, -- [新增] 缓存出口位置
        exit_unit_number = partner_data.unit_number, -- [新增] 缓存出口 ID (Tick密码)
    }

    if RiftRail.DEBUG_MODE_ENABLED then
        ltn_log("[LTNCompat] 已注册路由: " ..
            source_surface .. " -> " .. dest_surface .. " | Entry:" .. portal_data.id .. " -> Exit:" .. partner_data.id)
    end
end

-- 从路由表删除的核心函数 (v2.0 - 精准删除)
local function unregister_route(portal_data, partner_data)
    if not (portal_data and partner_data) then
        return
    end

    local source_surface = portal_data.surface.index
    local dest_surface = partner_data.surface.index
    local unit_number = portal_data.unit_number
    local exit_unit_number = partner_data.unit_number

    local table = storage.rift_rail_ltn_routing_table
    -- 安全检查层级
    if table and table[source_surface] and table[source_surface][dest_surface] and table[source_surface][dest_surface][unit_number] then
        local entry_record = table[source_surface][dest_surface][unit_number]

        -- [自适应兼容] 检查是旧结构还是新结构
        if entry_record.station_name then
            -- 旧结构：直接把整个入口记录删了 (虽然有点暴力，但在迁移期是安全的)
            table[source_surface][dest_surface][unit_number] = nil
            if RiftRail.DEBUG_MODE_ENABLED then
                ltn_log("[LTNCompat] 已清理旧版单向路由: ID " .. portal_data.id)
            end
        else
            -- 新结构：精准移除指定的出口
            if entry_record[exit_unit_number] then
                entry_record[exit_unit_number] = nil
                if RiftRail.DEBUG_MODE_ENABLED then
                    ltn_log("[LTNCompat] 已注销路由: Entry:" .. portal_data.id .. " -x- Exit:" .. partner_data.id)
                end
            end

            -- 如果该入口下没有任何出口了，清理入口 Key
            if next(entry_record) == nil then
                table[source_surface][dest_surface][unit_number] = nil
            end
        end
    end
end

-- 供外部调用的模式切换处理函数
-- 供外部调用的模式切换处理函数
function LTN.on_portal_mode_changed(portal_data, old_mode)
    -- [多对多改造] 检查 target_ids 而非 paired_to_id
    if not portal_data or not portal_data.ltn_enabled or not portal_data.target_ids then
        return
    end

    -- 遍历所有连接的目标
    for target_id, _ in pairs(portal_data.target_ids) do
        local partner_data = State.get_portaldata_by_id(target_id)
        if partner_data then
            -- 之前是入口，现在不是了 -> 删除路由
            if old_mode == "entry" and portal_data.mode ~= "entry" then
                unregister_route(portal_data, partner_data)
            end

            -- 之前不是入口，现在是了 -> 注册路由
            if old_mode ~= "entry" and portal_data.mode == "entry" then
                register_route(portal_data, partner_data)
            end
        end
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

    -- 初始化双向验证池子（用于 LTN 注册）
    if not storage.rr_ltn_pools then
        storage.rr_ltn_pools = {}
    end

    ltn_log("[LTNCompat] 模块已加载 (运行时检测 LTN 接口)。")
end

-- ============================================================================
-- 双向验证池子管理 (用于 LTN 真实注册)
-- ============================================================================

-- 获取池子
local function get_pool(s1, s2)
    if not storage.rr_ltn_pools then
        storage.rr_ltn_pools = {}
    end
    if not storage.rr_ltn_pools[s1] then
        storage.rr_ltn_pools[s1] = {}
    end
    if not storage.rr_ltn_pools[s1][s2] then
        storage.rr_ltn_pools[s1][s2] = {}
    end
    return storage.rr_ltn_pools[s1][s2]
end

-- 加入池子：建立双向连接并向 LTN 注册
local function join_pool(portaldata, target_portal)
    if not (portaldata and target_portal) then
        return 0
    end

    -- [关键] 只有 entry 模式的传送门才能加入池子
    -- 因为 entry 代表"从这个地表出发的入口"，exit 不需要在池子里
    if portaldata.mode ~= "entry" then
        return 0
    end

    local s1 = portaldata.surface.index
    local s2 = target_portal.surface.index
    local uid = portaldata.unit_number
    local station = get_station(portaldata)

    if not (station and station.valid) then
        return 0
    end

    local my_pool = get_pool(s1, s2)
    if my_pool[uid] then
        -- 已经在池子里，返回当前连接数
        local partner_pool = get_pool(s2, s1)
        local count = 0
        for _ in pairs(partner_pool) do
            count = count + 1
        end
        return count
    end

    -- 1. 加入自己的池子
    my_pool[uid] = station
    ltn_log("[Pool] " .. portaldata.name .. " 加入池子: " .. s1 .. " -> " .. s2)

    -- 2. 扫描反向池子，建立双向连接
    local partner_pool = get_pool(s2, s1)
    local count = 0

    for partner_uid, partner_station in pairs(partner_pool) do
        if partner_station and partner_station.valid then
            -- 找到对应的 portaldata（通过传送门外壳ID匹配）
            local partner_data = nil
            if storage.rift_rails then
                for _, pd in pairs(storage.rift_rails) do
                    if pd.unit_number == partner_uid then
                        partner_data = pd
                        break
                    end
                end
            end

            if partner_data then
                -- 向 LTN 注册双向连接
                local ok, err = pcall(function()
                    local nid = compute_network_id(station, partner_station, -1)
                    remote.call("logistic-train-network", "connect_surfaces", station, partner_station, nid)
                end)

                if ok then
                    count = count + 1
                    ltn_log("[LTN] 已向 LTN 注册双向连接: " .. portaldata.name .. " <-> " .. partner_data.name)
                else
                    ltn_log("[LTN] 注册失败: " .. tostring(err))
                end
            end
        end
    end

    ltn_log("[Pool] 建立连接数: " .. count)
    return count
end

-- 离开池子：断开连接并从 LTN 注销
local function leave_pool(portaldata, target_portal)
    if not portaldata then
        return
    end

    -- [关键] 只有 entry 才会在池子里，exit 直接返回
    if portaldata.mode ~= "entry" then
        return
    end

    local s1 = portaldata.surface.index
    local uid = portaldata.unit_number
    local station = get_station(portaldata)

    -- 定义清理函数
    local function clean_specific_pool(surface_index_2)
        -- [关键] 检查该 entry 在路由表中是否还有通往目标地表的其他记录
        local still_has_connection = false
        if storage.rift_rail_ltn_routing_table then
            local rt = storage.rift_rail_ltn_routing_table[s1]
            if rt and rt[surface_index_2] and rt[surface_index_2][uid] then
                -- 检查路由表中是否还有任何出口记录
                if next(rt[surface_index_2][uid]) ~= nil then
                    still_has_connection = true
                end
            end
        end

        -- 只有当完全失去对该地表的 LTN 连接能力时，才移出池子并通知 LTN
        if not still_has_connection then
            local my_pool = get_pool(s1, surface_index_2)
            if my_pool[uid] then
                -- 1. 扫描反向池子，断开所有 LTN 连接
                local partner_pool = get_pool(surface_index_2, s1)
                for partner_uid, partner_station in pairs(partner_pool) do
                    if partner_station and partner_station.valid and station and station.valid then
                        -- 从 LTN 断开连接
                        local ok, err = pcall(function()
                            remote.call("logistic-train-network", "disconnect_surfaces", station, partner_station)
                        end)

                        if ok then
                            ltn_log("[LTN] 已从 LTN 注销连接: " .. portaldata.name .. " <-> partner")
                        else
                            ltn_log("[LTN] 注销失败: " .. tostring(err))
                        end
                    end
                end

                -- 2. 移出池子
                my_pool[uid] = nil
                ltn_log("[Pool] " ..
                portaldata.name .. " 离开池子: " .. s1 .. " -> " .. surface_index_2 .. " (失去所有到该地表的LTN连接)")
            end
        else
            ltn_log("[Pool] " .. portaldata.name .. " 保留在池子中: 路由表中仍有到地表 " .. surface_index_2 .. " 的其他连接")
        end
    end

    -- 根据是否指定目标来清理
    if target_portal then
        -- 情况 A: 知道对方是谁，精准清理
        clean_specific_pool(target_portal.surface.index)
    else
        -- 情况 B: 不知道对方是谁，清理所有连接
        if storage.rr_ltn_pools and storage.rr_ltn_pools[s1] then
            for s2, _ in pairs(storage.rr_ltn_pools[s1]) do
                clean_specific_pool(s2)
            end
        end
    end
end

-- 切换连接状态（使用双向验证池子）
-- @param select_portal 当前操作的传送门
-- @param target_portal 对方传送门
-- @param connect 连接状态（双方都开启时为 true）
-- @param player 操作的玩家
-- @param my_enabled 当前操作建筑的新状态（用于区分开启/关闭操作）
function LTN.update_connection(select_portal, target_portal, connect, player, my_enabled, silent)
    -- silent 参数用于静默模式（例如迁移时），默认为 false
    silent = silent or false

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

    -- 1. [关键] 检查操作"之前"的真实连接状态（双向池子）
    local was_connected = false
    if storage.rr_ltn_pools then
        local s1, s2 = select_portal.surface.index, target_portal.surface.index
        local u1, u2 = station1.unit_number, station2.unit_number
        local pool1 = storage.rr_ltn_pools[s1] and storage.rr_ltn_pools[s1][s2]
        local pool2 = storage.rr_ltn_pools[s2] and storage.rr_ltn_pools[s2][s1]
        if pool1 and pool1[u1] and pool2 and pool2[u2] then
            was_connected = true
        end
    end

    -- 2. 维护单向池子（用于时刻表创作）
    if connect then
        -- 分别检查每一方是否为 Entry，只注册合法路径
        register_route(select_portal, target_portal)
        register_route(target_portal, select_portal)
    else
        -- 注销时同样分别处理
        unregister_route(select_portal, target_portal)
        unregister_route(target_portal, select_portal)
    end

    -- 3. 执行双向池子的入池/退池逻辑（使用外部传入的 connect 参数）
    if connect then
        -- 外部已经判断了双方都开启，执行加入池子
        join_pool(select_portal, target_portal)
        join_pool(target_portal, select_portal)
    else
        -- 至少有一方关闭，执行离开池子
        leave_pool(select_portal, target_portal)
        leave_pool(target_portal, select_portal)
    end

    -- 4. 准备消息参数
    local name1 = select_portal.name or "RiftRail"
    local pos1 = select_portal.shell.position
    local surface1 = select_portal.shell.surface.name
    local gps1 = "[gps=" .. pos1.x .. "," .. pos1.y .. "," .. surface1 .. "]"

    local name2 = target_portal.name or "RiftRail"
    local pos2 = target_portal.shell.position
    local surface2 = target_portal.shell.surface.name
    local gps2 = "[gps=" .. pos2.x .. "," .. pos2.y .. "," .. surface2 .. "]"

    local msg = nil

    -- 5. 根据操作类型和连接状态，决定消息内容
    if my_enabled then
        -- 用户正在开启开关
        if connect then
            -- 双方都开启了 → 连接建立
            msg = { "messages.rift-rail-info-ltn-connected", name1, gps1, name2, gps2 }
        else
            -- 只有自己开启，对方关闭 → 等待伙伴
            msg = { "messages.rift-rail-info-ltn-waiting-partner", name1, gps1, name2, gps2 }
        end
    else
        -- 用户正在关闭开关
        if was_connected then
            -- 之前是连接着的 → 已断开
            msg = { "messages.rift-rail-info-ltn-disconnected", name1, gps1, name2, gps2 }
        else
            -- 之前就是孤立的 → 已关闭
            msg = { "messages.rift-rail-info-ltn-disabled", name1, gps1 }
        end
    end

    if not msg then
        return
    end

    -- 6. 发送消息（静默模式下跳过）
    if silent then
        return
    end

    if player then
        -- 场景 A: 玩家点击开关 -> 私聊反馈
        local setting = settings.get_player_settings(player)["rift-rail-show-logistics-notifications"]
        if setting and setting.value then
            player.print(msg)
        end
    else
        -- 场景 B: 拆除/虫咬/脚本 -> 全服广播
        for _, p in pairs(game.connected_players) do
            local setting = settings.get_player_settings(p)["rift-rail-show-logistics-notifications"]
            if setting and setting.value then
                p.print(msg)
            end
        end
    end
end

function LTN.on_portal_destroyed(select_portal)
    -- 优先清理路由表
    -- [多对多改造] 遍历 target_ids
    if select_portal and select_portal.ltn_enabled and select_portal.mode == "entry" and select_portal.target_ids then
        for target_id, _ in pairs(select_portal.target_ids) do
            local partner = State.get_portaldata_by_id(target_id)
            if partner then
                unregister_route(select_portal, partner)
            end
        end
    end

    if not is_ltn_active() then
        return
    end

    -- [多对多改造] 通知 LTN 断开连接 (如果是入口，则断开所有目标)
    if select_portal and select_portal.ltn_enabled and select_portal.target_ids then
        for target_id, _ in pairs(select_portal.target_ids) do
            local opp = State.get_portaldata_by_id(target_id)
            if opp then
                LTN.update_connection(select_portal, opp, false, nil)
            end
        end
    else
        if RiftRail.DEBUG_MODE_ENABLED then
            ltn_log("[LTNCompat] 传送门已销毁，未执行断开连接 (无目标)")
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
-- 辅助函数：找总距离最小的路径（起点→入口 + 出口→终点）
-- 返回：最佳车站名, 最佳出口ID (Tick密码)
local function find_best_route_station(from_surface_idx, to_surface_idx, start_pos, dest_pos)
    local routing_table = storage.rift_rail_ltn_routing_table
    local available_entries = routing_table[from_surface_idx] and routing_table[from_surface_idx][to_surface_idx]

    if not (available_entries and next(available_entries)) then
        return nil, nil
    end

    -- 遍历所有入口和出口组合，找总距离最小的路径
    local best_station_name = nil
    local best_exit_id = nil
    local min_total_dist_sq = math.huge

    for entry_id, exit_list in pairs(available_entries) do
        -- 兼容性检查：确保是新结构
        if not exit_list.station_name then
            for exit_id, route_data in pairs(exit_list) do
                -- 计算起点到入口的距离（同一地表，坐标系一致）
                local entry_dist_sq = (start_pos.x - route_data.position.x) ^ 2 +
                    (start_pos.y - route_data.position.y) ^ 2

                -- 计算终点到出口的距离（同一地表，坐标系一致）
                local exit_dist_sq = (dest_pos.x - route_data.exit_position.x) ^ 2 +
                    (dest_pos.y - route_data.exit_position.y) ^ 2

                -- 总距离 = 入口距离 + 出口距离
                local total_dist_sq = entry_dist_sq + exit_dist_sq

                if total_dist_sq < min_total_dist_sq then
                    min_total_dist_sq = total_dist_sq
                    best_station_name = route_data.station_name
                    best_exit_id = route_data.exit_unit_number
                end
            end
        end
    end

    return best_station_name, best_exit_id
end

-- 辅助函数：插入传送门站点序列 (含清理站逻辑 + Tick密码)
local function insert_portal_sequence(train, station_name, exit_id, insert_index)
    local schedule = train.get_schedule()
    if not schedule then
        return
    end

    -- [关键] 构造等待条件：Tick = 出口ID
    -- 这是一个巧妙的 Hack，利用 wait_conditions 传递数据给 teleport.lua
    local wait_conds = {
        { type = "inactivity", compare_type = "and", ticks = 120 }, -- 基础防呆：静止2秒
    }
    if exit_id then
        -- 写入密码。注意：ticks 是等待时间，如果 ID 很大，列车会等很久。
        -- 但不用担心，teleport.lua 会在列车进站停稳的瞬间（撞击 collider）接管并传送它。
        table.insert(wait_conds, { type = "time", compare_type = "or", ticks = exit_id })
    end

    if settings.global["rift-rail-ltn-use-teleported"].value then
        -- === 情况 A: 开启了清理站 ===
        local teleported_name = settings.global["rift-rail-ltn-teleported-name"].value
        schedule.add_record({
            station = teleported_name,
            index = { schedule_index = insert_index },
            temporary = true,
            wait_conditions = { { type = "time", ticks = 0 } },
        })
        schedule.add_record({
            station = station_name,
            index = { schedule_index = insert_index },
            wait_conditions = wait_conds, -- 写入带密码的条件
        })
    else
        -- === 情况 B: 没开清理站 ===
        schedule.add_record({
            station = station_name,
            index = { schedule_index = insert_index },
            wait_conditions = wait_conds, -- 写入带密码的条件
        })
    end

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
        -- 起点：Requester位置，终点：列车原位置
        local station, exit_id = find_best_route_station(to_entity.surface.index, loco.surface.index, to_entity.position,
            loco.position)
        if station then
            insert_portal_sequence(train, station, exit_id, r_index + 1)
            if RiftRail.DEBUG_MODE_ENABLED then
                ltn_log("插入回程路由: " .. to_entity.surface.name .. " -> " .. loco.surface.name)
            end
        end
    end

    -- [阶段 B] Provider -> Requester (送货)
    if r_index and from_entity.surface.index ~= to_entity.surface.index then
        -- 起点：Provider位置，终点：Requester位置
        local station, exit_id = find_best_route_station(from_entity.surface.index, to_entity.surface.index,
            from_entity.position, to_entity.position)
        if station then
            insert_portal_sequence(train, station, exit_id, r_index)
            if RiftRail.DEBUG_MODE_ENABLED then
                ltn_log("插入送货路由: " .. from_entity.surface.name .. " -> " .. to_entity.surface.name)
            end
        end
    end

    -- [阶段 A] Loco -> Provider (取货)
    if p_index and loco.surface.index ~= from_entity.surface.index then
        -- 起点：列车位置，终点：Provider位置
        local station, exit_id = find_best_route_station(loco.surface.index, from_entity.surface.index, loco.position,
            from_entity.position)
        if station then
            insert_portal_sequence(train, station, exit_id, p_index)
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

-- 供迁移脚本调用的函数，用于清理旧版 LTN 远程连接
function LTN.purge_legacy_connections()
    if not (remote.interfaces["logistic-train-network"] and storage.rift_rails) then
        return
    end

    if RiftRail.DEBUG_MODE_ENABLED then
        ltn_log("[Migration] 开始清理旧版 LTN 连接...")
    end

    -- 收集所有有效车站实体
    local stations = {}
    for _, portal in pairs(storage.rift_rails) do
        local station = get_station(portal)
        if station and station.valid then
            stations[#stations + 1] = station
        end
    end

    -- 暴力断开所有可能的连接 (O(N^2))
    for i = 1, #stations do
        for j = i + 1, #stations do
            pcall(remote.call, "logistic-train-network", "disconnect_surfaces", stations[i], stations[j])
        end
    end

    -- 同步清空双向池子，避免残留
    storage.rr_ltn_pools = {}

    if RiftRail.DEBUG_MODE_ENABLED then
        ltn_log("[Migration] 旧版 LTN 连接清理完成。")
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
            -- 3. 检查是否满足注册条件：已开启LTN、是入口模式、有连接目标
            -- [多对多改造] 检查 target_ids
            if portaldata.ltn_enabled and portaldata.mode == "entry" and portaldata.target_ids then
                for target_id, _ in pairs(portaldata.target_ids) do
                    local partner = State.get_portaldata_by_id(target_id)
                    if partner then
                        -- 4. 注册每一条路径
                        register_route(portaldata, partner)
                    end
                end
            end
        end
    end
    if RiftRail.DEBUG_MODE_ENABLED then
        ltn_log("LTN 路由表重建完成。")
    end
end

return LTN
