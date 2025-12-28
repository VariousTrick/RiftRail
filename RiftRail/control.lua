-- control.lua
-- Rift Rail - 主入口
-- 功能：事件分发、日志管理、模块加载
-- 更新：集成传送逻辑、补全玩家传送、事件分流

-- ============================================================================
-- 1. 统一的日志与状态中心
-- ============================================================================
RiftRail = {} -- 创建一个全局可访问的表

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
local GUI = require("scripts.gui")
local State = require("scripts.state")
local Logic = require("scripts.logic")
local Schedule = require("scripts.schedule")
local Util = require("scripts.util")
local Teleport = require("scripts.teleport")
local CybersynSE = require("scripts.cybersyn_compat")
local CybersynScheduler = require("scripts.cybersyn_scheduler")
local LTN = require("scripts.ltn_compat")

-- 给 Builder 注入 CybersynSE (用于拆除清理)
if Builder.init then
    Builder.init({
        log_debug = log_debug,
        State = State,
        Logic = Logic,
        CybersynSE = CybersynSE,
    })
end

-- 初始化 Cybersyn 模块
if CybersynSE.init then
    CybersynSE.init({
        State = State,
        log_debug = log_debug,
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
    })
end

-- 给 Logic 注入 CybersynSE (用于GUI开关)
if Logic.init then
    Logic.init({
        State = State,
        GUI = GUI,
        log_debug = log_debug,
        CybersynSE = CybersynSE,
        LTN = LTN,
    })
end

if GUI.init then
    GUI.init({ State = State, log_debug = log_debug })
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
    -- 1. 先通知 Cybersyn 清理连接
    local entity = event.entity
    if entity and entity.valid then
        local struct = State.get_struct(entity)
        if struct then
            CybersynSE.on_portal_destroyed(struct)
        end
    end
    -- 2. 再执行原来的销毁逻辑
    Builder.on_destroy(event)
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
        local struct = State.get_struct(entity)
        if struct then
            CybersynSE.on_portal_destroyed(struct)
        end
        Builder.on_destroy(event)
    end
    -- 对于其他任何实体（火车、虫子、树）的死亡，我们一概不管
end, rr_filters)

