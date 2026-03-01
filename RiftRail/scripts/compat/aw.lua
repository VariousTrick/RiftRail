local AW = {}

local aw_mod_enabled = false
local log_debug = function() end

function AW.init(deps)
    if deps and deps.log_debug then
        log_debug = deps.log_debug
    end

    aw_mod_enabled = script.active_mods["AssemblyWagon"] ~= nil
end

function AW.on_car_replaced(old_car, new_car)
    if not aw_mod_enabled then
        return
    end

    if not (old_car and old_car.valid and new_car and new_car.valid) then
        return
    end

    if old_car.name ~= "assembly-wagon" or new_car.name ~= "assembly-wagon" then
        return
    end

    local iface = remote.interfaces["AssemblyWagon"]
    if not (iface and iface.transfer_binding) then
        return
    end

    local ok, err = pcall(remote.call, "AssemblyWagon", "transfer_binding", old_car.unit_number, new_car.unit_number)

    if not ok and RiftRail and RiftRail.DEBUG_MODE_ENABLED then
        log_debug("[RiftRail:Compat:AW] transfer_binding 调用失败: " .. tostring(err))
    end
end

return AW
