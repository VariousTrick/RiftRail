-- scripts/cybersyn_compat.lua
-- 【Rift Rail - Cybersyn 兼容模块】
-- 功能：将 Rift Rail 传送门伪装成 SE 太空电梯，接入 Cybersyn 物流网络
-- 核心逻辑复刻自 Railjump (zzzzz) 模组 v4 修正版

local CybersynSE = {}
local State = nil

local log_debug = function() end

local function log_cs(message)
    if not RiftRail.DEBUG_MODE_ENABLED then
        return
    end
    if log_debug then
        log_debug(message)
    end
end

-- [适配] 对应 gui.lua 中的开关名称
CybersynSE.BUTTON_NAME = "rift_rail_cybersyn_switch"

-- [新增] 动态检查函数：每次调用功能时才去确认接口是否存在
local function is_cybersyn_active()
    return remote.interfaces["cybersyn"] and remote.interfaces["cybersyn"]["write_global"]
end

-- [新增] 辅助函数：从 RiftRail 结构体中提取车站实体
local function get_station(portaldata)
    if portaldata.children then
        -- 【修改】适配新的 children 结构 {entity=..., relative_pos=...}
        for _, child_data in pairs(portaldata.children) do
            local child = child_data.entity -- <<-- [核心修改] 先从表中取出实体
            if child and child.valid and child.name == "rift-rail-station" then
                return child
            end
        end
    end
    return nil
end

function CybersynSE.init(dependencies)
    State = dependencies.State
    if dependencies.log_debug then
        log_debug = dependencies.log_debug
    end

    -- [修改] 这里不再进行检测！只做依赖注入。
    -- 因为此时 Cybersyn 可能还没注册接口。
    log_cs("[RiftRail:CybersynCompat] 模块已加载 (等待运行时检测接口)。")
end

-- 用于生成 Cybersyn 数据库键值的排序函数
local function sorted_pair_key(a, b)
    if a < b then
        return a .. "|" .. b
    else
        return b .. "|" .. a
    end
end

