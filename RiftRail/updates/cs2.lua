-- updates/cs2.lua
-- Register RiftRail topology and route plugin callbacks into Cybersyn 2 mod-data.

local cs2_md = data.raw["mod-data"] and data.raw["mod-data"]["cybersyn2"]
if not (cs2_md and cs2_md.data) then
    return
end

if cs2_md.data.route_plugins then
    cs2_md.data.route_plugins["riftrail"] = {
        route_callback = { "RiftRail", "cs2_route_callback" },
    }
end

if cs2_md.data.node_topology_plugins then
    table.insert(cs2_md.data.node_topology_plugins, { "RiftRail", "cs2_node_topology_callback" })
end

if cs2_md.data.vehicle_topology_plugins then
    table.insert(cs2_md.data.vehicle_topology_plugins, { "RiftRail", "cs2_vehicle_topology_callback" })
end

