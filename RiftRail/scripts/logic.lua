-- scripts/logic.lua v0.0.3
-- 功能：业务逻辑核心 (集成物理碰撞器管理)

local Logic = {}
local State = nil
local GUI = nil
local LTN = nil

local log_debug = function() end

-- ============================================================================
-- 配置与辅助函数
-- ============================================================================
-- WARNING: This value MUST be kept in sync with the one in scripts/gui.lua
-- 警告：此值必须与 scripts/gui.lua 中的值保持同步
local MAX_CONNECTIONS = 5 -- 在这里设置最大连接数上限

-- 计算一个表中的键值对数量 (比 # 更安全，因其能处理非连续索引)
local function count_connections(id_table)
    if not id_table then
        return 0
    end
    local count = 0
    for _ in pairs(id_table) do
        count = count + 1
    end
    return count
end

function Logic.init(deps)
    State = deps.State
    GUI = deps.GUI
    log_debug = deps.log_debug
    LTN = deps.LTN
end

-- ============================================================================
-- 辅助函数：广播刷新
-- ============================================================================
local function refresh_all_guis()
    for _, player in pairs(game.connected_players) do
        local opened = player.opened

        -- 情况 1: 如果 opened 是实体 (比如其他模组直接 opened 实体，或者是兼容旧版)
        if opened and opened.valid and opened.object_name == "LuaEntity" and State.get_portaldata(opened) then
            GUI.build_or_update(player, opened)

            -- 情况 2: 如果 opened 是我们的 GUI Frame
        elseif opened and opened.valid and opened.object_name == "LuaGuiElement" and opened.name == "rift_rail_main_frame" then
            -- 从 tags 中获取 unit_number
            local unit_number = opened.tags.unit_number
            if unit_number then
                -- 查找对应的实体数据
                local portaldata = State.get_portaldata_by_unit_number(unit_number)
                if portaldata and portaldata.shell and portaldata.shell.valid then
                    -- 传入实体进行刷新
                    GUI.build_or_update(player, portaldata.shell)
                end
            end
        end
    end
end

-- ============================================================================
-- 辅助函数：检查连接数并在归零时自动关闭物流开关
-- ============================================================================
local function check_and_reset_logistics(portaldata)
    if not portaldata then
        return
    end

    local connection_count = 0
    if portaldata.mode == "entry" and portaldata.target_ids then
        for _ in pairs(portaldata.target_ids) do
            connection_count = connection_count + 1
        end
    elseif portaldata.mode == "exit" and portaldata.source_ids then
        for _ in pairs(portaldata.source_ids) do
            connection_count = connection_count + 1
        end
    end

    -- 如果连接数已清零，则强制关闭开关
    if connection_count == 0 then
        portaldata.cybersyn_enabled = false
        portaldata.ltn_enabled = false
        if RiftRail.DEBUG_MODE_ENABLED then
            log_debug("[Logic] Portal " .. portaldata.id .. " 连接数为零，已关闭 Cybersyn 和 LTN 开关")
        end
    end
end
-- ============================================================================
-- 辅助函数：构建包含图标的富文本显示名称
-- ============================================================================
local function build_display_name(portaldata)
    local richtext = ""
    if portaldata and portaldata.icon and portaldata.icon.type and portaldata.icon.name then
        richtext = "[" .. portaldata.icon.type .. "=" .. portaldata.icon.name .. "] "
    end
    if portaldata then
        richtext = richtext .. portaldata.name
    end
    return richtext
end

-- ============================================================================
-- 辅助函数：根据当前模式强制刷新车站限制 (防止引擎自动同步或未初始化)
-- ============================================================================
function Logic.refresh_station_limit(portaldata)
    if not (portaldata and portaldata.children) then
        return
    end

    for _, child_data in pairs(portaldata.children) do
        local entity = child_data.entity
        if entity and entity.valid and entity.name == "rift-rail-station" then
            if portaldata.mode == "exit" then
                entity.trains_limit = 0
            else
                entity.trains_limit = nil -- 恢复默认
            end
            break
        end
    end
end

-- ============================================================================
-- 物理状态管理 (精准定点清除版)
-- ============================================================================
-- 物理状态管理 (带 children 列表同步)
local function update_collider_state(portaldata)
    if not (portaldata and portaldata.shell and portaldata.shell.valid) then
        return
    end

    -- 1. 清理旧的碰撞器 (同时从字典销户)
    if portaldata.children then
        -- 使用倒序遍历，安全地在循环中移除元素
        for i = #portaldata.children, 1, -1 do
            local child_data = portaldata.children[i]
            if child_data and child_data.entity and child_data.entity.valid and child_data.entity.name == "rift-rail-collider" then

                -- 防止字典泄漏
                if child_data.entity.unit_number and storage.collider_to_portal then
                    storage.collider_to_portal[child_data.entity.unit_number] = nil
                end

                -- 从地图上销毁
                child_data.entity.destroy()
                -- 从 children 列表中移除
                table.remove(portaldata.children, i)
            end
        end
    end

    -- 2. 如果是 [入口] 或 [中立] 模式，则创建新的碰撞器并登记
    if portaldata.mode == "entry" or portaldata.mode == "neutral" then
        local surface = portaldata.shell.surface
        local center = portaldata.shell.position
        local direction = portaldata.shell.direction

        -- 计算碰撞器的精确相对坐标
        local relative_pos = { x = 0, y = -2 } -- 基准 (North)
        if direction == 4 then -- East
            relative_pos = { x = 2, y = 0 }
        elseif direction == 8 then -- South
            relative_pos = { x = 0, y = 2 }
        elseif direction == 12 then -- West
            relative_pos = { x = -2, y = 0 }
        end

        -- 计算绝对世界坐标
        local target_pos = { x = center.x + relative_pos.x, y = center.y + relative_pos.y }

        -- 创建新实体
        local new_collider = surface.create_entity({
            name = "rift-rail-collider",
            position = target_pos,
            force = portaldata.shell.force,
        })

        -- 将新创建的碰撞器登记到 children 列表中并注册 ID
        if new_collider then
            if new_collider.unit_number then
                storage.collider_to_portal = storage.collider_to_portal or {}
                storage.collider_to_portal[new_collider.unit_number] = portaldata.unit_number
            end

            if portaldata.children then
                table.insert(portaldata.children, {
                    entity = new_collider,
                    relative_pos = relative_pos,
                })
            end
        end
    end
end


-- ============================================================================
-- 1. 更新名称
-- ============================================================================
function Logic.update_name(player_index, portal_id, new_string)
    local player = game.get_player(player_index)
    local my_data = State.get_portaldata_by_id(portal_id)
    if not (player and my_data) then
        return
    end

    -- 1. 解析输入 (显式捕获间隔符 %s* 和剩余文本)
    -- 原正则: "%[([%w%-]+)=([%w%-]+)%]%s*(.*)"
    local prefix, icon_type, icon_name, separator, plain_name = string.match(new_string, "^(%s*)%[([%w%-]+)=([%w%-]+)%](%s*)(.*)")

    -- 2. 智能去重与数据更新
    if icon_type and icon_name then
        if icon_name == "rift-rail-placer" then
            -- 玩家手动输入了主图标 -> 去重
            my_data.icon = nil
            my_data.prefix = prefix
            -- [关键] 名字 = 原始间隔符 + 原始名字 (忠实还原)
            my_data.name = (separator or "") .. (plain_name or "")
        else
            -- 玩家输入了自定义图标 -> 记录
            my_data.icon = { type = icon_type, name = icon_name }
            my_data.prefix = prefix
            -- [关键] 名字同样包含原始间隔符
            my_data.name = (separator or "") .. (plain_name or "")
        end
    else
        -- 没有检测到图标，整个字符串就是名字
        local p_space, p_name = string.match(new_string, "^(%s*)(.*)")
        my_data.prefix = p_space
        my_data.name = new_string
        my_data.icon = nil
    end

    -- 3. 更新实体显示名称
    if my_data.children then
        for _, child_data in pairs(my_data.children) do
            local child = child_data.entity
            if child and child.valid and child.name == "rift-rail-station" then
                local master_icon = "[item=rift-rail-placer]"
                local user_icon_str = ""
                if my_data.icon then
                    user_icon_str = "[" .. my_data.icon.type .. "=" .. my_data.icon.name .. "]"
                end
                -- 拼接：主图标 + 自定义图标 + 名字(名字里现在包含了用户输入的空格)
                child.backer_name = master_icon .. (my_data.prefix or "") .. user_icon_str .. my_data.name
                break
            end
        end
    end

    player.print({ "messages.rift-rail-mode-changed", my_data.name })

    -- 改名后强制刷新限制，防止引擎因为名字变动而错误同步限制
    Logic.refresh_station_limit(my_data)
    refresh_all_guis()
end

-- ============================================================================
-- 2. 模式切换
-- ============================================================================
function Logic.set_mode(player_index, portal_id, mode, skip_sync)
    local player = nil
    if player_index then
        player = game.get_player(player_index)
    end

    local my_data = State.get_portaldata_by_id(portal_id)
    if not my_data then
        return
    end

    local old_mode = my_data.mode
    if old_mode == mode then
        return
    end

    -- [关键步骤] 切换模式前，必须清理旧的连接关系
    -- 防止“带病上岗”导致数据拓扑错误
    -- 检查 target_ids 表，而不再是 paired_to_id
    if old_mode == "entry" and my_data.target_ids and next(my_data.target_ids) then
        -- [多对多改造] 遍历所有目标，并逐个通知它们断开连接
        for target_id, _ in pairs(my_data.target_ids) do
            local target = State.get_portaldata_by_id(target_id)
            if target and target.source_ids then
                target.source_ids[my_data.id] = nil
            end
        end

        -- 检查刚刚被断开的目标
        check_and_reset_logistics(target)
        -- 清空整个目标列表
        my_data.target_ids = {}

        if RiftRail.DEBUG_MODE_ENABLED then
            log_debug("[Logic] 模式切换清理: Entry " .. my_data.id .. " 断开连接")
        end
    elseif old_mode == "exit" and my_data.source_ids then
        -- 如果之前是出口，通知所有来源断开连接
        for src_id, _ in pairs(my_data.source_ids) do
            local src_data = State.get_portaldata_by_id(src_id)
            if src_data then
                src_data.paired_to_id = nil
                -- 顺便把来源重置为中立，或者保持原样?
                -- 建议保持原样或重置为中立。为了安全，重置为中立比较好。
                -- 这里直接修改数据，不调用 set_mode 以免递归
                src_data.mode = "neutral"
                -- 注意：这里简单处理了，实际上可能需要触发源端的GUI刷新
            end
            -- 检查刚刚被断开的来源
            check_and_reset_logistics(src_data)
        end
        my_data.source_ids = {}
        -- 清理互斥锁
        my_data.locking_entry_id = nil

        if RiftRail.DEBUG_MODE_ENABLED then
            log_debug("[Logic] 模式切换清理: Exit " .. my_data.id .. " 清空所有来源")
        end
    end

    -- 应用新模式
    my_data.mode = mode

    -- LTN 回调
    if LTN and LTN.on_portal_mode_changed then
        LTN.on_portal_mode_changed(my_data, old_mode)
    end

    -- 更新物理碰撞器
    update_collider_state(my_data)

    -- 刷新车站限制
    Logic.refresh_station_limit(my_data)

    -- 消息提示
    if player then
        local msg_key = "gui.rift-rail-mode-" .. mode
        player.print({ msg_key })
    end

    -- [重要修改] 移除了旧版的 "skip_sync" 和自动设置 partner 模式的逻辑
    -- 在多对一结构中，不再允许自动修改配对对象的模式

    refresh_all_guis()
end

-- ============================================================================
-- 3. 配对逻辑 (重构：单向连接 Entry -> Exit)
-- ============================================================================
function Logic.pair_portals(player_index, source_id, target_id)
    local player = game.get_player(player_index)
    local source = State.get_portaldata_by_id(source_id)
    local target = State.get_portaldata_by_id(target_id)

    if not (source and target) then
        return
    end

    -- 严格身份判定 (Strict Role Assignment)
    local final_source = source
    local final_target = target

    -- 情况 1: 双方都是中立 (默认发起者为入口，目标为出口)
    if source.mode == "neutral" and target.mode == "neutral" then
        final_source = source
        final_target = target

        -- 情况 2: 只有一方是中立 (中立者必须服从已定型的一方)
    elseif source.mode == "neutral" or target.mode == "neutral" then
        local fixed = (source.mode ~= "neutral") and source or target
        local neutral = (source.mode == "neutral") and source or target

        if fixed.mode == "entry" then
            -- 大哥是入口，那他必须是 Source，中立者是 Target (变出口)
            final_source = fixed
            final_target = neutral
        elseif fixed.mode == "exit" then
            -- 大哥是出口，那他必须是 Target，中立者是 Source (变入口)
            final_source = neutral
            final_target = fixed
        end

        -- 情况 3: 双方都有身份 (必须是一入一出)
    else
        if source.mode == "entry" and target.mode == "exit" then
            final_source = source
            final_target = target
        elseif source.mode == "exit" and target.mode == "entry" then
            -- 纠正方向：入口 -> 出口
            final_source = target
            final_target = source
        else
            -- 剩下的情况就是：入口配入口，或者出口配出口 -> 报错
            player.print({ "messages.rift-rail-error-same-mode" })
            return
        end
    end

    -- 应用判定结果
    source = final_source
    target = final_target
    source_id = source.id
    target_id = target.id

    -- 配对上限检查
    -- 此时 source 一定是入口，target 一定是出口，身份已确立，检查是准确的
    -- 检查是否重复配对
    if source.target_ids and source.target_ids[target_id] then
        player.print({ "messages.rift-rail-error-already-paired" })
        return
    end

    -- 检查入口(Source)是否满了
    if count_connections(source.target_ids) >= MAX_CONNECTIONS then
        local name = build_display_name(source)
        player.print({ "messages.rift-rail-error-limit-reached", name, MAX_CONNECTIONS })
        return
    end

    -- 检查出口(Target)是否满了
    if count_connections(target.source_ids) >= MAX_CONNECTIONS then
        local name = build_display_name(target)
        player.print({ "messages.rift-rail-error-limit-reached", name, MAX_CONNECTIONS })
        return
    end

    -- 1. 验证源：经过交换后，source 必须是 入口 或 中立
    if source.mode == "exit" then
        -- 如果到了这里 source 还是 exit，说明是 Exit -> Exit，报错
        player.print({ "messages.rift-rail-error-source-is-exit" })
        return
    end

    -- 2. 验证目标：经过交换后，target 必须是 出口 或 中立
    if target.mode == "entry" then
        -- 如果到了这里 target 是 entry，说明是 Entry -> Entry，报错
        player.print({ "messages.rift-rail-error-target-is-entry" })
        return
    end

    -- 3. 执行连接 (不对称结构)
    -- 源指向目标
    -- 初始化 target_ids 表（如果不存在）
    if not source.target_ids then
        source.target_ids = {}
    end
    -- 将目标 ID 加入列表 (缓存实体ID)
    source.target_ids[target_id] = {
        custom_id = target_id,
        unit_number = target.shell.unit_number,
    }

    -- 目标记录源
    if not target.source_ids then
        target.source_ids = {}
    end
    target.source_ids[source_id] = {
        custom_id = source_id,
        unit_number = source.shell.unit_number,
    }
    -- 注意：目标 (Exit) 的 paired_to_id 保持为 nil，因为它不再指向单一对象

    -- 4. 智能调整模式
    -- 如果源是中立，自动切为入口
    if source.mode == "neutral" then
        Logic.set_mode(player_index, source_id, "entry", true)
    end

    -- 如果目标是中立，自动切为出口
    if target.mode == "neutral" then
        Logic.set_mode(player_index, target_id, "exit", true)
    end

    -- 5. 反馈消息
    local source_display = build_display_name(source)
    local target_display = build_display_name(target)
    player.print({ "messages.rift-rail-pair-success", source_display, target_display })

    if RiftRail.DEBUG_MODE_ENABLED then
        log_debug("[Logic] 建立连接: Entry " .. source.id .. " -> Exit " .. target.id)
    end

    refresh_all_guis()
end

-- ============================================================================
-- 4. 解绑逻辑
-- ============================================================================
-- 这个函数现在主要由 GUI 的“踢出”按钮调用，并且只处理“入口”
function Logic.unpair_portals(player_index, portal_id)
    local player = nil
    if player_index then
        player = game.get_player(player_index)
    end
    local portal = State.get_portaldata_by_id(portal_id)

    if not portal then
        return
    end

    -- 将所有逻辑代理到 unpair_portals_specific
    if portal.mode == "entry" and portal.target_ids then
        -- 遍历所有目标并逐个断开
        for target_id, _ in pairs(portal.target_ids) do
            Logic.unpair_portals_specific(player_index, portal.id, target_id)
        end
    elseif portal.mode == "exit" and portal.source_ids then
        -- 遍历所有来源并逐个断开
        for source_id, _ in pairs(portal.source_ids) do
            Logic.unpair_portals_specific(player_index, source_id, portal.id)
        end
    end

    -- refresh_all_guis() 已经包含在 _specific 函数中，这里无需重复调用
end

-- ============================================================================
-- 5. 远程观察
-- ============================================================================
function Logic.open_remote_view_by_target(player_index, target_id)
    local player = game.get_player(player_index)
    if not (player and target_id) then
        return
    end

    -- 直接使用传入的目标ID查找目标建筑
    local target = State.get_portaldata_by_id(target_id)
    if target and target.shell and target.shell.valid then
        player.opened = nil
        player.set_controller({
            type = defines.controllers.remote,
            position = target.shell.position,
            surface = target.shell.surface,
            zoom = player.zoom,
        })
    end
end

-- ============================================================================
-- 7. LTN 开关控制
-- ==========================================================================
function Logic.set_ltn_enabled(player_index, portal_id, enabled)
    local player = game.get_player(player_index)
    local my_data = State.get_portaldata_by_id(portal_id)
    if not (player and my_data) then
        return
    end

    -- 1. 只修改自己的开关状态
    my_data.ltn_enabled = enabled

    -- 2. 收集所有与自己有连接关系的伙伴
    local partners = {}
    if my_data.target_ids then
        for target_id, _ in pairs(my_data.target_ids) do
            table.insert(partners, State.get_portaldata_by_id(target_id))
        end
    end
    if my_data.source_ids then
        for source_id, _ in pairs(my_data.source_ids) do
            table.insert(partners, State.get_portaldata_by_id(source_id))
        end
    end

    -- 3. 遍历所有伙伴，通知兼容模块去重新评估连接状态
    for _, partner_data in pairs(partners) do
        if partner_data and LTN and LTN.update_connection then
            -- 根据自己是源还是目标，正确传递参数
            -- update_connection 内部会根据双方的 ltn_enabled 状态决定是否注册
            if my_data.mode == "entry" then
                local should_connect = my_data.ltn_enabled and partner_data.ltn_enabled
                LTN.update_connection(my_data, partner_data, should_connect, player, enabled, nil, true)
            else -- exit
                local should_connect = partner_data.ltn_enabled and my_data.ltn_enabled
                LTN.update_connection(partner_data, my_data, should_connect, player, enabled, nil, false)
            end
        end
    end

    refresh_all_guis()
end

-- ============================================================================
-- 8. 传送玩家逻辑
-- ============================================================================
function Logic.teleport_player(player_index, portal_id)
    local player = game.get_player(player_index)
    local portaldata = State.get_portaldata_by_id(portal_id)
    if not (player and portaldata) then
        return
    end
    if player and portaldata and portaldata.shell and portaldata.shell.valid then
        -- 计算落点：位于建筑 "口子" 外面一点的位置，防止卡住
        -- 建筑中心到口子是 6 格，我们传送在 8 格的位置
        local dir = portaldata.shell.direction
        local offset = { x = 0, y = 0 }

        if dir == 0 then -- North (开口在下) -> 传送到上方
            offset = { x = 0, y = -8 }
        elseif dir == 4 then -- East (开口在左) -> 传送到右方
            offset = { x = 8, y = 0 }
        elseif dir == 8 then -- South (开口在上) -> 传送到下方
            offset = { x = 0, y = 8 }
        elseif dir == 12 then -- West (开口在右) -> 传送到左方
            offset = { x = -8, y = 0 }
        end

        local target_pos = {
            x = portaldata.shell.position.x + offset.x,
            y = portaldata.shell.position.y + offset.y,
        }

        -- 尝试寻找附近的无碰撞位置 (防止传送到树或石头里)
        local safe_pos = portaldata.shell.surface.find_non_colliding_position("character", target_pos, 5, 1)
        if not safe_pos then
            safe_pos = target_pos
        end -- 如果找不到，强行传送

        -- 执行传送
        player.teleport(safe_pos, portaldata.shell.surface)

        -- 强制查找并销毁 GUI，不再依赖事件监听
        if player.gui.screen.rift_rail_main_frame then
            player.gui.screen.rift_rail_main_frame.destroy()
        end

        -- 清空 opened 状态，确保逻辑闭环
        player.opened = nil
    else
        if player then
            player.print({ "messages.rift-rail-error-self-invalid" })
        end
    end
end

-- ============================================================================
-- 9. 一键断开所有来源
-- ============================================================================
function Logic.unpair_all_from_exit(player_index, portal_id)
    local player = game.get_player(player_index)
    local portal = State.get_portaldata_by_id(portal_id)
    if not (player and portal and portal.mode == "exit") then
        return
    end

    if portal.source_ids and next(portal.source_ids) then
        local count = 0
        -- 创建一个源ID的临时副本进行遍历，因为 unpair_portals 会修改原始表
        local source_ids_copy = {}
        for id, _ in pairs(portal.source_ids) do
            table.insert(source_ids_copy, id)
        end

        for _, src_id in ipairs(source_ids_copy) do
            -- 调用现有的单体解绑逻辑，它会处理所有清理工作
            Logic.unpair_portals(player_index, src_id)
            count = count + 1
        end

        player.print({ "messages.rift-rail-unpair-all-success", count })
    end
end

-- ============================================================================
-- 10.精准解绑逻辑 (断开指定的一对连接)
-- ============================================================================
function Logic.unpair_portals_specific(player_index, source_id, target_id)
    local player = nil
    if player_index then
        player = game.get_player(player_index)
    end

    local source = State.get_portaldata_by_id(source_id)
    local target = State.get_portaldata_by_id(target_id)

    if not (source and target) then
        return
    end

    -- 1. 清理源头 (Entry) 的记录
    if source.target_ids then
        source.target_ids[target_id] = nil
    end

    -- 2. 清理目标 (Exit) 的记录
    if target.source_ids then
        target.source_ids[source_id] = nil
    end

    -- 检查双方的连接数，如果归零则自动关闭开关
    check_and_reset_logistics(source)
    check_and_reset_logistics(target)

    -- LTN 清理逻辑
    -- script.active_mods 检查，只有在 LTN 模组实际启用时才尝试清理
    if script.active_mods["LogisticTrainNetwork"] and LTN and LTN.update_connection then
        -- 强制发送 "false" 指令来清理（最后一个参数 nil 表示非用户操作）
        if source.mode == "entry" then
            LTN.update_connection(source, target, false, player, false, nil)
        else
            LTN.update_connection(target, source, false, player, false, nil)
        end
    end

    -- 3. 反馈消息
    if player then
        -- 复用现有的本地化字符串，提示已断开与某某的连接
        local target_display = build_display_name(target)
        player.print({ "messages.rift-rail-unpair-success", target_display })
    end

    if RiftRail.DEBUG_MODE_ENABLED then
        log_debug("[Logic] 精准断开: " .. source_id .. " -x- " .. target_id)
    end

    refresh_all_guis()
end

-- ============================================================================
-- 11. 设置默认出口
-- ============================================================================
function Logic.set_default_exit(player_index, entry_unit_number, target_exit_id)
    local player = game.get_player(player_index)
    local entry_data = State.get_portaldata_by_unit_number(entry_unit_number)

    if not (player and entry_data) then
        return
    end

    -- 验证: 必须是入口，且目标ID必须在已连接列表中
    if entry_data.mode == "entry" and entry_data.target_ids and entry_data.target_ids[target_exit_id] then
        entry_data.default_exit_id = target_exit_id

        -- 获取目标名称用于提示
        local target_data = State.get_portaldata_by_id(target_exit_id)
        local target_name = target_data and target_data.name or ("ID:" .. target_exit_id)

        player.print({ "", "[img=utility/status_working] ", { "gui.rift-rail-default-set", target_name } })

        -- 刷新界面 (更新星星状态和列表显示)
        refresh_all_guis()
    end
end

-- ============================================================================
-- 12.车站改名事件 (从 control.lua 迁移)
-- ============================================================================
function Logic.on_entity_renamed(event)
    local entity = event.entity
    if not (entity and entity.valid and entity.name == "rift-rail-station") then
        return
    end

    local portaldata = State.get_portaldata(entity)
    if not portaldata then
        return
    end

    local master_icon = "[item=rift-rail-placer]"
    local raw_name = entity.backer_name or ""
    local clean_str = raw_name:gsub("%[item=rift%-rail%-placer%]", "", 1)

    local prefix, icon_type, icon_name, separator, plain_name = string.match(clean_str, "^(%s*)%[([%w%-]+)=([%w%-]+)%](%s*)(.*)")

    if icon_type and icon_name then
        if icon_name == "rift-rail-placer" then
            portaldata.icon = nil
            portaldata.prefix = prefix
            portaldata.name = (separator or "") .. (plain_name or "")
        else
            portaldata.icon = { type = icon_type, name = icon_name }
            portaldata.prefix = prefix
            portaldata.name = (separator or "") .. (plain_name or "")
        end
    else
        portaldata.icon = nil
        local p_space, p_name = string.match(clean_str, "^(%s*)(.*)")
        portaldata.prefix = p_space
        portaldata.name = p_name or ""
    end

    local user_icon_str = ""
    if portaldata.icon then
        user_icon_str = "[" .. portaldata.icon.type .. "=" .. portaldata.icon.name .. "]"
    end

    local final_backer_name = master_icon .. (portaldata.prefix or "") .. user_icon_str .. portaldata.name
    entity.backer_name = final_backer_name

    -- 强制刷新列车限制，修正引擎因改名可能产生的自动同步错误
    Logic.refresh_station_limit(portaldata)

    -- 更新 LTN 路由表中的车站名缓存
    if portaldata.ltn_enabled and LTN.update_station_name_in_routes then
        LTN.update_station_name_in_routes(portaldata.unit_number, final_backer_name)
    end

    if portaldata.shell and portaldata.shell.valid then
        for _, player in pairs(game.connected_players) do
            local frame = player.gui.screen.rift_rail_main_frame
            if frame and frame.valid and frame.tags.unit_number == portaldata.unit_number then
                GUI.build_or_update(player, portaldata.shell)
            end
        end
    end
end

return Logic
