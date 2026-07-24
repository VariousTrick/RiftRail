-- updates/cs2.lua
-- 将 RiftRail 的 CS2 回调注册到 Cybersyn 2 的 mod-data 中。

local cs2_md = data.raw["mod-data"] and data.raw["mod-data"]["cybersyn2"]
if not (cs2_md and cs2_md.data) then
    return
end

-- 新版 CS2：拓扑回调拆成 node / vehicle 两个入口。
if cs2_md.data.node_topology_plugins then
    table.insert(cs2_md.data.node_topology_plugins, { "RiftRail", "cs2_node_topology_callback" })
end

if cs2_md.data.vehicle_topology_plugins then
    table.insert(cs2_md.data.vehicle_topology_plugins, { "RiftRail", "cs2_vehicle_topology_callback" })
end

-- route_plugins 仍然保留给 route_callback 使用；拓扑注册已经迁移到新版入口。
if cs2_md.data.route_plugins then
    cs2_md.data.route_plugins["riftrail"] = {
        -- 该函数返回 true 会否决 CS2 生成的任务。RiftRail 原则上不投否决票，因此先保留接口，不主动启用。
        -- reachable_callback = { "RiftRail", "cs2_reachable_callback" },
        route_callback = { "RiftRail", "cs2_route_callback" },
    }
end
