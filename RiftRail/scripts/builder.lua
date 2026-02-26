-- scripts/builder.lua v0.0.10
-- 功能：移除所有多余的方向映射，直接使用 Factorio 标准 16方向制 (0, 4, 8, 12)

-- builder.lua
local Builder = {}
local State = nil

local log_debug = function() end

function Builder.init(deps)
    flib_util = deps.flib_util
    State = deps.State
    Logic = deps.Logic
    Util = deps.Util
    if deps.log_debug then
        log_debug = deps.log_debug
    end
end

-- ============================================================================
-- 基准布局 (方向 0 / North / 竖向)
-- 坐标系：X右(+), Y下(+)
-- 设定：入口在下方(Y=5)，死胡同在上方(Y=-4)
-- ============================================================================
local MASTER_LAYOUT = {
    -- 铁轨 (竖向排列)
    rails = {
        -- 延伸接口 (舌头)
        -- y=6 (这节铁轨覆盖 y=5 到 y=7)
        -- 这样 y=5 的信号灯就正好位于它和下一节铁轨的中间，位置完美！
        { x = 0, y = 6 },
        { x = 0, y = 4 },
        { x = 0, y = 2 },
        { x = 0, y = 0 },
        { x = 0, y = -2 },
        { x = 0, y = -4 },
    },

    -- 信号灯 (入口处 Y=5)
    signals = {
        -- 右侧 (同侧/进入): 必须反转180度，面对驶来的列车
        { x = 1.5,  y = 5, flip = true },
        -- 左侧 (异侧/离开): 保持同向，面对反向驶来的列车
        { x = -1.5, y = 5, flip = false },
    },

    -- 车站 (死胡同底部)
    -- 0方向(向上开)时，车站应在右侧 (East / +X)
    station = { x = 2, y = -4 },
    -- 物理堵头 (死胡同端 Y=-6)
    -- 铁轨结束于 -5，堵头放在 -6，正好封死出口
    blocker = { x = 0, y = -6 },
    collider = { x = 0, y = -2 },
    core = { x = 0, y = 0 },
    -- 照明灯 (放在中心，照亮整个建筑)
    lamp = { x = 0, y = 0 },
}

-- ============================================================================
-- 坐标旋转函数 (标准 2D 旋转)
-- ============================================================================
local function rotate_point(point, dir)
    local x, y = point.x, point.y

    if dir == 0 then      -- North (不转)
        return { x = x, y = y }
    elseif dir == 4 then  -- East (顺时针90度)
        return { x = -y, y = x }
    elseif dir == 8 then  -- South (180度)
        return { x = -x, y = -y }
    elseif dir == 12 then -- West (逆时针90度)
        return { x = y, y = -x }
    end
    return { x = x, y = y }
end

-- ============================================================================
-- 铁轨方向判断 (Factorio 直轨只有 0 和 2)
-- ============================================================================
local function get_rail_dir(dir)
    -- 如果建筑是横向 (4 或 12)，铁轨就是横向
    if dir == 4 or dir == 12 then
        return 4 -- [修正] 从 2 改为 4。在16方向制中，4才是正东(横向)。
    end
    -- 否则是竖向 (0)
    return 0
