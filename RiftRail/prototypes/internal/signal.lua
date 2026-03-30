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
    -- 使用小尺寸宝石信号图集（G/Y/R，16 方向）
    filename = "__RiftRail__/graphics/rail-signal-gem-sheet-256-optimized.png",
    priority = "low",
    draw_as_light = false,
    frame_count = 3,
    direction_count = 16,
    width = 256,
    height = 256,
    scale = 0.15,
}

-- rail-signal 在 2.0 使用 structure + frame_index 映射
signal.ground_picture_set.structure = vortex_structure
-- 隐藏信号与铁轨之间的原版连接件（仅平地）
signal.ground_picture_set.rail_piece = nil
signal.ground_picture_set.upper_rail_piece = nil

-- 关闭原版信号灯灯头，避免与自定义状态图标叠加
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
