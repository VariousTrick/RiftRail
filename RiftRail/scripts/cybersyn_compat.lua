-- scripts/cybersyn_compat.lua
-- 【Rift Rail - Cybersyn 兼容模块 v0.8.0】
-- 策略：N x M 全互联池 + SE 数据伪装
-- 策略：SE 环境下启用 N x M 全互联池 + SE 数据伪装
--       非 SE 环境下，本模块为空壳，不提供任何功能。

local CybersynSE = {}
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

-- [关键] 环境检测与函数置空
if not script.active_mods["space-exploration"] then
    -- 如果没有 SE，返回一个包含所有接口的空表，防止其他文件调用时报错
    return {
        init = function() end,
        purge_legacy_connections = function() end,
        update_connection = function() end,
        on_portal_destroyed = function() end,
        on_portal_cloned = function() end,
        on_teleport_start = function() end,
        on_teleport_end = function() end,
    }
end

-- 对应 gui.lua 中的开关名称
CybersynSE.BUTTON_NAME = "rift_rail_cybersyn_switch"

-- 生成排序键
local function sorted_pair_key(a, b)
    if a < b then
        return a .. "|" .. b
    else
        return b .. "|" .. a
    end
end

-- 构造伪装成 SE 车站的实体表 (Duck Typing)
local function make_fake_entity(real_entity)
    return {
        valid = true,
        name = "se-space-elevator-train-stop", -- 核心欺骗点
        unit_number = real_entity.unit_number,
        surface = { index = real_entity.surface.index, name = real_entity.surface.name, valid = true },
        position = real_entity.position,
        operable = true,
        backer_name = real_entity.backer_name,
        __self = "lua_table_wrapper", -- 标记，方便调试
    }
end

-- 从 RiftRail 结构体中提取车站实体
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

-- 为了解决加载顺序问题，将表结构检查放在 init 内部，配合 control.lua 的逻辑
function CybersynSE.init(dependencies)
    State = dependencies.State
    if dependencies.log_debug then
        log_debug = dependencies.log_debug
    end

    -- 确保池子存在
    if not storage.rr_cybersyn_pools then
        storage.rr_cybersyn_pools = {}
    end

    log_cs("[CybersynCompat] 伪装池化架构已加载。")
end

-- 【迁移函数】清理旧版(Entry-Exit)连接
-- 【迁移函数】暴力清理旧版连接
-- 策略：不依赖 Rift Rail 内部的配对数据（因为可能已迁移），而是遍历所有传送门，
-- 尝试清理所有可能的两两组合。这能确保 100% 清除所有残留的脏数据。
function CybersynSE.purge_legacy_connections()
    if not (remote.interfaces["cybersyn"] and storage.rift_rails) then
        return
    end
    log_cs("[Migration] 开始执行暴力清理 (Brute Force Purge)...")

    -- 1. 收集所有现存的有效车站实体
    local all_stations = {}
    for _, portal in pairs(storage.rift_rails) do
        local station = get_station(portal)
        if station and station.valid then
            table.insert(all_stations, station)

            -- 第一步：无条件清除 se_elevators (单体数据)
            remote.call("cybersyn", "write_global", nil, "se_elevators", station.unit_number)
        end
    end

    -- 2. 暴力遍历所有两两组合，清除 connected_surfaces (连接数据)
    -- 这是一个 O(N^2) 操作，但 N 通常很小（几十到几百），在迁移阶段完全可以接受
    for i = 1, #all_stations do
        for j = i + 1, #all_stations do
            local s1 = all_stations[i]
            local s2 = all_stations[j]

            -- 模拟旧版 Key 生成逻辑
            local s1_idx = s1.surface.index
            local s2_idx = s2.surface.index
            local k_surf = sorted_pair_key(s1_idx, s2_idx)
            local k_ent = sorted_pair_key(s1.unit_number, s2.unit_number)

            -- 发送删除指令 (如果不存在则忽略，如果存在则删除)
            remote.call("cybersyn", "write_global", nil, "connected_surfaces", k_surf, k_ent)
        end
    end

    log_cs("[Migration] 暴力清理完成，所有潜在旧连接已移除。")
end

