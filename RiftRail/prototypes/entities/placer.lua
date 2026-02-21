local util = require("prototypes.util.util")
local sprites = require("prototypes.sprites.rift-rail-sprites")
data:extend({
    {
        type = "simple-entity-with-owner",
        name = "rift-rail-placer-entity",
        icon = "__RiftRail__/graphics/icon/riftrail.png",
        icon_size = 64,
        flags = { "placeable-neutral", "placeable-player", "player-creation" },
        minable = { mining_time = 0.5, result = "rift-rail-placer" },
        max_health = 1000,
        collision_box = util.create_centered_box(3.8, 11.8),
        selection_box = util.create_centered_box(4, 12),
        build_grid_size = 1,
        picture = {
            north = sprites.sprite_down,
            south = sprites.sprite_up,
            east  = sprites.sprite_left,
            west  = sprites.sprite_right,
        },
        render_layer = "object",
    }
})
