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

function GUI.init(dependencies)
    State = dependencies.State
    log_debug = dependencies.log_debug
    log_gui("[RiftRail:GUI] 模块初始化完成 (Relative Mode)。")
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

    -- [多对多改造] 确定当前视图模式 (管理/添加)
    local view_mode = "management" -- 默认为管理模式
    if player.gui.screen.rift_rail_main_frame and player.gui.screen.rift_rail_main_frame.valid and player.gui.screen.rift_rail_main_frame.tags.view_mode then
        view_mode = player.gui.screen.rift_rail_main_frame.tags.view_mode
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
        "",                               -- 空字符串开头，表示这是一个拼接列表
        title_icon,                       -- 图标字符串 "[item=...]"
        " ",                              -- 空格
        { "entity-name.rift-rail-core" }, -- 读取 locale 中的中文名
        " (ID: " .. my_data.id .. ")",    -- 后面拼接 ID
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
    -- [多对多改造] 同时保存 unit_number 和 view_mode
    frame.tags = { unit_number = my_data.unit_number, view_mode = view_mode }

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
        tooltip = (switch_state == "left" and { "gui.rift-rail-mode-tooltip-left" }) or
        (switch_state == "right" and { "gui.rift-rail-mode-tooltip-right" }) or { "gui.rift-rail-mode-tooltip-none" },
    })
    mode_switch.style.bottom_margin = 12

    -- 6. 连接状态
    inner_flow.add({ type = "line", direction = "horizontal" })
    local status_flow = inner_flow.add({ type = "flow", direction = "vertical" })
    status_flow.add({ type = "label", caption = { "gui.rift-rail-status-label" } })

    -- [多对多改造] 重构连接状态显示
    if my_data.mode == "entry" then
        local count = 0
        if my_data.target_ids then
            for _ in pairs(my_data.target_ids) do
                count = count + 1
            end
        end
        if count > 0 then
            status_flow.add({
                type = "label",
                caption = { "gui.rift-rail-status-connected-targets", count }, -- 新增本地化 key
                style = "bold_label",
            })
        else
            status_flow.add({ type = "label", caption = { "gui.rift-rail-status-unpaired" }, style = "bold_label" })
        end
    elseif my_data.mode == "exit" then
        local count = 0
        if my_data.source_ids then
            for _ in pairs(my_data.source_ids) do
                count = count + 1
            end
        end
        status_flow.add({
            type = "label",
            caption = { "gui.rift-rail-status-connected-sources", count },
            style = "bold_label",
        })
    else -- neutral
        status_flow.add({ type = "label", caption = { "gui.rift-rail-status-unpaired" }, style = "bold_label" })
    end
    status_flow.style.bottom_margin = 12

    -- 7. 连接控制 (下拉框与按钮)
    --[[ local selector_caption = { "gui.rift-rail-target-selector" }
    if my_data.mode == "exit" then
        selector_caption = { "gui.rift-rail-source-selector" }
    end ]]
    -- [多对多改造] 动态标题与“添加”按钮
    local selector_flow = inner_flow.add({ type = "flow", direction = "horizontal" })
    selector_flow.style.vertical_align = "center"

    local selector_caption_key = "gui.rift-rail-target-selector" -- 默认
    if my_data.mode == "exit" then
        selector_caption_key = "gui.rift-rail-source-selector"
    end
    -- 在添加模式下，强制显示特定标题
    if view_mode == "addition" then
        selector_caption_key = "gui.rift-rail-add-new-connection" -- 新增本地化 key
    end

    selector_flow.add({ type = "label", caption = { selector_caption_key } })

    -- 仅在管理模式下显示“添加”或“取消”按钮
    if view_mode == "management" then
        selector_flow.add({
            type = "sprite-button",
            name = "rift_rail_enter_add_mode_button",
            sprite = "utility/add",
            tooltip = { "gui.rift-rail-tooltip-add-connection" }, -- 新增本地化 key
            style = "tool_button",
        })
    else -- addition mode
        selector_flow.add({
            type = "sprite-button",
            name = "rift_rail_cancel_add_mode_button",
            sprite = "utility/close",
            tooltip = { "gui.rift-rail-tooltip-cancel-add" }, -- 新增本地化 key
            style = "tool_button_red",
        })
    end

    local dropdown = inner_flow.add({ type = "drop-down", name = "rift_rail_target_dropdown" })
    local dropdown_items = {}
    local dropdown_ids = {}
    local selected_idx = 0

    local all_portals = State.get_all_portaldatas()

    if view_mode == "management" then
        -- ==================== 管理模式: 显示已连接列表 ====================
        local connected_ids_map = {}
        if my_data.mode == "entry" then
            connected_ids_map = my_data.target_ids or {}
        elseif my_data.mode == "exit" then
            connected_ids_map = my_data.source_ids or {}
        end

        for id, _ in pairs(connected_ids_map) do
            local p_data = State.get_portaldata_by_id(id)
            if p_data then
                -- 构建列表项文本
                local icon_str = ""
                if p_data.icon and p_data.icon.name then
                    icon_str = "[" .. p_data.icon.type .. "=" .. p_data.icon.name .. "] "
                end
                local item_text = { "", icon_str, p_data.name, " (ID:", p_data.id, ") [", p_data.surface.name, "]" }
                table.insert(dropdown_items, item_text)
                table.insert(dropdown_ids, id)
            end
        end
        -- 在管理模式下，恢复上次选择
        if #dropdown_items > 0 then
            if my_data.last_selected_source_id then
                for i, id in ipairs(dropdown_ids) do
                    if id == my_data.last_selected_source_id then
                        selected_idx = i
                        break
                    end
                end
            end
            if selected_idx == 0 then
                selected_idx = 1
            end
        end
    else -- view_mode == "addition"
        -- ==================== 添加模式: 显示未连接列表 ====================
        local existing_connections = {}
        if my_data.mode == "entry" then
            existing_connections = my_data.target_ids or {}
        elseif my_data.mode == "exit" then
            existing_connections = my_data.source_ids or {}
        end

        for _, p_data in pairs(all_portals) do
            -- 筛选条件：不是自己，尚未连接，且模式合法
            if p_data.id ~= my_data.id and not existing_connections[p_data.id] then
                if (my_data.mode == "entry" and p_data.mode ~= "entry") or (my_data.mode == "exit" and p_data.mode ~= "exit") or (my_data.mode == "neutral") then -- 中立模式可以连接任何非自身的
                    -- 构建列表项文本
                    local icon_str = ""
                    if p_data.icon and p_data.icon.name then
                        icon_str = "[" .. p_data.icon.type .. "=" .. p_data.icon.name .. "] "
                    end
                    local item_text = { "", icon_str, p_data.name, " (ID:", p_data.id, ") [", p_data.surface.name, "]" }
                    table.insert(dropdown_items, item_text)
                    table.insert(dropdown_ids, p_data.id)
                end
            end
        end
        if #dropdown_items > 0 then
            selected_idx = 1
        end
    end

    dropdown.items = dropdown_items
    -- [重要] tags 中除了 ids，还要存入 my_data.id，方便事件处理
    dropdown.tags = { ids = dropdown_ids, self_id = my_data.id }
    if selected_idx > 0 then
        dropdown.selected_index = selected_idx
    end
    dropdown.style.width = 280

    -- [多对多改造] 动态按钮组
    local btn_flow = inner_flow.add({ type = "flow", direction = "horizontal" })
    btn_flow.style.top_margin = 4

    if view_mode == "management" then
        btn_flow.add({
            type = "button",
            name = "rift_rail_unpair_button",
            caption = { "gui.rift-rail-btn-unpair" },
            style = "red_button",
            enabled = (#dropdown_items > 0),
            tooltip = { "gui.rift-rail-tooltip-unpair-selected" }, -- 新增本地化 key
        })
    else                                                           -- view_mode == "addition"
        btn_flow.add({
            type = "button",
            name = "rift_rail_pair_button",
            caption = { "gui.rift-rail-btn-pair" },
            --[[ style = "confirm_button", -- 使用绿色确认按钮样式 ]]
            enabled = (#dropdown_items > 0),
        })
    end

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

    -- 8. Cybersyn 开关 (适配多对一启用条件)
    if script.active_mods["cybersyn"] and script.active_mods["space-exploration"] then
        inner_flow.add({ type = "line", direction = "horizontal" })
        local cs_flow = inner_flow.add({ type = "flow", direction = "horizontal" })
        cs_flow.style.vertical_align = "center"
        cs_flow.add({ type = "label", caption = { "gui.rift-rail-cybersyn-label" } })

        -- [多对多改造] 判定条件更新：检查 target_ids
        local cs_enabled = (my_data.mode == "entry" and my_data.target_ids and next(my_data.target_ids)) or
        (my_data.mode == "exit" and my_data.source_ids and next(my_data.source_ids))

        cs_flow.add({
            type = "switch",
            name = "rift_rail_cybersyn_switch",
            switch_state = my_data.cybersyn_enabled and "right" or "left",
            right_label_caption = { "gui.rift-rail-cybersyn-connected" },
            left_label_caption = { "gui.rift-rail-cybersyn-disconnected" },
            tooltip = { "gui.rift-rail-cybersyn-tooltip" },
            enabled = cs_enabled,
        })
    end

    -- 8b. LTN 开关 (适配多对一启用条件)
    if script.active_mods["LogisticTrainNetwork"] then
        inner_flow.add({ type = "line", direction = "horizontal" })
        local ltn_flow = inner_flow.add({ type = "flow", direction = "horizontal" })
        ltn_flow.style.vertical_align = "center"
        ltn_flow.add({ type = "label", caption = { "gui.rift-rail-ltn-label" } })

        local ltn_btn_enabled = (my_data.mode == "entry" and my_data.target_ids and next(my_data.target_ids)) or
        (my_data.mode == "exit" and my_data.source_ids and next(my_data.source_ids))

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

    -- network_id 输入 (仅 LTN)
    -- [已注释：默认使用 -1，不再提供手动设置]
    --[[ if script.active_mods["LogisticTrainNetwork"] then
        local ltn_net_flow = inner_flow.add({ type = "flow", direction = "horizontal" })
        ltn_net_flow.style.vertical_align = "center"
        ltn_net_flow.add({ type = "label", caption = { "gui.rift-rail-ltn-network-label" } })
        local nid_text = tostring(my_data.ltn_network_id or -1)
        local nid_field = ltn_net_flow.add({
            type = "textfield",
            name = "rift_rail_ltn_network_id",
            text = nid_text,
            numeric = true,
            allow_negative = true,
            tooltip = { "gui.rift-rail-ltn-network-tooltip" },
        })
        nid_field.style.width = 80

        local ltn_apply_enabled = (my_data.mode == "entry" and my_data.target_ids and next(my_data.target_ids)) or
        (my_data.mode == "exit" and my_data.source_ids and next(my_data.source_ids))

        ltn_net_flow.add({
            type = "button",
            name = "rift_rail_ltn_apply_network",
            caption = { "gui.rift-rail-ltn-apply-network" },
            tooltip = { "gui.rift-rail-ltn-network-tooltip" },
            enabled = ltn_apply_enabled,
        })
    end ]]

    -- 9. 远程预览 (适配 Exit 模式下的来源预览)
    inner_flow.add({ type = "line", direction = "horizontal" })

    -- [多对多改造] 统一预览逻辑：直接使用下拉框选中的目标
    -- 无论 Entry/Exit，也无论 Management/Addition 模式，只要下拉框里有选中的 ID，就预览它
    -- dropdown_ids 和 selected_idx 是我们在上面构建列表时生成的局部变量
    local preview_target_id = nil
    if dropdown_ids and selected_idx and selected_idx > 0 then
        preview_target_id = dropdown_ids[selected_idx]
    end

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
    if preview_target_id then
        tool_flow.add({
            type = "button",
            name = "rift_rail_remote_view_button",
            caption = { "gui.rift-rail-btn-view" },
        })
    end

    -- 10. 摄像头预览窗口
    if preview_target_id and player_settings.show_preview then
        local partner = State.get_portaldata_by_id(preview_target_id)
        if partner and partner.shell and partner.shell.valid then
            inner_flow.add({
                type = "label",
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
                position = partner.shell.position,
                surface_index = partner.shell.surface.index,
                zoom = 0.2,
            })
            cam.style.horizontally_stretchable = true
            cam.style.vertically_stretchable = true
        end
    end
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

    -- [多对多改造] 视图模式切换 (修正 tags 写回逻辑)
    if el_name == "rift_rail_enter_add_mode_button" then
        local tags = frame.tags
        tags.view_mode = "addition"
        frame.tags = tags -- 必须显式写回
        GUI.build_or_update(player, my_data.shell)
        return
    elseif el_name == "rift_rail_cancel_add_mode_button" then
        local tags = frame.tags
        tags.view_mode = "management"
        frame.tags = tags -- 必须显式写回
        GUI.build_or_update(player, my_data.shell)
        return
    end

    -- 配对
    if el_name == "rift_rail_pair_button" then
        -- 递归查找 dropdown (根据结构)
        -- Frame -> InnerFlow -> InnerFlow (配对区域) -> Dropdown
        -- 建议直接在构建时给 flow 命名，或者这里简单遍历查找
        local dropdown = nil
        -- 简单遍历查找 dropdown 元素
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
        dropdown = find_dropdown(frame)

        if dropdown and dropdown.selected_index > 0 then
            -- 直接从 tags 读取 ID (安全且支持本地化)
            local target_id = nil
            if dropdown.tags and dropdown.tags.ids then
                target_id = dropdown.tags.ids[dropdown.selected_index]
            end

            if target_id then
                remote.call("RiftRail", "pair_portals", player.index, my_data.id, target_id)
            end
        end

        -- 解绑 / 断开 (Exit 模式下为踢出指定来源，或 Shift 点击清空)
    elseif el_name == "rift_rail_unpair_button" then
        -- [多对多改造] “断开”现在总是断开下拉框中选中的那个
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

        if dropdown and dropdown.selected_index > 0 and dropdown.tags and dropdown.tags.ids then
            local target_to_unpair_id = dropdown.tags.ids[dropdown.selected_index]
            if target_to_unpair_id then
                -- 根据当前建筑模式决定谁是“源”，谁是“目标”
                if my_data.mode == "entry" then
                    -- 入口断开出口: source=自己, target=选中项
                    remote.call("RiftRail", "unpair_portals_specific", player.index, my_data.id, target_to_unpair_id)
                else -- exit 或 neutral
                    -- 出口“踢出”入口: source=选中项, target=自己
                    remote.call("RiftRail", "unpair_portals_specific", player.index, target_to_unpair_id, my_data.id)
                end
            end
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

        -- 玩家传送
    elseif el_name == "rift_rail_tp_player_button" then
        remote.call("RiftRail", "teleport_player", player.index, my_data.id)

        -- 远程观察
    elseif el_name == "rift_rail_remote_view_button" then
        -- [多对多改造] 统一逻辑：目标永远是下拉框当前选中的那个
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

        -- 应用 LTN Network ID
        --[[ elseif el_name == "rift_rail_ltn_apply_network" then
        -- 查找 network_id 文本框
        local function find_field(element)
            if element.name == "rift_rail_ltn_network_id" then
                return element
            end
            for _, child in pairs(element.children) do
                local found = find_field(child)
                if found then
                    return found
                end
            end
        end
        local field = find_field(frame)
        if field and field.text then
            local val = tonumber(field.text) or -1
            my_data.ltn_network_id = val
            -- 若当前已连接，则刷新连接以应用新的 network_id
            if my_data.paired_to_id and my_data.ltn_enabled then
                remote.call("RiftRail", "set_ltn_enabled", player.index, my_data.id, false)
                remote.call("RiftRail", "set_ltn_enabled", player.index, my_data.id, true)
            end
            GUI.build_or_update(player, my_data.shell)
        end ]]
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
    elseif el_name == "rift_rail_cybersyn_switch" then
        local enabled = (event.element.switch_state == "right")
        remote.call("RiftRail", "set_cybersyn_enabled", player.index, my_data.id, enabled)
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
            element = { name = "rift_rail_confirm_rename_button" }, -- 简化处理，直接传名字匹配
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

function GUI.handle_selection_state_changed(event)
    if not (event.element and event.element.valid) then
        return
    end

    -- 只关心我们的下拉框
    if event.element.name ~= "rift_rail_target_dropdown" then
        return
    end

    local player = game.get_player(event.player_index)
    local frame = player.gui.screen.rift_rail_main_frame
    if not (frame and frame.valid) then
        return
    end

    -- 新增“智能判断”逻辑
    -- 1. 定义一个辅助函数，用于在 GUI 元素中递归查找指定名称的子元素
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

    -- 2. 在当前窗口中查找是否存在“配对”按钮
    local pair_button = find_element_recursively(frame, "rift_rail_pair_button")

    -- 3. 如果找到了“配对”按钮，说明当前是“配对意图”，应立即停止执行，不做任何事
    if pair_button then
        return
    end

    -- 只有在找不到“配对”按钮时（即“浏览意图”），才执行以下代码

    local my_data = State.get_portaldata_by_unit_number(frame.tags.unit_number)
    if not my_data then
        return
    end

    local dropdown = event.element
    local selected_index = dropdown.selected_index
    local new_selected_id = nil

    if selected_index > 0 and dropdown.tags and dropdown.tags.ids then
        new_selected_id = dropdown.tags.ids[selected_index]
    end

    my_data.last_selected_source_id = new_selected_id

    GUI.build_or_update(player, my_data.shell)
end

return GUI
