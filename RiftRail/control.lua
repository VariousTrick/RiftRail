-- control.lua
-- Rift Rail - 主入口 v0.0.4
-- 功能：事件分发、日志管理、模块加载
-- 更新：集成传送逻辑、补全玩家传送、事件分流

-- 1. 定义调试总开关
-- local DEBUG_MODE = false

-- 2. 定义日志函数
local function log_debug(msg)
    -- [修改] 不再读取本地变量，而是直接检查全局设置
    if settings.global["rift-rail-debug-mode"].value then
        log("[RiftRail] " .. msg)
        if game then
            game.print("[RiftRail] " .. msg)
        end
    end
end

-- 3. 加载模块
local flib_util = require("util") -- 引入官方库，命名为 flib_util 避免和你自己的 Util 冲突
local Builder = require("scripts.builder")
local GUI = require("scripts.gui")
local State = require("scripts.state")
local Logic = require("scripts.logic")
local Schedule = require("scripts.schedule")
local Util = require("scripts.util")
local Teleport = require("scripts.teleport")
local CybersynSE = require("scripts.cybersyn_compat")           -- [新增] 加载兼容模块
local CybersynScheduler = require("scripts.cybersyn_scheduler") -- [新增]

-- [修改] 给 Builder 注入 CybersynSE (用于拆除清理)
if Builder.init then
    Builder.init({
        log_debug = log_debug,
        CybersynSE = CybersynSE, -- (Builder目前暂不直接调用，清理逻辑我们接管了)
    })
end

