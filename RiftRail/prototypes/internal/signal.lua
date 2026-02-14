local util = require("prototypes.util.util")
local sprites = require("prototypes.sprites.rift-rail-sprites")

local signal = table.deepcopy(data.raw["rail-signal"]["rail-signal"])

signal.name = "rift-rail-signal"
signal.minable = nil
signal.flags = {
    "hide-alt-info",
    "not-repairable",
    "not-blueprintable",
    "not-deconstructable",
    "not-on-map"
}

signal.hidden = true
signal.selectable_in_game = false

data:extend({ signal })