end
-- ============================================================================
-- 构建函数 (支持蓝图恢复与标签读取)
-- ============================================================================
function Builder.on_built(event)
    local entity = event.entity
    if not (entity and entity.valid) then
        return
    end
    if entity.name ~= "rift-rail-placer-entity" and entity.name ~= "rift-rail-entity" then
        return
    end

    -- 确保 storage 结构完整
    if not storage.rift_rails then
        storage.rift_rails = {}
    end
    if not storage.rift_rail_id_map then
        storage.rift_rail_id_map = {}
    end

    -- 生成新 ID
    if not storage.next_rift_id then
        storage.next_rift_id = 1
    end
    local custom_id = storage.next_rift_id
    storage.next_rift_id = storage.next_rift_id + 1

    local surface = entity.surface
    local force = entity.force
    local direction = entity.direction

    local tags = event.tags or {}
    local recovered_mode = tags.rr_mode or "neutral"
    local recovered_name = tags.rr_name or tostring(custom_id)
    local recovered_icon = tags.rr_icon
    local recovered_prefix = tags.rr_prefix

    local shell = nil
    local position = nil

    if entity.name == "rift-rail-placer-entity" then
        local raw_position = entity.position
        position = {
            x = math.floor(raw_position.x / 2) * 2 + 1,
            y = math.floor(raw_position.y / 2) * 2 + 1,
        }
        entity.destroy()
        shell = surface.create_entity({
            name = "rift-rail-entity",
            position = position,
            direction = direction,
            force = force,
        })
    else
        shell = entity
        position = shell.position
    end

    if not shell then
        return
    end

    local children = {}

    -- 辅助函数，用于创建子实体并记录相对坐标
    local function create_child(name, relative_pos, child_dir, extra_properties)
        local world_pos = { x = position.x + relative_pos.x, y = position.y + relative_pos.y }
        local entity_proto = {
            name = name,
            position = world_pos,
            direction = child_dir,
            force = force,
        }

        -- 1. 先创建实体，不包含 backer_name
        local child_entity = surface.create_entity(entity_proto)

        -- 2. 在实体创建之后，再设置它的运行时属性
        if extra_properties and child_entity and child_entity.valid then
            if extra_properties.backer_name then
                child_entity.backer_name = extra_properties.backer_name
            end
            -- 未来如果需要设置其他运行时属性，也可以加在这里
        end

        table.insert(children, { entity = child_entity, relative_pos = relative_pos })
        return child_entity
    end

    -- 2. 创建铁轨
    local rail_dir = get_rail_dir(direction)
    for _, p in pairs(MASTER_LAYOUT.rails) do
        local offset = rotate_point(p, direction)
        create_child("rift-rail-internal-rail", offset, rail_dir)
    end

    -- 3. 创建信号灯
    for _, s in pairs(MASTER_LAYOUT.signals) do
        local offset = rotate_point(s, direction)
        local sig_dir = direction
        if s.flip then
            sig_dir = (direction + 8) % 16
        end
        create_child("rift-rail-signal", offset, sig_dir)
    end

    -- 4. 创建车站
    local st_offset = rotate_point(MASTER_LAYOUT.station, direction)

    -- 计算搜索坐标
    -- 这样搜索点就位于 (2, 7) 而不是 (0, 6.5)，完美避开铁轨
    local search_pos = { x = position.x, y = position.y }

    if direction == 0 then
        search_pos.x = search_pos.x + 2
        search_pos.y = search_pos.y + 7
    elseif direction == 4 then
        search_pos.x = search_pos.x - 7
        search_pos.y = search_pos.y + 2
    elseif direction == 8 then
        search_pos.x = search_pos.x - 2
        search_pos.y = search_pos.y - 7
    elseif direction == 12 then
        search_pos.x = search_pos.x + 7
        search_pos.y = search_pos.y - 2
    end

    if RiftRail.DEBUG_MODE_ENABLED then
        log_debug("[Builder] 正在侧面安全区搜寻幽灵: " .. search_pos.x .. ", " .. search_pos.y)
    end

    local ghosts = surface.find_entities_filtered({
        type = "entity-ghost",
        ghost_name = "rift-rail-station",
        position = search_pos,
        radius = 2, -- 范围 1.0 足够覆盖了
        limit = 1,
    })

    local prefix = recovered_prefix

    -- 幽灵数据解析与重组
    if ghosts[1] and ghosts[1].valid then
        local ghost = ghosts[1]
        local snatched_str = ghost.backer_name

        if snatched_str and snatched_str ~= "" then
            if RiftRail.DEBUG_MODE_ENABLED then
                log_debug("[Builder] 窃取到原始名字: " .. snatched_str)
            end

            -- 1. 清洗：移除专用图标
            local clean_str = string.gsub(snatched_str, "%[item=rift%-rail%-placer%]", "")

            -- 2. 解析：提取自定义图标和名字
            local prefix, icon_type, icon_name, separator, plain_name = string.match(clean_str,
                "^(%s*)%[([%w%-]+)=([%w%-]+)%](%s*)(.*)")

            if icon_type and icon_name then
                recovered_icon = { type = icon_type, name = icon_name }
                recovered_name = (separator or "") .. (plain_name or "")
            else
                recovered_icon = nil
                -- 纯文本模式也要分离出 prefix
                local p_space, p_name = string.match(clean_str, "^(%s*)(.*)")
                prefix = p_space
                recovered_name = p_name or ""
            end
        end
        ghost.destroy()
    end

    -- 3. 标准化重组 (这一步确保了无论蓝图怎么改，生成的格式永远是标准的)
    local master_icon = "[item=rift-rail-placer]"

    local user_icon_str = ""
    if recovered_icon then
        user_icon_str = "[" .. recovered_icon.type .. "=" .. recovered_icon.name .. "]"
    end

    local final_backer_name = master_icon .. (prefix or "") .. user_icon_str .. recovered_name

    -- 4. 创建实体车站
    -- 捕获返回的车站实体，以便设置初始属性
    local station_ent = create_child("rift-rail-station", st_offset, direction, { backer_name = final_backer_name })

    -- 如果蓝图/恢复时是出口模式，初始化为禁止驶入
    if recovered_mode == "exit" and station_ent and station_ent.valid then
        station_ent.trains_limit = 0
    end

    -- 5. 创建 GUI 核心
    local core_offset = rotate_point(MASTER_LAYOUT.core, direction)
    create_child("rift-rail-core", core_offset, direction)

    -- 6. 创建触发器
    if recovered_mode == "entry" or recovered_mode == "neutral" then
        local col_offset = rotate_point(MASTER_LAYOUT.collider, direction)

        -- 1. 捕获创建出的实体
        local collider = create_child("rift-rail-collider", col_offset, direction)

        -- 2. 建立碰撞器与传送门的映射关系 (Collider -> Portal)
        if collider and collider.unit_number then
            storage.collider_to_portal = storage.collider_to_portal or {}
            -- 写入映射: 碰撞器ID -> 传送门ID
            storage.collider_to_portal[collider.unit_number] = shell.unit_number
        end
    end

    -- 7. 创建物理堵头
    local blk_offset = rotate_point(MASTER_LAYOUT.blocker, direction)
    local blocker_entity = create_child("rift-rail-blocker", blk_offset, direction)
    if blocker_entity then
        storage.temp_blocker_pos = blocker_entity.position
    end

    -- 8. 创建照明灯
    local lamp_offset = rotate_point(MASTER_LAYOUT.lamp, direction)
    create_child("rift-rail-lamp", lamp_offset, direction)

    -- 9. 连接车站和核心的信号线（红线+绿线，不连接电力线）
    local station_entity = nil
    local core_entity = nil
    for _, child_data in pairs(children) do
        local child = child_data.entity
        if child and child.valid then
            if child.name == "rift-rail-station" then
                station_entity = child
            elseif child.name == "rift-rail-core" then
                core_entity = child
            end
        end
    end

    if station_entity and core_entity then
        -- 连接红色信号线
        core_entity.get_wire_connector(defines.wire_connector_id.circuit_red, true).connect_to(
        station_entity.get_wire_connector(defines.wire_connector_id.circuit_red, true), false, defines.wire_origin
        .script)
        -- 连接绿色信号线
        core_entity.get_wire_connector(defines.wire_connector_id.circuit_green, true).connect_to(
        station_entity.get_wire_connector(defines.wire_connector_id.circuit_green, true), false,
            defines.wire_origin.script)
        if RiftRail.DEBUG_MODE_ENABLED then
            log_debug("[Builder] 车站和核心的红绿信号线已连接")
        end
    end

    -- 批量设置内部组件属性
    for _, child_data in pairs(children) do
        local child = child_data.entity
        if child and child.valid then
            if child.name == "rift-rail-collider" then
                child.destructible = true
            else
                child.destructible = false
            end
        end
    end

    local cached_spawn, cached_area = Util.calculate_teleport_cache(shell.position, shell.direction)

    storage.rift_rails[shell.unit_number] = {
        id = custom_id,
        unit_number = shell.unit_number,
        name = recovered_name,
        icon = recovered_icon,
        mode = recovered_mode,
        surface = shell.surface,
        cybersyn_enabled = false,
        prefix = prefix,
        shell = shell,
        children = children,
        blocker_position = storage.temp_blocker_pos,
        cached_spawn_pos = cached_spawn,
        cached_check_area = cached_area,
    }
    storage.temp_blocker_pos = nil

    -- 维护 id_map 缓存
    storage.rift_rail_id_map[custom_id] = shell.unit_number
