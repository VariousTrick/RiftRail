-- scripts/ltn_compat_v2.lua
-- 【Rift Rail - LTN 兼容模块 v2.0】
-- 作用：重构后的 LTN 兼容逻辑，旨在提升代码的清晰度、健壮性和可维护性。
--      负责管理与 LTN 模组的接口交互，以及动态修改列车时刻表以实现跨地表运输。

local LTN = {}
local State = nil
local log_ltn = function(...) end -- 接受任意参数的占位函数
local ROUTING_TABLE_VERSION = 2

-- ============================================================================
-- 工具函数与常量
-- ============================================================================

-- 日志：遵循全局调试开关
local function ltn_log(msg)
    if RiftRail and RiftRail.DEBUG_MODE_ENABLED then
        if log_ltn then
            log_ltn("[LTN] " .. msg)
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

local function get_or_create_route_bucket(source_surface, dest_surface, entry_unit_number)
    local routing_table = storage.rift_rail_ltn_routing_table
    if not routing_table then
        storage.rift_rail_ltn_routing_table = {}
        routing_table = storage.rift_rail_ltn_routing_table
    end

    if not routing_table[source_surface] then
        routing_table[source_surface] = {}
    end
    if not routing_table[source_surface][dest_surface] then
        routing_table[source_surface][dest_surface] = {}
    end
    if not routing_table[source_surface][dest_surface][entry_unit_number] then
        routing_table[source_surface][dest_surface][entry_unit_number] = {}
    end

    return routing_table[source_surface][dest_surface][entry_unit_number]
end

-- 迁移旧版路由表结构，仅在版本变更时运行
local function migrate_routing_table()
    -- 版本不匹配 → 直接清空整个路由表，让系统重新通过规范接口重建
    storage.rift_rail_ltn_routing_table = {}
    storage.rift_rail_ltn_routing_table_version = ROUTING_TABLE_VERSION

    if RiftRail.DEBUG_MODE_ENABLED then
        ltn_log("[Migration] 已清空路由表，等待系统重建")
    end
end

-- ============================================================================
-- 初始化
-- ============================================================================

function LTN.init(dependencies)
    State = dependencies.State
    if dependencies.log_ltn then
        log_ltn = dependencies.log_ltn
    elseif dependencies.log_debug then
        log_ltn = dependencies.log_debug
    end

    -- 初始化双向验证池子（用于 LTN 注册）
    if not storage.rr_ltn_pools then
        storage.rr_ltn_pools = {}
    end

    if storage.rift_rail_ltn_routing_table_version ~= ROUTING_TABLE_VERSION then
        migrate_routing_table()
    end

    ltn_log("[LTNCompat] 模块已加载 (运行时检测 LTN 接口)。")
end

-- ============================================================================
-- 核心同步逻辑：单一数据源架构
-- ============================================================================

-- Forward declarations（函数前向声明）
local sync_portal_ltn_state
local compute_desired_routes
local update_routing_table_for_portal
local find_portal_by_unit_number
local check_if_connected_before_sync
local check_if_connected_after_sync
local build_connection_message
local send_connection_message

-- 新的池子管理函数
local p_get_desired_pools
local p_get_current_pools
local p_join_pool
local p_leave_pool
local p_commit_all_ltn_connections

--- 辅助函数：通过 unit_number 查找传送门数据
--- @param unit_number number 传送门的 unit_number
--- @return table|nil 传送门数据
find_portal_by_unit_number = function(unit_number)
    if not storage.rift_rails then
        return nil
    end

    for _, portal_data in pairs(storage.rift_rails) do
        if portal_data.unit_number == unit_number then
            return portal_data
        end
    end

    return nil
end

--- 计算一个传送门"应该拥有"的所有路径
--- @param portal_data table 传送门数据
--- @return table 路径映射表 [target_id] = { partner_data, should_register }
compute_desired_routes = function(portal_data)
    local result = {}

    if not portal_data.target_ids then
        return result
    end

    -- 遍历所有配对目标
    for target_id, _ in pairs(portal_data.target_ids) do
        local partner_data = State and State.get_portaldata_by_id(target_id)
        if partner_data then
            -- 路由表只记录 Entry -> 任意 的路径
            local should_register = (portal_data.mode == "entry")
            result[target_id] = {
                partner = partner_data,
                should_register = should_register
            }
        end
    end

    return result
