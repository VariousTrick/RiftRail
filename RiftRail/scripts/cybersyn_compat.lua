-- scripts/cybersyn_compat.lua
-- 【Rift Rail - Cybersyn 兼容模块】
-- 功能：将 Rift Rail 传送门伪装成 SE 太空电梯，接入 Cybersyn 物流网络
-- 核心逻辑复刻自 Railjump (zzzzz) 模组 v4 修正版

local CybersynSE = {}
local State = nil
local log_debug = function() end

-- [适配] 对应 gui.lua 中的开关名称
CybersynSE.BUTTON_NAME = "rift_rail_cybersyn_switch"

-- [新增] 动态检查函数：每次调用功能时才去确认接口是否存在
local function is_cybersyn_active()
    return remote.interfaces["cybersyn"] and remote.interfaces["cybersyn"]["write_global"]
end

-- [新增] 辅助函数：从 RiftRail 结构体中提取车站实体
local function get_station(struct)
    if struct.children then
        for _, child in pairs(struct.children) do
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
    log_debug("Cybersyn 兼容: 模块已加载 (等待运行时检测接口)。")
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
-- @param portal_struct table: 当前传送门数据
-- @param opposite_struct table: 配对传送门数据
-- @param connect boolean: true=连接, false=断开
-- @param player LuaPlayer: (可选) 操作玩家，用于发送提示
function CybersynSE.update_connection(portal_struct, opposite_struct, connect, player)
    -- [修改] 使用动态检查
    if not is_cybersyn_active() then
        if player then
            player.print({ "messages.rift-rail-error-cybersyn-not-found" })
        end
        return
    end

    -- 1. 获取真实的车站实体
    local station1 = get_station(portal_struct)
    local station2 = get_station(opposite_struct)

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
            if portal_struct.surface.index < opposite_struct.surface.index then
                ground_portal = portal_struct
                orbit_portal = opposite_struct
            else
                ground_portal = opposite_struct
                orbit_portal = portal_struct
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
            local result = remote.call("cybersyn", "write_global", connection_data, "connected_surfaces",
                surface_pair_key, entity_pair_key)
            -- [修改] 如果 result 为 false (说明 surface_pair_key 这张大表还不存在)，则初始化这张表
            if not result then
                remote.call("cybersyn", "write_global", { [entity_pair_key] = connection_data }, "connected_surfaces",
                    surface_pair_key)
            end

            log_debug("Cybersyn 兼容: [连接] " .. portal_struct.name .. " <--> " .. opposite_struct.name)
            success = true
        else
            -- 断开连接：清理数据
            -- [修改] 使用 4 个参数进行定点删除
            -- 只把我们这一对 (entity_pair_key) 设为 nil，绝对不触碰同地表的其他数据
            remote.call("cybersyn", "write_global", nil, "connected_surfaces", surface_pair_key, entity_pair_key)
            -- 清理 SE 表 (保持不变)
            remote.call("cybersyn", "write_global", nil, "se_elevators", station1.unit_number)
            remote.call("cybersyn", "write_global", nil, "se_elevators", station2.unit_number)
            log_debug("Cybersyn 兼容: [断开] 连接清理完毕。")
            success = true
        end
    end)

    if success then
        portal_struct.cybersyn_enabled = connect -- [注意] control.lua/state.lua 中使用的是 cybersyn_enabled
        opposite_struct.cybersyn_enabled = connect

        if player then
            -- 检查设置：只有玩家开启了通知才显示
            if settings.get_player_settings(player)["rift-rail-show-cybersyn-notifications"].value then
                if connect then
                    player.print({ "messages.rift-rail-info-cybersyn-connected", portal_struct.name })
                else
                    player.print({ "messages.rift-rail-info-cybersyn-disconnected", portal_struct.name })
                end
            end
        end
    end
end

--- 处理传送门销毁
function CybersynSE.on_portal_destroyed(portal_struct)
    -- [修改] 使用动态检查
    if not is_cybersyn_active() then
        return
    end

    -- 如果已连接，则尝试断开
    if portal_struct and portal_struct.cybersyn_enabled then
        local opposite_struct = State.get_struct_by_id(portal_struct.paired_to_id)
        local station = get_station(portal_struct)

        -- 即使对侧不存在，也需要清理自己的数据
        if station and station.valid then
            -- 尝试完整断开
            if opposite_struct then
                CybersynSE.update_connection(portal_struct, opposite_struct, false, nil)
            else
                -- 紧急清理模式 (只清理自己)
                pcall(remote.call, "cybersyn", "write_global", nil, "se_elevators", station.unit_number)
            end
        end
    end
end

--- 处理克隆/移动 (支持 SE 飞船起飞降落)
function CybersynSE.on_portal_cloned(old_struct, new_struct, is_landing)
    -- [修改] 使用动态检查
    if not is_cybersyn_active() then
        return
    end

    -- 只有旧实体开启了连接才处理
    if not (old_struct and new_struct and old_struct.cybersyn_enabled) then
        return
    end

    -- 获取配对目标
    local partner = State.get_struct_by_id(new_struct.paired_to_id)
    if not partner then
        return
    end

    -- 1. 无条件注销旧连接
    -- CybersynSE.update_connection(old_struct, partner, false, nil)

    -- 2. 判断逻辑
    local is_takeoff = false

    if is_landing then
        -- 降落：静默处理，保持 enabled=true，但不发送通知，隐身模式
        log_debug("Cybersyn 兼容: 飞船降落，维持连接状态 (静默)。")
        new_struct.cybersyn_enabled = true
        -- 这里什么都不做，不向 Cybersyn 注册，仅仅保留开关状态
    else
        -- 起飞或搬家：注册新 ID
        CybersynSE.update_connection(new_struct, partner, true, nil)
        log_debug("Cybersyn 兼容: 实体迁移，重新注册连接。")

        if string.find(new_struct.surface.name, "spaceship") then
            is_takeoff = true
        end
    end

    -- 3. 通知玩家 (如果设置允许)
    if is_landing or is_takeoff then
        for _, player in pairs(game.players) do
            if settings.get_player_settings(player)["rift-rail-show-cybersyn-notifications"].value then
                if is_landing then
                    player.print({ "messages.rift-rail-cybersyn-landing", new_struct.name })
                elseif is_takeoff then
                    player.print({ "messages.rift-rail-cybersyn-takeoff", new_struct.name })
                end
            end
        end
    end
end

return CybersynSE
