-- scripts/maintenance.lua
local Maintenance = {}
local Util = nil
local LTN = nil
local State = nil

local log_debug = function() end

function Maintenance.init(deps)
    Util = deps.Util
    LTN = deps.LTN
    State = deps.State
    if deps.log_debug then
        log_debug = deps.log_debug
    end
end

-- 处理模组设置变更事件
function Maintenance.on_settings_changed(event)
    -- 1. 重建碰撞器
    if event.setting == "rift-rail-reset-colliders" and settings.global["rift-rail-reset-colliders"].value then
        Util.rebuild_all_colliders()
        settings.global["rift-rail-reset-colliders"] = { value = false }
        game.print({ "messages.rift-rail-colliders-reset" })
    end

    -- 2. 卸载清理
    if event.setting == "rift-rail-uninstall-cleanup" and settings.global["rift-rail-uninstall-cleanup"].value then
        local count_ltn = 0
        if storage.rift_rails then
            for _, portaldata in pairs(storage.rift_rails) do
                if portaldata.ltn_enabled and LTN.on_portal_destroyed then
                    LTN.on_portal_destroyed(portaldata)
                    portaldata.ltn_enabled = false
                    count_ltn = count_ltn + 1
                end
            end
        end

        local active_count = storage.active_teleporter_list and #storage.active_teleporter_list or 0
        if active_count > 0 then
            game.print({ "messages.rift-rail-warning-active-teleport-during-cleanup", active_count })
        end

        settings.global["rift-rail-uninstall-cleanup"] = { value = false }
        game.print({ "messages.rift-rail-uninstall-complete", count_ltn })
    end

    -- 3. 调试模式
    if event.setting == "rift-rail-debug-mode" then
        RiftRail.DEBUG_MODE_ENABLED = settings.global["rift-rail-debug-mode"].value
    end
end

return Maintenance
