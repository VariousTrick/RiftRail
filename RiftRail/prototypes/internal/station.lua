local util = require("prototypes.util.util")
local sprites = require("prototypes.sprites.rift-rail-sprites")

local station = table.deepcopy(data.raw["train-stop"]["train-stop"])

station.name = "rift-rail-station"
station.minable = nil
station.flags = {
    "player-creation",
    "hide-alt-info",
    "not-repairable",
    "not-deconstructable",
    "not-on-map"
}

station.hidden = true
station.selectable_in_game = false
station.collision_mask = { layers = {} }
station.selection_box = util.create_centered_box(1, 1)

station.placeable_by = { item = "rift-rail-station-item", count = 1 }

station.animations = sprites.blank_sprite
station.top_animations = sprites.blank_sprite
station.rail_overlay_animations = sprites.blank_sprite
station.light1 = nil
station.light2 = nil
station.drawing_boxes = nil

data:extend({ station })
