-- =================================================================================================
-- Rift Rail - data.lua (v0.0.2 竖向修正版)
-- =================================================================================================

-- 入口在左 (Left)
local sprite_left = {
    filename = "__RiftRail__/graphics/sprite_horiz_atlas.png", -- 指向新图集
    priority = "high",
    width = 1344,                                              -- 单个贴图的宽度
    height = 528,                                              -- 单个贴图的高度
    frame_count = 1,
    direction_count = 1,
    shift = { 0, 0 },
    scale = 0.35,
    x = 0, -- 左侧贴图位于图集的 x=0 坐标
    y = 0
}

-- 入口在右 (Right)
local sprite_right = {
    filename = "__RiftRail__/graphics/sprite_horiz_atlas.png", -- 指向新图集
    priority = "high",
    width = 1344,
    height = 528,
    frame_count = 1,
    direction_count = 1,
    shift = { 0, 0 },
    scale = 0.35,
    x = 1344, -- 右侧贴图位于图集的 x=1344 坐标
    y = 0
}

-- 入口在下 (Down)
local sprite_down = {
    filename = "__RiftRail__/graphics/sprite_vert_atlas.png", -- 指向新图集
    priority = "high",
    width = 528,                                              -- 单个贴图的宽度
    height = 1344,                                            -- 单个贴图的高度
    frame_count = 1,
    direction_count = 1,
    shift = { 0, 0 },
    scale = 0.35,
    x = 0,
    y = 0 -- 下侧贴图位于图集的 y=0 坐标
}

-- 入口在上 (Up)
local sprite_up = {
    filename = "__RiftRail__/graphics/sprite_vert_atlas.png", -- 指向新图集
    priority = "high",
    width = 528,
    height = 1344,
    frame_count = 1,
    direction_count = 1,
    shift = { 0, 0 },
    scale = 0.35,
    x = 0,
    y = 1344 -- 上侧贴图位于图集的 y=1344 坐标
}

local function create_centered_box(width, height)
    local half_width = width / 2
    local half_height = height / 2
    return { { -half_width, -half_height }, { half_width, half_height } }
end

local blank_sprite = {
    filename = "__RiftRail__/graphics/blank.png",
    priority = "high",
    width = 1,
    height = 1,
    frame_count = 1,
    direction_count = 1,
}

-- 竖向占位图
local entity_sprite = {
    filename = "__RiftRail__/graphics/entity.png",
    priority = "high",
    width = 256,  -- 4格
    height = 768, -- 12格
    frame_count = 1,
    direction_count = 1,
    shift = { 0, 0 },
}