-- D. Tick 循环
script.on_event(defines.events.on_tick, function(event)
    -- 1. 执行传送逻辑
    Teleport.on_tick(event)

    -- 2. 执行 Cybersyn 调度器逻辑
    if CybersynScheduler.on_tick then
        CybersynScheduler.on_tick()
    end
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

script.on_event(defines.events.on_gui_opened, function(event)
    local entity = event.entity
    if entity and entity.valid and State.get_struct(entity) then
        GUI.build_or_update(game.get_player(event.player_index), entity)
    end
end)

script.on_event(defines.events.on_gui_click, GUI.handle_click)
script.on_event(defines.events.on_gui_switch_state_changed, GUI.handle_switch_state_changed)
script.on_event(defines.events.on_gui_checked_state_changed, GUI.handle_checked_state_changed)
script.on_event(defines.events.on_gui_confirmed, GUI.handle_confirmed)

-- 当玩家按 E 或 ESC 关闭窗口时触发
script.on_event(defines.events.on_gui_closed, GUI.handle_close)
-- ============================================================================
-- 克隆/传送事件处理
-- ============================================================================
script.on_event(defines.events.on_entity_cloned, function(event)
    local new_entity = event.destination
    local old_entity = event.source

    if not (new_entity and new_entity.valid) then
        return
    end

    -- 分支 A: Cybersyn 控制器
    if new_entity.name == "cybersyn-combinator" then
        if script.active_mods["zzzzz"] then
            return
        end
        if string.find(new_entity.surface.name, "spaceship") then
            script.raise_event(defines.events.script_raised_built, { entity = new_entity })
        end
        return
    end

    -- 分支 B: RiftRail 主体
    if new_entity.name ~= "rift-rail-entity" then
        return
    end

    local old_unit_number = old_entity.unit_number
    local old_data = storage.rift_rails and storage.rift_rails[old_unit_number]

    if not old_data then
        return
    end

    local new_data = flib_util.table.deepcopy(old_data)
    local new_unit_number = new_entity.unit_number

    new_data.unit_number = new_unit_number
    new_data.shell = new_entity
    new_data.surface = new_entity.surface

    -- 使用“精准且容错的定位”重建 children 列表
    local old_children_list = new_data.children
    new_data.children = {}
    local new_center_pos = new_entity.position

    if old_children_list then
        for _, old_child_data in pairs(old_children_list) do
            -- 增加安全检查，确保旧数据是有效的
            if old_child_data.relative_pos and old_child_data.entity and old_child_data.entity.valid then
                -- 1. 获取子实体的名字，用于精准点名
                local child_name = old_child_data.entity.name

                -- 2. 计算子实体在新地表上的精确预期坐标
                local expected_pos = {
                    x = new_center_pos.x + old_child_data.relative_pos.x,
                    y = new_center_pos.y + old_child_data.relative_pos.y,
                }

                -- 3. 在这个精确位置的稍大范围内，按名字查找克隆体

                -- 为 'lamp' 使用更大的搜索半径，以应对克隆时的坐标漂移
                local search_radius = 0.5 -- 默认使用高精度半径
                if child_name == "rift-rail-lamp" then
                    search_radius = 1.5 -- 只为灯放宽到 1.5
                end

                local found_clone = new_entity.surface.find_entities_filtered({
                    name = child_name,
                    position = expected_pos,
                    radius = search_radius, -- 使用动态半径
                    limit = 1,
                })

                if found_clone and found_clone[1] then
                    table.insert(new_data.children, {
                        entity = found_clone[1],
                        relative_pos = old_child_data.relative_pos,
                    })
                else
                    log_debug("RiftRail Clone Error: 在位置 " .. serpent.line(expected_pos) .. " 附近未能找到名为 " .. child_name .. " 的子实体克隆体。")
                end
            end
        end
    end

    -- 清除旧的坐标缓存，强制 teleport.lua 在下次使用时重新计算 ("懒加载")
    new_data.blocker_position = nil

    -- 4. 保存新数据
    storage.rift_rails[new_unit_number] = new_data
    if storage.rift_rail_id_map then
        storage.rift_rail_id_map[new_data.id] = new_unit_number
    end

    -- 5. Cybersyn 迁移
    local is_landing = false
    local old_is_space = string.find(old_entity.surface.name, "spaceship")
    local new_is_space = string.find(new_entity.surface.name, "spaceship")
    if old_is_space and not new_is_space then
        is_landing = true
    end
    CybersynSE.on_portal_cloned(old_data, new_data, is_landing)

    -- 6. 删除旧数据
    storage.rift_rails[old_unit_number] = nil

    log_debug("[RiftRail] 克隆迁移成功: ID " .. new_data.id .. " | 实体ID " .. old_unit_number .. " -> " .. new_unit_number)
end)

-- ============================================================================
-- [最终修复版] 蓝图创建时“源头掉包” (修复 "not-rotatable" 报错)
-- ============================================================================
script.on_event(defines.events.on_player_setup_blueprint, function(event)
    -- 这个事件只在“创建蓝图(Ctrl+C)”时有 mapping，我们只处理这种情况
    if not event.mapping then
        return
    end

    local player = game.get_player(event.player_index)

    -- 智能获取正在编辑的蓝图
    -- 优先检查 "新建蓝图" 界面 (Alt+B)，其次检查鼠标上的蓝图 (Ctrl+C)
    local blueprint = player.blueprint_to_setup
    if not (blueprint and blueprint.valid and blueprint.is_blueprint) then
        blueprint = player.cursor_stack
    end

    -- 如果两种情况都不是有效的蓝图，则退出
    if not (blueprint and blueprint.valid and blueprint.is_blueprint) then
        return
    end

    local entities = blueprint.get_blueprint_entities()
    if not entities then
        return
    end

    local mapping = event.mapping.get()

    local modified = false
    local new_entities = {} -- 创建一个新的实体列表

    -- 1. 遍历原始蓝图实体，寻找主体并进行“掉包”
    for i, bp_entity in pairs(entities) do
        local source_entity = mapping[bp_entity.entity_number]

        if source_entity and source_entity.valid and source_entity.name == "rift-rail-entity" then
            -- 找到了“顽固”的主体，我们不把它加入新列表
            -- 而是创建一个全新的、“灵活”的放置器来替换它
            modified = true

            local data = storage.rift_rails[source_entity.unit_number]

            local placer_entity = {
                entity_number = bp_entity.entity_number,
                name = "rift-rail-placer-entity",
                position = bp_entity.position,
                direction = bp_entity.direction,
                tags = {}, -- 初始化 tags
            }

            -- 将配置信息保存到这个新放置器的 tags 中
            if data then
                placer_entity.tags.rr_name = data.name
                placer_entity.tags.rr_mode = data.mode
                placer_entity.tags.rr_icon = data.icon
            end

            -- 将改造后的“安装包”加入新列表
            table.insert(new_entities, placer_entity)
            log_debug("蓝图源头掉包: RiftRail Entity -> Placer")
        elseif not (source_entity and source_entity.valid and source_entity.name:find("rift-rail-")) then
            -- 如果这个实体不是任何 RiftRail 的组件，就把它保留下来
            table.insert(new_entities, bp_entity)
        end
        -- 注意: 所有 RiftRail 的内部组件 (core, station 等) 都会被自动忽略，不会加入 new_entities
    end

    -- 2. 如果发生了“掉包”，就用我们净化过的新列表覆盖整个蓝图
    if modified then
        blueprint.set_blueprint_entities(new_entities)
    end
end)

-- ============================================================================
-- 复制粘贴设置 (Shift+右键 -> Shift+左键)
-- ============================================================================
script.on_event(defines.events.on_entity_settings_pasted, function(event)
    local source = event.source
    local dest = event.destination
    local player = game.get_player(event.player_index)

    -- 1. 验证：必须是从我们的建筑复制到我们的建筑
    if not (source.valid and dest.valid) then
        return
    end
    if source.name ~= "rift-rail-entity" or dest.name ~= "rift-rail-entity" then
        return
    end

    -- 2. 获取数据
    local source_data = storage.rift_rails[source.unit_number]
    local dest_data = storage.rift_rails[dest.unit_number]

    if source_data and dest_data then
        -- 3. 复制基础配置 (名字、图标)
        dest_data.name = source_data.name
        dest_data.icon = source_data.icon -- 这是一个 table，直接引用没问题，因为后续通常是读操作

        -- 4. 应用模式 (Entry/Exit/Neutral)
        -- 我们调用 Logic.set_mode，这样它会自动处理碰撞器的生成/销毁，以及打印提示信息
        -- 注意：这里传入 player_index，所以玩家会收到 "模式已切换为入口" 的提示，反馈感很好
        Logic.set_mode(event.player_index, dest_data.id, source_data.mode)

        -- 5. 刷新车站显示名称 (backer_name)
        if dest_data.children then
            for _, child_data in pairs(dest_data.children) do
                -- 先从数据结构中取出实体对象
                local child = child_data.entity
                if child and child.valid and child.name == "rift-rail-station" then
                    -- 移除强制空格，保持与 Logic/Builder 一致
                    local master_icon = "[item=rift-rail-placer]"
                    local user_icon_str = ""
                    if dest_data.icon then
                        user_icon_str = "[" .. dest_data.icon.type .. "=" .. dest_data.icon.name .. "]"
                    end
                    -- dest_data.name 此时已包含必要的空格（如果有），直接拼接
                    child.backer_name = master_icon .. user_icon_str .. dest_data.name
                    break
                end
            end
        end

        -- 手动播放原版粘贴音效
        -- 这会让 Shift+左键 时也能听到熟悉的“咔嚓”声
        player.play_sound{path = "utility/entity_settings_pasted"}

        -- 6. Debug 信息
        log_debug("设置已粘贴: " .. source_data.name .. " -> " .. dest_data.name)
    end
end)
-- ============================================================================
-- 监听设置变更：处理紧急修复指令
-- ============================================================================
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    -- 只有当开关被打开时才执行
    if event.setting == "rift-rail-reset-colliders" and settings.global["rift-rail-reset-colliders"].value then
        -- 1. 【焦土】销毁全图所有的旧碰撞器
        for _, surface in pairs(game.surfaces) do
            local old_colliders = surface.find_entities_filtered({ name = "rift-rail-collider" })
            for _, c in pairs(old_colliders) do
                c.destroy()
            end
        end

        -- 2. 【重生】在正确位置重新生成
        if storage.rift_rails then
            for _, struct in pairs(storage.rift_rails) do
                if struct.shell and struct.shell.valid then
                    -- 只有入口和中立需要碰撞器
                    if struct.mode == "entry" or struct.mode == "neutral" then
                        local dir = struct.shell.direction
                        local offset = { x = 0, y = 0 }

                        -- 偏移量计算
                        if dir == 0 then
                            offset = { x = 0, y = -2 } -- North
                        elseif dir == 4 then
                            offset = { x = 2, y = 0 } -- East
                        elseif dir == 8 then
                            offset = { x = 0, y = 2 } -- South
                        elseif dir == 12 then
                            offset = { x = -2, y = 0 } -- West
                        end

                        -- 获取新创建的 collider 实体
                        local new_collider = struct.surface.create_entity({
                            name = "rift-rail-collider",
                            position = { x = struct.shell.position.x + offset.x, y = struct.shell.position.y + offset.y },
                            force = struct.shell.force,
                        })

                        -- 将新 collider 同步回 children 列表
                        if new_collider and struct.children then
                            -- 1. 清理旧的 collider 引用
                            for i = #struct.children, 1, -1 do
                                local child_data = struct.children[i]
                                if child_data and child_data.entity and (not child_data.entity.valid or child_data.entity.name == "rift-rail-collider") then
                                    table.remove(struct.children, i)
                                end
                            end
                            -- 2. 注册新的 collider
                            table.insert(struct.children, {
                                entity = new_collider,
                                relative_pos = offset, -- "offset" 就是我们刚算好的相对坐标
                            })
                        end
                    end
                    -- 重置标记
                    struct.collider_needs_rebuild = false
                end
            end
        end

        -- 3. 【自复位】执行完后自动把开关关掉
        settings.global["rift-rail-reset-colliders"] = { value = false }

        game.print({ "messages.rift-rail-colliders-reset" })
        -- 监听调试模式的变更
    elseif event.setting == "rift-rail-debug-mode" then
        RiftRail.DEBUG_MODE_ENABLED = settings.global["rift-rail-debug-mode"].value
    end
end)

