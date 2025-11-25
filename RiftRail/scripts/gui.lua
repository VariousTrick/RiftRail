-- scripts/gui.lua
-- 【Rift Rail - GUI 模块 v1.0 正式版】
-- 功能：基于 Container 的相对 GUI，实现完美的打开/关闭体验
-- 复刻自传送门 Mod 逻辑

local GUI = {}

local State = nil
local log_debug = function() end

function GUI.init(dependencies)
    State = dependencies.State
    log_debug = dependencies.log_debug
    if log_debug then
        log_debug("GUI 模块初始化完成 (Relative Mode)。")
    end
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
    local display_caption = icon_str .. " " .. my_data.name .. " (ID: " .. my_data.id .. ")"

    -- 3. 创建 Label
    parent_flow.add({ type = "label", caption = display_caption, style = "bold_label" })

    parent_flow.add({
        type = "sprite-button",
        name = "rift_rail_rename_button",
        sprite = "utility/rename_icon",
        tooltip = { "gui.rift-rail-rename-tooltip" },
        style = "tool_button"
    })
end

-- 构建编辑名称
function GUI.build_edit_name_flow(parent_flow, my_data)
    parent_flow.clear()

    -- 1. 确定初始文本 (默认图标 + 名字)
    local current_icon_str = "[item=rift-rail-placer] " -- 默认预填
    if my_data.icon and my_data.icon.type and my_data.icon.name then
        current_icon_str = "[" .. my_data.icon.type .. "=" .. my_data.icon.name .. "] "
    end

    local textfield = parent_flow.add({
        type = "textfield",
        name = "rift_rail_rename_textfield",
        text = current_icon_str .. my_data.name,
        icon_selector = true,
        handler = "on_gui_confirmed"
    })
    textfield.style.width = 200
    textfield.focus()
    textfield.select_all()

    parent_flow.add({
        type = "sprite-button",
        name = "rift_rail_confirm_rename_button",
        sprite = "utility/check_mark",
        style = "tool_button_green"
    })
end

-- =================================================================================
-- 主界面构建
-- =================================================================================

