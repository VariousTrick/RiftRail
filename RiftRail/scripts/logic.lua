-- scripts/logic.lua v0.0.3
-- 功能：业务逻辑核心 (集成物理碰撞器管理)

local Logic = {}
local State = nil
local GUI = nil
-- local CybersynSE = nil -- [新增] 本地变量
local log_debug = function() end


function Logic.init(deps)
    State = deps.State
    GUI = deps.GUI
    log_debug = deps.log_debug
    -- CybersynSE = deps.CybersynSE -- [新增] 获取依赖
end

-- ============================================================================
-- 辅助函数：广播刷新
-- ============================================================================
local function refresh_all_guis()
    for _, player in pairs(game.connected_players) do
        local opened = player.opened
        if opened and opened.valid and State.get_struct(opened) then
            GUI.build_or_update(player, opened)
        end
    end
end

-- ============================================================================
-- [新增] 物理状态管理 (精准定点清除版)
-- ============================================================================
local function update_collider_state(struct)
    if not (struct and struct.shell and struct.shell.valid) then return end

    local surface = struct.shell.surface
    local center = struct.shell.position
    local direction = struct.shell.direction

    -- 1. 计算碰撞器的精确相对坐标
    -- 基于 Builder.lua 的旋转逻辑 (顺时针: N->E->S->W)
    -- 基础位置 (North): {x=0, y=-2}
    local offset = { x = 0, y = 0 }

    if direction == 0 then         -- North (上)
        offset = { x = 0, y = -2 }
    elseif direction == 4 then     -- East (右) -> Builder 旋转逻辑 x=-y, y=x -> -(-2), 0 -> 2, 0
        offset = { x = 2, y = 0 }  -- [修正] 确保是右边 (2, 0)
    elseif direction == 8 then     -- South (下)
        offset = { x = 0, y = 2 }
    elseif direction == 12 then    -- West (左) -> Builder 旋转逻辑 x=y, y=-x -> -2, 0
        offset = { x = -2, y = 0 } -- [修正] 确保是左边 (-2, 0)
    end

    -- 2. 计算碰撞器的绝对世界坐标
    local target_pos = { x = center.x + offset.x, y = center.y + offset.y }

    -- 3. 精准定点清理
    -- 只在 target_pos 周围 0.5 格内寻找碰撞器
    -- 这样绝对不会误伤隔壁邻居 (因为邻居的碰撞器至少在 2 格以外)
    local existing = surface.find_entities_filtered {
        name = "rift-rail-collider",
        position = target_pos, -- 锁定目标点
        radius = 0.5           -- 极小范围
    }

    for _, e in pairs(existing) do
        if e.valid then e.destroy() end
    end

    -- 4. 如果是 [入口] 模式，则在原地创建新的碰撞器
    if struct.mode == "entry" then
        local collider = surface.create_entity {
            name = "rift-rail-collider",
            position = target_pos, -- 使用相同的坐标
            force = struct.shell.force
        }
        -- log_debug("Logic: 已在精准坐标 (" .. target_pos.x .. "," .. target_pos.y .. ") 重建碰撞器。")
    end
end

-- ============================================================================
-- 1. 更新名称
-- ============================================================================
function Logic.update_name(player_index, portal_id, new_string)
    local player = game.get_player(player_index)
    local my_data = State.get_struct_by_id(portal_id)
    if not (player and my_data) then return end

    -- 1. 解析输入
    local icon_type, icon_name, plain_name = string.match(new_string, "%[([%w%-]+)=([%w%-]+)%]%s*(.*)")

    -- 2. [核心修正] 智能去重
    if icon_type and icon_name then
        -- 如果解析出的图标就是我们的 "Rift Rail 放置器"，说明这是默认图标
        -- 我们将其视为 "无自定义图标" (nil)，避免和强制添加的主图标重复
        if icon_name == "rift-rail-placer" then
            my_data.icon = nil
        else
            my_data.icon = { type = icon_type, name = icon_name }
        end
        my_data.name = plain_name
    else
        -- 没有图标，只存名字
        my_data.name = new_string
        my_data.icon = nil
    end

    -- 3. 更新实体显示名称
    if my_data.children then
        for _, child in pairs(my_data.children) do
            if child.valid and child.name == "rift-rail-station" then
                -- 强制添加的主图标
                local master_icon = "[item=rift-rail-placer] "

                -- 用户自定义图标字符串
                local user_icon_str = ""
                -- 只有当 icon 存在且不是主图标时(上面已经过滤了)，这里才会生成字符串
                if my_data.icon then
                    user_icon_str = "[" .. my_data.icon.type .. "=" .. my_data.icon.name .. "] "
                end

                -- 拼接：[主图标] + [用户图标(如果有)] + 名字
                child.backer_name = master_icon .. user_icon_str .. my_data.name
                break
            end
        end
    end

    player.print({ "messages.rift-rail-mode-changed", my_data.name })
    refresh_all_guis()
