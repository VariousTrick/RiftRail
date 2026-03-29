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

local vortex_structure = {
    filename = "__RiftRail__/graphics/rail-signal-vortex-sheet.png",
    priority = "low",
    blend_mode = "additive",
    draw_as_light = false,
    frame_count = 3,
    direction_count = 16,
    width = 128,
    height = 512,
    scale = 0.9,
}

-- rail-signal 在 2.0 使用 structure + frame_index 映射
if signal.ground_picture_set then
    signal.ground_picture_set.structure = vortex_structure
end

-- 关闭原版信号灯灯头，避免与旋涡叠加
signal.animation = nil
signal.red_light = nil
signal.orange_light = nil
signal.green_light = nil
signal.rail_piece = nil
signal.ground_patch = nil
signal.ground_piece = nil
signal.ground_light = nil
signal.circuit_connector = nil

data:extend({ signal })