data:extend({
    -- 物品与配方
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
    {
        type = "recipe",
        name = "rift-rail-placer",
        enabled = true,
        energy_required = 0.1,
        ingredients = {
            { type = "item", name = "iron-plate", amount = 1 }
        },
        results = { { type = "item", name = "rift-rail-placer", amount = 1 } },
    },

    -- 1. 放置器实体 (Placer)
    {
        type = "simple-entity-with-owner",
        name = "rift-rail-placer-entity",
        icon = "__RiftRail__/graphics/icon/riftrail.png",
        icon_size = 64,
        -- [修正] 加入 placeable-off-grid，允许玩家自由移动以对齐铁轨网格
        flags = { "placeable-neutral", "placeable-player", "player-creation", "placeable-off-grid" },
        minable = { mining_time = 0.5, result = "rift-rail-placer" },
        max_health = 1000,
        -- [修正] 竖向尺寸 4x12
        collision_box = create_centered_box(3.8, 11.8),

        selection_box = create_centered_box(4, 12),
        -- [修正] 强制 2x2 网格对齐，解决错位
        build_grid_size = 2,
        picture = {
            north = sprite_down,
            south = sprite_up,
            east = sprite_left,
            west = sprite_right
        },
        render_layer = "object",
    },

    -- 2. 建筑主体
    {
        type = "simple-entity-with-owner",
        name = "rift-rail-entity",
        icon = "__RiftRail__/graphics/entity.png",
        icon_size = 64,
        -- [修正] 加入 placeable-off-grid，防止引擎自动吸附导致与铁轨网格错位
        -- >>>>> [修改开始] >>>>>
        -- 原代码：flags = { "placeable-neutral", "player-creation", "not-blueprintable", "placeable-off-grid" },
        -- 修改后：移除了 "not-blueprintable"，允许生成幽灵实体
        flags = { "placeable-neutral", "player-creation", "placeable-off-grid" },
        -- <<<<< [修改结束] <<<<

        -- >>>>> [新增开始] >>>>>
        -- 修复 Q 键吸取 (Pipette) 功能
        -- 原理：强制告诉引擎，当对着这个实体按 Q 时，选取 "rift-rail-placer" 这个物品
        placeable_by = { { item = "rift-rail-placer", count = 1 } },
        -- <<<<< [新增结束] <<<<<

        minable = { mining_time = 1, result = "rift-rail-placer" },
        max_health = 2000,
        collision_mask = {
            layers = {
                ["water_tile"] = true,
                ["item"] = true,
                -- ["object"] = true, -- 移除！这样铁轨规划器就不会认为它是个障碍物
                ["player"] = true,
                -- ["train"] = true, -- 允许火车通行
            }
        },
        -- [修正] 竖向尺寸 4x12
        -- 因为不再挡铁轨了，所以我们可以把它做得和贴图一样大，不用留缝隙
        collision_box = create_centered_box(3.8, 11.8),

        selection_box = create_centered_box(4, 12),
        -- [修正] 强制 2x2 网格对齐
        build_grid_size = 2,
        -- [修正] 将 animations 改回 picture
        -- simple-entity 的 picture 属性支持这种方向分类写法
        picture = {
            north = sprite_down,
            south = sprite_up,
            east = sprite_left,
            west = sprite_right
        },
        render_layer = "train-stop-top",
    },

    -- 8. 内部照明灯
    {
        type = "lamp",
        name = "rift-rail-lamp",
        icon = "__base__/graphics/icons/small-lamp.png",
        icon_size = 64,
        flags = { "hide-alt-info", "not-repairable", "not-blueprintable", "not-deconstructable", "not-on-map" },
        hidden = true,
        selectable_in_game = false,
        -- 无碰撞，不挡路
        collision_mask = { layers = {} },
        collision_box = create_centered_box(0, 0),
        selection_box = create_centered_box(0, 0),

        -- 使用虚空能源（自带电池），这样它永远亮着，不会闪烁红电图标
        energy_source = { type = "void" },
        energy_usage_per_tick = "1W",

        -- 视觉上不可见（没有灯柱子），只有光
        picture_off = blank_sprite,
        picture_on = blank_sprite,

        -- 光照参数 (你可以调整 size 和 intensity)
        light = { intensity = 0.9, size = 40, color = { r = 0.9, g = 0.9, b = 1.0 } }
    },


    -- 3. 内部组件占位符
    { type = "train-stop",           name = "rift-rail-station" },
    { type = "rail-signal",          name = "rift-rail-signal" },
    { type = "legacy-straight-rail", name = "rift-rail-internal-rail" },
    { type = "container",            name = "rift-rail-core" },    -- [修改] 改为容器(箱子)，以便利用原生的 GUI 锚定机制
    { type = "simple-entity",        name = "rift-rail-collider" },
    { type = "simple-entity",        name = "rift-rail-blocker" }, -- 物理堵头

    -- 爆炸效果
    {
        type = "explosion",
        name = "rift-rail-train-collision-explosion",
        icon = "__base__/graphics/icons/iron-plate.png",
        icon_size = 64,
        hidden = true,
        flags = { "not-on-map", "placeable-off-grid" },
        animations = blank_sprite,
    },
    -- 用于火车传送的隐形拖船 (Tug)
    -- 完全复刻自传送门/SE的物理参数，确保拼接稳定
    {
        type = "locomotive",
        name = "rift-rail-tug",
        subgroup = "other",
        flags = { "not-blueprintable", "not-deconstructable" },
        hidden = true, -- 隐藏实体

        -- 物理属性
        collision_box = { { -0.6, -0.3 }, { 0.6, 0.3 } },
        selection_box = { { -1, -1 }, { 1, 3 } },
        max_health = 1000,
        energy_per_hit_point = 5,
        weight = 20000,

        -- 动力参数
        max_power = "10000kW",
        max_speed = 1,
        reversing_power_modifier = 1,
        braking_force = 10,

        -- 阻力参数
        air_resistance = 0,
        friction_force = 0.5,

        -- 连接参数
        connection_distance = 0.1,
        joint_distance = 0.1,

        -- 无限能源，无需燃料
        energy_source = { type = "void" },

        -- 隐形贴图
        pictures = { rotated = blank_sprite },
        vertical_selection_shift = -0.5,
    },
})

-- 后期处理
local function table_merge(destination, source)
    for k, v in pairs(source) do destination[k] = v end
    return destination
end

-- 配置内部组件
local internal_station = data.raw["train-stop"]["rift-rail-station"]
table_merge(internal_station, table.deepcopy(data.raw["train-stop"]["train-stop"]))
internal_station.name = "rift-rail-station"
internal_station.minable = nil
internal_station.flags = { "hide-alt-info", "not-repairable", "not-blueprintable", "not-deconstructable", "not-on-map" }
internal_station.hidden = true
internal_station.selectable_in_game = false
internal_station.collision_mask = { layers = {} }
internal_station.selection_box = create_centered_box(0, 0)

