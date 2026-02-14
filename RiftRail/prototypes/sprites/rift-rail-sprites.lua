local sprites = {}

sprites.sprite_left = {
    filename = "__RiftRail__/graphics/sprite_horiz_atlas_placer.png", -- 指向新图集
    priority = "high",
    width = 1344,                                                     -- 单个贴图的宽度
    height = 528,                                                     -- 单个贴图的高度
    frame_count = 1,
    direction_count = 1,
    shift = { 0, 0 },
    scale = 0.35,
    x = 0, -- 左侧贴图位于图集的 x=0 坐标
    y = 0,
}
sprites.sprite_right = {
    filename = "__RiftRail__/graphics/sprite_horiz_atlas_placer.png", -- 指向新图集
    priority = "high",
    width = 1344,
    height = 528,
    frame_count = 1,
    direction_count = 1,
    shift = { 0, 0 },
    scale = 0.35,
    x = 1344, -- 右侧贴图位于图集的 x=1344 坐标
    y = 0,
}
sprites.sprite_down = {
    filename = "__RiftRail__/graphics/sprite_vert_atlas_placer.png", -- 指向新图集
    priority = "high",
    width = 528,                                                     -- 单个贴图的宽度
    height = 1344,                                                   -- 单个贴图的高度
    frame_count = 1,
    direction_count = 1,
    shift = { 0, 0 },
    scale = 0.35,
    x = 0,
    y = 0, -- 下侧贴图位于图集的 y=0 坐标 }
}
sprites.sprite_up = {
    filename = "__RiftRail__/graphics/sprite_vert_atlas_placer.png", -- 指向新图集
    priority = "high",
    width = 528,
    height = 1344,
    frame_count = 1,
    direction_count = 1,
    shift = { 0, 0 },
    scale = 0.35,
    x = 0,
    y = 1344, -- 上侧贴图位于图集的 y=1344 坐标
}

sprites.blank_sprite = {
    filename = "__RiftRail__/graphics/blank.png",
    priority = "high",
    width = 1,
    height = 1,
    frame_count = 1,
    direction_count = 1,
}
sprites.entity_sprite = {
    filename = "__RiftRail__/graphics/entity.png",
    priority = "high",
    width = 256,  -- 4格
    height = 768, -- 12格
    frame_count = 1,
    direction_count = 1,
    shift = { 0, 0 },
}

sprites.blank_sheet = {
    north = sprites.blank_sprite,
    east = sprites.blank_sprite,
    south = sprites.blank_sprite,
    west = sprites.blank_sprite,

    north_east = sprites.blank_sprite,
    south_east = sprites.blank_sprite,
    south_west = sprites.blank_sprite,
    north_west = sprites.blank_sprite,

    north_north_east = sprites.blank_sprite,
    east_north_east = sprites.blank_sprite,
    east_south_east = sprites.blank_sprite,
    south_south_east = sprites.blank_sprite,
    south_south_west = sprites.blank_sprite,
    west_south_west = sprites.blank_sprite,
    west_north_west = sprites.blank_sprite,
    north_north_west = sprites.blank_sprite,
}

return sprites