-- ============================================================================
-- 延迟加载事件注册
-- ============================================================================

-- on_init: 只在创建新游戏时运行
script.on_init(function()
    State.ensure_storage() -- 会创建空的 rift_rails 和 id_map
    storage.collider_map = {}
    storage.active_teleporter_list = {}
    -- 注册 LTN 事件（若可用）
    register_ltn_events()
end)

-- on_configuration_changed: 处理模组更新或配置变更
script.on_configuration_changed(function(event)
    -- 1. 确保基础表结构存在
    State.ensure_storage()

    -- 2. 【迁移】为旧存档构建 id_map 缓存
    if storage.rift_rails and next(storage.rift_rails) ~= nil and next(storage.rift_rail_id_map) == nil then
        log_debug("[Migration] 检测到旧存档，正在构建 id_map 缓存...")
        for unit_number, struct in pairs(storage.rift_rails) do
            storage.rift_rail_id_map[struct.id] = unit_number
        end
    end

    -- 3. 【迁移】为旧建筑的 children 列表补充相对坐标
    if storage.rift_rails then
        for _, struct in pairs(storage.rift_rails) do
            -- 判断是否为需要修复的旧数据：检查第一个 child 是否是实体对象，而不是 table
            if struct.children and #struct.children > 0 and struct.children[1].valid then
                log_debug("[Migration] 正在修复建筑 ID " .. struct.id .. " 的 children 列表...")
                local new_children = {}
                if struct.shell and struct.shell.valid then
                    local center_pos = struct.shell.position
                    for _, child_entity in pairs(struct.children) do
                        if child_entity and child_entity.valid then
                            table.insert(new_children, {
                                entity = child_entity,
                                relative_pos = {
                                    x = child_entity.position.x - center_pos.x,
                                    y = child_entity.position.y - center_pos.y,
                                },
                            })
                        end
                    end
                    struct.children = new_children
                end
            end
        end
    end

    -- 4. 【迁移】GC优化相关的活跃列表
    if not storage.active_teleporter_list then
        storage.active_teleporter_list = {}
        if storage.active_teleporters then
            for _, struct in pairs(storage.active_teleporters) do
                table.insert(storage.active_teleporter_list, struct)
            end
            table.sort(storage.active_teleporter_list, function(a, b)
                return a.unit_number < b.unit_number
            end)
        end
    end
end)

