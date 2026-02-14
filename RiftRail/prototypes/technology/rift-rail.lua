-- RiftRail - technology.lua
-- 新科技：Rift Rail

local riftrail_tech = {
    type = "technology",
    name = "rift-rail-tech",
    icon = "__RiftRail__/graphics/icon/riftrail.png",
    icon_size = 64,
    prerequisites = { "automated-rail-transportation" },
    unit = {
        count = 1500,
        ingredients = {
            { "automation-science-pack", 1 },
            { "logistic-science-pack",   1 },
            { "chemical-science-pack",   1 },
            { "space-science-pack",      1 }
        },
        time = 30
    },
    effects = {
        {
            type = "unlock-recipe",
            recipe = "rift-rail-placer"
        }
    },
    order = "a-b-c"
}

data:extend({ riftrail_tech })
