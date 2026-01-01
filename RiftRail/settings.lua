-- settings.lua
-- 确保 data 表存在
if not data then
    data = {}
end

data:extend({
    -- [新增] 统一的跨地表连接通知开关（Cybersyn + LTN）
    {
        type = "bool-setting",
        name = "rift-rail-show-logistics-notifications", -- 统一的设置名
        setting_type = "runtime-per-user",               -- 每个玩家单独设置
        default_value = true,                            -- 默认开启
        order = "a",                                     -- 排序
        localised_name = { "mod-setting-name.rift-rail-show-logistics-notifications" },
        localised_description = { "mod-setting-description.rift-rail-show-logistics-notifications" },
    },
    -- 追加在最后一个设置的后面，别忘了逗号
    {
        type = "bool-setting",
        name = "rift-rail-debug-mode",   -- 代码中使用的内部名称
        setting_type = "runtime-global", -- 全局运行时设置
        default_value = false,           -- 默认关闭
        order = "z",                     -- 放在设置菜单的末尾
        localised_name = { "mod-setting-name.rift-rail-debug-mode" },
    },
    -- [新增] 紧急修复开关
    {
        type = "bool-setting",
        name = "rift-rail-reset-colliders",
        setting_type = "runtime-global", -- 地图设置，只有管理员能改
        default_value = false,
        order = "z-b",                   -- 排在最后
        localised_name = { "mod-setting-name.rift-rail-reset-colliders" },
        localised_description = { "mod-setting-description.rift-rail-reset-colliders" },
    },
    -- [新增] 卸载准备/清理数据开关
    {
        type = "bool-setting",
        name = "rift-rail-uninstall-cleanup",
        setting_type = "runtime-global", -- 地图全局设置
        default_value = false,
        order = "z-c",                   -- 排在重置碰撞器之后
        localised_name = { "mod-setting-name.rift-rail-uninstall-cleanup" },
        localised_description = { "mod-setting-description.rift-rail-uninstall-cleanup" },
    },
})