function GUI.build_or_update(player, entity)
    if not (player and entity and entity.valid) then return end

    -- 1. 获取数据
    local my_data = State.get_struct(entity)
    if not my_data then
        log_debug("GUI 错误: 无法找到实体关联的数据。")
        return
    end

    -- 2. 初始化玩家设置
    if not storage.rift_rail_player_settings then storage.rift_rail_player_settings = {} end
    if not storage.rift_rail_player_settings[player.index] then
        storage.rift_rail_player_settings[player.index] = { show_preview = true }
    end
    local player_settings = storage.rift_rail_player_settings[player.index]

    -- 3. 创建/清理 GUI
    -- [核心] 使用 relative 容器，而不是 screen
    local gui = player.gui.relative
    if gui.rift_rail_main_frame then gui.rift_rail_main_frame.destroy() end

    -- [核心] 锚定到箱子界面 (container_gui)
    -- [修正] 增加 names 字段，指定只挂载到 "rift-rail-core" 实体上
    -- 这样打开普通箱子时，这个 GUI 就不会出现
    local anchor = {
        gui = defines.relative_gui_type.container_gui,
        position = defines.relative_gui_position.right,
        names = { "rift-rail-core" } -- <=== 加上这一行！
    }

    -- [修改] 动态标题栏 (逻辑修正：如果没有自定义图标，强制显示默认图标)

    -- 1. 预设默认图标
    local title_icon = "[item=rift-rail-placer]"

    -- 2. 如果有自定义图标，则覆盖默认图标
    if my_data.icon and my_data.icon.type and my_data.icon.name then
        title_icon = "[" .. my_data.icon.type .. "=" .. my_data.icon.name .. "]"
    end

    -- 3. 拼接最终标题: [图标] 名字 (ID: 123)
    local title_caption = title_icon .. " " .. my_data.name .. " (ID: " .. my_data.id .. ")"

    local frame = gui.add({
        type = "frame",
        name = "rift_rail_main_frame",
        direction = "vertical",
        anchor = anchor,
        caption = title_caption -- 使用带图标的标题
    })
    -- 存储 ID 用于事件处理
    frame.tags = { unit_number = my_data.unit_number }

    local inner_flow = frame.add({ type = "flow", direction = "vertical" })
    inner_flow.style.padding = 8

    -- 4. 名称区域
    local name_flow = inner_flow.add({ type = "flow", name = "name_flow", direction = "horizontal" })
    name_flow.style.vertical_align = "center"
    name_flow.style.bottom_margin = 8
    GUI.build_display_name_flow(name_flow, my_data)

    -- 5. 模式切换 (三态开关)
    local switch_state = "none"
    if my_data.mode == "entry" then switch_state = "left" end
    if my_data.mode == "exit" then switch_state = "right" end

    inner_flow.add({ type = "label", caption = { "gui.rift-rail-mode-label" } })
    local mode_switch = inner_flow.add({
        type = "switch",
        name = "rift_rail_mode_switch",
        switch_state = switch_state,
        allow_none_state = true,
        left_label_caption = { "gui.rift-rail-mode-entry" },
        right_label_caption = { "gui.rift-rail-mode-exit" },
        tooltip = (switch_state == "left" and { "gui.rift-rail-mode-tooltip-left" }) or
            (switch_state == "right" and { "gui.rift-rail-mode-tooltip-right" }) or
            { "gui.rift-rail-mode-tooltip-none" }
    })
    mode_switch.style.bottom_margin = 12

    -- 6. 连接状态
    inner_flow.add({ type = "line", direction = "horizontal" })
    local status_flow = inner_flow.add({ type = "flow", direction = "vertical" })
    status_flow.add({ type = "label", caption = { "gui.rift-rail-status-label" } })

    if my_data.paired_to_id then
        local partner = State.get_struct_by_id(my_data.paired_to_id)
        if partner then
            status_flow.add({
                type = "label",
                caption = { "gui.rift-rail-status-paired", partner.name, partner.id, partner.surface.name },
                style = "bold_label"
            })
        else
            status_flow.add({ type = "label", caption = "Error: Partner data missing", style = "bold_red_label" })
        end
    else
        status_flow.add({ type = "label", caption = { "gui.rift-rail-status-unpaired" }, style = "bold_label" })
    end
    status_flow.style.bottom_margin = 12

    -- 7. 配对控制
    inner_flow.add({ type = "label", caption = { "gui.rift-rail-target-selector" } })
    local dropdown = inner_flow.add({ type = "drop-down", name = "rift_rail_target_dropdown" })

    -- 填充列表 & 自动选中
    local dropdown_items = {}
    local selected_idx = 0
    local all_portals = State.get_all_structs()

    for _, p_data in pairs(all_portals) do
        -- 排除自己，排除已配对的(除非是当前配对对象)
        if p_data.id ~= my_data.id and (not p_data.paired_to_id or p_data.paired_to_id == my_data.id) then
            local icon_str = ""
            if p_data.icon and p_data.icon.name then
                icon_str = "[" .. p_data.icon.type .. "=" .. p_data.icon.name .. "] "
            end
            local mode_str = "[?]"
            if p_data.mode == "entry" then mode_str = "[入口]" end
            if p_data.mode == "exit" then mode_str = "[出口]" end
            if p_data.mode == "neutral" then mode_str = "[待机]" end

            local item_text = icon_str ..
                p_data.name .. " (ID:" .. p_data.id .. ") " .. mode_str .. " [" .. p_data.surface.name .. "]"
            table.insert(dropdown_items, item_text)

            -- [修复] 如果这个就是当前配对的对象，记录索引
            if my_data.paired_to_id == p_data.id then
                selected_idx = #dropdown_items
            end
        end
    end
    dropdown.items = dropdown_items
    -- [修复] 设置选中项
    if selected_idx > 0 then
        dropdown.selected_index = selected_idx
    end
    dropdown.style.width = 280

    -- 按钮组
    local btn_flow = inner_flow.add({ type = "flow", direction = "horizontal" })
    btn_flow.style.top_margin = 4

    if my_data.paired_to_id then
        btn_flow.add({
            type = "button",
            name = "rift_rail_unpair_button",
            caption = { "gui.rift-rail-btn-unpair" },
            style = "red_button"
        })
    else
        local pair_btn = btn_flow.add({
            type = "button",
            name = "rift_rail_pair_button",
            caption = { "gui.rift-rail-btn-pair" }
        })
        if #dropdown_items == 0 then pair_btn.enabled = false end
    end

    -- 8. Cybersyn 开关 (仅当安装了 Cybersyn 模组时显示)
    -- [新增] 加入这个 if 判断
    if script.active_mods["cybersyn"] then
        inner_flow.add({ type = "line", direction = "horizontal" })
        local cs_flow = inner_flow.add({ type = "flow", direction = "horizontal" })
        cs_flow.style.vertical_align = "center"

        cs_flow.add({ type = "label", caption = { "gui.rift-rail-cybersyn-label" } })
        cs_flow.add({
            type = "switch",
            name = "rift_rail_cybersyn_switch",
            switch_state = my_data.cybersyn_enabled and "right" or "left",
            right_label_caption = { "gui.rift-rail-cybersyn-connected" },
            left_label_caption = { "gui.rift-rail-cybersyn-disconnected" },
            tooltip = { "gui.rift-rail-cybersyn-tooltip" },
            enabled = (my_data.paired_to_id ~= nil)
        })
    end
    -- [新增] if 判断结束

    -- 9. 远程预览
    inner_flow.add({ type = "line", direction = "horizontal" })

    -- [修改] 先创建勾选框 (直接加在垂直的 inner_flow 里)
    if my_data.paired_to_id then
        inner_flow.add({
            type = "checkbox",
            name = "rift_rail_preview_check",
            state = player_settings.show_preview,
            caption = { "gui.rift-rail-preview-checkbox" }
        })
    end

    -- [修改] 再创建按钮容器 (水平 flow)
    local tool_flow = inner_flow.add({ type = "flow", direction = "horizontal" })

    -- 传送玩家按钮
    tool_flow.add({
        type = "button",
        name = "rift_rail_tp_player_button",
        caption = { "gui.rift-rail-btn-player-teleport" },
        -- [修改] 删除下面这一行，让按钮永远可用
        -- enabled = (my_data.paired_to_id ~= nil)
    })

    -- 远程观察按钮
    if my_data.paired_to_id then
        tool_flow.add({
            type = "button",
            name = "rift_rail_remote_view_button",
            caption = { "gui.rift-rail-btn-view" }
        })
    end

    -- 10. 摄像头预览窗口 (修复版：照搬传送门布局)
    if my_data.paired_to_id and player_settings.show_preview then
        local partner = State.get_struct_by_id(my_data.paired_to_id)
        if partner and partner.shell and partner.shell.valid then
            -- [新增] 标题 Label
            inner_flow.add({
                type = "label",
                style = "frame_title",
                caption = "远程预览: " .. partner.name .. " [" .. partner.shell.surface.name .. "]"
            }).style.left_padding = 8

            -- [修正] 预览框 (inside_shallow_frame) + 拉伸属性
            local preview_frame = inner_flow.add({ type = "frame", style = "inside_shallow_frame" })
            -- 设置最小尺寸，防止太小
            preview_frame.style.minimal_width = 280
            preview_frame.style.minimal_height = 200
            -- 开启拉伸，填满剩余空间
            preview_frame.style.horizontally_stretchable = true
            preview_frame.style.vertically_stretchable = true

            -- [修正] 摄像头
            local cam = preview_frame.add({
                type = "camera",
                position = partner.shell.position,
                surface_index = partner.shell.surface.index,
                zoom = 0.2
            })
            -- 摄像头也要开启拉伸
            cam.style.horizontally_stretchable = true
            cam.style.vertically_stretchable = true
        end
    end