end

--- 【决策者】计算一个传送门应该存在于哪些连接池中
--- 设计原则：这是一个纯函数，只负责计算，不修改任何状态
---
--- @param portal_data table 传送门数据
--- @return table<number, boolean> 地表索引映射表 {[dest_surface_index] = true}
---
--- 池子加入规则：
---   1. 必须启用 LTN (`ltn_enabled = true`)
---   2. 必须是 Entry 模式 (`mode = "entry"`)
---   3. 必须有配对的目标传送门 (`target_ids` 非空)
---
--- 返回示例：
---   {[2] = true, [5] = true}  -- 应该存在于通往地表2和地表5的池子中
p_get_desired_pools = function(portal_data)
    local result = {}

    -- 检查是否启用 LTN
    if not portal_data.ltn_enabled then
        return result -- 未启用 LTN，不应在任何池子中
    end

    -- 检查是否为 Entry 模式
    if portal_data.mode ~= "entry" then
        return result -- Exit 模式不参与连接池
    end

    -- 检查是否有配对目标
    if not portal_data.target_ids then
        return result
    end

    -- 遍历所有配对目标，收集目标地表
    for target_id, _ in pairs(portal_data.target_ids) do
        local partner_data = State and State.get_portaldata_by_id(target_id)
        if partner_data then
            local dest_surface = partner_data.surface.index
            result[dest_surface] = true
        end
    end

    return result
end

--- 【历史学家】查询一个传送门当前存在于哪些连接池中
--- 设计原则：这是一个纯查询函数，只读取状态，不修改任何数据
---
--- @param portal_data table 传送门数据
--- @return table<number, boolean> 地表索引映射表 {[dest_surface_index] = true}
---
--- 返回示例：
---   {[2] = true}  -- 当前存在于通往地表2的池子中
p_get_current_pools = function(portal_data)
    local result = {}

    if not storage.rr_ltn_pools then
        return result
    end

    local source_surface = portal_data.surface.index
    local unit_number = portal_data.unit_number

    -- 扫描所有池子，查找包含当前传送门的记录
    if storage.rr_ltn_pools[source_surface] then
        for dest_surface, pool in pairs(storage.rr_ltn_pools[source_surface]) do
            if pool[unit_number] then
                result[dest_surface] = true
            end
        end
    end

    return result
end

--- 【执行者】将传送门加入指定的连接池，并与反向池中的伙伴建立 LTN 连接
--- 设计原则：这是原子操作，负责同时更新池子状态和调用 LTN API
---
--- @param portal_data table 传送门数据
--- @param dest_surface number 目标地表索引
--- @param batch_mode boolean|nil 批量模式（true时跳过 remote.call，用于批量重建）
---
--- 执行步骤：
---   1. 将自己加入 pools[source_surface][dest_surface]
---   2. 如果不是批量模式，扫描反向池子 pools[dest_surface][source_surface]
---   3. 与反向池中的每个伙伴调用 LTN connect_surfaces
p_join_pool = function(portal_data, dest_surface, batch_mode)
    local source_surface = portal_data.surface.index
    local unit_number = portal_data.unit_number
    local station = get_station(portal_data)

    if not station or not station.valid then
        return
    end

    -- Step 1: 将自己加入池子（宣告自身存在）
    local my_pool = get_pool(source_surface, dest_surface)
    my_pool[unit_number] = station

    if RiftRail.DEBUG_MODE_ENABLED then
        ltn_log("[Pool] 加入池子: " .. portal_data.name .. " (" .. source_surface .. " -> " .. dest_surface .. ")")
    end

    -- Step 2: 如果不是批量模式，立即与反向池中的伙伴建立连接
    if not batch_mode then
        local partner_pool = get_pool(dest_surface, source_surface)
        local connection_count = 0

        for partner_unit, partner_station in pairs(partner_pool) do
            if partner_station and partner_station.valid and station.valid then
                local ok, err = pcall(function()
                    local nid = compute_network_id(station, partner_station, -1)
                    remote.call("logistic-train-network", "connect_surfaces",
                        station, partner_station, nid)
                end)

                if ok then
                    connection_count = connection_count + 1
                    if RiftRail.DEBUG_MODE_ENABLED then
                        ltn_log("[LTN] 已注册连接: " .. portal_data.name .. " <-> partner#" .. partner_unit)
                    end
                else
                    ltn_log("[LTN] 注册失败: " .. tostring(err))
                end
            end
        end

        if RiftRail.DEBUG_MODE_ENABLED then
            ltn_log("[Pool] 建立连接数: " .. connection_count)
        end
    end