end

-- 强制清理区域内的火车 (防止拆除铁轨后留下幽灵车厢)
local function clear_trains_inside(shell_entity)
    if not (shell_entity and shell_entity.valid) then
        return
    end

    -- 定义搜索范围 (以建筑中心为原点，稍微大一点点以覆盖边缘)
    local search_area = {
        left_top = { x = shell_entity.position.x - 2.5, y = shell_entity.position.y - 6.5 },
        right_bottom = { x = shell_entity.position.x + 2.5, y = shell_entity.position.y + 6.5 },
    }

    -- 查找所有类型的车辆
    local trains = shell_entity.surface.find_entities_filtered({
        area = search_area,
        type = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" },
    })

    -- 强制销毁
    for _, car in pairs(trains) do
        if car and car.valid then
            car.destroy()
        end
    end
end

-- ============================================================================
-- 拆除函数 (最终修复版，整合精准抢救与清理逻辑)
-- ============================================================================
function Builder.on_destroy(event, player_index)
    local entity = event.entity
    if not (entity and entity.valid) then
        return
    end

    if not string.find(entity.name, "rift%-rail") then
        return
    end
    if entity.name == "rift-rail-collider" then
        return
    end

    -- 1: "精准抢救"核心信息
    -- 在任何销毁操作开始前，必须先确定建筑的中心位置和方向
    local final_center_pos = nil
    local final_direction = nil
    local surface = entity.surface
    local shell_entity_ref = nil -- 用于后续操作的 shell 实体引用

    if entity.name == "rift-rail-entity" then
        -- 情况 A: 拆除的就是外壳本身
        log_debug("[Destroy] Triggered by Shell entity.")
        shell_entity_ref = entity
    elseif entity.name == "rift-rail-core" then
        -- 情况 B: 拆除的是核心，在极小范围内反查外壳
        log_debug("[Destroy] Triggered by Core entity. Searching for shell nearby...")
        local shells = surface.find_entities_filtered({
            name = "rift-rail-entity",
            position = entity.position, -- 核心和外壳在同一中心点
            radius = 0.5,               -- 极小范围，杜绝误伤
        })
        if shells and shells[1] then
            shell_entity_ref = shells[1]
            log_debug("  - Shell found via core lookup.")
        end
    end

    -- 如果成功找到了外壳，就"抢救"它的信息
    if shell_entity_ref and shell_entity_ref.valid then
        final_center_pos = shell_entity_ref.position
        final_direction = shell_entity_ref.direction
        log_debug("[Destroy] Core info salvaged: Direction=" .. final_direction)
    else
        log_debug("[Destroy] Warning: Could not salvage core info (shell not found). Cleanup may be incomplete.")
    end
    -- [抢救结束]

    -- 2: 封装"最终清扫"逻辑
    -- 这个函数负责对最容易变"幽灵"的 collider 进行精准的点清除
    local function final_cleanup()
        if not (final_center_pos and final_direction) then
            log_debug("[Destroy] Final cleanup skipped: Missing position or direction.")
            return
        end

        log_debug("[Destroy] Executing final cleanup for collider...")
        -- 计算并清理碰撞器 (Collider)
        local col_relative_pos = { x = 0, y = -2 }
        if final_direction == 4 then
            col_relative_pos = { x = 2, y = 0 }
        elseif final_direction == 8 then
            col_relative_pos = { x = 0, y = 2 }
        elseif final_direction == 12 then
            col_relative_pos = { x = -2, y = 0 }
        end
        local collider_pos = { x = final_center_pos.x + col_relative_pos.x, y = final_center_pos.y + col_relative_pos.y }
        local colliders_found = surface.find_entities_filtered({ name = "rift-rail-collider", position = collider_pos, radius = 0.5 })
        for _, c in pairs(colliders_found) do
            if c.valid then
                log_debug("  - Found and destroyed a ghost collider via final cleanup.")
                c.destroy()
            end
        end
    end

    -- 开始查找 portaldata 以执行精准销毁
    local target_unit_number = nil
    local portaldata = State.get_portaldata(entity)
    if portaldata then
        target_unit_number = portaldata.unit_number
    end

    -- 路径 A: "精准销毁"
    if target_unit_number and storage.rift_rails and storage.rift_rails[target_unit_number] then
        log_debug("[Destroy] Path A: Precise cleanup based on portaldata.")
        local data = storage.rift_rails[target_unit_number]

        --[[ if data.paired_to_id then
            -- 【性能优化】使用 State.get_portaldata_by_id (它现在很快)
            local partner = State.get_portaldata_by_id(data.paired_to_id)
            if partner then
                partner.paired_to_id = nil
                if Logic.set_mode then
                    Logic.set_mode(nil, partner.id, "neutral", true)
                end -- 调用Logic来正确处理碰撞器
                if partner.leadertrain and partner.leadertrain.valid then
                    partner.leadertrain.destroy()
                    partner.leadertrain = nil
                end
            end
        end ]]
        -- [多对多改造] 拆除时，必须对每一个连接都执行“精准解绑”
        if data.mode == "entry" and data.target_ids then
            for target_id, _ in pairs(data.target_ids) do
                Logic.unpair_portals_specific(player_index, data.id, target_id)
            end
        elseif data.mode == "exit" and data.source_ids then
            for source_id, _ in pairs(data.source_ids) do
                Logic.unpair_portals_specific(player_index, source_id, data.id)
            end
        end

        local shell_to_check = data.shell
        if shell_to_check and shell_to_check.valid then
            clear_trains_inside(shell_to_check)
        end

        if data.children then
            for _, child_data in pairs(data.children) do
                local child = child_data.entity
                if child and child.valid and child ~= entity then
                    if child.unit_number and storage.collider_to_portal then
                        if storage.collider_to_portal[child.unit_number] then
                            storage.collider_to_portal[child.unit_number] = nil
                        end
                    end

                    child.destroy()
                end
            end
        end

        if shell_to_check and shell_to_check.valid and shell_to_check ~= entity then
            shell_to_check.destroy()
        end

        -- 维护 id_map 缓存
        storage.rift_rail_id_map[data.id] = nil
        storage.rift_rails[target_unit_number] = nil

        -- 3: 在路径 A 的出口调用清理
        final_cleanup()

        log_debug("[Destroy] Path A finished.")
        return
    end

    -- 路径 B: 如果前面的"精准销毁"失败了
    log_debug("[Destroy] Path B: Fallback cleanup (portaldata not found).")
    -- 我们不再需要旧的“暴力扫荡”了，因为 final_cleanup 已经足够精准且能处理所有情况
    -- 4: 在路径 B 的出口调用清理
    final_cleanup()
    log_debug("[Destroy] Path B finished.")