end

-- =================================================================================
-- 事件处理
-- =================================================================================

function GUI.handle_click(event)
    if not (event.element and event.element.valid) then return end
    local player = game.get_player(event.player_index)
    local el_name = event.element.name

    -- [核心] 查找 relative GUI
    local frame = player.gui.relative.rift_rail_main_frame
    if not (frame and frame.valid) then return end

    local unit_number = frame.tags.unit_number
    -- [修正] 使用 unit_number 直接查找，而不是查自定义 ID
    local my_data = State.get_struct_by_unit_number(unit_number)
    if not my_data then return end

    log_debug("GUI 点击: " .. el_name .. " (ID: " .. unit_number .. ")")

    -- 配对
    if el_name == "rift_rail_pair_button" then
        -- 递归查找 dropdown (根据结构)
        -- Frame -> InnerFlow -> InnerFlow (配对区域) -> Dropdown
        -- 建议直接在构建时给 flow 命名，或者这里简单遍历查找
        local dropdown = nil
        -- 简单遍历查找 dropdown 元素
        local function find_dropdown(element)
            if element.type == "drop-down" and element.name == "rift_rail_target_dropdown" then return element end
            for _, child in pairs(element.children) do
                local found = find_dropdown(child)
                if found then return found end
            end
        end
        dropdown = find_dropdown(frame)

        if dropdown and dropdown.selected_index > 0 then
            local selected_str = dropdown.items[dropdown.selected_index]
            local target_id = tonumber(string.match(selected_str, "ID:(%d+)"))
            if target_id then
                remote.call("RiftRail", "pair_portals", player.index, my_data.id, target_id)
            end
        end

        -- 解绑
    elseif el_name == "rift_rail_unpair_button" then
        remote.call("RiftRail", "unpair_portals", player.index, my_data.id)

        -- 重命名
    elseif el_name == "rift_rail_rename_button" then
        -- 查找 name_flow
        local function find_name_flow(element)
            if element.name == "name_flow" then return element end
            for _, child in pairs(element.children) do
                local found = find_name_flow(child)
                if found then return found end
            end
        end
        local name_flow = find_name_flow(frame)
        if name_flow then GUI.build_edit_name_flow(name_flow, my_data) end
    elseif el_name == "rift_rail_confirm_rename_button" then
        -- 查找 textfield (通过 name_flow 找)
        local function find_textfield(element)
            if element.name == "rift_rail_rename_textfield" then return element end
            for _, child in pairs(element.children) do
                local found = find_textfield(child)
                if found then return found end
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
        remote.call("RiftRail", "open_remote_view", player.index, my_data.id)
    end