end

--- 【执行者】将传送门从指定的连接池中移除，并断开与反向池中伙伴的 LTN 连接
--- 设计原则：这是原子操作，负责同时断开连接和更新池子状态
---
--- @param portal_data table 传送门数据
--- @param dest_surface number 目标地表索引
--- @param batch_mode boolean|nil 批量模式（true时跳过 remote.call）
---
--- 执行步骤：
---   1. 如果不是批量模式，扫描反向池子并与每个伙伴调用 LTN disconnect_surfaces
---   2. 将自己从 pools[source_surface][dest_surface] 中移除
p_leave_pool = function(portal_data, dest_surface, batch_mode)
    local source_surface = portal_data.surface.index
    local unit_number = portal_data.unit_number
    local station = get_station(portal_data)

    -- Step 1: 如果不是批量模式，先断开所有连接
    if not batch_mode and station and station.valid then
        local partner_pool = get_pool(dest_surface, source_surface)
        local disconnection_count = 0

        for partner_unit, partner_station in pairs(partner_pool) do
            if partner_station and partner_station.valid then
                local ok, err = pcall(function()
                    remote.call("logistic-train-network", "disconnect_surfaces",
                        station, partner_station)
                end)

                if ok then
                    disconnection_count = disconnection_count + 1
                    if RiftRail.DEBUG_MODE_ENABLED then
                        ltn_log("[LTN] 已注销连接: " .. portal_data.name .. " <-> partner#" .. partner_unit)
                    end
                else
                    ltn_log("[LTN] 注销失败: " .. tostring(err))
                end
            end
        end

        if RiftRail.DEBUG_MODE_ENABLED then
            ltn_log("[Pool] 断开连接数: " .. disconnection_count)
        end
    end

    -- Step 2: 将自己从池子中移除
    if storage.rr_ltn_pools and
        storage.rr_ltn_pools[source_surface] and
        storage.rr_ltn_pools[source_surface][dest_surface] then
        storage.rr_ltn_pools[source_surface][dest_surface][unit_number] = nil

        if RiftRail.DEBUG_MODE_ENABLED then
            ltn_log("[Pool] 离开池子: " .. portal_data.name .. " (" .. source_surface .. " -> " .. dest_surface .. ")")
        end
    end
end

--- 【批量提交】在批量重建后，统一建立所有 LTN 连接
--- 设计原则：只在批量重建的最后一步调用，避免重复的 remote.call
---
--- 前提条件：
---   - routing_table 和 connection_pools 已经通过批量 sync 完全重建
---   - 所有传送门都已加入应该存在的池子
---
--- 执行逻辑：
---   遍历所有池子，将池子中的传送门两两配对，建立 LTN 连接
p_commit_all_ltn_connections = function()
    if not is_ltn_active() then
        return
    end

    if not storage.rr_ltn_pools then
        return
    end

    local total_connections = 0

    -- 遍历所有地表对
    for source_surface, destinations in pairs(storage.rr_ltn_pools) do
        for dest_surface, source_pool in pairs(destinations) do
            -- 获取反向池子
            local dest_pool = storage.rr_ltn_pools[dest_surface] and
                storage.rr_ltn_pools[dest_surface][source_surface]

            if dest_pool then
                -- 将两个池子中的所有传送门两两配对
                for source_unit, source_station in pairs(source_pool) do
                    for dest_unit, dest_station in pairs(dest_pool) do
                        if source_station.valid and dest_station.valid then
                            local ok, err = pcall(function()
                                local nid = compute_network_id(source_station, dest_station, -1)
                                remote.call("logistic-train-network", "connect_surfaces",
                                    source_station, dest_station, nid)
                            end)

                            if ok then
                                total_connections = total_connections + 1
                            else
                                ltn_log("[LTN] 批量连接失败: " .. tostring(err))
                            end
                        end
                    end
                end
            end
        end
    end

    if RiftRail.DEBUG_MODE_ENABLED then
        ltn_log("[Commit] 批量建立 LTN 连接完成，总计: " .. total_connections)
    end