-- ============================================================================
-- 核心逻辑：伪装数据读写
-- ============================================================================

-- 向 Cybersyn 注册一个“电梯”
local function register_fake_elevator(portaldata, station)
    -- 构造 SE 风格的数据结构
    -- Cybersyn 需要查 se_elevators[unit_number]
    local fake_data = {
        elevator = portaldata.shell,
        stop = station,
        surface_id = portaldata.surface.index,
        stop_id = station.unit_number,
        elevator_id = portaldata.shell.unit_number,
        -- 下面这些是为了防止 Cybersyn 读取时报错
        ground = { stop = station },
        orbit = { stop = station },
        cs_enabled = true,
        network_masks = nil,
        [portaldata.surface.index] = { stop = station },
    }
    remote.call("cybersyn", "write_global", fake_data, "se_elevators", station.unit_number)
end

-- 从 Cybersyn 注销一个“电梯”
local function unregister_fake_elevator(unit_number)
    remote.call("cybersyn", "write_global", nil, "se_elevators", unit_number)
end

-- 建立两个车站之间的连接 (写入 connected_surfaces)
local function link_stations(s1, s2)
    local k_surf = sorted_pair_key(s1.surface.index, s2.surface.index)
    local k_ent = sorted_pair_key(s1.unit_number, s2.unit_number)

    -- 无论 ID 大小，我们都必须传入“伪装实体”，否则 Cybersyn 检查名字时会失败
    -- Cybersyn 逻辑：if entity1.name == "se-space-elevator-train-stop" ...
    local f1 = make_fake_entity(s1)
    local f2 = make_fake_entity(s2)

    -- 确保 ID 小的在前面作为 entity1 (虽然 Cybersyn 写入时也会排序，但我们预处理更稳妥)
    local ent1, ent2 = f1, f2
    local primary_unit_number = s1.unit_number -- 默认 s1 是主
    local secondary_station = s2

    if s1.unit_number > s2.unit_number then
        ent1 = f2
        ent2 = f1
        primary_unit_number = s2.unit_number
        secondary_station = s1
    end

    -- 动态修补 se_elevators 数据
    -- 必须确保 ID 较小的那个实体 (Cybersyn 认定的 "电梯本体") 包含对面地表的映射
    -- 否则当火车在对面地表时，Cybersyn 查不到入口会崩溃
    if remote.interfaces["cybersyn"] then
        -- 1. 读取现有的伪装数据
        local fake_data = remote.call("cybersyn", "read_global", "se_elevators", primary_unit_number)
        if fake_data then
            -- 2. 补全缺失的地表映射
            fake_data[secondary_station.surface.index] = { stop = secondary_station }
            -- 3. 写回
            remote.call("cybersyn", "write_global", fake_data, "se_elevators", primary_unit_number)
        end
    end

    local conn_data = { entity1 = ent1, entity2 = ent2 }

    -- 尝试定点写入 (兼容性写入)
    local success = remote.call("cybersyn", "write_global", conn_data, "connected_surfaces", k_surf, k_ent)
    if not success then
        -- 如果表不存在，初始化该表
        remote.call("cybersyn", "write_global", { [k_ent] = conn_data }, "connected_surfaces", k_surf)
    end
end

-- 断开连接
local function unlink_stations(s1, s2)
    local k_surf = sorted_pair_key(s1.surface.index, s2.surface.index)
    local k_ent = sorted_pair_key(s1.unit_number, s2.unit_number)
    remote.call("cybersyn", "write_global", nil, "connected_surfaces", k_surf, k_ent)
end

-- ============================================================================
-- 核心逻辑：池化管理 (N x M)
-- ============================================================================

local function get_pool(s1, s2)
    if not storage.rr_cybersyn_pools then
        storage.rr_cybersyn_pools = {}
    end
    if not storage.rr_cybersyn_pools[s1] then
        storage.rr_cybersyn_pools[s1] = {}
    end
    if not storage.rr_cybersyn_pools[s1][s2] then
        storage.rr_cybersyn_pools[s1][s2] = {}
    end
    return storage.rr_cybersyn_pools[s1][s2]
end