--- 更新连接状态 (核心逻辑)
-- @param select_portal table: 当前传送门数据
-- @param target_portal table: 配对传送门数据
-- @param connect boolean: true=连接, false=断开
-- @param player LuaPlayer: (可选) 操作玩家，用于发送提示
function CybersynSE.update_connection(select_portal, target_portal, connect, player)
    -- [修改] 使用动态检查
    if not is_cybersyn_active() then
        if player then
            player.print({ "messages.rift-rail-error-cybersyn-not-found" })
        end
        return
    end

    -- 1. 获取真实的车站实体
    local station1 = get_station(select_portal)
    local station2 = get_station(target_portal)

    if not (station1 and station1.valid and station2 and station2.valid) then
        if player then
            player.print({ "messages.rift-rail-error-cybersyn-no-station" })
        end
        return
    end

    -- 2. 准备键值
    local surface_pair_key = sorted_pair_key(station1.surface.index, station2.surface.index)
    local entity_pair_key = sorted_pair_key(station1.unit_number, station2.unit_number)

    local success = false

    -- 3. 使用 pcall 保护远程调用
    pcall(function()
        if connect then
            -- =================================================================
            -- 【完美伪装策略】
            -- Cybersyn 要求 entity1.unit_number < entity2.unit_number
            -- 并且 entity1 的名字必须是 "se-space-elevator-train-stop"
            -- =================================================================

            local min_station, max_station
            if station1.unit_number < station2.unit_number then
                min_station = station1
                max_station = station2
            else
                min_station = station2
                max_station = station1
            end

            -- 构建伪造的车站对象 (Duck Typing)
            -- 我们用 min_station 的真实数据，但披上 SE 的名字
            local fake_station_for_check = {
                valid = true,
                name = "se-space-elevator-train-stop", -- [关键] 骗过 Cybersyn 的名字检查
                unit_number = min_station.unit_number, -- [关键] ID 必须对应真实 ID
                surface = { index = min_station.surface.index, name = min_station.surface.name, valid = true },
                position = min_station.position,
                operable = true,
                backer_name = min_station.backer_name,
            }

            -- 准备写入 se_elevators 表的数据
            local ground_portal, orbit_portal
            -- 简单按地表 ID 排序，小的当“地面”，大的当“轨道”
            if select_portal.surface.index < target_portal.surface.index then
                ground_portal = select_portal
                orbit_portal = target_portal
            else
                ground_portal = target_portal
                orbit_portal = select_portal
            end

            local s_ground = get_station(ground_portal)
            local s_orbit = get_station(orbit_portal)

            local ground_end_data = {
                elevator = ground_portal.shell, -- 使用 RiftRail 的 shell 作为主体
                stop = s_ground,
                surface_id = ground_portal.surface.index,
                stop_id = s_ground.unit_number,
                elevator_id = ground_portal.shell.unit_number,
            }
            local orbit_end_data = {
                elevator = orbit_portal.shell,
                stop = s_orbit,
                surface_id = orbit_portal.surface.index,
                stop_id = s_orbit.unit_number,
                elevator_id = orbit_portal.shell.unit_number,
            }

            local fake_elevator_data = {
                ground = ground_end_data,
                orbit = orbit_end_data,
                cs_enabled = true,
                network_masks = nil,
                [ground_portal.surface.index] = ground_end_data,
                [orbit_portal.surface.index] = orbit_end_data,
            }

            -- A. 写入 SE 电梯数据库
            remote.call("cybersyn", "write_global", fake_elevator_data, "se_elevators", s_ground.unit_number)
            remote.call("cybersyn", "write_global", fake_elevator_data, "se_elevators", s_orbit.unit_number)

            -- B. 写入地表连接数据库
            -- entity1 必须是伪造的那个，entity2 是真实的
            local connection_data = {
                entity1 = fake_station_for_check,
                entity2 = max_station,
            }
            -- [修改] 尝试使用 4 个参数进行定点插入
            -- 尝试在 connected_surfaces -> surface_pair_key 下直接写入 entity_pair_key
            -- 这样不会覆盖掉同地表下的 SE 电梯或其他连接
            local result = remote.call("cybersyn", "write_global", connection_data, "connected_surfaces", surface_pair_key, entity_pair_key)
            -- [修改] 如果 result 为 false (说明 surface_pair_key 这张大表还不存在)，则初始化这张表
            if not result then
                remote.call("cybersyn", "write_global", { [entity_pair_key] = connection_data }, "connected_surfaces", surface_pair_key)
            end

            log_cs("[RiftRail:CybersynCompat] [连接] " .. select_portal.name .. " <--> " .. target_portal.name)
            success = true
        else
            -- 断开连接：清理数据
            -- [修改] 使用 4 个参数进行定点删除
            -- 只把我们这一对 (entity_pair_key) 设为 nil，绝对不触碰同地表的其他数据
            remote.call("cybersyn", "write_global", nil, "connected_surfaces", surface_pair_key, entity_pair_key)
            -- 清理 SE 表 (保持不变)
            remote.call("cybersyn", "write_global", nil, "se_elevators", station1.unit_number)
            remote.call("cybersyn", "write_global", nil, "se_elevators", station2.unit_number)
            log_cs("[RiftRail:CybersynCompat] [断开] 连接清理完毕。")
            success = true
        end
    end)

    if success then
        select_portal.cybersyn_enabled = connect -- [注意] control.lua/state.lua 中使用的是 cybersyn_enabled
        target_portal.cybersyn_enabled = connect

        -- [修改] 改为全局提示，所有玩家都能看到
        -- 玩家通知（带双向 GPS 标签，受统一设置控制）
        local name1 = select_portal.name or "RiftRail"
        local pos1 = select_portal.shell.position
        local surface1 = select_portal.shell.surface.name
        local gps1 = "[gps=" .. pos1.x .. "," .. pos1.y .. "," .. surface1 .. "]"

        local name2 = target_portal.name or "RiftRail"
        local pos2 = target_portal.shell.position
        local surface2 = target_portal.shell.surface.name
        local gps2 = "[gps=" .. pos2.x .. "," .. pos2.y .. "," .. surface2 .. "]"

        for _, player in pairs(game.connected_players) do
            local setting = settings.get_player_settings(player)["rift-rail-show-logistics-notifications"]
            if setting and setting.value then
                if connect then
                    player.print({ "messages.rift-rail-info-cybersyn-connected", name1, gps1, name2, gps2 })
                else
                    player.print({ "messages.rift-rail-info-cybersyn-disconnected", name1, gps1, name2, gps2 })
                end
            end
        end
    end
