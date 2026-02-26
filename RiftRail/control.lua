-- control.lua
-- Rift Rail - 主入口
-- 功能：事件分发、日志管理、模块加载
-- 更新：集成传送逻辑、补全玩家传送、事件分流
-- add print msg tp the game when the mod is loaded
script.on_event(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    player.print({ "messages.rift-rail-welcome" })
    if script.active_mods["cybersyn"] then
        player.print({ "messages.rift-rail-cybersyn-allremoved" })
    end
end)

-- ==========================================================================
-- Rift Rail 自定义事件ID注册（供外部模组监听）
-- ==========================================================================
RiftRail = {} -- 创建一个全局可访问的表
RiftRail.Events = RiftRail.Events or {}
RiftRail.Events.TrainDeparting = script.generate_event_name()
RiftRail.Events.TrainArrived = script.generate_event_name()

-- 将调试开关挂载到全局表上
RiftRail.DEBUG_MODE_ENABLED = settings.global["rift-rail-debug-mode"].value

-- 定义一个纯粹的、只负责打印的日志函数
local function log_debug(msg)
    if not RiftRail.DEBUG_MODE_ENABLED then
        return
    end
    log("[RiftRail] " .. msg)
    if game then
        game.print("[RiftRail] " .. msg)
    end
end

-- 3. 加载模块
local flib_util = require("util") -- 引入官方库，命名为 flib_util 避免和自己的 Util 冲突
local Builder = require("scripts.builder")
local Remote = require("scripts.remote")
local GUI = require("scripts.gui")
local State = require("scripts.state")
local Logic = require("scripts.logic")
local Schedule = require("scripts.schedule")
local Util = require("scripts.util")
local Teleport = require("scripts.teleport")
local LTN = require("scripts.ltn_compat")
local Migrations = require("scripts.migrations")
local Maintenance = require("scripts.maintenance")
-- 仅当玩家安装并启用了 informatron 模组时，才加载并注册说明书接口
if script.active_mods["informatron"] then
    local InformatronSetup = require("scripts.informatron")
    InformatronSetup.setup_interface()
end

-- 给 Builder 注入 CybersynSE (用于拆除清理)
if Builder.init then
    Builder.init({
        log_debug = log_debug,
        flib_util = flib_util,
        State = State,
        Logic = Logic,
        Util = Util,
    })
end

-- 初始化 LTN 模块（仅依赖注入，实际接口运行时检查）
if LTN.init then
    LTN.init({
        State = State,
        log_debug = log_debug,
    })
end

if Schedule.init then
    Schedule.init({ log_debug = log_debug })
end

if Util.init then
    Util.init({ log_debug = log_debug })
end

-- 注入 Teleport 依赖
if Teleport.init then
    Teleport.init({
        State = State,
        Util = Util,
        Schedule = Schedule,
        log_debug = log_debug,
        LtnCompat = LTN,
        Events = RiftRail.Events,
    })
end

-- 给 Logic 注入 CybersynSE (用于GUI开关)
if Logic.init then
    Logic.init({
        State = State,
        GUI = GUI,
        log_debug = log_debug,
        LTN = LTN,
    })
end

if GUI.init then
    GUI.init({ State = State, log_debug = log_debug })
end

-- 初始化 Migrations 模块
if Migrations.init then
    Migrations.init({
        State = State,
        log_debug = log_debug,
        LTN = LTN,
        Util = Util,
    })
end

-- 给 Remote 注入依赖
if Remote.init then
    Remote.init({
        State = State,
        Logic = Logic,
        Builder = Builder,
        GUI = GUI,
        log_debug = log_debug,
    })
end

if Maintenance.init then
    Maintenance.init({
        State = State,
        LTN = LTN,
        Util = Util,
        log_debug = log_debug,
    })
end

-- ============================================================================
-- 5. 事件注册
-- ============================================================================

-- 实体过滤器：只监听本模组相关的实体
local rr_filters = {
    { filter = "name", name = "rift-rail-entity" },
    { filter = "name", name = "rift-rail-placer-entity" },
    { filter = "name", name = "rift-rail-collider" },
    { filter = "name", name = "rift-rail-station" },
    { filter = "name", name = "rift-rail-core" },
    { filter = "name", name = "rift-rail-signal" },
    { filter = "name", name = "rift-rail-internal-rail" },
    { filter = "name", name = "rift-rail-blocker" },
    { filter = "name", name = "rift-rail-lamp" },
}

-- A. 建造事件 (拆分优化版 - 修正 API 限制)
-- 1. 原生建造 (玩家): 单独注册 + 过滤器
script.on_event(defines.events.on_built_entity, Builder.on_built, rr_filters)

-- 2. 原生建造 (机器人): 单独注册 + 过滤器
script.on_event(defines.events.on_robot_built_entity, Builder.on_built, rr_filters)

-- 3. 脚本建造: 不支持过滤器，保持批量注册 (无变化)
script.on_event({
    defines.events.script_raised_built,
    defines.events.script_raised_revive,
}, Builder.on_built)

-- B. 拆除/挖掘事件 (拆分优化版 - 修正 API 限制)
-- 定义处理函数 (保持不变)
local function on_mined_handler(event)
    Builder.on_destroy(event, event.player_index)
end

