-- updates/cs2.lua
-- Register RiftRail route plugin callbacks into Cybersyn 2 mod-data.

local cs2_md = data.raw["mod-data"] and data.raw["mod-data"]["cybersyn2"]
if not (cs2_md and cs2_md.data and cs2_md.data.route_plugins) then
    return
end

cs2_md.data.route_plugins["riftrail"] = {
    train_topology_callback = { "RiftRail", "cs2_train_topology_callback" },
    -- 该函数返回trun会否决CS2生成的任务，RiftRail原则上不投否决票，因此直接注释掉，保留函数接口以备未来需要。
    -- reachable_callback = { "RiftRail", "cs2_reachable_callback" },
    route_callback = { "RiftRail", "cs2_route_callback" },
}