end

--- 更新路由表（对比期望状态与当前状态）
--- @param portal_data table 传送门数据
--- @param desired_routes table 期望的路径集合
update_routing_table_for_portal = function(portal_data, desired_routes)
    local source_surface = portal_data.surface.index
    local unit_number = portal_data.unit_number
    local station = get_station(portal_data)

    if not station then
        return
    end

    -- 处理每一条期望的路径
    for target_id, route_info in pairs(desired_routes) do
        local partner_data = route_info.partner
        local should_register = route_info.should_register

        if should_register then
            -- 写入路由表
            local dest_surface = partner_data.surface.index
            local route_bucket = get_or_create_route_bucket(source_surface, dest_surface, unit_number)

            route_bucket[partner_data.unit_number] = {
                station_name = station.backer_name,
                position = portal_data.shell.position,
                unit_number = unit_number,
                exit_position = partner_data.shell.position,
                exit_custom_id = partner_data.id,
                exit_unit_number = partner_data.unit_number,
            }

            if RiftRail.DEBUG_MODE_ENABLED then
                ltn_log("[RouteTable] 注册路由: " .. portal_data.id .. " -> " .. partner_data.id)
            end
        end
    end

    -- 清理不再需要的路径（反向扫描现有数据）
    local routing_table = storage.rift_rail_ltn_routing_table
    if routing_table[source_surface] then
        for dest_surface, entries in pairs(routing_table[source_surface]) do
            local entry_record = entries[unit_number]
            if entry_record then
                for exit_unit_number, _ in pairs(entry_record) do
                    -- 检查这条路径是否还在 desired_routes 中
                    local still_wanted = false
                    for _, route_info in pairs(desired_routes) do
                        if route_info.should_register and route_info.partner.unit_number == exit_unit_number then
                            still_wanted = true
                            break
                        end
                    end

                    if not still_wanted then
                        entry_record[exit_unit_number] = nil
                        if RiftRail.DEBUG_MODE_ENABLED then
                            ltn_log("[RouteTable] 注销路由: Entry:" .. unit_number .. " -x- Exit:" .. exit_unit_number)
                        end
                    end
                end

                -- 清理空桶
                if next(entry_record) == nil then
                    entries[unit_number] = nil
                end
            end
        end
    end
end

--- 【核心函数】幂等地同步一个传送门的 LTN 状态
--- 设计原则：
---   1. 路由表和连接池都是从传送门状态推导的派生数据
---   2. 此函数是唯一的状态更新入口，保证一致性
---   3. 可被重复调用，结果幂等（相同输入 → 相同输出）
---
--- @param portal_data table 需要同步的传送门数据
--- @param batch_mode boolean|nil 批量模式（true时跳过远程调用，用于批量重建）
---
--- 执行流程：
---   Part A: 更新路由表（记录 Entry → Exit 映射，用于生成时刻表）
---   Part B: 更新连接池（记录 Entry 的存在，用于 LTN 连接）
---     1. 计算应该存在的池子（决策者）
---     2. 查询当前存在的池子（历史学家）
---     3. 计算差异集，执行增量更新（执行者）
sync_portal_ltn_state = function(portal_data, batch_mode)
    if not portal_data then
        return
    end

    -- Part A: 更新路由表（用于列车时刻表生成）
    local desired_routes = compute_desired_routes(portal_data)
    update_routing_table_for_portal(portal_data, desired_routes)

    -- Part B: 更新连接池（用于 LTN 连接管理）
    local desired_pools = p_get_desired_pools(portal_data)
    local current_pools = p_get_current_pools(portal_data)

    -- 找出需要加入的池子（在 desired 但不在 current）
    for dest_surface, _ in pairs(desired_pools) do
        if not current_pools[dest_surface] then
            p_join_pool(portal_data, dest_surface, batch_mode)
        end
    end

    -- 找出需要离开的池子（在 current 但不在 desired）
    for dest_surface, _ in pairs(current_pools) do
        if not desired_pools[dest_surface] then
            p_leave_pool(portal_data, dest_surface, batch_mode)
        end
    end

    if RiftRail.DEBUG_MODE_ENABLED then
        ltn_log("[Sync] 已完成传送门 LTN 状态同步: " .. portal_data.name)
    end