-- [修正] 隐藏贴图：将所有视觉元素替换为透明或移除
internal_station.animations = blank_sprite
internal_station.top_animations = blank_sprite
internal_station.rail_overlay_animations = blank_sprite
internal_station.light1 = nil
internal_station.light2 = nil
internal_station.drawing_boxes = nil

local internal_signal = data.raw["rail-signal"]["rift-rail-signal"]
table_merge(internal_signal, table.deepcopy(data.raw["rail-signal"]["rail-signal"]))
internal_signal.name = "rift-rail-signal"
internal_signal.minable = nil
internal_signal.flags = { "hide-alt-info", "not-repairable", "not-blueprintable", "not-deconstructable", "not-on-map" }
internal_signal.hidden = true
internal_signal.selectable_in_game = false

-- [修正] 铁轨名称兼容性修复
local internal_rail = data.raw["legacy-straight-rail"]["rift-rail-internal-rail"]
local source_rail = data.raw["legacy-straight-rail"]["legacy-straight-rail"]
    or data.raw["legacy-straight-rail"]["straight-rail"]
table_merge(internal_rail, table.deepcopy(source_rail))
internal_rail.name = "rift-rail-internal-rail"
internal_rail.minable = nil
internal_rail.flags = { "hide-alt-info", "not-repairable", "not-blueprintable", "not-deconstructable", "not-on-map" }
internal_rail.hidden = true
internal_rail.selectable_in_game = false

-- D. 配置 GUI 交互核心 (Core)
-- [修正] 获取 container 类型的原型
local gui_core = data.raw["container"]["rift-rail-core"]
-- [修正] 复制木箱 (wooden-chest) 作为基础模板
table_merge(gui_core, table.deepcopy(data.raw["container"]["wooden-chest"]))

gui_core.name = "rift-rail-core"
-- >>>>> [修改开始] >>>>>
-- 原代码：gui_core.minable = { mining_time = 0.5, result = "rift-rail-placer" }
-- 修改后：直接设为 nil，禁止挖掘
gui_core.minable = nil

-- 原代码：gui_core.flags = { "hide-alt-info", "not-repairable", "not-blueprintable", "not-on-map", "not-rotatable" }
-- 修改后：增加 "not-deconstructable" 防止机器人试图拆它
gui_core.flags = { "hide-alt-info", "not-repairable", "not-blueprintable", "not-on-map", "not-rotatable",
    "not-deconstructable" }
-- <<<<< [修改结束] <<<<
gui_core.hidden = true
gui_core.collision_mask = { layers = {} } -- 无碰撞
gui_core.collision_box = create_centered_box(0, 0)
-- 选择框 (4x12)
gui_core.selection_box = create_centered_box(4, 4)
-- [修正] Container 使用 picture 属性，而不是 sprites
gui_core.picture = blank_sprite
-- [修正] 设置库存大小为 1 (最小化，仅用于附着 GUI)
gui_core.inventory_size = 1
-- [注意] 之前所有的 activity_led 和 circuit_wire 代码必须全部删除，因为箱子没有这些属性

-- [修正] 触发器配置 (手动设置，不复制)
local trigger = data.raw["simple-entity"]["rift-rail-collider"]
trigger.name = "rift-rail-collider"
trigger.flags = { "hide-alt-info", "not-repairable", "not-blueprintable", "not-deconstructable", "not-on-map" }
trigger.hidden = true
trigger.selectable_in_game = false
trigger.max_health = 1
trigger.picture = blank_sprite
trigger.collision_box = create_centered_box(2, 2)
trigger.collision_mask = { layers = { ["train"] = true } }
trigger.dying_trigger_effect = {
    type = "create-entity",
    entity_name = "rift-rail-train-collision-explosion",
    trigger_created_entity = true
}

-- F. 配置物理堵头 (Blocker)
-- 需求：放在死胡同端，阻止铁路连接
local blocker = data.raw["simple-entity"]["rift-rail-blocker"]
-- 借用 simple-entity-with-owner 模板
-- table_merge(blocker, table.deepcopy(data.raw["simple-entity"]["simple-entity-with-owner"])) -- [已删除 table_merge 行]
blocker.name = "rift-rail-blocker"
blocker.flags = { "hide-alt-info", "not-repairable", "not-blueprintable", "not-deconstructable", "not-on-map" }
blocker.hidden = true
blocker.selectable_in_game = false
blocker.max_health = 1000
blocker.picture = blank_sprite
-- 设置为 2x2 的方块，足以挡住铁轨
blocker.collision_box = create_centered_box(2, 2)
-- 确保它能阻挡玩家、车辆和铁轨铺设
blocker.collision_mask = {
    layers = {
        ["water_tile"] = true,
        ["item"] = true,
        ["object"] = true, -- 移除！这样铁轨规划器就不会认为它是个障碍物
        ["player"] = true,
        -- ["train"] = true, -- 允许火车通行
    }
}
