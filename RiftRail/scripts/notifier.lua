-- scripts/notifier.lua
-- 【Rift Rail - 通知管理中心】
-- 作用：统一管理跨地表物流通知（LTN & Cybersyn）、GPS 坐标超链接拼装、多对多聚合摘要及个人设置过滤。

local Notifier = {}
local State = require("scripts.state")

function Notifier.init(dependencies)
    if dependencies and dependencies.State then
        State = dependencies.State
    end
end

-- ============================================================================
-- 1. 辅助函数：显示名称与 GPS 链接
-- ============================================================================

local function build_display_name(portaldata)
    local richtext = ""
    if portaldata and portaldata.icon and portaldata.icon.type and portaldata.icon.name then
        richtext = "[" .. portaldata.icon.type .. "=" .. portaldata.icon.name .. "] "
    end
    if portaldata then
        richtext = richtext .. (portaldata.name or "RiftRail")
    end
    return richtext
end

local function get_portal_gps(portaldata)
    if portaldata and portaldata.shell and portaldata.shell.valid then
        local pos = portaldata.shell.position
        local surface = portaldata.shell.surface.name
        return "[gps=" .. pos.x .. "," .. pos.y .. "," .. surface .. "]"
    end
    return ""
end

-- 供外部模块可选调用
Notifier.build_display_name = build_display_name
Notifier.get_portal_gps = get_portal_gps

-- ============================================================================
-- 2. 设置过滤与消息分发
-- ============================================================================

local function should_notify_player(p)
    if not (p and p.valid) then
        return false
    end
    local setting = settings.get_player_settings(p)["rift-rail-show-logistics-notifications"]
    return setting and setting.value
end

local function send_notification(player, msg)
    if not msg then
        return
    end
    if player then
        if should_notify_player(player) then
            player.print(msg)
        end
    else
        for _, p in pairs(game.connected_players) do
            if should_notify_player(p) then
                p.print(msg)
            end
        end
    end
end

-- ============================================================================
-- 3. 伙伴收集与状态拆分
-- ============================================================================

--- 收集指定传送门的所有关联伙伴，并按物流服务开启状态拆分为 active 与 inactive 组
---@param portaldata table
---@param service_key string "ltn_enabled" | "cs2_enabled"
---@return table active_partners, table inactive_partners
local function get_service_partners(portaldata, service_key)
    local active = {}
    local inactive = {}
    if not portaldata then
        return active, inactive
    end

    local partner_map = {}
    if portaldata.target_ids then
        for target_id, _ in pairs(portaldata.target_ids) do
            partner_map[target_id] = true
        end
    end
    if portaldata.source_ids then
        for source_id, _ in pairs(portaldata.source_ids) do
            partner_map[source_id] = true
        end
    end

    for id, _ in pairs(partner_map) do
        local p = State and State.get_portaldata_by_id(id)
        if p then
            if p[service_key] then
                table.insert(active, p)
            else
                table.insert(inactive, p)
            end
        end
    end

    return active, inactive
end

-- ============================================================================
-- 4. 聚合摘要文本构造
-- ============================================================================

local function build_logistics_toggle_summary(portal, service_name, enabled, active_partners, inactive_partners)
    local portal_display = build_display_name(portal)
    local portal_gps = get_portal_gps(portal)
    local active_count = #active_partners
    local inactive_count = #inactive_partners

    if enabled then
        -- 开启场景
        if active_count == 0 and inactive_count == 0 then
            return { "messages.rift-rail-logistics-enabled-isolated", service_name, portal_display, portal_gps }
        elseif active_count == 1 and inactive_count == 0 then
            local partner = active_partners[1]
            return {
                "messages.rift-rail-logistics-connected-single",
                service_name,
                portal_display,
                portal_gps,
                build_display_name(partner),
                get_portal_gps(partner),
            }
        elseif active_count == 0 and inactive_count == 1 then
            local partner = inactive_partners[1]
            return {
                "messages.rift-rail-logistics-waiting-partner-single",
                service_name,
                portal_display,
                portal_gps,
                build_display_name(partner),
                get_portal_gps(partner),
            }
        elseif active_count == 0 and inactive_count > 1 then
            return { "messages.rift-rail-logistics-waiting-all", service_name, portal_display, portal_gps, inactive_count }
        else
            -- active_count >= 1 (可能伴随 inactive_count)
            local msg = {
                "",
                { "messages.rift-rail-logistics-connected-multi-header", service_name, portal_display, portal_gps, active_count },
            }
            for _, partner in ipairs(active_partners) do
                table.insert(msg, "\n  -> [color=cyan]")
                table.insert(msg, build_display_name(partner))
                table.insert(msg, "[/color] ")
                table.insert(msg, get_portal_gps(partner))
            end
            if inactive_count > 0 then
                table.insert(msg, "\n  ")
                table.insert(msg, { "messages.rift-rail-logistics-waiting-partner-note", inactive_count, service_name })
            end
            return msg
        end
    else
        -- 关闭场景：只报告被真正切断的 active_partners
        if active_count == 0 then
            return { "messages.rift-rail-logistics-disabled-isolated", service_name, portal_display, portal_gps }
        elseif active_count == 1 then
            local partner = active_partners[1]
            return {
                "messages.rift-rail-logistics-disconnected-single",
                service_name,
                portal_display,
                portal_gps,
                build_display_name(partner),
                get_portal_gps(partner),
            }
        else
            local msg = {
                "",
                { "messages.rift-rail-logistics-disconnected-multi-header", service_name, portal_display, portal_gps, active_count },
            }
            for _, partner in ipairs(active_partners) do
                table.insert(msg, "\n  -> [color=yellow]")
                table.insert(msg, build_display_name(partner))
                table.insert(msg, "[/color] ")
                table.insert(msg, get_portal_gps(partner))
            end
            return msg
        end
    end