end

--- 检查两个传送门之间是否已连接（同步前）
--- @param portal1 table 传送门1
--- @param portal2 table 传送门2
--- @return boolean 是否已连接
check_if_connected_before_sync = function(portal1, portal2)
    if not (portal1 and portal2) then
        return false
    end

    local station1 = get_station(portal1)
    local station2 = get_station(portal2)

    if not (station1 and station1.valid and station2 and station2.valid) then
        return false
    end

    -- 检查连接池
    if not storage.rr_ltn_pools then
        return false
    end

    local s1, s2 = portal1.surface.index, portal2.surface.index
    local u1, u2 = station1.unit_number, station2.unit_number
    local pool1 = storage.rr_ltn_pools[s1] and storage.rr_ltn_pools[s1][s2]
    local pool2 = storage.rr_ltn_pools[s2] and storage.rr_ltn_pools[s2][s1]

    return (pool1 and pool1[u1] and pool2 and pool2[u2]) or false
end

--- 检查两个传送门之间是否已连接（同步后）
--- @param portal1 table 传送门1
--- @param portal2 table 传送门2
--- @return boolean 是否已连接
check_if_connected_after_sync = function(portal1, portal2)
    -- 连接的条件：双方都启用 LTN，且至少有一方是 Entry 模式
    if not (portal1 and portal2) then
        return false
    end

    if not (portal1.ltn_enabled and portal2.ltn_enabled) then
        return false
    end

    -- 至少有一方是 Entry，且在 target_ids 中互相包含
    local has_route = false

    if portal1.mode == "entry" and portal1.target_ids and portal1.target_ids[portal2.id] then
        has_route = true
    end

    if portal2.mode == "entry" and portal2.target_ids and portal2.target_ids[portal1.id] then
        has_route = true
    end

    return has_route
end

--- 构造连接状态变化的提示消息
--- @param my_enabled boolean 当前操作建筑的新状态
--- @param was_connected boolean 操作前是否已连接
--- @param now_connected boolean 操作后是否已连接
--- @param select_portal table 源传送门
--- @param target_portal table 目标传送门
--- @param operator_is_first boolean|nil 操作者顺序标记
--- @return table|nil 本地化消息表
build_connection_message = function(my_enabled, was_connected, now_connected, select_portal, target_portal,
                                    operator_is_first)
    local first_portal = select_portal
    local second_portal = target_portal
    if operator_is_first == false then
        first_portal = target_portal
        second_portal = select_portal
    end

    local name1 = first_portal.name or "RiftRail"
    local pos1 = first_portal.shell.position
    local surface1 = first_portal.shell.surface.name
    local gps1 = "[gps=" .. pos1.x .. "," .. pos1.y .. "," .. surface1 .. "]"

    local name2 = second_portal.name or "RiftRail"
    local pos2 = second_portal.shell.position
    local surface2 = second_portal.shell.surface.name
    local gps2 = "[gps=" .. pos2.x .. "," .. pos2.y .. "," .. surface2 .. "]"

    if my_enabled then
        -- 用户正在开启开关
        if now_connected then
            -- 双方都开启了 → 连接建立
            return { "messages.rift-rail-info-ltn-connected", name1, gps1, name2, gps2 }
        end

        -- 只有自己开启，对方关闭 → 等待伙伴
        return { "messages.rift-rail-info-ltn-waiting-partner", name1, gps1, name2, gps2 }
    end

    -- 用户正在关闭开关
    if was_connected then
        -- 之前是连接着的 → 已断开
        return { "messages.rift-rail-info-ltn-disconnected", name1, gps1, name2, gps2 }
    end

    -- 之前就是孤立的 → 已关闭
    return { "messages.rift-rail-info-ltn-disabled", name1, gps1 }
end

--- 发送连接状态提示消息
--- @param msg table|nil 本地化消息
--- @param player LuaPlayer|nil 目标玩家
--- @param silent boolean|nil 静默模式
send_connection_message = function(msg, player, silent)
    if not msg or silent then
        return
    end

    if player then
        -- 场景 A: 玩家点击开关 -> 私聊反馈
        local setting = settings.get_player_settings(player)["rift-rail-show-logistics-notifications"]
        if setting and setting.value then
            player.print(msg)
        end
        return
    end

    -- 场景 B: 拆除/虫咬/脚本 -> 全服广播
    for _, p in pairs(game.connected_players) do
        local setting = settings.get_player_settings(p)["rift-rail-show-logistics-notifications"]
        if setting and setting.value then
            p.print(msg)
        end
    end