end

--- 处理传送门销毁
function CybersynSE.on_portal_destroyed(select_portal)
    -- [修改] 使用动态检查
    if not is_cybersyn_active() then
        return
    end

    -- 如果已连接，则尝试断开
    if select_portal and select_portal.cybersyn_enabled then
        local target_portal = State.get_portaldata_by_id(select_portal.paired_to_id)
        local station = get_station(select_portal)

        -- 即使对侧不存在，也需要清理自己的数据
        if station and station.valid then
            -- 尝试完整断开
            if target_portal then
                CybersynSE.update_connection(select_portal, target_portal, false, nil)
            else
                -- 紧急清理模式 (只清理自己)
                pcall(remote.call, "cybersyn", "write_global", nil, "se_elevators", station.unit_number)
            end
        end
    end
end

--- 处理克隆/移动 (支持 SE 飞船起飞降落)
function CybersynSE.on_portal_cloned(old_portaldata, new_portaldata, is_landing)
    -- [修改] 使用动态检查
    if not is_cybersyn_active() then
        return
    end

    -- 只有旧实体开启了连接才处理
    if not (old_portaldata and new_portaldata and old_portaldata.cybersyn_enabled) then
        return
    end

    -- 获取配对目标
    local partner = State.get_portaldata_by_id(new_portaldata.paired_to_id)
    if not partner then
        return
    end

    -- 1. 无条件注销旧连接
    CybersynSE.update_connection(old_portaldata, partner, false, nil)

    -- 2. 判断逻辑
    local is_takeoff = false

    if is_landing then
        -- 降落：静默处理，保持 enabled=true，但不发送通知，隐身模式
        log_cs("[RiftRail:CybersynCompat] 飞船降落，维持连接状态 (静默)。")
        new_portaldata.cybersyn_enabled = true
        -- 这里什么都不做，不向 Cybersyn 注册，仅仅保留开关状态
    else
        -- 起飞或搬家：注册新 ID
        CybersynSE.update_connection(new_portaldata, partner, true, nil)
        log_cs("[RiftRail:CybersynCompat] 实体迁移，重新注册连接。")

        if string.find(new_portaldata.surface.name, "spaceship") then
            is_takeoff = true
        end
    end

    if is_landing or is_takeoff then
        for _, player in pairs(game.players) do
            if settings.get_player_settings(player)["rift-rail-show-logistics-notifications"].value then
                if is_landing then
                    player.print({ "messages.rift-rail-cybersyn-landing", new_portaldata.name })
                elseif is_takeoff then
                    player.print({ "messages.rift-rail-cybersyn-takeoff", new_portaldata.name })
                end
            end
        end
    end
end

-- ============================================================================
-- [新增] 传送生命周期钩子 (策略模式)
-- ============================================================================

-- 1. 定义具体的逻辑实现

-- 逻辑 A: 完整模式 (无 SE) - 贴标签 + 存快照
local function logic_on_start_full(train)
    if not (train and train.valid) then
        return nil
    end
    -- 贴标签: 防止被 Cybersyn 误判丢失
    if remote.interfaces["cybersyn"] then
        remote.call("cybersyn", "write_global", true, "trains", train.id, "se_is_being_teleported")
    end
    -- 存快照: 手动读取数据
    if remote.interfaces["cybersyn"] then
        local success, snapshot = pcall(remote.call, "cybersyn", "read_global", "trains", train.id)
        if success then
            if RiftRail.DEBUG_MODE_ENABLED then
                log_cs("Cybersyn兼容: 已保存列车快照 ID=" .. train.id)
            end
            return snapshot
        end
    end
    return nil
end

-- 逻辑 B: 轻量模式 (有 SE) - 只贴标签
local function logic_on_start_tag_only(train)
    if not (train and train.valid) then
        return nil
    end
    -- 即使有 SE，也要贴标签作为双重保险
    if remote.interfaces["cybersyn"] then
        remote.call("cybersyn", "write_global", true, "trains", train.id, "se_is_being_teleported")
    end
    -- 不返回快照，后续交给 SE 事件处理
    return nil
end

