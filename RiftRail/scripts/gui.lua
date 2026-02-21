-- scripts/gui.lua
-- 【Rift Rail - GUI 模块 v1.0 正式版】
-- 功能：基于 Container 的相对 GUI，实现完美的打开/关闭体验
-- 复刻自传送门 Mod 逻辑

local GUI = {}

local State = nil

local log_debug = function() end

local function log_gui(message)
    if not RiftRail.DEBUG_MODE_ENABLED then
        return
    end
    if log_debug then
        log_debug(message)
    end
end

-- WARNING: This value MUST be kept in sync with the one in scripts/logic.lua
-- 警告：此值必须与 scripts/logic.lua 中的值保持同步
local MAX_CONNECTIONS = 5

function GUI.init(dependencies)
    State = dependencies.State
    log_debug = dependencies.log_debug
    log_gui("[RiftRail:GUI] 模块初始化完成 (Relative Mode)。")
end

-- =================================================================================
-- 辅助函数：递归查找子元素
-- =================================================================================
local function find_element_recursively(element, name)
    if not (element and element.valid) then
        return nil
    end
    if element.name == name then
        return element
    end
    if element.children then
        for _, child in pairs(element.children) do
            local found = find_element_recursively(child, name)
            if found then
                return found
            end
        end
    end
    return nil
end
-- =================================================================================
-- 辅助视图函数
-- =================================================================================

-- 构建显示名称
function GUI.build_display_name_flow(parent_flow, my_data)
    parent_flow.clear()

    -- 1. 确定图标字符串 (如果有自定义用自定义，没有则用默认)
    local icon_str = "[item=rift-rail-placer]" -- 默认图标
    if my_data.icon and my_data.icon.type and my_data.icon.name then
        icon_str = "[" .. my_data.icon.type .. "=" .. my_data.icon.name .. "]"
    end

    -- 2. 拼接: [图标] 名字 (ID: xx)
    local display_caption = icon_str .. my_data.name .. " (ID: " .. my_data.id .. ")"

    -- 3. 创建 Label
    parent_flow.add({ type = "label", caption = display_caption, style = "bold_label" })

    parent_flow.add({
        type = "sprite-button",
        name = "rift_rail_rename_button",
        sprite = "utility/rename_icon",
        tooltip = { "gui.rift-rail-rename-tooltip" },
        style = "tool_button",
    })
end

-- 构建编辑名称
function GUI.build_edit_name_flow(parent_flow, my_data)
    parent_flow.clear()

    -- 1. 确定初始文本 (默认图标 + 名字)
    local current_icon_str = "[item=rift-rail-placer]"
    if my_data.icon and my_data.icon.type and my_data.icon.name then
        current_icon_str = "[" .. my_data.icon.type .. "=" .. my_data.icon.name .. "]"
    end

    local textfield = parent_flow.add({
        type = "textfield",
        name = "rift_rail_rename_textfield",
        text = current_icon_str .. my_data.name,
        icon_selector = true,
        handler = "on_gui_confirmed",
    })
    textfield.style.width = 200
    textfield.focus()
    textfield.select_all()

    parent_flow.add({
        type = "sprite-button",
        name = "rift_rail_confirm_rename_button",
        sprite = "utility/check_mark",
        style = "tool_button_green",
    })
end

-- =================================================================================
-- 主界面构建
-- =================================================================================

