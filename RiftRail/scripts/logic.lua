-- scripts/logic.lua v0.0.3
-- 功能：业务逻辑核心 (集成物理碰撞器管理)

local Logic = {}
local State = nil
local GUI = nil
local CybersynSE = nil
local LTN = nil

local log_debug = function() end

function Logic.init(deps)
    State = deps.State
    GUI = deps.GUI
    log_debug = deps.log_debug
    CybersynSE = deps.CybersynSE
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

-- 辅助函数：构建包含图标的富文本显示名称
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

-- 辅助函数：根据当前模式强制刷新车站限制 (防止引擎自动同步或未初始化)
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

    -- 1. 清理旧的碰撞器 (同时从户口本上除名)
    if portaldata.children then
        -- 使用倒序遍历，安全地在循环中移除元素
        for i = #portaldata.children, 1, -1 do
            local child_data = portaldata.children[i]
            if child_data and child_data.entity and child_data.entity.valid and child_data.entity.name == "rift-rail-collider" then
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
        if direction == 4 then                 -- East
            relative_pos = { x = 2, y = 0 }
        elseif direction == 8 then             -- South
            relative_pos = { x = 0, y = 2 }
        elseif direction == 12 then            -- West
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

        -- [核心修复] 将新创建的碰撞器登记到 children 列表中
        if new_collider and portaldata.children then
            table.insert(portaldata.children, {
                entity = new_collider,
                relative_pos = relative_pos,
            })
        end
    end
end

-- scripts/logic.lua
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
    local prefix, icon_type, icon_name, separator, plain_name = string.match(new_string,
        "^(%s*)%[([%w%-]+)=([%w%-]+)%](%s*)(.*)")

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
-- 2. 模式切换 (重构：适配多对一，移除双向同步，增加自动清理)
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
    if old_mode == "entry" and my_data.paired_to_id then
        -- 如果之前是入口，断开与目标的单向连接
        -- 我们手动执行清理，避免调用 unpair_portals 导致递归或模式重置循环
        local target = State.get_portaldata_by_id(my_data.paired_to_id)
        if target and target.source_ids then
            target.source_ids[my_data.id] = nil
        end
        my_data.paired_to_id = nil

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
        end
        my_data.source_ids = {}
        -- [新增] 清理互斥锁
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

    -- 1. 验证源 (Entry)：必须未配对 (因为一个入口只能去一个地方)
    if source.paired_to_id then
        player.print({ "messages.rift-rail-error-self-already-paired" })
        return
    end

    -- 2. 验证目标 (Exit)：目标必须是 出口 或 中立
    -- 如果目标已经是入口模式，则不能作为目的地
    if target.mode == "entry" then
        player.print({ "messages.rift-rail-error-target-is-entry" })
        return
    end

    -- [安全检查] 源不能是出口模式 (GUI层面会屏蔽，这里做双重保险)
    if source.mode == "exit" then
        player.print({ "messages.rift-rail-error-source-is-exit" })
        return
    end

    -- 3. 执行连接 (不对称结构)
    -- 源指向目标
    source.paired_to_id = target_id

    -- 目标记录源 (多对一支持)
    if not target.source_ids then
        target.source_ids = {}
    end
    target.source_ids[source_id] = true
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
-- 4. 解绑逻辑 (重构：适配多对一结构)
-- ============================================================================
function Logic.unpair_portals(player_index, portal_id)
    local player = game.get_player(player_index)
    local portal = State.get_portaldata_by_id(portal_id)

    if not portal then
        return
    end

    -- 分支 A: 这是一个 入口 (Entry)，或者被当作入口处理
    -- 操作：切断它通往出口的线，并将其重置为中立
    if portal.paired_to_id then
        local target_id = portal.paired_to_id
        local target = State.get_portaldata_by_id(target_id)
        local target_display = target and build_display_name(target) or "Unknown"

        -- 1. 清理自身的指针
        portal.paired_to_id = nil

        -- 2. 清理目标的反向引用 (从 source_ids 列表中移除自己)
        if target and target.source_ids then
            target.source_ids[portal_id] = nil
        end

        -- 3. 将自身重置为中立 (因为它失去了唯一的目标)
        -- 注意：目标(出口)保持原样，因为可能还有其他入口连着它
        Logic.set_mode(nil, portal_id, "neutral", true)

        -- 4. 反馈消息
        player.print({ "messages.rift-rail-unpair-success", target_display })

        if RiftRail.DEBUG_MODE_ENABLED then
            log_debug("[Logic] 断开连接: Entry " .. portal.id .. " -x- Exit " .. (target_id or "nil"))
        end

        -- 分支 B: 这是一个 出口 (Exit)
        -- 操作：由于出口是被动端，这意味着“断开所有连接”
    elseif portal.source_ids and next(portal.source_ids) then
        local count = 0
        -- 遍历所有连着我的入口，强制它们断开
        for src_id, _ in pairs(portal.source_ids) do
            local src_data = State.get_portaldata_by_id(src_id)
            if src_data then
                -- 递归调用自己，走分支 A 逻辑
                -- 这样可以复用分支 A 中的清理和模式重置逻辑
                Logic.unpair_portals(player_index, src_id)
                count = count + 1
            end
        end
        -- 彻底清空列表 (双重保险)
        portal.source_ids = {}

        if RiftRail.DEBUG_MODE_ENABLED then
            log_debug("[Logic] 出口清空: Exit " .. portal.id .. " 断开了 " .. count .. " 个来源")
        end
    end

    refresh_all_guis()
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
-- 6. Cybersyn 开关控制 (最终版：智能同步与多对一保护)
-- ============================================================================
function Logic.set_cybersyn_enabled(player_index, portal_id, enabled)
    local player = game.get_player(player_index)
    local my_data = State.get_portaldata_by_id(portal_id)

    if not (player and my_data) then
        return
    end

    -- 更新自身状态
    my_data.cybersyn_enabled = enabled

    if my_data.mode == "entry" then
        -- [分闸逻辑]
        local partner = my_data.paired_to_id and State.get_portaldata_by_id(my_data.paired_to_id)
        if partner then
            -- 1. 智能状态同步
            if enabled then
                -- A. 开启时：确保总闸(出口)也是开的
                if not partner.cybersyn_enabled then
                    partner.cybersyn_enabled = true
                end
            else
                -- B. 关闭时：检查是否需要关闭总闸 (最后一个关灯的人负责关总闸)
                local any_other_active = false
                if partner.source_ids then
                    for src_id, _ in pairs(partner.source_ids) do
                        if src_id ~= my_data.id then
                            local src = State.get_portaldata_by_id(src_id)
                            if src and src.cybersyn_enabled then
                                any_other_active = true
                                break
                            end
                        end
                    end
                end
                -- 如果没有其他开启的来源，顺便把总闸也关了
                if not any_other_active then
                    partner.cybersyn_enabled = false
                end
            end

            -- 2. 执行连接 (仅当前这一对)
            if CybersynSE then
                -- 连接条件：两者都开 (经过上面的同步，如果 enabled=true，这里一定成立)
                local should_connect = my_data.cybersyn_enabled and partner.cybersyn_enabled
                CybersynSE.update_connection(my_data, partner, should_connect, player)
            end

            -- 3. 多对一提示
            -- 计算来源数量
            local source_count = 0
            if partner.source_ids then
                for _ in pairs(partner.source_ids) do
                    source_count = source_count + 1
                end
            end

            if source_count > 1 then
                player.print({ "messages.rift-rail-info-logistics-entry-only-notice" })
            end
        end
    elseif my_data.mode == "exit" then
        -- [总闸逻辑]
        -- 强制同步所有来源的状态，保持一致性
        if my_data.source_ids then
            for src_id, _ in pairs(my_data.source_ids) do
                local source = State.get_portaldata_by_id(src_id)
                if source then
                    -- 强制同步来源状态
                    source.cybersyn_enabled = enabled

                    if CybersynSE then
                        -- 这里的 connect 也就等于 enabled，因为两者现在状态一致了
                        CybersynSE.update_connection(source, my_data, enabled, player)
                    end
                end
            end
        end
    end

    refresh_all_guis()
