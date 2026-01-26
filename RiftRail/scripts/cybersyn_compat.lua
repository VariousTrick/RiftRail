-- scripts/cybersyn_compat.lua
-- 【Rift Rail - Cybersyn 通用兼容模块 v3.0】
-- 功能：基于 Cybersyn 新版通用接口实现的跨地表支持
-- 架构：N x M 全互联池化管理 (Candidate Pools)
-- 注意：本模块不再包含任何 SE 伪装代码，仅支持打过补丁或未来的官方 Cybersyn。

local CybersynCompat = {}
local State = nil
local log_debug = function() end

local function log_cs(msg)
    if not RiftRail.DEBUG_MODE_ENABLED then
        return
    end
    if log_debug then
        log_debug(msg)
    end
end

-- [适配] 对应 gui.lua 中的开关名称
CybersynCompat.BUTTON_NAME = "rift_rail_cybersyn_switch"

-- [辅助] 从 RiftRail 结构体中提取车站实体
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

-- [新增] 懒加载初始化函数
-- 确保在第一次访问时创建 storage 表，解决加载顺序问题
local function lazy_init_storage()
    if not storage.rr_cybersyn_pools then
        storage.rr_cybersyn_pools = {}
    end
end

-- [辅助] 检查 Cybersyn 接口是否可用
local function is_api_available()
    return remote.interfaces["cybersyn"] and remote.interfaces["cybersyn"]["register_surface_connection"]
end

function CybersynCompat.init(dependencies)
    State = dependencies.State
    if dependencies.log_debug then
        log_debug = dependencies.log_debug
    end
    log_cs("[CybersynCompat] 全新池化架构已加载 (懒加载模式)。")
end

-- ============================================================================
-- 核心逻辑：池化管理 (Pool Management)
-- ============================================================================

-- 从池中获取或创建特定的列表
local function get_pool(s1, s2)
    -- [关键修改] 在访问前确保 storage 表已初始化
    lazy_init_storage()

    if not storage.rr_cybersyn_pools[s1] then
        storage.rr_cybersyn_pools[s1] = {}
    end
    if not storage.rr_cybersyn_pools[s1][s2] then
        storage.rr_cybersyn_pools[s1][s2] = {}
    end
    return storage.rr_cybersyn_pools[s1][s2]
end

-- [内部] 执行注册/注销操作
-- action: "register_surface_connection" 或 "remove_surface_connection"
local function perform_batch_operation(action, entity_a, pool_b)
    if not (entity_a and entity_a.valid) then
        return
    end

    -- 遍历对面池子里的所有候补，执行操作
    for _, entity_b in pairs(pool_b) do
        if entity_b and entity_b.valid then
            -- 调用 Cybersyn 接口
            remote.call("cybersyn", action, entity_a, entity_b, nil) -- nil 代表默认网络掩码
        end
    end
end

-- [动作] 加入候选池 (Join Pool)
-- 当一个传送门变为合格的“入口”时调用
local function join_pool(portaldata, target_portal)
    if not is_api_available() then
        return
    end

    local s1 = portaldata.surface.index
    local s2 = target_portal.surface.index
    local uid = portaldata.unit_number
    local station = get_station(portaldata)

    if not (station and station.valid) then
        return
    end

    -- 1. 加入己方池子
    local my_pool = get_pool(s1, s2)

    -- 如果已经在池子里，无需重复操作
    if my_pool[uid] then
        -- [修复] 返回当前已有的连接数，而不是 nil
        local partner_pool = get_pool(s2, s1)
        local count = 0
        for _ in pairs(partner_pool) do
            count = count + 1
        end
        return count
    end

    my_pool[uid] = station
    log_cs("[Pool] 传送门加入池子: " .. portaldata.name .. " (" .. s1 .. "->" .. s2 .. ")")

    -- 2. 获取对方池子 (反向：从 s2 到 s1 的入口)
    -- 注意：我们只和对面的“入口”配对，形成双向通路
    local partner_pool = get_pool(s2, s1)

    -- 3. 批量注册：我和对面的每一个入口都握手
    if next(partner_pool) then
        local count = 0
        for _ in pairs(partner_pool) do
            count = count + 1
        end
        log_cs("[Link] 发现回程节点，正在建立 " .. count .. " 条连接...")
        perform_batch_operation("register_surface_connection", station, partner_pool)
        return count -- 返回建立的连接数
    else
        log_cs("[Info] 对面没有回程入口，暂不注册 Cybersyn 连接 (等待回程)。")
        return 0 -- [修改] 返回 0
    end
end