function GUI.build_or_update(player, entity)
    if not (player and entity and entity.valid) then
        return
    end

    -- 1. 获取数据
    local my_data = State.get_portaldata(entity)
    if not my_data then
        log_gui("[RiftRail:GUI] 错误: 无法找到实体关联的数据。")
        return
    end

    -- 2. 初始化玩家设置
    if not storage.rift_rail_player_settings then
        storage.rift_rail_player_settings = {}
    end
    if not storage.rift_rail_player_settings[player.index] then
        storage.rift_rail_player_settings[player.index] = { show_preview = true }
    end
    local player_settings = storage.rift_rail_player_settings[player.index]

    -- 统计当前连接数，用于决定初始视图模式
    local connection_count = 0
    if my_data.mode == "entry" then
        if my_data.target_ids then
            for _ in pairs(my_data.target_ids) do
                connection_count = connection_count + 1
            end
        end
    elseif my_data.mode == "exit" then
        if my_data.source_ids then
            for _ in pairs(my_data.source_ids) do
                connection_count = connection_count + 1
            end
        end
    end

    -- 3. 创建/清理 GUI
    -- 3.1. 改用 screen (屏幕) 容器，不再使用 relative
    local gui = player.gui.screen -- <--- 改动点 1

    -- 3.2. 清理旧窗口 (防止重复打开)
    if gui.rift_rail_main_frame then
        gui.rift_rail_main_frame.destroy()
    end

    -- 动态标题栏 (逻辑修正：如果没有自定义图标，强制显示默认图标)

    -- 1. 预设默认图标
    local title_icon = "[item=rift-rail-placer]"

    -- 2. 如果有自定义图标，则覆盖默认图标
    if my_data.icon and my_data.icon.type and my_data.icon.name then
        title_icon = "[" .. my_data.icon.type .. "=" .. my_data.icon.name .. "]"
    end

    -- 3. 拼接最终标题: [图标] 名字 (ID: 123)

    -- 使用 Factorio 的本地化拼接语法 {"", A, B, C}
    -- 这里的 {"entity-name.rift-rail-core"} 会自动读取 locale 文件显示为 "裂隙铁路控制核心"
    local title_caption = {
        "", -- 空字符串开头，表示这是一个拼接列表
        title_icon, -- 图标字符串 "[item=...]"
        " ", -- 空格
        { "entity-name.rift-rail-core" }, -- 读取 locale 中的中文名
        " (ID: " .. my_data.id .. ")", -- 后面拼接 ID
    }

    log_gui("[RiftRail:GUI] 标题已更新为本地化名称 (ID: " .. my_data.id .. ")")

    local frame = gui.add({
        type = "frame",
        name = "rift_rail_main_frame",
        direction = "vertical",
        caption = title_caption, -- 使用带图标的标题
    })

    -- 6. 让窗口自动居中
    frame.auto_center = true

    -- 7. [核心] 存储 Unit Number，用于后续逻辑
    -- 同时保存 unit_number 和 view_mode
    frame.tags = { unit_number = my_data.unit_number }

    -- 8. [关键一步] 欺骗引擎：告诉游戏“现在玩家打开的是这个窗口”
    -- 这会自动关闭原本的箱子界面！
    player.opened = frame

    log_gui("[RiftRail:GUI] 已创建独立窗口并接管 player.opened")

    local inner_flow = frame.add({ type = "flow", direction = "vertical" })
    inner_flow.style.padding = 8

    -- 4. 名称区域
    local name_flow = inner_flow.add({ type = "flow", name = "name_flow", direction = "horizontal" })
    name_flow.style.vertical_align = "center"
    name_flow.style.bottom_margin = 8
    GUI.build_display_name_flow(name_flow, my_data)

    -- 5. 模式切换 (三态开关)
    local switch_state = "none"
    if my_data.mode == "entry" then
        switch_state = "left"
    end
    if my_data.mode == "exit" then
        switch_state = "right"
    end

    inner_flow.add({ type = "label", caption = { "gui.rift-rail-mode-label" } })
    local mode_switch = inner_flow.add({
        type = "switch",
        name = "rift_rail_mode_switch",
        switch_state = switch_state,
        allow_none_state = true,
        left_label_caption = { "gui.rift-rail-mode-entry" },
        right_label_caption = { "gui.rift-rail-mode-exit" },
        tooltip = (switch_state == "left" and { "gui.rift-rail-mode-tooltip-left" }) or (switch_state == "right" and { "gui.rift-rail-mode-tooltip-right" }) or { "gui.rift-rail-mode-tooltip-none" },
    })
    mode_switch.style.bottom_margin = 12

    -- 定义一个通用的启用状态变量
    local any_connection_exists = (connection_count > 0)

    -- 6. 连接状态
    inner_flow.add({ type = "line", direction = "horizontal" })
    local status_flow = inner_flow.add({ type = "flow", direction = "vertical" })
    status_flow.add({ type = "label", caption = { "gui.rift-rail-status-label" } })

    -- 重构连接状态显示
    -- 使用预计算的 count
    if my_data.mode == "entry" then
        if connection_count > 0 then
            status_flow.add({
                type = "label",
                caption = { "gui.rift-rail-status-connected-targets", connection_count },
                style = "bold_label",
            })
        else
            status_flow.add({ type = "label", caption = { "gui.rift-rail-status-unpaired" }, style = "bold_label" })
        end
    elseif my_data.mode == "exit" then
        if connection_count > 0 then
            status_flow.add({
                type = "label",
                caption = { "gui.rift-rail-status-connected-sources", connection_count },
                style = "bold_label",
            })
        else
            status_flow.add({ type = "label", caption = { "gui.rift-rail-status-unpaired" }, style = "bold_label" })
        end
    else -- neutral
        status_flow.add({ type = "label", caption = { "gui.rift-rail-status-unpaired" }, style = "bold_label" })
    end
    status_flow.style.bottom_margin = 12

    -- 7. 连接控制
    inner_flow.add({ type = "label", caption = { "gui.rift-rail-connections-label" } }) -- 你可能需要去 locale 添加 "Connections" 或 "连接列表"

    -- 创建一个水平容器，用于并排显示下拉框和默认按钮
    local drop_flow = inner_flow.add({ type = "flow", direction = "horizontal" })
    drop_flow.style.vertical_align = "center"

    local dropdown = drop_flow.add({ type = "drop-down", name = "rift_rail_target_dropdown" })
    local dropdown_items = {}
    local dropdown_ids = {}
    local dropdown_is_paired = {} -- true: 已连接, false: 未连接, nil: 分隔符
    local selected_idx = 1
    local all_portals = State.get_all_portaldatas()

    -- 1. 添加已连接的伙伴 (统一逻辑)
    local connected_map = {}
    if my_data.mode == "entry" then
        connected_map = my_data.target_ids or {}
    elseif my_data.mode == "exit" then
        connected_map = my_data.source_ids or {}
    end

    local ordered_ids = {}
    for id, _ in pairs(connected_map) do
        table.insert(ordered_ids, id)
    end
    table.sort(ordered_ids)

    for idx, id in ipairs(ordered_ids) do
        local p_data = State.get_portaldata_by_id(id)
        if p_data then
            local icon_str = (p_data.icon and p_data.icon.name) and ("[" .. p_data.icon.type .. "=" .. p_data.icon.name .. "] ") or ""
            local item_text = { "", "[", tostring(idx), "] ", icon_str, p_data.name, " (ID:", p_data.id, ") [", p_data.surface.name, "]" }
            if my_data.mode == "entry" and my_data.default_exit_id == id then
                item_text = { "", "[color=0.2, 0.8, 0.2]", item_text, "[/color]" }
            end
            table.insert(dropdown_items, item_text)
            table.insert(dropdown_ids, id)
            table.insert(dropdown_is_paired, true)
        end
    end

    -- 【新逻辑】只有当自己还没满员时，才显示“未连接”列表
    local current_connection_count = #ordered_ids
    if current_connection_count < MAX_CONNECTIONS then
        -- 2. 添加分隔符 (仅当列表不为空时)
        if #ordered_ids > 0 then
            table.insert(dropdown_items, "──────────")
            table.insert(dropdown_ids, 0) -- 【修复】使用 0 占位，保证索引对齐
            table.insert(dropdown_is_paired, "separator") -- 【修复】使用字符串占位
        end

        -- 3. 添加未连接的伙伴 (统一逻辑)
        local existing_connections = connected_map
        for _, p_data in pairs(all_portals) do
            if p_data.id ~= my_data.id and not existing_connections[p_data.id] then
                -- 入口可以连接到 (出口 或 中立)
                local can_connect = (my_data.mode == "entry" and p_data.mode ~= "entry")
                    -- 出口可以连接到 (入口 或 中立)
                    or (my_data.mode == "exit" and p_data.mode ~= "exit")
                    -- 中立可以连接到任何
                    or (my_data.mode == "neutral")

                if can_connect then
                    -- 额外检查目标是否已满员
                    local target_connection_count = 0
                    if p_data.mode == "entry" and p_data.target_ids then
                        for _ in pairs(p_data.target_ids) do
                            target_connection_count = target_connection_count + 1
                        end
                    elseif p_data.mode == "exit" and p_data.source_ids then
                        for _ in pairs(p_data.source_ids) do
                            target_connection_count = target_connection_count + 1
                        end
                    end

                    if target_connection_count < MAX_CONNECTIONS then
                        -- 只有当目标也没满员时，才把它加到列表里
                        local icon_str = (p_data.icon and p_data.icon.name) and ("[" .. p_data.icon.type .. "=" .. p_data.icon.name .. "] ") or ""
                        table.insert(dropdown_items, { "", icon_str, p_data.name, " (ID:", p_data.id, ") [", p_data.surface.name, "]" })
                        table.insert(dropdown_ids, p_data.id)
                        table.insert(dropdown_is_paired, false)
                    end
                end
            end
        end
    end

    -- 如果之前有选中的目标，尝试在新的列表中找回它的序号
    if my_data.last_selected_source_id then
        for i, id in ipairs(dropdown_ids) do
            if id == my_data.last_selected_source_id then
                selected_idx = i
                break
            end
        end
    end

    dropdown.items = dropdown_items
    dropdown.tags = { ids = dropdown_ids, self_id = my_data.id, is_paired_map = dropdown_is_paired }

    if #dropdown_items > 0 then
        dropdown.selected_index = selected_idx
    end

    -- 默认设置全宽
    dropdown.style.width = 280
    -- 卫星按钮：设为默认 (仅在管理模式且为入口时显示)
    if my_data.mode == "entry" then
        -- 缩窄下拉框宽度，腾出空间给按钮
        dropdown.style.width = 248 -- 原280减去约32

        drop_flow.add({
            type = "sprite-button",
            name = "rift_rail_set_default_button",
            sprite = "utility/status_working",
            tooltip = { "gui.rift-rail-tooltip-set-default" },
            style = "tool_button",
            enabled = (#dropdown_items > 0),
        })
    end

    -- 统一的动态主操作按钮
    local btn_flow = inner_flow.add({ type = "flow", direction = "horizontal" })
    btn_flow.style.top_margin = 4

    btn_flow.add({
        type = "button",
        name = "rift_rail_action_button",
        caption = "...", -- 稍后由事件更新
        style = "red_button", -- 默认样式
        enabled = (#dropdown_items > 0),
    })

    local station_exists = false
    if my_data.children then
        for _, child_data in pairs(my_data.children) do
            local child = child_data.entity
            if child and child.valid and child.name == "rift-rail-station" then
                station_exists = true
                break
            end
        end
    end

    btn_flow.add({
        type = "button",
        name = "rift_rail_open_station_button",
        caption = { "gui.rift-rail-btn-open-station" },
        enabled = station_exists,
    })

    -- 8. LTN 开关 (适配多对一启用条件)
    if script.active_mods["LogisticTrainNetwork"] then
        inner_flow.add({ type = "line", direction = "horizontal" })
        local ltn_flow = inner_flow.add({ type = "flow", direction = "horizontal" })
        ltn_flow.style.vertical_align = "center"
        ltn_flow.add({ type = "label", caption = { "gui.rift-rail-ltn-label" } })

        -- LTN 开关启用条件
        local ltn_btn_enabled = any_connection_exists

        ltn_flow.add({
            type = "switch",
            name = "rift_rail_ltn_switch",
            switch_state = my_data.ltn_enabled and "right" or "left",
            right_label_caption = { "gui.rift-rail-ltn-connected" },
            left_label_caption = { "gui.rift-rail-ltn-disconnected" },
            tooltip = { "gui.rift-rail-ltn-tooltip" },
            enabled = ltn_btn_enabled,
        })
    end

    -- 9. 远程预览 (适配 Exit 模式下的来源预览)
    inner_flow.add({ type = "line", direction = "horizontal" })

    -- 统一预览逻辑：直接使用下拉框选中的目标
    -- dropdown_ids 和 selected_idx 是我们在上面构建列表时生成的局部变量
    local preview_target_id = nil
    if dropdown_ids and selected_idx and selected_idx > 0 then
        preview_target_id = dropdown_ids[selected_idx]
    end

    -- 只要有目标 ID，就允许显示勾选框（无论是管理模式还是添加模式）
    if preview_target_id then
        inner_flow.add({
            type = "checkbox",
            name = "rift_rail_preview_check",
            state = player_settings.show_preview,
            caption = { "gui.rift-rail-preview-checkbox" },
        })
    end

    local tool_flow = inner_flow.add({ type = "flow", direction = "horizontal" })

    -- 传送玩家按钮
    tool_flow.add({
        type = "button",
        name = "rift_rail_tp_player_button",
        caption = { "gui.rift-rail-btn-player-teleport" },
    })

    -- 远程观察按钮
    -- 【修改】新的显示条件：只要选中的是已连接的伙伴，就显示
    if preview_target_id and dropdown_is_paired[selected_idx] == true then
        tool_flow.add({
            type = "button",
            name = "rift_rail_remote_view_button",
            caption = { "gui.rift-rail-btn-view" },
        })
    end

    -- 10. 摄像头预览窗口
    -- 只要有目标 ID 且 玩家勾选了预览，就显示
    if preview_target_id and player_settings.show_preview then
        local partner = State.get_portaldata_by_id(preview_target_id)
        if partner and partner.shell and partner.shell.valid then
            inner_flow.add({
                type = "label",
                name = "rift_rail_preview_title",
                style = "frame_title",
                caption = { "gui.rift-rail-preview-title", partner.name, partner.shell.surface.name },
            }).style.left_padding = 8

            local preview_frame = inner_flow.add({ type = "frame", style = "inside_shallow_frame" })
            preview_frame.style.minimal_width = 280
            preview_frame.style.minimal_height = 400
            preview_frame.style.horizontally_stretchable = true
            preview_frame.style.vertically_stretchable = true

            local cam = preview_frame.add({
                type = "camera",
                name = "rift_rail_preview_camera",
                position = partner.shell.position,
                surface_index = partner.shell.surface.index,
                zoom = 0.2,
            })
            cam.style.horizontally_stretchable = true
            cam.style.vertically_stretchable = true
        end
    end

    -- 手动初始化按钮状态
    -- 强制触发一次选择状态更新，以设置按钮的初始外观
    local fake_event = {
        element = dropdown,
        player_index = player.index, -- 把当前玩家的 index 加到 fake_event 中
    }
    GUI.handle_selection_state_changed(fake_event, frame)
end

-- =================================================================================
-- 事件处理
-- =================================================================================

function GUI.handle_click(event)
    if not (event.element and event.element.valid) then
        return
    end
    local player = game.get_player(event.player_index)
    local el_name = event.element.name

    local frame = player.gui.screen.rift_rail_main_frame
    if not (frame and frame.valid) then
        return
    end

    local unit_number = frame.tags.unit_number
    -- 使用 unit_number 直接查找，而不是查自定义 ID
    local my_data = State.get_portaldata_by_unit_number(unit_number)
    if not my_data then
        return
    end

    log_gui("[RiftRail:GUI] 点击: " .. el_name .. " (ID: " .. unit_number .. ")")

    -- 配对
    if el_name == "rift_rail_action_button" then
        local dropdown = find_element_recursively(frame, "rift_rail_target_dropdown")
        if not (dropdown and dropdown.selected_index > 0) then
            return
        end

        local selected_index = dropdown.selected_index
        local is_paired_map = dropdown.tags.is_paired_map
        local target_id = dropdown.tags.ids[selected_index]
        local status = is_paired_map[selected_index]

        -- 【修复】检查占位符
        if not target_id or target_id == 0 or status == "separator" then
            return
        end

        if status == true then
            -- 【断开连接】
            if my_data.mode == "entry" then
                -- 入口断开出口: source=自己, target=选中项
                remote.call("RiftRail", "unpair_portals_specific", player.index, my_data.id, target_id)
            else -- exit 或 neutral
                -- 出口“踢出”入口: source=选中项, target=自己
                remote.call("RiftRail", "unpair_portals_specific", player.index, target_id, my_data.id)
            end
        else
            -- 【配对连接】
            -- pair_portals 内部会自动判断谁是入口谁是出口，所以直接传就行
            remote.call("RiftRail", "pair_portals", player.index, my_data.id, target_id)
        end
    elseif el_name == "rift_rail_open_station_button" then
        local station = nil
        if my_data.children then
            for _, child_data in pairs(my_data.children) do
                local child = child_data.entity
                if child and child.valid and child.name == "rift-rail-station" then
                    station = child
                    break
                end
            end
        end

        if station then
            player.opened = station
        else
            player.print({ "messages.rift-rail-error-station-missing" })
        end

        -- 重命名
    elseif el_name == "rift_rail_rename_button" then
        -- 查找 name_flow
        local function find_name_flow(element)
            if element.name == "name_flow" then
                return element
            end
            for _, child in pairs(element.children) do
                local found = find_name_flow(child)
                if found then
                    return found
                end
            end
        end
        local name_flow = find_name_flow(frame)
        if name_flow then
            GUI.build_edit_name_flow(name_flow, my_data)
        end
    elseif el_name == "rift_rail_confirm_rename_button" then
        -- 查找 textfield (通过 name_flow 找)
        local function find_textfield(element)
            if element.name == "rift_rail_rename_textfield" then
                return element
            end
            for _, child in pairs(element.children) do
                local found = find_textfield(child)
                if found then
                    return found
                end
            end
        end
        local textfield = find_textfield(frame)
        if textfield then
            remote.call("RiftRail", "update_portal_name", player.index, my_data.id, textfield.text)
        end

        -- 设为默认出口
    elseif el_name == "rift_rail_set_default_button" then
        -- 1. 查找旁边的下拉菜单 (它是按钮的兄弟元素)
        -- 结构: Frame -> InnerFlow -> DropFlow -> [Dropdown, Button]
        local drop_flow = event.element.parent
        local dropdown = drop_flow["rift_rail_target_dropdown"]

        if dropdown and dropdown.selected_index > 0 and dropdown.tags and dropdown.tags.ids then
            local target_id = dropdown.tags.ids[dropdown.selected_index]
            if target_id then
                -- 调用 Logic 设置默认
                remote.call("RiftRail", "set_default_exit", player.index, my_data.unit_number, target_id)
            end
        end

        -- 玩家传送
    elseif el_name == "rift_rail_tp_player_button" then
        remote.call("RiftRail", "teleport_player", player.index, my_data.id)

        -- 远程观察
    elseif el_name == "rift_rail_remote_view_button" then
        -- 统一逻辑：目标永远是下拉框当前选中的那个
        local function find_dropdown(element)
            if element.type == "drop-down" and element.name == "rift_rail_target_dropdown" then
                return element
            end
            for _, child in pairs(element.children) do
                local found = find_dropdown(child)
                if found then
                    return found
                end
            end
        end
        local dropdown = find_dropdown(frame)
        local target_id = nil

        if dropdown and dropdown.selected_index > 0 and dropdown.tags and dropdown.tags.ids then
            target_id = dropdown.tags.ids[dropdown.selected_index]
        end

        if target_id then
            remote.call("RiftRail", "open_remote_view_by_target", player.index, target_id)
        end
    end
end

function GUI.handle_switch_state_changed(event)
    if not (event.element and event.element.valid) then
        return
    end

    local player = game.get_player(event.player_index)
    local el_name = event.element.name

    local frame = player.gui.screen.rift_rail_main_frame
    if not (frame and frame.valid) then
        return
    end

    local my_data = State.get_portaldata_by_unit_number(frame.tags.unit_number)
    if not my_data then
        return
    end

    if el_name == "rift_rail_mode_switch" then
        local state = event.element.switch_state
        local mode = "neutral"
        if state == "left" then
            mode = "entry"
        end
        if state == "right" then
            mode = "exit"
        end
        remote.call("RiftRail", "set_portal_mode", player.index, my_data.id, mode)
    elseif el_name == "rift_rail_ltn_switch" then
        local enabled = (event.element.switch_state == "right")
        remote.call("RiftRail", "set_ltn_enabled", player.index, my_data.id, enabled)
    end
end

function GUI.handle_checked_state_changed(event)
    if event.element.name == "rift_rail_preview_check" then
        local player = game.get_player(event.player_index)
        if storage.rift_rail_player_settings[player.index] then
            storage.rift_rail_player_settings[player.index].show_preview = event.element.state
            local frame = player.gui.screen.rift_rail_main_frame
            if frame then
                local my_data = State.get_portaldata_by_unit_number(frame.tags.unit_number)
                GUI.build_or_update(player, my_data.shell) -- 传入实体刷新
            end
        end
    end
end

function GUI.handle_confirmed(event)
    if not (event.element and event.element.valid) then
        return
    end
    if event.element.name == "rift_rail_rename_textfield" then
        local player = game.get_player(event.player_index)
        local frame = player.gui.screen.rift_rail_main_frame
        if not frame then
            return
        end

        -- 模拟点击确认
        local fake_event = {
            element = { name = "rift_rail_confirm_rename_button" },
            player_index = event.player_index,
        }
        GUI.handle_click(fake_event)
    end
end

-- 处理关闭事件
function GUI.handle_close(event)
    -- event.element 是刚刚被关闭的那个界面元素
    local element = event.element

    if element and element.valid and element.name == "rift_rail_main_frame" then
        log_gui("[RiftRail:GUI] 检测到关闭事件，销毁窗口。")
        element.destroy()
    end
end

function GUI.handle_selection_state_changed(event, frame_override)
    if not (event and event.element and event.element.valid) then
        return
    end
    if not frame_override and event.element.name ~= "rift_rail_target_dropdown" then
        return
    end

    local player = game.get_player(event.player_index)
    local frame = frame_override or player.gui.screen.rift_rail_main_frame
    if not (frame and frame.valid) then
        return
    end

    local dropdown = event.element
    local selected_index = dropdown.selected_index

    -- 【核心修复】如果选中了分隔符，则禁用所有相关按钮并立刻停止执行
    local is_paired_map = dropdown.tags.is_paired_map
    local status = is_paired_map and is_paired_map[selected_index]

    -- 检查状态是否有效 (既不是 nil 也不是占位符)
    if status == nil or status == "separator" then
        -- 查找所有可能需要禁用的按钮
        local action_button = find_element_recursively(frame, "rift_rail_action_button")
        local set_default_button = find_element_recursively(frame, "rift_rail_set_default_button")
        local remote_view_button = find_element_recursively(frame, "rift_rail_remote_view_button")

        -- 统一禁用
        if action_button then
            action_button.enabled = false
        end
        if set_default_button then
            set_default_button.enabled = false
        end
        if remote_view_button then
            remote_view_button.enabled = false
        end

        return -- 提前退出，不执行后续逻辑
    end

    -- 根据不同调用模式，选择不同的查找方式
    local action_button
    if frame_override then
        action_button = find_element_recursively(frame, "rift_rail_action_button")
    else
        action_button = find_element_recursively(frame, "rift_rail_action_button")
    end
    if not (action_button and action_button.valid) then
        return
    end

    -- 更新按钮状态
    if is_paired_map[selected_index] == true then
        action_button.caption = { "gui.rift-rail-btn-unpair" }
        action_button.style = "red_button"
    else
        action_button.caption = { "gui.rift-rail-btn-pair" }
        action_button.style = "button"
    end
    action_button.enabled = true

    -- 刷新预览
    local my_data = State.get_portaldata_by_unit_number(frame.tags.unit_number)
    if not my_data then
        return
    end

    local new_selected_id = dropdown.tags.ids[selected_index]
    my_data.last_selected_source_id = new_selected_id

    if not frame_override then
        local update_success = GUI.update_camera_preview(player, frame, new_selected_id)
        if not update_success then
            GUI.build_or_update(player, my_data.shell)
        end
    end
end

-- 只刷新摄像头预览区域
-- player: 玩家对象
-- frame: 主窗口frame对象
-- target_id: 目标portal id
-- partner_data: portal数据（可选，若未传则自动查找）
-- 只刷新摄像头属性，不销毁重建
-- 返回 true 表示更新成功，返回 false 表示没找到控件（需要外部重建）
function GUI.update_camera_preview(player, frame, target_id)
    if not (frame and frame.valid and target_id) then
        return false
    end

    -- 1. 定义递归查找函数（或者放在模块顶部作为通用函数）
    local function find_element_recursively(element, name)
        if element.name == name then
            return element
        end
        if element.children then
            for _, child in pairs(element.children) do
                local found = find_element_recursively(child, name)
                if found then
                    return found
                end
            end
        end
        return nil
    end

    -- 2. 查找 标题(Label) 和 摄像头(Camera)
    local title_label = find_element_recursively(frame, "rift_rail_preview_title")
    local camera_widget = find_element_recursively(frame, "rift_rail_preview_camera")

    -- 如果找不到控件（说明之前可能没勾选预览），返回 false，让外部去执行完整的 build_or_update
    if not (title_label and title_label.valid and camera_widget and camera_widget.valid) then
        return false
    end

    -- 3. 获取目标数据
    local partner = State.get_portaldata_by_id(target_id)
    if not (partner and partner.shell and partner.shell.valid) then
        -- 目标无效，这里也可以选择隐藏控件，但暂时不做处理
        return true
    end

    -- 4. 【核心】直接修改属性（无闪烁切换）

    -- 修改标题文字
    title_label.caption = { "gui.rift-rail-preview-title", partner.name, partner.shell.surface.name }

    -- 修改摄像头视角 (Factorio 引擎会自动处理跨地表切换)
    camera_widget.position = partner.shell.position
    camera_widget.surface_index = partner.shell.surface.index
    -- 如果需要，也可以重置缩放
    -- camera_widget.zoom = 0.2

    return true
end

return GUI