end

-- ============================================================================
-- 外部接口：使用核心同步函数
-- ============================================================================

--- 传送门模式切换时的处理函数
--- @param portal_data table 传送门数据
--- @param old_mode string|nil 旧模式
function LTN.on_portal_mode_changed(portal_data, old_mode)
    if not portal_data or not portal_data.ltn_enabled then
        return
    end

    -- 简单调用同步函数即可，幂等设计保证结果正确
    sync_portal_ltn_state(portal_data, false)

    -- 如果有配对目标，也同步它们（因为反向路径可能改变）
    if portal_data.target_ids then
        for target_id, _ in pairs(portal_data.target_ids) do
            local partner_data = State and State.get_portaldata_by_id(target_id)
            if partner_data and partner_data.ltn_enabled then
                sync_portal_ltn_state(partner_data, false)
            end
        end
    end

    if RiftRail.DEBUG_MODE_ENABLED then
        ltn_log("[ModeChanged] 已同步传送门模式切换: " ..
            portal_data.name .. " (old=" .. tostring(old_mode) .. " new=" .. portal_data.mode .. ")")
    end
end

--- 传送门销毁时的处理函数
--- @param portal_data table 传送门数据
function LTN.on_portal_destroyed(portal_data)
    if not portal_data then
        return
    end

    -- 通过调用 sync 清理该传送门的所有 LTN 状态
    -- sync 函数会检测到 station 无效或配对目标为空，自动执行清理
    sync_portal_ltn_state(portal_data, false)

    -- 同步所有相关的配对传送门
    if portal_data.target_ids then
        for target_id, _ in pairs(portal_data.target_ids) do
            local partner_data = State and State.get_portaldata_by_id(target_id)
            if partner_data and partner_data.ltn_enabled then
                sync_portal_ltn_state(partner_data, false)
            end
        end
    end

    if RiftRail.DEBUG_MODE_ENABLED then
        ltn_log("[Destroyed] 已清理销毁的传送门 LTN 状态: " .. portal_data.name)
    end
end

--- 更新 LTN 连接（简化版，使用核心同步函数）
--- @param select_portal table 操作的传送门
--- @param target_portal table 目标传送门
--- @param connect boolean 连接状态（此参数在新架构中被忽略，自动从数据推导）
--- @param player LuaPlayer|nil 操作玩家（用于消息提示）
--- @param my_enabled boolean 当前操作建筑的新状态
--- @param silent boolean|nil 静默模式
--- @param operator_is_first boolean|nil 操作者顺序标记
function LTN.update_connection(select_portal, target_portal, connect, player, my_enabled, silent, operator_is_first)
    silent = silent or false

    if not is_ltn_active() and not silent then
        if player then
            player.print({ "messages.rift-rail-error-ltn-not-found" })
        end
        return
    end

    -- 记录操作前的连接状态（用于消息提示）
    local was_connected = check_if_connected_before_sync(select_portal, target_portal)

    -- 同步两个传送门的状态（幂等操作）
    sync_portal_ltn_state(select_portal, false)
    sync_portal_ltn_state(target_portal, false)

    -- 检查操作后的连接状态
    local now_connected = check_if_connected_after_sync(select_portal, target_portal)

    -- 发送消息提示
    if not silent then
        local msg = build_connection_message(my_enabled, was_connected, now_connected, select_portal, target_portal,
            operator_is_first)
        send_connection_message(msg, player, silent)
    end

    if RiftRail.DEBUG_MODE_ENABLED then
        ltn_log("[UpdateConnection] 已同步连接状态: " .. select_portal.name .. " <-> " .. target_portal.name)
    end
end

-- ============================================================================
-- 车站名更新
-- ============================================================================