-- on_load: 只在加载存档时运行
-- 使用独立的 script.on_load 函数，它不依赖 defines 表
script.on_load(function(event)
    if Teleport.init_se_events then
        Teleport.init_se_events()
    end
    register_ltn_events()
end)
-- ============================================================================
-- 7. 远程接口
-- ============================================================================
remote.add_interface("RiftRail", {
    update_portal_name = function(player_index, portal_id, new_name)
        Logic.update_name(player_index, portal_id, new_name)
    end,

    pair_portals = function(player_index, source_id, target_id)
        Logic.pair_portals(player_index, source_id, target_id)
    end,

    unpair_portals = function(player_index, portal_id)
        Logic.unpair_portals(player_index, portal_id)
    end,

    set_portal_mode = function(player_index, portal_id, mode)
        Logic.set_mode(player_index, portal_id, mode)
    end,

    set_cybersyn_enabled = function(player_index, portal_id, enabled)
        -- [修改] 连接到 Logic 模块
        Logic.set_cybersyn_enabled(player_index, portal_id, enabled)
    end,

    set_ltn_enabled = function(player_index, portal_id, enabled)
        Logic.set_ltn_enabled(player_index, portal_id, enabled)
    end,

    -- 玩家传送逻辑：传送到当前建筑外部，而非配对目标
    teleport_player = function(player_index, portal_id)
        local player = game.get_player(player_index)
        local struct = State.get_struct_by_id(portal_id)

        if player and struct and struct.shell and struct.shell.valid then
            -- 计算落点：位于建筑 "口子" 外面一点的位置，防止卡住
            -- 建筑中心到口子是 6 格，我们传送在 8 格的位置
            local dir = struct.shell.direction
            local offset = { x = 0, y = 0 }

            if dir == 0 then -- North (开口在下) -> 传送到上方
                offset = { x = 0, y = -8 }
            elseif dir == 4 then -- East (开口在左) -> 传送到右方
                offset = { x = 8, y = 0 }
            elseif dir == 8 then -- South (开口在上) -> 传送到下方
                offset = { x = 0, y = 8 }
            elseif dir == 12 then -- West (开口在右) -> 传送到左方
                offset = { x = -8, y = 0 }
            end

            local target_pos = {
                x = struct.shell.position.x + offset.x,
                y = struct.shell.position.y + offset.y,
            }

            -- 尝试寻找附近的无碰撞位置 (防止传送到树或石头里)
            local safe_pos = struct.shell.surface.find_non_colliding_position("character", target_pos, 5, 1)
            if not safe_pos then
                safe_pos = target_pos
            end -- 如果找不到，强行传送

            -- 执行传送
            player.teleport(safe_pos, struct.shell.surface)

            -- 强制查找并销毁 GUI，不再依赖事件监听
            if player.gui.screen.rift_rail_main_frame then
                player.gui.screen.rift_rail_main_frame.destroy()
            end

            -- 清空 opened 状态，确保逻辑闭环
            player.opened = nil
        else
            if player then
                player.print({ "messages.rift-rail-error-self-invalid" })
            end
        end
    end,

    open_remote_view = function(player_index, portal_id)
        Logic.open_remote_view(player_index, portal_id)
    end,

    -- ============================================================================
    -- [调试专用接口]
    -- ============================================================================
    --[[
        [使用方法] (在控制台 ~ 中输入)

        1. 查询总数:
        /c game.print(remote.call("RiftRail", "debug_storage", "count"))

        2. 查询存档大小:
        /c game.print(remote.call("RiftRail", "debug_storage", "size"))

        3. 查询鼠标悬停的传送门数据 (最常用):
        /c local data = remote.call("RiftRail", "debug_storage", "selected", nil, game.player.index); game.print(serpent.line(data, {compact = true, singleline = {'table', 4}}))

        4. 通过自定义ID查询 (例如 ID为 27):
        /c local id=27; game.print(serpent.line(remote.call("RiftRail", "debug_storage", "get_by_id", id)))
        
        5. 通过实体Unit Number查询 (旧方法):
        /c local id=12345; game.print(serpent.block(remote.call("RiftRail", "debug_storage", "get_by_unit", id)))

        6. 查找幽灵数据报告:
        /c game.print(serpent.block(remote.call("RiftRail", "debug_storage", "find_ghosts")))
    ]]
    debug_storage = function(key, param, player_index)
        -- 内部辅助函数，用于获取 struct (保持不变)
        local function get_struct(struct_key, search_param)
            if struct_key == "selected" then
                if not player_index then
                    return "Error: 'selected' requires player context."
                end
                local player = game.get_player(player_index)
                if not (player and player.valid) then
                    return "Error: Invalid player."
                end
                local selected = player.selected
                if not (selected and selected.valid) then
                    return "Error: No entity selected. Hover mouse over a Rift Rail building."
                end
                return State.get_struct(selected) or "Error: Selected entity is not a Rift Rail portal."
            elseif struct_key == "get_by_id" then
                if not search_param then
                    return "Error: 'get_by_id' requires a custom ID parameter."
                end
                return State.get_struct_by_id(search_param) or "Error: Struct with custom ID " .. tostring(search_param) .. " not found."
            elseif struct_key == "get_by_unit" then
                if not search_param then
                    return "Error: 'get_by_unit' requires a unit_number parameter."
                end
                if storage.rift_rails and storage.rift_rails[search_param] then
                    return storage.rift_rails[search_param]
                else
                    return "Error: Struct with unit_number " .. tostring(search_param) .. " not found."
                end
            end
            return nil
        end

        if key == "count" then
            local count = 0
            if storage.rift_rails then
                for _ in pairs(storage.rift_rails) do
                    count = count + 1
                end
            end
            return "Total Rift Rails in storage: " .. count
        elseif key == "size" then
            if storage.rift_rails then
                local data_string = serpent.block(storage.rift_rails)
                local size_kb = string.len(data_string) / 1024
                return "RiftRail storage size: " .. string.format("%.2f KB", size_kb)
            else
                return "storage.rift_rails not found!"
            end
        elseif key == "find_ghosts" then
            local report = {}
            local data_ghosts = {}
            local entity_ghosts = {}
            local total_structs = 0

            -- 1. 查找"数据幽灵" (数据存在，实体已消失)
            if storage.rift_rails then
                for unit_number, struct in pairs(storage.rift_rails) do
                    total_structs = total_structs + 1
                    if not (struct.shell and struct.shell.valid) then
                        table.insert(data_ghosts, "Struct for unit_number " .. unit_number .. " (ID: " .. (struct.id or "N/A") .. ") has an invalid shell.")
                    end
                end
            end
            report["Data Ghosts (Data exists, Entity gone)"] = data_ghosts

            -- 2. 查找"实体幽灵" (实体存在，数据已消失)
            local component_names = {
                "rift-rail-entity",
                "rift-rail-core",
                "rift-rail-station",
                "rift-rail-signal",
                "rift-rail-internal-rail",
                "rift-rail-collider",
                "rift-rail-blocker",
                "rift-rail-lamp",
            }
            local total_components = 0
            for _, surface in pairs(game.surfaces) do
                for _, entity in pairs(surface.find_entities_filtered({ name = component_names })) do
                    total_components = total_components + 1
                    if not State.get_struct(entity) then
                        -- [修正] 对 entity.unit_number 进行安全转换，防止 simple-entity (如 collider) 因没有 unit_number 而报错
                        table.insert(entity_ghosts, "Entity '" .. entity.name .. "' (Unit No: " .. tostring(entity.unit_number) .. ") at [gps=" .. entity.position.x .. "," .. entity.position.y .. "," .. entity.surface.name .. "] has no corresponding struct data.")
                    end
                end
            end
            report["Entity Ghosts (Entity exists, Data gone)"] = entity_ghosts

            -- 3. 总结
            report["Summary"] = {
                ["Total structs in storage"] = total_structs,
                ["Total Rift Rail components in world"] = total_components, -- 修正了描述
                ["Data ghosts found"] = #data_ghosts,
                ["Entity ghosts found"] = #entity_ghosts,
            }

            return report
        elseif key == "selected" or key == "get_by_id" or key == "get_by_unit" then
            return get_struct(key, param)
        end

        -- 更新可用键列表
        return "Unknown debug key. Available: 'count', 'size', 'find_ghosts', 'selected', 'get_by_id', 'get_by_unit'."
    end,
})
