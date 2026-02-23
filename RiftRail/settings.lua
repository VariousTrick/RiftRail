-- settings.lua
-- 确保 data 表存在
if not data then
    data = {}
end

data:extend({
    -- 统一的跨地表连接通知开关（Cybersyn + LTN）
    {
        type = "bool-setting",
        name = "rift-rail-show-logistics-notifications", -- 统一的设置名
        setting_type = "runtime-per-user",               -- 每个玩家单独设置
        default_value = true,                            -- 默认开启
        order = "a",                                     -- 排序
        localised_name = { "mod-setting-name.rift-rail-show-logistics-notifications" },
        localised_description = { "mod-setting-description.rift-rail-show-logistics-notifications" },
    },
    -- 列车界面追踪功能开关（地图全局设置）
    {
        type = "bool-setting",
        name = "rift-rail-train-gui-track",
        setting_type = "runtime-global", -- 地图全局设置
        default_value = true,
        order = "a-b", -- 紧跟在通知开关之后
        localised_name = { "mod-setting-name.rift-rail-train-gui-track" },
        localised_description = { "mod-setting-description.rift-rail-train-gui-track" },
    },
    -- 调试日志
    {
        type = "bool-setting",
        name = "rift-rail-debug-mode",   -- 代码中使用的内部名称
        setting_type = "runtime-global", -- 全局运行时设置
        default_value = false,           -- 默认关闭
        order = "z",                     -- 放在设置菜单的末尾
        localised_name = { "mod-setting-name.rift-rail-debug-mode" },
    },
    -- 紧急修复开关
    {
        type = "bool-setting",
        name = "rift-rail-reset-colliders",
        setting_type = "runtime-global", -- 地图设置，只有管理员能改
        default_value = false,
        order = "z-b",                   -- 排在最后
        localised_name = { "mod-setting-name.rift-rail-reset-colliders" },
        localised_description = { "mod-setting-description.rift-rail-reset-colliders" },
    },
    -- 卸载准备/清理数据开关
    {
        type = "bool-setting",
        name = "rift-rail-uninstall-cleanup",
        setting_type = "runtime-global", -- 地图全局设置
        default_value = false,
        order = "z-c",                   -- 排在重置碰撞器之后
        localised_name = { "mod-setting-name.rift-rail-uninstall-cleanup" },
        localised_description = { "mod-setting-description.rift-rail-uninstall-cleanup" },
    },
    -- 性能与稳定性微调 (Performance & Stability Tuning)
    {
        type = "double-setting",         -- 使用 double 类型来表示可以有小数的速度
        name = "rift-rail-teleport-speed",
        setting_type = "runtime-global", -- 全局设置，影响所有传送
        default_value = 1.0,
        minimum_value = 0.1,
        maximum_value = 8.0,
        order = "b-a", -- 将性能相关的设置放在一起
        localised_name = { "mod-setting-name.rift-rail-teleport-speed" },
        localised_description = { "mod-setting-description.rift-rail-teleport-speed" },
    },
    {
        type = "int-setting",            -- 使用 int 类型表示间隔必须是整数
        name = "rift-rail-placement-interval",
        setting_type = "runtime-global", -- 全局设置
        default_value = 1,
        minimum_value = 1,
        maximum_value = 10,
        order = "b-b", -- 紧跟在速度设置之后
        localised_name = { "mod-setting-name.rift-rail-placement-interval" },
        localised_description = { "mod-setting-description.rift-rail-placement-interval" },
    },
    {
        type = "string-setting",
        name = "rift-rail-mod-integration",
        setting_type = "startup",
        default_value = "none", -- only one value can be active
        allowed_values = { "easy-mode", "none", "space-age", "krastorio2", "space-exploration", "se-k2" },
        order = "a[riftrail]-a[mod-integration]",
        localised_name = { "mod-setting-name.rift-rail-mod-integration" },
        localised_description = { "mod-setting-description.rift-rail-mod-integration" },
        --[[ description = "Select which mod integration to enable (only one can be active)" ]]
    },
    -- LTN 防堵塞清理机制开关
    {
        type = "bool-setting",
        name = "rift-rail-ltn-use-teleported",
        setting_type = "runtime-global",
        default_value = false, -- 默认关闭
        order = "c-a",
        localised_name = { "mod-setting-name.rift-rail-ltn-use-teleported" },
        localised_description = { "mod-setting-description.rift-rail-ltn-use-teleported" },
    },
    -- LTN 防堵塞清理站名称
    {
        type = "string-setting",
        name = "rift-rail-ltn-teleported-name",
        setting_type = "runtime-global",
        default_value = "[item=rift-rail-placer]teleported", -- 带图标的默认名字
        allow_blank = false,
        order = "c-b",
        localised_name = { "mod-setting-name.rift-rail-ltn-teleported-name" },
        localised_description = { "mod-setting-description.rift-rail-ltn-teleported-name" },
    },
})
