--- START OF FILE tips-and-tricks.lua ---

data:extend({
    {
        type = "tips-and-tricks-item-category",
        name = "RiftRail",
        order = "-a",
        localised_name = { "tips.tips-and-tricks-category" },
    },

    -- 【第 1 课：基础配对】
    {
        type = "tips-and-tricks-item",
        name = "rift-rail-pairing-tutorial",
        category = "RiftRail",
        localised_name = { "tips.rift-rail-pairing-tutorial" },
        localised_description = { "tips.item-description-pairing" },
        is_title = true,
        tag = "[item=rift-rail-placer]",
        order = "a",
        -- indent = 0,
        trigger = { type = "research", technology = "rift-rail-tech" },
        simulation = {
            mods = { "RiftRail" },
            init_update_count = 60,
            init = [[require("__RiftRail__/scripts/simulations/basic-pairing")]],
        },
    },

    -- 【第 2 课：进阶路由】
    {
        type = "tips-and-tricks-item",
        name = "rift-rail-advanced-routing",
        category = "RiftRail",
        localised_name = { "tips.rift-rail-advanced-routing" },
        localised_description = { "tips.item-description-advanced" },
        order = "b",
        indent = 1,
        dependencies = { "rift-rail-pairing-tutorial" },
        trigger = { type = "research", technology = "rift-rail-tech" },
        simulation = {
            mods = { "RiftRail" },
            init_update_count = 60,
            init = [[require("__RiftRail__/scripts/simulations/advanced-routing")]],
        },
    },
})