end

-- ============================================================================
-- 2. 模式切换 (核心修改)
-- ============================================================================
function Logic.set_mode(player_index, portal_id, mode, skip_sync)
    local player = nil
    if player_index then player = game.get_player(player_index) end

    local my_data = State.get_struct_by_id(portal_id)
    if not my_data then return end

    if my_data.mode == mode then return end

    my_data.mode = mode

    -- [新增] 立即更新物理碰撞器状态
    update_collider_state(my_data)

    -- 消息提示
    if player then
        if mode == "entry" then player.print({ "gui.rift-rail-mode-entry" }) end
        if mode == "exit" then player.print({ "gui.rift-rail-mode-exit" }) end
        if mode == "neutral" then player.print({ "gui.rift-rail-mode-neutral" }) end
    end

    -- 智能同步配对对象
    if not skip_sync and my_data.paired_to_id then
        local partner = State.get_struct_by_id(my_data.paired_to_id)
        if partner then
            local partner_mode = "neutral"
            if mode == "entry" then partner_mode = "exit" end
            if mode == "exit" then partner_mode = "entry" end

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
    local source = State.get_struct_by_id(source_id)
    local target = State.get_struct_by_id(target_id)

    if not (source and target) then return end

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

    player.print({ "messages.rift-rail-pair-success", source.name, target.name })

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
    local source = State.get_struct_by_id(portal_id)
    if not source or not source.paired_to_id then return end

    local target = State.get_struct_by_id(source.paired_to_id)
    local target_name = target and target.name or "Unknown"

    source.paired_to_id = nil
    Logic.set_mode(nil, source.id, "neutral", true)

    if target then
        target.paired_to_id = nil
        Logic.set_mode(nil, target.id, "neutral", true)
    end

    player.print({ "messages.rift-rail-unpair-success", target_name })
    refresh_all_guis()
end

-- ============================================================================
-- 5. 远程观察
-- ============================================================================
function Logic.open_remote_view(player_index, portal_id)
    local player = game.get_player(player_index)
    local my_data = State.get_struct_by_id(portal_id)
    if not (player and my_data and my_data.paired_to_id) then return end

    local target = State.get_struct_by_id(my_data.paired_to_id)
    if target and target.shell and target.shell.valid then
        player.opened = nil
        player.set_controller({
            type = defines.controllers.remote,
            position = target.shell.position,
            surface = target.shell.surface,
            zoom = player.zoom
        })
    end
end

-- ============================================================================
-- 6. [修改] Cybersyn 开关控制 (占位符功能)
-- ============================================================================
function Logic.set_cybersyn_enabled(player_index, portal_id, enabled)
    local player = game.get_player(player_index)
    local my_data = State.get_struct_by_id(portal_id)

    if not (player and my_data) then return end

    -- 只更新数据和UI，不执行任何实际功能
    my_data.cybersyn_enabled = enabled

    if enabled then
        player.print("Cybersyn 开关已打开 (占位符)")
    else
        player.print("Cybersyn 开关已关闭 (占位符)")
    end

    -- 刷新界面以更新开关状态
    refresh_all_guis()
end

return Logic