-- 加入池子：自己变成有效入口
local function join_pool(portaldata, target_portal)
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

    -- 1. 注册自己为 SE 电梯 (伪装身份)
    register_fake_elevator(portaldata, station)
    my_pool[uid] = station

    log_cs("[Pool] 入池: " .. portaldata.name)

    -- 2. 扫描回程池，建立连接
    local partner_pool = get_pool(s2, s1)
    local count = 0

    for _, partner_station in pairs(partner_pool) do
        if partner_station and partner_station.valid then
            link_stations(station, partner_station)
            count = count + 1
        end
    end

    log_cs("[Link] 建立连接数: " .. count)
    return count
end

-- 离开池子：自己不再是有效入口
local function leave_pool(portaldata, target_portal)
    local s1 = portaldata.surface.index
    local uid = portaldata.unit_number
    local station = get_station(portaldata) -- 尝试获取，可能已失效

    -- 定义一个内部清理函数，用来清理特定方向的连接
    local function clean_specific_pool(surface_index_2)
        local my_pool = get_pool(s1, surface_index_2)
        if my_pool[uid] then
            -- 1. 扫描回程池，断开连接
            local partner_pool = get_pool(surface_index_2, s1)
            for _, partner_station in pairs(partner_pool) do
                -- station 即使无效了，只要不为 nil，传给 remove 接口也是安全的(会尝试用ID删)
                if partner_station and partner_station.valid and station then
                    -- 无论 station 是否 valid，只要它曾经注册过，我们就尝试注销
                    -- 注意：如果 station 彻底没了，这里可能注销失败，但我们在迁移脚本里有兜底
                    if station.valid then
                        unlink_stations(station, partner_station)
                    end
                end
            end
            -- 2. 移出池子
            my_pool[uid] = nil
        end
    end

    -- [逻辑分叉]
    if target_portal then
        -- 情况 A: 知道对方是谁，精准清理
        clean_specific_pool(target_portal.surface.index)
    else
        -- 情况 B: 不知道对方是谁 (比如传入了 nil)，暴力扫描
        -- 遍历 s1 下面所有的 s2 池子
        if storage.rr_cybersyn_pools and storage.rr_cybersyn_pools[s1] then
            for s2, _ in pairs(storage.rr_cybersyn_pools[s1]) do
                clean_specific_pool(s2)
            end
        end
    end

    -- 3. [修复] 检查是否还在其他池子中
    local still_in_use = false
    if storage.rr_cybersyn_pools and storage.rr_cybersyn_pools[s1] then
        for _, pool in pairs(storage.rr_cybersyn_pools[s1]) do
            -- 注意：池子的 Key 是 Shell ID (uid)，这是内部逻辑，没问题
            if pool[uid] then
                still_in_use = true
                break
            end
        end
    end

    -- 只有当没有任何连接时，才彻底注销身份证
    if not still_in_use then
        -- [关键修正] 注销时必须使用 Station ID，而不是 Shell ID (uid)
        -- 我们尝试使用前面获取的 station 对象
        if station and station.valid then
            unregister_fake_elevator(station.unit_number)
            log_cs("[Pool] 退池(彻底销毁): " .. portaldata.name .. " ID:" .. station.unit_number)
        else
            -- 如果 station 实体已经无效了（比如被拆了），我们无法获取 ID，
            -- 但这种情况下 Cybersyn 可能已经通过 valid 检查自动清理了，或者我们在 purge 中处理了。
            log_cs("[Pool] 退池警告: 无法获取有效车站实体，跳过注销。")
        end
    else
        log_cs("[Pool] 退池(保留身份): " .. portaldata.name .. " 仍有其他连接")
    end
end

-- ============================================================================
-- 外部接口
-- ============================================================================

