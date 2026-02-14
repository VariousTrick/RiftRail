local util = require("prototypes.util.util")
local sprites = require("prototypes.sprites.rift-rail-sprites")

data:extend({
    {
        type = "simple-entity-with-owner",
        name = "rift-rail-entity",
        icon = "__RiftRail__/graphics/entity.png",
        icon_size = 64,

        flags = {
            "placeable-neutral",
            "player-creation",
            "placeable-off-grid",
            "not-rotatable"
        },

        placeable_by = { { item = "rift-rail-placer", count = 1 } },

        minable = { mining_time = 1, result = "rift-rail-placer" },
        max_health = 100000,

        collision_mask = {
            layers = {
                ["water_tile"] = true,
                ["item"] = true,
                ["player"] = true,
            },
        },

        collision_box = util.create_centered_box(3.8, 11.8),
        selection_box = util.create_centered_box(4, 12),
        build_grid_size = 2,

        picture = {
            north = {
                layers = {
                    {
                        filename = "__RiftRail__/graphics/sprite_vert_atlas_warning.png",
                        priority = "high",
                        width = 528,
                        height = 1344,
                        scale = 0.35,
                        shift = { 0, 0 },
                        y = 0,
                        blend_mode = "additive",
                    },
                    {
                        filename = "__RiftRail__/graphics/sprite_vert_atlas.png",
                        priority = "high",
                        width = 528,
                        height = 1344,
                        scale = 0.35,
                        shift = { 0, 0 },
                        y = 0,
                    },
                },
            },

            south = {
                layers = {
                    {
                        filename = "__RiftRail__/graphics/sprite_vert_atlas_warning.png",
                        priority = "high",
                        width = 528,
                        height = 1344,
                        scale = 0.35,
                        shift = { 0, 0 },
                        y = 1344,
                        blend_mode = "additive",
                    },
                    {
                        filename = "__RiftRail__/graphics/sprite_vert_atlas.png",
                        priority = "high",
                        width = 528,
                        height = 1344,
                        scale = 0.35,
                        shift = { 0, 0 },
                        y = 1344,
                    },
                },
            },

            east = {
                layers = {
                    {
                        filename = "__RiftRail__/graphics/sprite_horiz_atlas_warning.png",
                        priority = "high",
                        width = 1344,
                        height = 528,
                        scale = 0.35,
                        shift = { 0, 0 },
                        x = 0,
                        blend_mode = "additive",
                    },
                    {
                        filename = "__RiftRail__/graphics/sprite_horiz_atlas.png",
                        priority = "high",
                        width = 1344,
                        height = 528,
                        scale = 0.35,
                        shift = { 0, 0 },
                        x = 0,
                    },
                },
            },

            west = {
                layers = {
                    {
                        filename = "__RiftRail__/graphics/sprite_horiz_atlas_warning.png",
                        priority = "high",
                        width = 1344,
                        height = 528,
                        scale = 0.35,
                        shift = { 0, 0 },
                        x = 1344,
                        blend_mode = "additive",
                    },
                    {
                        filename = "__RiftRail__/graphics/sprite_horiz_atlas.png",
                        priority = "high",
                        width = 1344,
                        height = 528,
                        scale = 0.35,
                        shift = { 0, 0 },
                        x = 1344,
                    },
                },
            },
        },

        render_layer = "train-stop-top",
    },
})