end

-- ============================================================================
-- 7. LTN 开关控制 (最终版：智能同步与多对一保护)
-- ==========================================================================
function Logic.set_ltn_enabled(player_index, portal_id, enabled)
    local player = game.get_player(player_index)
    local my_data = State.get_portaldata_by_id(portal_id)
    if not (player and my_data) then
        return
    end

    -- 更新自身状态
    my_data.ltn_enabled = enabled

    if my_data.mode == "entry" then
        -- [分闸逻辑]
        local partner = my_data.paired_to_id and State.get_portaldata_by_id(my_data.paired_to_id)
        if partner then
            -- 1. 智能状态同步
            if enabled then
                -- A. 开启时：确保总闸(出口)也是开的
                if not partner.ltn_enabled then
                    partner.ltn_enabled = true
                end
            else
                -- B. 关闭时：检查是否需要关闭总闸
                local any_other_active = false
                if partner.source_ids then
                    for src_id, _ in pairs(partner.source_ids) do
                        if src_id ~= my_data.id then
                            local src = State.get_portaldata_by_id(src_id)
                            if src and src.ltn_enabled then
                                any_other_active = true
                                break
                            end
                        end
                    end
                end
                if not any_other_active then
                    partner.ltn_enabled = false
                end
            end

            -- 2. 执行连接
            if LTN then
                local should_connect = my_data.ltn_enabled and partner.ltn_enabled
                LTN.update_connection(my_data, partner, should_connect, player)
            end

            -- 3. 多对一提示
            local source_count = 0
            if partner.source_ids then
                for _ in pairs(partner.source_ids) do
                    source_count = source_count + 1
                end
            end

            if source_count > 1 then
                player.print({ "messages.rift-rail-info-logistics-entry-only-notice" })
            end
        end
    elseif my_data.mode == "exit" then
        -- [总闸逻辑] 强制同步
        if my_data.source_ids then
            for src_id, _ in pairs(my_data.source_ids) do
                local source = State.get_portaldata_by_id(src_id)
                if source then
                    source.ltn_enabled = enabled
                    if LTN then
                        LTN.update_connection(source, my_data, enabled, player)
                    end
                end
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

        if dir == 0 then      -- North (开口在下) -> 传送到上方
            offset = { x = 0, y = -8 }
        elseif dir == 4 then  -- East (开口在左) -> 传送到右方
            offset = { x = 8, y = 0 }
        elseif dir == 8 then  -- South (开口在上) -> 传送到下方
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
-- 9. 一键断开所有来源 (新增功能)
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

return Logic