-- 更新连接状态
function CybersynSE.update_connection(portaldata, target_portal, connect, player, is_migration)
    if not portaldata or not target_portal then
        return
    end

    local station1 = get_station(portaldata)
    local station2 = get_station(target_portal)
    if not (station1 and station1.valid and station2 and station2.valid) then
        return
    end

    -- 1. [关键] 检查操作“之前”的真实连接状态
    -- 我们通过检查“海关池”来确定上一刻是否真的双向连通
    local was_connected = false
    if storage.rr_cybersyn_pools then
        local s1, s2 = portaldata.surface.index, target_portal.surface.index
        local u1, u2 = portaldata.unit_number, target_portal.unit_number
        local pool1 = storage.rr_cybersyn_pools[s1] and storage.rr_cybersyn_pools[s1][s2]
        local pool2 = storage.rr_cybersyn_pools[s2] and storage.rr_cybersyn_pools[s2][s1]
        if pool1 and pool1[u1] and pool2 and pool2[u2] then
            was_connected = true
        end
    end

    -- 2. 计算操作“之后”期望的连接状态
    local should_connect_now = portaldata.cybersyn_enabled and target_portal.cybersyn_enabled

    -- 3. 执行核心的入池/退池逻辑
    if should_connect_now then
        join_pool(portaldata, target_portal)
    else
        leave_pool(portaldata, target_portal)
    end

    -- 迁移模式下不发送任何通知
    if is_migration then
        return
    end

    -- 4. 准备消息参数 (保持不变)
    local name1 = portaldata.name or "Portal"
    local gps1 = "[gps=" ..
        portaldata.shell.position.x .. "," .. portaldata.shell.position.y .. "," .. portaldata.shell.surface.name .. "]"
    local name2 = target_portal.name or "Portal"
    local gps2 = "[gps=" ..
        target_portal.shell.position.x ..
        "," .. target_portal.shell.position.y .. "," .. target_portal.shell.surface.name .. "]"

    local msg = nil

    -- 5. 根据“现在”的状态和“过去”的状态，决定消息内容
    if should_connect_now then
        msg = { "messages.rift-rail-info-cybersyn-connected", name1, gps1, name2, gps2 }
    elseif was_connected then -- 如果现在不连接了，但过去是连着的
        msg = { "messages.rift-rail-info-cybersyn-disconnected", name1, gps1, name2, gps2 }
    elseif portaldata.cybersyn_enabled and not target_portal.cybersyn_enabled then
        msg = { "messages.rift-rail-info-cybersyn-waiting-partner", name1, gps1, name2, gps2 }
    elseif not portaldata.cybersyn_enabled and target_portal.cybersyn_enabled then
        msg = { "messages.rift-rail-info-cybersyn-waiting-partner", name2, gps2, name1, gps1 }
    end

    if not msg then
        return
    end

    -- 6. 发送消息
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

-- 传送门被销毁
function CybersynSE.on_portal_destroyed(portaldata)
    if portaldata and portaldata.cybersyn_enabled then
        CybersynSE.update_connection(portaldata, nil, false, nil, false)
    end
end

-- 传送门克隆 (起飞/降落)
function CybersynSE.on_portal_cloned(old_data, new_data, is_landing)
    -- 1. 旧的退池
    -- [多对多改造] 遍历旧数据的 target_ids
    if old_data.cybersyn_enabled and old_data.target_ids then
        for target_id, _ in pairs(old_data.target_ids) do
            local partner = State.get_portaldata_by_id(target_id)
            leave_pool(old_data, partner)
        end
    end

    -- 2. 新的入池 (非降落状态)
    -- [多对多改造] 遍历新数据的 target_ids
    if new_data.cybersyn_enabled and not is_landing and new_data.target_ids then
        for target_id, _ in pairs(new_data.target_ids) do
            local partner = State.get_portaldata_by_id(target_id)
            if partner then
                join_pool(new_data, partner)
            end
        end
    end
end

-- 传送开始 (旧版 Hack: 打标签)
function CybersynSE.on_teleport_start(train)
    if not (train and train.valid) then
        return
    end
    if remote.interfaces["cybersyn"] then
        remote.call("cybersyn", "write_global", true, "trains", train.id, "se_is_being_teleported")
    end
end

-- 传送结束 (旧版 Hack: 删标签)
function CybersynSE.on_teleport_end(new_train, old_id)
    if not (new_train and new_train.valid) then
        return
    end
    if remote.interfaces["cybersyn"] then
        remote.call("cybersyn", "write_global", nil, "trains", new_train.id, "se_is_being_teleported")
    end
end

return CybersynSE
