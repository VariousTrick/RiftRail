data:extend({
    {
        type = "item",
        name = "rift-rail-station-item",
        icon = "__base__/graphics/icons/train-stop.png",
        icon_size = 64,
        icon_mipmaps = 4,
        hidden = true,
        flags = { "only-in-cursor" },
        subgroup = "train-transport",
        order = "z-[rift-rail-station]",
        stack_size = 1,
    },
    {
        type = "item",
        name = "rift-rail-placer",
        icon = "__RiftRail__/graphics/icon/riftrail.png",
        icon_size = 64,
        subgroup = "transport",
        order = "a[train-system]-z[rift-rail]",
        place_result = "rift-rail-placer-entity",
        stack_size = 10,
    },
})
