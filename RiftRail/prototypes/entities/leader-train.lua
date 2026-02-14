local util = require("prototypes.util.util")
local sprites = require("prototypes.sprites.rift-rail-sprites")


 data:extend({
 {
        type = "locomotive",
        name = "rift-rail-leader-train",
        subgroup = "other",
        flags = { "not-blueprintable", "not-deconstructable" },
        hidden = true, -- 隐藏实体
        icon = "__RiftRail__/graphics/icon/riftrail.png",
        icon_size = 64,

        -- 物理属性
        collision_box = util.create_centered_box(1.2, 0.6),
        selection_box = util.create_centered_box(2, 6),
        max_health = 50000,
        energy_per_hit_point = 5,
        weight = 1000,

        -- 动力参数
        max_power = "500kW",
        max_speed = 5,
        reversing_power_modifier = 1,
        braking_force = 2,

        -- 阻力参数
        air_resistance = 0,
        friction_force = 2,

        -- 连接参数
        connection_distance = 0.1,
        joint_distance = 0.1,

        -- 无限能源，无需燃料
        energy_source = { type = "void" },

        -- 隐形贴图
        pictures = { rotated = sprites.blank_sprite },
        vertical_selection_shift = -0.5,
    },
})