end

-- ============================================================================
-- 蓝图与高级建造事件 (从 control.lua 迁移)
-- ============================================================================

-- 1. 处理克隆事件
function Builder.on_cloned(event)
    local new_entity = event.destination
    local old_entity = event.source

    if not (new_entity and new_entity.valid) then
        return
    end
    if new_entity.name ~= "rift-rail-entity" then
        return
    end

    local old_unit_number = old_entity.unit_number
    -- 注意：因为 Builder 里可能没有引入 flib_util，如果你没引入，可以直接用 util.table.deepcopy
    local flib_util = require("util")

    local old_data = storage.rift_rails and storage.rift_rails[old_unit_number]
    if not old_data then
        return
    end

    local new_data = flib_util.table.deepcopy(old_data)
    local new_unit_number = new_entity.unit_number

    new_data.unit_number = new_unit_number
    new_data.shell = new_entity
    new_data.surface = new_entity.surface

    -- 重建 children 列表
    local old_children_list = new_data.children
    new_data.children = {}
    local new_center_pos = new_entity.position

    if old_children_list then
        for _, old_child_data in pairs(old_children_list) do
            if old_child_data.relative_pos and old_child_data.entity and old_child_data.entity.valid then
                local child_name = old_child_data.entity.name
                local expected_pos = {
                    x = new_center_pos.x + old_child_data.relative_pos.x,
                    y = new_center_pos.y + old_child_data.relative_pos.y,
                }
                local search_radius = (child_name == "rift-rail-lamp") and 1.5 or 0.5
                local found_clone = new_entity.surface.find_entities_filtered({
                    name = child_name,
                    position = expected_pos,
                    radius = search_radius,
                    limit = 1,
                })

                if found_clone and found_clone[1] then
                    table.insert(new_data.children, {
                        entity = found_clone[1],
                        relative_pos = old_child_data.relative_pos,
                    })

                    -- 【重要】如果是碰撞器，必须给克隆体上户口！
                    if child_name == "rift-rail-collider" and found_clone[1].unit_number then
                        storage.collider_to_portal = storage.collider_to_portal or {}
                        storage.collider_to_portal[found_clone[1].unit_number] = new_unit_number
                    end
                end
            end
        end
    end

    -- 清除旧的速度方向缓存
    new_data.blocker_position = nil

    -- 【核心修复】：克隆后，必须重新计算绝对坐标缓存！
    -- 假设你的 Builder.lua 顶部已经 require 了 "scripts.util" 并命名为 Util
    local cached_spawn, cached_area = Util.calculate_teleport_cache(new_entity.position, new_entity.direction)
    new_data.cached_spawn_pos = cached_spawn
    new_data.cached_check_area = cached_area

    -- 保存新数据，清理旧数据
    storage.rift_rails[new_unit_number] = new_data
    if storage.rift_rail_id_map then
        storage.rift_rail_id_map[new_data.id] = new_unit_number
    end
    storage.rift_rails[old_unit_number] = nil
