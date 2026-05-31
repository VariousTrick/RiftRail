local AW = {}

local aw_mod_enabled = false
function AW.init(_deps)
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

    pcall(remote.call, "AssemblyWagon", "transfer_binding", old_car, new_car)
end

return AW
