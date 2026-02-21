--- START OF FILE tips-and-tricks.lua ---

data:extend({
    {
        type = "tips-and-tricks-item-category",
        name = "RiftRail",
        order = "-a",
        localised_name = { "tips.tips-and-tricks-category" },
    },

    -- 【第 1 课：基础配对（你接下来要写的新场景）】
    {
        type = "tips-and-tricks-item",
        name = "rift-rail-pairing-tutorial",
        category = "RiftRail",

        -- 记得去 locale 文件里加上这两行的翻译
        localised_name = { "tips.rift-rail-pairing-tutorial" },
        localised_description = { "tips.item-description-pairing" },

        is_title = true, -- 第一课带个大标题
        order = "a", -- 排在最前面
        indent = 0,

        length = 11,

        -- 【关键修复】：不加这个，玩家研究了科技也不会解锁教程！
        trigger = { type = "research", technology = "rift-rail-tech" },

        simulation = {
            mods = { "RiftRail" },
            init_update_count = 60,
            init = [[require("__RiftRail__/scripts/simulations/basic-pairing")]],
        },
    },

    -- 【第 2 课：进阶路由（原来的“大杂烩”）】
    {
        type = "tips-and-tricks-item",
        name = "rift-rail-advanced-routing", -- 告别 dazahui，拥抱专业命名
        category = "RiftRail",

        localised_name = { "tips.rift-rail-advanced-routing" },
        localised_description = { "tips.item-description-advanced" },

        order = "b", -- 排在基础教程后面
        indent = 1,

        length = 18,

        -- 【优雅的设定】：必须看完配对教程，才会解锁进阶教程
        -- dependencies = { "rift-rail-pairing-tutorial" },

        simulation = {
            mods = { "RiftRail" },
            init_update_count = 60,
            -- 【关键修复】：统一放在 simulations 文件夹下，保持清爽
            init = [[require("__RiftRail__/scripts/simulations/advanced-routing")]],
        },
    },
})