-- 更新路由表中的车站名（当玩家改名时调用）
function LTN.update_station_name_in_routes(entry_unit_number, new_station_name)
    local routing_table = storage.rift_rail_ltn_routing_table
    if not routing_table then
        return
    end

    -- 遍历所有地表对
    for source_surface, dest_surfaces in pairs(routing_table) do
        for dest_surface, entries in pairs(dest_surfaces) do
            -- 检查这个入口是否存在
            local entry_routes = entries[entry_unit_number]
            if entry_routes then
                -- 更新该入口的所有出口记录
                for exit_id, route_data in pairs(entry_routes) do
                    route_data.station_name = new_station_name
                end
                if RiftRail.DEBUG_MODE_ENABLED then
                    ltn_log("已更新路由表中的车站名: entry_id=" .. entry_unit_number .. " -> " .. new_station_name)
                end
            end
        end
    end
end

-- ============================================================================
-- 事件处理：LTN 调度更新
-- ============================================================================

function LTN.on_stops_updated(e)
    -- e.logistic_train_stops: map[id] = { entity = stop-entity, ... }
    storage.ltn_stops = e.logistic_train_stops or {}
end

-- 辅助函数：找总距离最小的路径（起点→入口 + 出口→终点）
-- 返回：最佳车站名, 最佳出口ID
local function find_best_route_station(from_surface_idx, to_surface_idx, start_pos, dest_pos)
    local routing_table = storage.rift_rail_ltn_routing_table
    local available_entries = routing_table[from_surface_idx] and routing_table[from_surface_idx][to_surface_idx]

    if RiftRail.DEBUG_MODE_ENABLED then
        ltn_log("find_best_route_station: from=" .. from_surface_idx .. " to=" .. to_surface_idx)
    end

    if not (available_entries and next(available_entries)) then
        if RiftRail.DEBUG_MODE_ENABLED then
            ltn_log("available_entries为空")
        end
        return nil, nil
    end

    if RiftRail.DEBUG_MODE_ENABLED then
        ltn_log("available_entries存在，开始遍历")
    end

    -- 遍历所有入口和出口组合，找总距离最小的路径
    local best_station_name = nil
    local best_exit_id = nil
    local min_total_dist_sq = math.huge

    for entry_id, exit_list in pairs(available_entries) do
        if RiftRail.DEBUG_MODE_ENABLED then
            ltn_log("处理entry_id=" .. entry_id .. " exit_list类型=" .. type(exit_list))
        end

        -- 遍历该入口的所有出口
        if type(exit_list) == "table" then
            for exit_id, route_data in pairs(exit_list) do
                if type(route_data) == "table" and route_data.position and route_data.exit_position then
                    if RiftRail.DEBUG_MODE_ENABLED then
                        ltn_log("处理exit_id=" .. exit_id)
                    end

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
                        best_exit_id = route_data.exit_custom_id
                        if RiftRail.DEBUG_MODE_ENABLED then
                            ltn_log("找到更优路线: station=" .. best_station_name .. " dist_sq=" .. total_dist_sq)
                        end
                    end
                end
            end
        end
    end

    if RiftRail.DEBUG_MODE_ENABLED then
        ltn_log("返回结果: station=" .. tostring(best_station_name) .. " exit_id=" .. tostring(best_exit_id))
    end

    return best_station_name, best_exit_id
end

-- 辅助函数：插入传送门站点序列
local function insert_portal_sequence(train, station_name, exit_id, insert_index)
    local schedule = train.get_schedule()
    if not schedule then
        return
    end

    -- 构造等待条件：使用信号 riftrail-go-to-id 传递目标ID
    local wait_conds = {}
    if exit_id then
        -- 使用信号方式：在电路条件中传递目标ID
        -- teleport.lua 会在列车进站停稳的瞬间（撞击 collider）读取这个信号
        table.insert(wait_conds, {
            type = "circuit",
            compare_type = "or",
            condition = {
                first_signal = { type = "virtual", name = "riftrail-go-to-id" },
                comparator = "=",
                constant = exit_id
            }
        })
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
            wait_conditions = wait_conds,
        })
    else
        -- === 情况 B: 没开清理站 ===
        schedule.add_record({
            station = station_name,
            index = { schedule_index = insert_index },
            wait_conditions = wait_conds,
        })
    end

    if schedule.current >= insert_index then
        train.go_to_station(insert_index)
    end
end

