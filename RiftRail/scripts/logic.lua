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
-- 2. 模式切换 (核心修改)
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

    if my_data.mode == mode then
        return
    end

    my_data.mode = mode

    -- 立即更新物理碰撞器状态
    update_collider_state(my_data)

    -- 使用统一函数刷新车站限制
    Logic.refresh_station_limit(my_data)

    -- 消息提示
    if player then
        if mode == "entry" then
            player.print({ "gui.rift-rail-mode-entry" })
        end
        if mode == "exit" then
            player.print({ "gui.rift-rail-mode-exit" })
        end
        if mode == "neutral" then
            player.print({ "gui.rift-rail-mode-neutral" })
        end
    end

    -- 智能同步配对对象
    if not skip_sync and my_data.paired_to_id then
        local partner = State.get_portaldata_by_id(my_data.paired_to_id)
        if partner then
            local partner_mode = "neutral"
            if mode == "entry" then
                partner_mode = "exit"
            end
            if mode == "exit" then
                partner_mode = "entry"
            end

            Logic.set_mode(nil, partner.id, partner_mode, true)

            if player then
                player.print({ "messages.rift-rail-mode-synced", partner_mode })
            end
        end
    end

    refresh_all_guis()
end

-- ============================================================================
-- 3. 配对逻辑
-- ============================================================================
function Logic.pair_portals(player_index, source_id, target_id)
    local player = game.get_player(player_index)
    local source = State.get_portaldata_by_id(source_id)
    local target = State.get_portaldata_by_id(target_id)

    if not (source and target) then
        return
    end

    if source.paired_to_id then
        player.print({ "messages.rift-rail-error-self-already-paired" })
        return
    end
    if target.paired_to_id then
        player.print({ "messages.rift-rail-error-target-already-paired" })
        return
    end

    source.paired_to_id = target_id
    target.paired_to_id = source_id

    -- 使用富文本显示，支持图标（玩家个人消息，保留本地化）
    local source_display = build_display_name(source)
    local target_display = build_display_name(target)
    player.print({ "messages.rift-rail-pair-success", source_display, target_display })

    -- 智能初始化状态
    if source.mode == "entry" then
        Logic.set_mode(player_index, target_id, "exit", true)
    elseif source.mode == "exit" then
        Logic.set_mode(player_index, target_id, "entry", true)
    elseif target.mode == "entry" then
        Logic.set_mode(player_index, source_id, "exit", true)
    elseif target.mode == "exit" then
        Logic.set_mode(player_index, source_id, "entry", true)
    end

    refresh_all_guis()
end

-- ============================================================================
-- 4. 解绑逻辑
-- ============================================================================
function Logic.unpair_portals(player_index, portal_id)
    local player = game.get_player(player_index)
    local source = State.get_portaldata_by_id(portal_id)
    if not source or not source.paired_to_id then
        return
    end

    local target = State.get_portaldata_by_id(source.paired_to_id)
    local target_name = target and target.name or "Unknown"

    source.paired_to_id = nil
    Logic.set_mode(nil, source.id, "neutral", true)

    if target then
        target.paired_to_id = nil
        Logic.set_mode(nil, target.id, "neutral", true)
    end

    -- [修改] 使用富文本显示，支持图标（玩家个人消息，保留本地化）
    local target_display = build_display_name(target)
    player.print({ "messages.rift-rail-unpair-success", target_display })
    refresh_all_guis()
end

-- ============================================================================
-- 5. 远程观察
-- ============================================================================
function Logic.open_remote_view(player_index, portal_id)
    local player = game.get_player(player_index)
    local my_data = State.get_portaldata_by_id(portal_id)
    if not (player and my_data and my_data.paired_to_id) then
        return
    end

    local target = State.get_portaldata_by_id(my_data.paired_to_id)
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
-- 6. Cybersyn 开关控制 (接入真实逻辑)
-- ============================================================================
function Logic.set_cybersyn_enabled(player_index, portal_id, enabled)
    local player = game.get_player(player_index)
    local my_data = State.get_portaldata_by_id(portal_id)

    if not (player and my_data) then
        return
    end

    -- 获取配对对象
    local partner = nil
    if my_data.paired_to_id then
        partner = State.get_portaldata_by_id(my_data.paired_to_id)
    end

    if not partner then
        player.print({ "messages.rift-rail-error-cybersyn-unpaired" }) -- 需要配对才能开
        return
    end

    -- [修改] 调用兼容模块执行实际操作
    if CybersynSE then
        CybersynSE.update_connection(my_data, partner, enabled, player)
        -- 注意：update_connection 内部成功后会更新 my_data.cybersyn_enabled
    else
        my_data.cybersyn_enabled = enabled --保底逻辑
    end

    -- 刷新界面
    refresh_all_guis()
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

    local partner = nil
    if my_data.paired_to_id then
        partner = State.get_portaldata_by_id(my_data.paired_to_id)
    end
    if not partner then
        player.print({ "messages.rift-rail-error-ltn-unpaired" })
        return
    end

    if LTN then
        LTN.update_connection(my_data, partner, enabled, player)
    else
        my_data.ltn_enabled = enabled
    end

    refresh_all_guis()
end

return Logic