end

-- 2. 处理蓝图放置
function Builder.on_setup_blueprint(event)
    if not event.mapping then
        return
    end

    local player = game.get_player(event.player_index)
    -- 智能获取蓝图
    local blueprint = player.blueprint_to_setup
    if not (blueprint and blueprint.valid and blueprint.is_blueprint) then
        blueprint = player.cursor_stack
    end
    if not (blueprint and blueprint.valid and blueprint.is_blueprint) then
        return
    end

    local entities = blueprint.get_blueprint_entities()
    if not entities then
        return
    end

    local mapping = event.mapping.get()
    local modified = false
    local new_entities = {}

    -- 用于生成唯一的 entity_number
    local max_entity_number = 0
    for _, e in pairs(entities) do
        if e.entity_number > max_entity_number then
            max_entity_number = e.entity_number
        end
    end

    for i, bp_entity in pairs(entities) do
        local source_entity = mapping[bp_entity.entity_number]

        if source_entity and source_entity.valid and source_entity.name == "rift-rail-entity" then
            -- 1. 处理主建筑 -> 替换为放置器
            modified = true
            local data = storage.rift_rails[source_entity.unit_number]

            local placer_entity = {
                entity_number = bp_entity.entity_number,
                name = "rift-rail-placer-entity",
                position = bp_entity.position,
                direction = bp_entity.direction,
                tags = {},
            }
            if data then
                placer_entity.tags.rr_name = data.name
                placer_entity.tags.rr_mode = data.mode
                placer_entity.tags.rr_icon = data.icon
                placer_entity.tags.rr_prefix = data.prefix
            end
            table.insert(new_entities, placer_entity)

            -- 2. 注入内部车站 (实现蓝图参数化)
            if data and data.children then
                for _, child_data in pairs(data.children) do
                    local child = child_data.entity
                    if child and child.valid and child.name == "rift-rail-station" then
                        -- 计算原始相对坐标 (保留横向偏移 x=2)
                        local offset_x = child.position.x - source_entity.position.x
                        local offset_y = child.position.y - source_entity.position.y
                        local dir = source_entity.direction

                        -- 纵向保持 6.5 (红绿灯下方)
                        -- 横向从 2.0 改为 3.5 (确保边缘不重叠)
                        if dir == 0 then -- North
                            offset_x = 2 -- 向右更远一点
                            offset_y = 7
                        elseif dir == 4 then -- East
                            offset_x = -7
                            offset_y = 2 -- 向下更远一点
                        elseif dir == 8 then -- South
                            offset_x = -2 -- 向左更远一点
                            offset_y = -7
                        elseif dir == 12 then -- West
                            offset_x = 7
                            offset_y = -2 -- 向上更远一点
                        end

                        max_entity_number = max_entity_number + 1

                        local station_bp_entity = {
                            entity_number = max_entity_number,
                            name = "rift-rail-station",
                            position = {
                                x = bp_entity.position.x + offset_x,
                                y = bp_entity.position.y + offset_y,
                            },
                            direction = child.direction,
                            station = child.backer_name,
                        }

                        table.insert(new_entities, station_bp_entity)
                        if RiftRail.DEBUG_MODE_ENABLED then
                            log_debug("[Control] 蓝图注入车站: 偏移修正 (" .. offset_x .. ", " .. offset_y .. ")")
                        end
                        break
                    end
                end
            end

            -- [重要] 允许车站通过过滤器
        elseif not (source_entity and source_entity.valid and source_entity.name:find("rift-rail-")) or (source_entity.name == "rift-rail-station") then
            table.insert(new_entities, bp_entity)
        end
    end

    if modified then
        blueprint.set_blueprint_entities(new_entities)
    end
end

-- 3. 处理配置粘贴 (Shift+右键/左键)
function Builder.on_settings_pasted(event)
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
        dest_data.prefix = source_data.prefix

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
                    child.backer_name = master_icon .. (dest_data.prefix or "") .. user_icon_str .. dest_data.name
                    break
                end
            end
        end

        -- 手动播放原版粘贴音效
        -- 这会让 Shift+左键 时也能听到熟悉的“咔嚓”声
        player.play_sound({ path = "utility/entity_settings_pasted" })

        -- 6. Debug 信息
        if RiftRail.DEBUG_MODE_ENABLED then
            log_debug("设置已粘贴: " .. source_data.name .. " -> " .. dest_data.name)
        end
    end
end

return Builder