-- [动作] 离开候选池 (Leave Pool)
-- 当一个传送门不再合格时调用
local function leave_pool(portaldata, target_portal)
    if not is_api_available() then
        return
    end

    -- 这里的 target_portal 可能为 nil (如果是因为解绑而触发)
    -- 如果为 nil，我们需要通过 portaldata 的数据尝试推断，或者遍历清理
    -- 为简化逻辑，我们假设调用者会传入原来的配对对象，或者我们只清理已知的数据

    local s1 = portaldata.surface.index
    -- 如果没传 target，尝试从配对ID获取
    if not target_portal and portaldata.paired_to_id then
        target_portal = State.get_portaldata_by_id(portaldata.paired_to_id)
    end

    if not target_portal then
        -- 如果找不到目标地表，理论上它不在任何 s1->sX 的池子里有效，但为了安全，我们可以遍历清理
        -- 这是一个边缘情况，通常 update_connection 会传入 target
        return
    end

    local s2 = target_portal.surface.index
    local uid = portaldata.unit_number
    local station = get_station(portaldata) -- 即使实体快销毁了，只要 LuaEntity 还在就能读

    local my_pool = get_pool(s1, s2)

    -- 如果不在池子里，直接退出
    if not my_pool[uid] then
        return
    end

    -- 1. 获取对方池子
    local partner_pool = get_pool(s2, s1)

    -- 2. 批量注销：断开所有相关连接
    if station and station.valid then
        perform_batch_operation("remove_surface_connection", station, partner_pool)
    end

    -- 3. 从己方池子移除
    my_pool[uid] = nil
    log_cs("[Pool] 传送门移出池子: " .. portaldata.name)
end

-- ============================================================================
-- 外部调用接口
-- ============================================================================

-- 更新连接状态 (由 Logic.set_cybersyn_enabled, Logic.set_mode, Builder 等调用)
-- @param connect: boolean, true 表示希望连接，false 表示希望断开
-- @param is_migration: boolean, 是否为迁移模式 (不打印通知)
function CybersynCompat.update_connection(portaldata, target_portal, connect, player, is_migration)
    if not (portaldata and target_portal) then
        return
    end

    -- [关键判定] 到底能不能进池子？
    -- 条件：
    -- 1. 用户开关必须是 ON (connect == true)
    -- 2. 模式必须是 ENTRY (只有入口才有资格做路由节点)
    -- 3. 必须已配对 (有目标地表)

    local should_be_in_pool = connect and (portaldata.mode == "entry") and portaldata.paired_to_id

    if should_be_in_pool then
        join_pool(portaldata, target_portal)
        portaldata.cybersyn_enabled = true    -- 记录状态
        target_portal.cybersyn_enabled = true -- 同步记录(可选)
    else
        leave_pool(portaldata, target_portal)
        if not connect then
            portaldata.cybersyn_enabled = false
        end
    end

    -- 通知逻辑 (仅在非迁移且成功操作时)
    if should_be_in_pool then
        -- [修改] 接收 join_pool 的返回值
        local connections_made = join_pool(portaldata, target_portal)

        portaldata.cybersyn_enabled = true
        target_portal.cybersyn_enabled = true

        -- [修改] 智能通知逻辑
        if not is_migration and player then
            local setting = settings.get_player_settings(player)["rift-rail-show-logistics-notifications"]
            if setting and setting.value then
                local portal_gps = "[gps=" ..
                portaldata.shell.position.x ..
                "," .. portaldata.shell.position.y .. "," .. portaldata.shell.surface.name .. "]"

                if connections_made > 0 then
                    -- 情况 A: 成功建立连接
                    player.print({ "messages.rift-rail-info-cybersyn-link-established", portaldata.name, portal_gps,
                        connections_made })
                else
                    -- 情况 B: 已加入候补池，等待回程
                    player.print({ "messages.rift-rail-info-cybersyn-waiting-partner", portaldata.name, portal_gps })
                end
            end
        end
    else
        leave_pool(portaldata, target_portal)
        if not connect then
            portaldata.cybersyn_enabled = false
        end
    end
end

-- 传送门被销毁时
function CybersynCompat.on_portal_destroyed(portaldata)
    if portaldata and portaldata.cybersyn_enabled then
        -- 尝试离开池子
        CybersynCompat.update_connection(portaldata, nil, false, nil, true)
    end
end

-- 传送门被克隆时
function CybersynCompat.on_portal_cloned(old_data, new_data, is_landing)
    -- 1. 旧的退池
    if old_data.cybersyn_enabled then
        -- 尝试获取旧的配对对象 (可能已经失效，但尽力而为)
        local partner = State.get_portaldata_by_id(old_data.paired_to_id)
        leave_pool(old_data, partner)
    end

    -- 2. 新的入池 (如果是起飞/搬家)
    if new_data.cybersyn_enabled and not is_landing then
        local partner = State.get_portaldata_by_id(new_data.paired_to_id)
        if partner then
            join_pool(new_data, partner)
        end
    end
end

-- 传送开始 (调用新接口)
function CybersynCompat.on_teleport_start(train)
    if not is_api_available() then
        return
    end
    if train and train.valid then
        remote.call("cybersyn", "on_train_teleport_started", train.id)
    end
end

-- 传送结束 (调用新接口)
function CybersynCompat.on_teleport_end(new_train, old_id)
    if not is_api_available() then
        return
    end
    if new_train and new_train.valid and old_id then
        remote.call("cybersyn", "on_train_teleported", old_id, new_train)
    end
end

return CybersynCompat
