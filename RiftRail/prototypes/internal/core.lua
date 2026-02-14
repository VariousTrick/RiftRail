local util = require("prototypes.util.util")
local sprites = require("prototypes.sprites.rift-rail-sprites")

local core = table.deepcopy(data.raw["container"]["wooden-chest"])

core.name = "rift-rail-core"
core.minable = nil

core.flags = {
    "hide-alt-info",
    "not-repairable",
    "not-blueprintable",
    "not-on-map",
    "not-rotatable",
    "not-deconstructable"
}

core.hidden = true
core.collision_mask = { layers = {} }
core.collision_box = util.create_centered_box(0, 0)

core.selection_box = util.create_centered_box(4, 4)

core.picture = {
    filename = "__RiftRail__/graphics/mist_fixed.png",
    priority = "extra-high",
    width = 1024,
    height = 1024,
    blend_mode = "additive",
    scale = 0.18,
    shift = { 0, 0 },
}

core.render_layer = "train-stop-top"
core.secondary_draw_order = 10

core.inventory_size = 1

data:extend({ core })