end

-- ============================================================================
-- 5. 公开业务通知接口
-- ============================================================================

--- 物流开关（LTN / Cybersyn）切换时发送聚合摘要通知
---@param player LuaPlayer|nil
---@param portaldata table
---@param service_name string "LTN" | "Cybersyn"
---@param enabled boolean
function Notifier.notify_logistics_toggle(player, portaldata, service_name, enabled)
    local service_key = (service_name == "LTN") and "ltn_enabled" or "cs2_enabled"
    local active_partners, inactive_partners = get_service_partners(portaldata, service_key)
    local msg = build_logistics_toggle_summary(portaldata, service_name, enabled, active_partners, inactive_partners)
    send_notification(player, msg)
end

--- 解绑（解除配对）时发送物流切断通知（仅当此前存在双向生效的跨地表物流时发送）
---@param player LuaPlayer|nil
---@param source table
---@param target table
---@param ltn_was_active boolean
---@param cs2_was_active boolean
function Notifier.notify_unpaired(player, source, target, ltn_was_active, cs2_was_active)
    if not (ltn_was_active or cs2_was_active) then
        return
    end

    local source_display = build_display_name(source)
    local target_display = build_display_name(target)
    local source_gps = get_portal_gps(source)
    local target_gps = get_portal_gps(target)

    if ltn_was_active then
        local ltn_msg = {
            "messages.rift-rail-logistics-disconnected-single",
            "LTN",
            source_display,
            source_gps,
            target_display,
            target_gps,
        }
        send_notification(player, ltn_msg)
    end

    if cs2_was_active then
        local cs2_msg = {
            "messages.rift-rail-logistics-disconnected-single",
            "Cybersyn",
            source_display,
            source_gps,
            target_display,
            target_gps,
        }
        send_notification(player, cs2_msg)
    end
end

--- 建立配对时发送物流连通通知（仅当双方原本均已开启物流时发送）
---@param player LuaPlayer|nil
---@param source table
---@param target table
function Notifier.notify_paired(player, source, target)
    if not (source and target) then
        return
    end

    local ltn_active = (source.ltn_enabled and target.ltn_enabled)
    local cs2_active = (source.cs2_enabled and target.cs2_enabled)

    if not (ltn_active or cs2_active) then
        return
    end

    local source_display = build_display_name(source)
    local target_display = build_display_name(target)
    local source_gps = get_portal_gps(source)
    local target_gps = get_portal_gps(target)

    if ltn_active then
        local ltn_msg = {
            "messages.rift-rail-logistics-connected-single",
            "LTN",
            source_display,
            source_gps,
            target_display,
            target_gps,
        }
        send_notification(player, ltn_msg)
    end

    if cs2_active then
        local cs2_msg = {
            "messages.rift-rail-logistics-connected-single",
            "Cybersyn",
            source_display,
            source_gps,
            target_display,
            target_gps,
        }
        send_notification(player, cs2_msg)
    end
end

--- CS2 单向路径警告通知（受物流通知设置管辖）
---@param player LuaPlayer|nil
---@param one_way_pairs table
function Notifier.notify_cs2_one_way(player, one_way_pairs)
    if not (player and one_way_pairs and #one_way_pairs > 0) then
        return
    end
    if not should_notify_player(player) then
        return
    end

    for _, pair in ipairs(one_way_pairs) do
        local from_surface = game.surfaces[pair.from_surface_index]
        local to_surface = game.surfaces[pair.to_surface_index]
        local from_name = (from_surface and from_surface.name) or tostring(pair.from_surface_index)
        local to_name = (to_surface and to_surface.name) or tostring(pair.to_surface_index)
        player.print({ "messages.rift-rail-warning-cs2-one-way", from_name, to_name })
    end
end

return Notifier