-- 1. 原生拆除 (玩家): 单独注册 + 过滤器
script.on_event(defines.events.on_player_mined_entity, on_mined_handler, rr_filters)

-- 2. 原生拆除 (机器人): 单独注册 + 过滤器
script.on_event(defines.events.on_robot_mined_entity, on_mined_handler, rr_filters)

-- 3. 脚本拆除: 不使用过滤器 (无变化)
script.on_event(defines.events.script_raised_destroy, on_mined_handler)

-- C. 死亡事件分流 (on_entity_died)
-- 加入过滤器，此时虫子死亡绝对不会触发此函数，彻底消除战斗卡顿
script.on_event(defines.events.on_entity_died, function(event)
    local entity = event.entity
    if not (entity and entity.valid) then
        return
    end

    if entity.name == "rift-rail-collider" then
        -- 情况1: 碰撞器死亡 -> 触发传送逻辑
        Teleport.on_collider_died(event)
    elseif entity.name == "rift-rail-entity" then
        -- 情况2: 建筑主体死亡 -> 触发拆除逻辑
        Builder.on_destroy(event)
    end
    -- 对于其他任何实体（火车、虫子、树）的死亡，我们一概不管
end, rr_filters)

-- D. Tick 循环
script.on_event(defines.events.on_tick, function(event)
    -- 1. 执行传送逻辑
    Teleport.on_tick(event)
end)

-- E. 注册 LTN 事件（在运行时可用时）
local function register_ltn_events()
    if remote.interfaces["logistic-train-network"] then
        local ok1, ev1 = pcall(remote.call, "logistic-train-network", "on_stops_updated")
        if ok1 and ev1 then
            script.on_event(ev1, function(e)
                if LTN and LTN.on_stops_updated then
                    LTN.on_stops_updated(e)
                end
            end)
            log_debug("[LTN] 已注册 on_stops_updated 事件")
        end

        local ok2, ev2 = pcall(remote.call, "logistic-train-network", "on_dispatcher_updated")
        if ok2 and ev2 then
            script.on_event(ev2, function(e)
                if LTN and LTN.on_dispatcher_updated then
                    LTN.on_dispatcher_updated(e)
                end
            end)
            log_debug("[LTN] 已注册 on_dispatcher_updated 事件")
        end
    end
end

-- ============================================================================
-- 6. GUI 事件 (保持不变)
-- ============================================================================

script.on_event(defines.events.on_entity_renamed, Logic.on_entity_renamed)

script.on_event(defines.events.on_gui_opened, function(event)
    local entity = event.entity

    -- 增加例外判断
    if entity and entity.valid then
        -- 如果打开的是内部车站，直接返回，不执行拦截
        -- 这样引擎就会默认打开车站的原生 GUI
        if entity.name == "rift-rail-station" then
            return
        end

        -- 其他组件（外壳、核心等）继续保持拦截，打开自定义 GUI
        if State.get_portaldata(entity) then
            GUI.build_or_update(game.get_player(event.player_index), entity)
        end
    end
end)

script.on_event(defines.events.on_gui_click, GUI.handle_click)
script.on_event(defines.events.on_gui_switch_state_changed, GUI.handle_switch_state_changed)
script.on_event(defines.events.on_gui_checked_state_changed, GUI.handle_checked_state_changed)
script.on_event(defines.events.on_gui_confirmed, GUI.handle_confirmed)
script.on_event(defines.events.on_gui_selection_state_changed, GUI.handle_selection_state_changed)
script.on_event(defines.events.on_gui_closed, GUI.handle_close)
script.on_event(defines.events.on_entity_cloned, Builder.on_cloned)
script.on_event(defines.events.on_player_setup_blueprint, Builder.on_setup_blueprint)
script.on_event(defines.events.on_entity_settings_pasted, Builder.on_settings_pasted)
script.on_event(defines.events.on_runtime_mod_setting_changed, Maintenance.on_settings_changed)


-- 延迟加载事件注册
-- on_init: 只在创建新游戏时运行
script.on_init(function()
    State.ensure_storage() -- 会创建空的 rift_rails 和 id_map
    storage.collider_map = {}
    storage.active_teleporter_list = {}
    storage.collider_to_portal = {}
    if not storage.rift_rail_ltn_routing_table then
        storage.rift_rail_ltn_routing_table = {} -- 初始化 LTN 路由表
    end
    register_ltn_events() -- 注册 LTN 事件（若可用）
    storage.collider_migration_done = true
    storage.rift_rail_teleport_cache_calculated = true
end)

-- on_configuration_changed: 处理模组更新或配置变更
script.on_configuration_changed(function(event)
    -- 1. 确保基础表结构存在
    State.ensure_storage()

    -- 确保 LTN 路由表存在
    if not storage.rift_rail_ltn_routing_table then
        storage.rift_rail_ltn_routing_table = {}
    end

    -- 2. 执行所有迁移任务
    Migrations.run_all()

    -- 处理碰撞器获得实体ID
    if not storage.collider_migration_done then
        Util.rebuild_all_colliders()
        storage.collider_migration_done = true
    end
    if not storage.collider_to_portal then
        storage.collider_to_portal = {}
    end
end)

-- on_load: 只在加载存档时运行
-- 使用独立的 script.on_load 函数，它不依赖 defines 表
script.on_load(function(event)
    register_ltn_events()
end)