-- 逻辑 C: 恢复模式 (无 SE) - 注入快照 + 撕标签
local function logic_on_end_restore(new_train, old_id, snapshot)
    if not (new_train and new_train.valid and snapshot) then
        return
    end

    if remote.interfaces["cybersyn"] then
        -- 1. 注入数据到新 ID
        -- 注意：快照中的 entity 还是旧的，Cybersyn 内部通常只用 ID 索引，或者我们需要更新 entity 引用
        -- 但根据旧代码，直接写入 snapshot 即可，Cybersyn 会处理
        snapshot.entity = new_train -- 修正实体引用
        remote.call("cybersyn", "write_global", snapshot, "trains", new_train.id)

        -- 2. 清除旧 ID 数据 (手动 GC)
        if old_id then
            remote.call("cybersyn", "write_global", nil, "trains", old_id)
        end

        -- 3. 撕掉新车身上的标签 (恢复监管)
        remote.call("cybersyn", "write_global", nil, "trains", new_train.id, "se_is_being_teleported")

        -- [新增] 4. 时刻表 Rail 补全 (修复异地表 Rail 指向问题)
        -- 逻辑来源：原 handle_cybersyn_migration
        local schedule = new_train.schedule
        if schedule and schedule.records then
            local records = schedule.records
            local current_index = schedule.current
            local current_record = records[current_index]

            -- 只有当下一站是真实操作站 (P/R/Depot) 且没有 Rail 时才尝试补全
            -- (如果有 Rail 说明已经是精准导航了，不需要我们干预)
            if current_record and current_record.station and not current_record.rail then
                local target_id = nil

                -- Cybersyn 状态映射: 1=去供货站(P), 3=去请求站(R), 5/6=去车库(Depot)
                if snapshot.status == 1 then
                    target_id = snapshot.p_station_id
                elseif snapshot.status == 3 then
                    target_id = snapshot.r_station_id
                elseif snapshot.status == 5 or snapshot.status == 6 then
                    target_id = snapshot.depot_id
                end

                if target_id then
                    -- 确定查询表名 (depots 或 stations)
                    local table_name = (snapshot.status == 5 or snapshot.status == 6) and "depots" or "stations"

                    -- 从 Cybersyn 数据库读取目标站点的真实物理信息
                    local ok, st_data = pcall(remote.call, "cybersyn", "read_global", table_name, target_id)

                    -- 如果目标站在当前地表，插入 Rail 导航点
                    if ok and st_data and st_data.entity_stop and st_data.entity_stop.valid and st_data.entity_stop.surface == new_train.front_stock.surface then
                        -- 在当前目标前插入一个临时导航点，强制列车走这个 Rail
                        table.insert(records, current_index, {
                            rail = st_data.entity_stop.connected_rail,
                            rail_direction = st_data.entity_stop.connected_rail_direction,
                            temporary = true,
                            wait_conditions = { { type = "time", ticks = 1 } }, -- 1 tick 即刻通过
                        })
                        schedule.records = records
                        new_train.schedule = schedule

                        if RiftRail.DEBUG_MODE_ENABLED then
                            log_cs("Cybersyn兼容: 已修正时刻表导航 -> " .. st_data.entity_stop.backer_name)
                        end
                    end
                end
            end
        end

        if RiftRail.DEBUG_MODE_ENABLED then
            log_cs("Cybersyn兼容: 数据迁移完成 -> 新ID=" .. new_train.id)
        end
    end
end

-- 空函数 (占位符)
local function noop() end

-- 2. 策略分发 (在加载时决定使用哪个函数)

-- 默认初始化为空
CybersynSE.on_teleport_start = noop
CybersynSE.on_teleport_end = noop

if script.active_mods["cybersyn"] then
    if script.active_mods["space-exploration"] then
        -- 情况: Cybersyn + SE
        -- 开始: 只贴标签
        -- 结束: 啥都不做 (SE事件接管)
        CybersynSE.on_teleport_start = logic_on_start_tag_only
        CybersynSE.on_teleport_end = noop
        log_cs("Cybersyn兼容模式: SE 托管")
    else
        -- 情况: Cybersyn (无 SE)
        -- 开始: 完整快照
        -- 结束: 手动恢复
        CybersynSE.on_teleport_start = logic_on_start_full
        CybersynSE.on_teleport_end = logic_on_end_restore
        log_cs("Cybersyn兼容模式: 手动迁移")
    end
end

return CybersynSE
