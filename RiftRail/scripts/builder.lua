-- scripts/builder.lua v0.0.10
-- 功能：移除所有多余的方向映射，直接使用 Factorio 标准 16方向制 (0, 4, 8, 12)

-- builder.lua
local Builder = {}
local State = nil

local log_debug = function() end

function Builder.init(deps)
    State = deps.State
    Logic = deps.Logic
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
        { x = 1.5, y = 5, flip = true },
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

    if dir == 0 then -- North (不转)
        return { x = x, y = y }
    elseif dir == 4 then -- East (顺时针90度)
        return { x = -y, y = x }
    elseif dir == 8 then -- South (180度)
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
            local icon_type, icon_name, separator, plain_name = string.match(clean_str, "^%s*%[([%w%-]+)=([%w%-]+)%](%s*)(.*)")

            if icon_type and icon_name then
                recovered_icon = { type = icon_type, name = icon_name }
                recovered_name = (separator or "") .. (plain_name or "")
            else
                recovered_icon = nil
                recovered_name = string.match(clean_str, "^%s*(.*)") or ""
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

    local final_backer_name = master_icon .. user_icon_str .. recovered_name

    -- 创建实体
    create_child("rift-rail-station", st_offset, direction, { backer_name = final_backer_name })

    -- 5. 创建 GUI 核心
    local core_offset = rotate_point(MASTER_LAYOUT.core, direction)
    create_child("rift-rail-core", core_offset, direction)

    -- 6. 创建触发器
    if recovered_mode == "entry" or recovered_mode == "neutral" then
        local col_offset = rotate_point(MASTER_LAYOUT.collider, direction)
        create_child("rift-rail-collider", col_offset, direction)
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

    storage.rift_rails[shell.unit_number] = {
        id = custom_id,
        unit_number = shell.unit_number,
        name = recovered_name,
        icon = recovered_icon,
        mode = recovered_mode,
        surface = shell.surface,
        cybersyn_enabled = false,
        shell = shell,
        children = children,
        blocker_position = storage.temp_blocker_pos,
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
    for _, carriage in pairs(trains) do
        if carriage and carriage.valid then
            carriage.destroy()
        end
    end
end

-- ============================================================================
-- 拆除函数 (最终修复版，整合精准抢救与清理逻辑)
-- ============================================================================
function Builder.on_destroy(event)
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
            radius = 0.5, -- 极小范围，杜绝误伤
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

    -- 开始查找 struct 以执行精准销毁
    local target_unit_number = nil
    local struct = State.get_struct(entity)
    if struct then
        target_unit_number = struct.unit_number
    end

    -- 路径 A: "精准销毁"
    if target_unit_number and storage.rift_rails and storage.rift_rails[target_unit_number] then
        log_debug("[Destroy] Path A: Precise cleanup based on struct.")
        local data = storage.rift_rails[target_unit_number]

        if data.paired_to_id then
            -- 【性能优化】使用 State.get_struct_by_id (它现在很快)
            local partner = State.get_struct_by_id(data.paired_to_id)
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
        end

        local shell_to_check = data.shell
        if shell_to_check and shell_to_check.valid then
            clear_trains_inside(shell_to_check)
        end

        if data.children then
            for _, child_data in pairs(data.children) do
                local child = child_data.entity
                if child and child.valid and child ~= entity then
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
    log_debug("[Destroy] Path B: Fallback cleanup (struct not found).")
    -- 我们不再需要旧的“暴力扫荡”了，因为 final_cleanup 已经足够精准且能处理所有情况
    -- 4: 在路径 B 的出口调用清理
    final_cleanup()
    log_debug("[Destroy] Path B finished.")
end

return Builder