-- [新增] 初始化 Cybersyn 模块
if CybersynSE.init then
    CybersynSE.init({
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

-- [新增] 注入 Teleport 依赖
if Teleport.init then
    Teleport.init({
        State = State,
        Util = Util,
        Schedule = Schedule,
        log_debug = log_debug,
    })
end

-- [修改] 给 Logic 注入 CybersynSE (用于GUI开关)
if Logic.init then
    Logic.init({
        State = State,
        GUI = GUI,
        log_debug = log_debug,
        CybersynSE = CybersynSE, -- [新增] 正式注入
    })
end

if GUI.init then
    GUI.init({ State = State, log_debug = log_debug })
end

-- ============================================================================
-- 5. 事件注册
-- ============================================================================

-- A. 建造事件 (保持不变)
local build_events = {
    defines.events.on_built_entity,
    defines.events.on_robot_built_entity,
    defines.events.script_raised_built,
    defines.events.script_raised_revive,
}
script.on_event(build_events, Builder.on_built)

-- B. 拆除/挖掘事件 (不包含死亡事件，死亡事件单独处理)
local mine_events = {
    defines.events.on_player_mined_entity,
    defines.events.on_robot_mined_entity,
    defines.events.script_raised_destroy,
}
-- [修改] 使用匿名函数拦截
script.on_event(mine_events, function(event)
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
end)

-- C. [核心修改] 死亡事件分流 (on_entity_died)
-- 我们需要区分是 "碰撞器被撞死(触发传送)" 还是 "建筑被打爆(触发拆除)"
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
end)

-- D. [修改] Tick 循环
script.on_event(defines.events.on_tick, function(event)
    -- 1. 执行传送逻辑
    Teleport.on_tick(event)

    -- 2. [新增] 执行 Cybersyn 调度器逻辑
    if CybersynScheduler.on_tick then
        CybersynScheduler.on_tick()
    end
end)

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
-- [新增] 克隆/传送事件处理 (修复 SE 飞船移动导致的数据丢失)
-- ============================================================================
script.on_event(defines.events.on_entity_cloned, function(event)
    local new_entity = event.destination
    local old_entity = event.source

    if not (new_entity and new_entity.valid) then
        return
    end

    -- [新增] 1.1 唤醒 Cybersyn 控制器 (与 Railjump 互斥)
    if new_entity.name == "cybersyn-combinator" then
        -- 如果安装了 Railjump (zzzzz)，我们避嫌，让他去处理
        if script.active_mods["zzzzz"] then
            return
        end

        -- 否则我们自己处理：只要是在飞船上，就唤醒
        if string.find(new_entity.surface.name, "spaceship") then
            script.raise_event(defines.events.script_raised_built, { entity = new_entity })
        end
        return -- 处理完毕，退出
    end

    -- 1.2 过滤：我们只关心主体的克隆 (原有逻辑)
    if new_entity.name ~= "rift-rail-entity" then
        return
    end

    -- 2. 查找旧数据
    -- 注意：old_entity 在这一刻还是 valid 的，但马上就会被 SE 销毁
    local old_id = old_entity.unit_number
    local old_data = storage.rift_rails and storage.rift_rails[old_id]

    if not old_data then
        -- 如果旧实体本身就是个没有数据的“僵尸”，那我们无能为力
        return
    end

    -- 3. 深度拷贝数据 (避免引用传递问题)
    local new_data = flib_util.table.deepcopy(old_data)

    -- 4. 更新核心引用
    new_data.unit_number = new_entity.unit_number
    new_data.shell = new_entity
    new_data.surface = new_entity.surface

    -- 5. 重建子实体列表 (Children)
    -- 旧数据里的 children 指向的是旧表面的实体，我们需要在新表面找到对应的克隆体
    -- 方法：在主体周围小范围内搜索同名组件
    new_data.children = {}

    local child_names = {
        "rift-rail-station",
        "rift-rail-core",
        "rift-rail-signal",
        "rift-rail-internal-rail",
        "rift-rail-collider",
        "rift-rail-blocker",
        "rift-rail-lamp",
    }

    local found_children = new_entity.surface.find_entities_filtered({
        position = new_entity.position,
        radius = 10, -- 建筑本身不大，10格半径足够覆盖所有组件
        name = child_names,
    })

    for _, child in pairs(found_children) do
        table.insert(new_data.children, child)
    end

    -- 6. 保存新数据
    storage.rift_rails[new_entity.unit_number] = new_data

    -- [新增] Cybersyn 智能迁移
    local is_landing = false
    local old_is_space = string.find(old_entity.surface.name, "spaceship")
    local new_is_space = string.find(new_entity.surface.name, "spaceship")
    if old_is_space and not new_is_space then
        is_landing = true
    end

    CybersynSE.on_portal_cloned(old_data, storage.rift_rails[new_entity.unit_number], is_landing)

    -- 7. [关键] 删除旧数据
    -- 这样做是为了“欺骗” Builder.on_destroy。
    -- 当 SE 稍后销毁旧实体时，on_destroy 去查表会发现数据已经没了，
    -- 因此它不会执行“解除配对”的逻辑。配对关系得以保留。
    storage.rift_rails[old_id] = nil

    -- 8. 调试日志
    if DEBUG_MODE then
        game.print("[RiftRail] 克隆迁移成功: ID " .. old_data.id .. " | 实体ID " .. old_id .. " -> " .. new_entity.unit_number)
    end
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

    -- [关键修复] 智能获取正在编辑的蓝图
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
            if DEBUG_MODE then
                player.print("[RiftRail] 蓝图源头掉包: RiftRail Entity -> Placer")
            end
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
-- [新增] 复制粘贴设置 (Shift+右键 -> Shift+左键)
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
        -- 因为 Logic.update_name 是处理 GUI 原始字符串输入的，这里直接操作实体更方便
        if dest_data.children then
            for _, child in pairs(dest_data.children) do
                if child.valid and child.name == "rift-rail-station" then
                    -- 重建显示名称：[主图标] + [自定义图标] + 名字
                    local master_icon = "[item=rift-rail-placer] "
                    local user_icon_str = ""
                    if dest_data.icon then
                        user_icon_str = "[" .. dest_data.icon.type .. "=" .. dest_data.icon.name .. "] "
                    end
                    child.backer_name = master_icon .. user_icon_str .. dest_data.name
                    break
                end
            end
        end

        -- 6. Debug 信息
        if DEBUG_MODE then
            player.print("[RiftRail] 设置已粘贴: " .. source_data.name .. " -> " .. dest_data.name)
        end
    end
end)

-- ============================================================================
-- [最终修复] 延迟加载事件注册 (正确 API 调用版)
-- ============================================================================

-- on_init: 只在创建新游戏时运行
script.on_init(function()
    -- (这里可以留空，或者处理新游戏逻辑)
end)

-- on_load: 只在加载存档时运行
-- 使用独立的 script.on_load 函数，它不依赖 defines 表
script.on_load(function(event)
    if Teleport.init_se_events then
        Teleport.init_se_events()
    end
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

    -- [修改] 玩家传送逻辑：传送到当前建筑外部，而非配对目标
    teleport_player = function(player_index, portal_id)
        local player = game.get_player(player_index)
        local struct = State.get_struct_by_id(portal_id)

        if player and struct and struct.shell and struct.shell.valid then
            -- 计算落点：位于建筑 "口子" 外面一点的位置，防止卡住
            -- 建筑中心到口子是 6 格，我们传送在 8 格的位置
            local dir = struct.shell.direction
            local offset = { x = 0, y = 0 }

            if dir == 0 then      -- North (开口在下) -> 传送到上方
                offset = { x = 0, y = -8 }
            elseif dir == 4 then  -- East (开口在左) -> 传送到右方
                offset = { x = 8, y = 0 }
            elseif dir == 8 then  -- South (开口在上) -> 传送到下方
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

            -- >>>>> [修改开始] >>>>>
            -- 原代码: player.opened = nil
            -- 新代码: 强制查找并销毁 GUI，不再依赖事件监听
            if player.gui.screen.rift_rail_main_frame then
                player.gui.screen.rift_rail_main_frame.destroy()
            end

            -- 清空 opened 状态，确保逻辑闭环
            player.opened = nil
            -- <<<<< [修改结束] <<<<<
        else
            if player then
                player.print({ "messages.rift-rail-error-self-invalid" })
            end
        end
    end,

    open_remote_view = function(player_index, portal_id)
        Logic.open_remote_view(player_index, portal_id)
    end,
})