-- 处理单条交付任务
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
    -- [阶段 C] Requester -> Loco Surface
    if r_index and to_entity.surface.index ~= loco.surface.index then
        local station, exit_id = find_best_route_station(to_entity.surface.index, loco.surface.index, to_entity.position,
            loco.position)
        if station then
            insert_portal_sequence(train, station, exit_id, r_index + 1)
            if RiftRail.DEBUG_MODE_ENABLED then
                ltn_log("插入回程路由: " .. to_entity.surface.name .. " -> " .. loco.surface.name)
            end
        end
    end

    -- [阶段 B] Provider -> Requester
    if r_index and from_entity.surface.index ~= to_entity.surface.index then
        local station, exit_id = find_best_route_station(from_entity.surface.index, to_entity.surface.index,
            from_entity.position, to_entity.position)
        if station then
            insert_portal_sequence(train, station, exit_id, r_index)
            if RiftRail.DEBUG_MODE_ENABLED then
                ltn_log("插入送货路由: " .. from_entity.surface.name .. " -> " .. to_entity.surface.name)
            end
        end
    end

    -- [阶段 A] Loco -> Provider
    if p_index and loco.surface.index ~= from_entity.surface.index then
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

-- 主入口函数：处理 LTN 调度更新事件
function LTN.on_dispatcher_updated(e)
    if not is_ltn_active() then
        return
    end

    local deliveries = e.deliveries
    local stops = storage.ltn_stops or {}

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

-- ============================================================================
-- 迁移相关
-- ============================================================================

--- 清理所有旧版 LTN 连接和数据
--- 用于迁移或重建前的彻底清空
function LTN.purge_legacy_connections()
    if not storage.rift_rails then
        return
    end

    if RiftRail.DEBUG_MODE_ENABLED then
        ltn_log("[Purge] 开始清理旧版 LTN 连接...")
    end

    -- 1. 断开所有 LTN 连接
    if remote.interfaces["logistic-train-network"] then
        local stations = {}
        for _, portal in pairs(storage.rift_rails) do
            local station = get_station(portal)
            if station and station.valid then
                stations[#stations + 1] = station
            end
        end

        local disconnect_count = 0
        for i = 1, #stations do
            for j = i + 1, #stations do
                local ok = pcall(remote.call, "logistic-train-network", "disconnect_surfaces",
                    stations[i], stations[j])
                if ok then
                    disconnect_count = disconnect_count + 1
                end
            end
        end

        if RiftRail.DEBUG_MODE_ENABLED then
            ltn_log("[Purge] 已断开 " .. disconnect_count .. " 个 LTN 连接")
        end
    end

    -- 2. 清空路由表
    storage.rift_rail_ltn_routing_table = {}

    -- 3. 清空连接池
    storage.rr_ltn_pools = {}

    if RiftRail.DEBUG_MODE_ENABLED then
        ltn_log("[Purge] 旧版 LTN 连接清理完成")
    end
end

-- ============================================================================
-- 重建路由表（使用批量同步模式 - 三步走策略）
-- ============================================================================

--- 供迁移脚本调用的函数，用于从旧数据重建整个路由表和连接池
---
--- 三步走策略：
---   Step 1: Purge（清空） - 断开所有 LTN 连接，清空数据表
---   Step 2: Rebuild（重建） - 纯内存计算，更新路由表和连接池
---   Step 3: Commit（提交） - 统一建立所有 LTN 连接
function LTN.rebuild_routing_table_from_storage()
    if RiftRail.DEBUG_MODE_ENABLED then
        ltn_log("[Rebuild] 开始重建 LTN 路由表...")
    end

    -- Step 1: Purge - 彻底清空（包括 LTN 连接）
    LTN.purge_legacy_connections()

    -- Step 2: Rebuild - 批量同步所有传送门（纯内存计算，batch_mode=true）
    if storage.rift_rails then
        local sync_count = 0
        for _, portaldata in pairs(storage.rift_rails) do
            -- 为所有传送门调用 sync（包括未启用 LTN 的，让它们正确清理）
            sync_portal_ltn_state(portaldata, true)
            sync_count = sync_count + 1
        end

        if RiftRail.DEBUG_MODE_ENABLED then
            ltn_log("[Rebuild] 已同步 " .. sync_count .. " 个传送门")
        end
    end

    -- Step 3: Commit - 统一建立所有 LTN 连接
    p_commit_all_ltn_connections()

    if RiftRail.DEBUG_MODE_ENABLED then
        ltn_log("[Rebuild] LTN 路由表重建完成")
    end
end

return LTN