end

function GUI.handle_switch_state_changed(event)
    if not (event.element and event.element.valid) then return end
    local player = game.get_player(event.player_index)
    local el_name = event.element.name

    local frame = player.gui.relative.rift_rail_main_frame
    if not (frame and frame.valid) then return end
    -- [修正]
    local my_data = State.get_struct_by_unit_number(frame.tags.unit_number)
    if not my_data then return end

    if el_name == "rift_rail_mode_switch" then
        local state = event.element.switch_state
        local mode = "neutral"
        if state == "left" then mode = "entry" end
        if state == "right" then mode = "exit" end
        remote.call("RiftRail", "set_portal_mode", player.index, my_data.id, mode)
    elseif el_name == "rift_rail_cybersyn_switch" then
        local enabled = (event.element.switch_state == "right")
        remote.call("RiftRail", "set_cybersyn_enabled", player.index, my_data.id, enabled)
    end
end

function GUI.handle_checked_state_changed(event)
    if event.element.name == "rift_rail_preview_check" then
        local player = game.get_player(event.player_index)
        if storage.rift_rail_player_settings[player.index] then
            storage.rift_rail_player_settings[player.index].show_preview = event.element.state
            local frame = player.gui.relative.rift_rail_main_frame
            if frame then
                -- [修正]
                local my_data = State.get_struct_by_unit_number(frame.tags.unit_number)
                GUI.build_or_update(player, my_data.shell) -- 传入实体刷新
            end
        end
    end
end

function GUI.handle_confirmed(event)
    if not (event.element and event.element.valid) then return end
    if event.element.name == "rift_rail_rename_textfield" then
        local player = game.get_player(event.player_index)
        local frame = player.gui.relative.rift_rail_main_frame
        if not frame then return end

        -- 模拟点击确认
        local fake_event = {
            element = { name = "rift_rail_confirm_rename_button" }, -- 简化处理，直接传名字匹配
            player_index = event.player_index
        }
        GUI.handle_click(fake_event)
    end
end

return GUI
