-- scripts/builder.lua v0.0.10
-- 功能：移除所有多余的方向映射，直接使用 Factorio 标准 16方向制 (0, 4, 8, 12)

local Builder = {}
-- local CybersynSE = nil -- [新增]
local log_debug = function() end

function Builder.init(deps)
    if deps.log_debug then log_debug = deps.log_debug end
    -- CybersynSE = deps.CybersynSE -- [新增]
end

-- ============================================================================
-- 基准布局 (方向 0 / North / 竖向)
-- 坐标系：X右(+), Y下(+)
-- 设定：入口在下方(Y=5)，死胡同在上方(Y=-4)
-- ============================================================================
local MASTER_LAYOUT = {
    -- 铁轨 (竖向排列)
    rails = {
        -- [新增] 延伸接口 (舌头)
        -- y=6 (这节铁轨覆盖 y=5 到 y=7)
        -- 这样 y=5 的信号灯就正好位于它和下一节铁轨的中间，位置完美！
        { x = 0, y = 6 },
        { x = 0, y = 4 },
        { x = 0, y = 2 },
        { x = 0, y = 0 },
        { x = 0, y = -2 },
        { x = 0, y = -4 }
    },

    -- 信号灯 (入口处 Y=5)
    signals = {
        -- 右侧 (同侧/进入): 必须反转180度，面对驶来的列车
        { x = 1.5,  y = 5, flip = true },
        -- 左侧 (异侧/离开): 保持同向，面对反向驶来的列车
        { x = -1.5, y = 5, flip = false }
    },

    -- 车站 (死胡同底部)
    -- 0方向(向上开)时，车站应在右侧 (East / +X)
    station = { x = 2, y = -4 },
    -- 物理堵头 (死胡同端 Y=-6)
    -- 铁轨结束于 -5，堵头放在 -6，正好封死出口
    blocker = { x = 0, y = -6 },
    collider = { x = 0, y = -2 },
    core = { x = 0, y = 0 },
    -- [新增] 照明灯 (放在中心，照亮整个建筑)
    lamp = { x = 0, y = 0 }
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
-- 构建函数
-- ============================================================================
function Builder.on_built(event)
    local entity = event.entity
    if not (entity and entity.valid and entity.name == "rift-rail-placer-entity") then return end

    if not storage.rift_rails then storage.rift_rails = {} end

    -- >>>>> [新增：提前计算 ID] >>>>>
    if not storage.next_rift_id then storage.next_rift_id = 1 end
    local custom_id = storage.next_rift_id
    storage.next_rift_id = storage.next_rift_id + 1
    -- <<<<< [新增结束] <<<<<

    local surface = entity.surface
    local raw_position = entity.position
    local direction = entity.direction -- 0, 4, 8, 12
    local force = entity.force

    -- 网格吸附 (保持这个，非常重要)
    local position = {
        x = math.floor(raw_position.x / 2) * 2 + 1,
        y = math.floor(raw_position.y / 2) * 2 + 1
    }

    -- 直接使用 direction，不进行任何奇怪的映射
    log_debug("构建... 方向: " .. direction)

    entity.destroy()

    -- 1. 创建主体
    local shell = surface.create_entity {
        name = "rift-rail-entity",
        position = position,
        direction = direction, -- 直接传 0, 4, 8, 12
        force = force
    }
    if not shell then return end
    shell.destructible = false

    local children = {}

    -- 2. 创建铁轨
    local rail_dir = get_rail_dir(direction) -- 获取 0 或 2
    for _, p in pairs(MASTER_LAYOUT.rails) do
        local offset = rotate_point(p, direction)
        local rail = surface.create_entity {
            name = "rift-rail-internal-rail",
            position = { x = position.x + offset.x, y = position.y + offset.y },
            direction = rail_dir,
            force = force
        }
        table.insert(children, rail)
    end

    -- 3. 创建信号灯
    for _, s in pairs(MASTER_LAYOUT.signals) do
        local offset = rotate_point(s, direction)

        local sig_dir = direction
        if s.flip then
            -- 16方向制下，旋转180度 = 加8
            sig_dir = (direction + 8) % 16
        end

        local signal = surface.create_entity {
            name = "rift-rail-signal",
            position = { x = position.x + offset.x, y = position.y + offset.y },
            direction = sig_dir,
            force = force
        }
        table.insert(children, signal)
    end

    -- 4. 创建车站
    local st_offset = rotate_point(MASTER_LAYOUT.station, direction)
    local station = surface.create_entity {
        name = "rift-rail-station",
        position = { x = position.x + st_offset.x, y = position.y + st_offset.y },
        direction = direction,
        force = force
    }

    -- [新增] 设置初始名称: [图标] ID
    -- 这样一建造出来，车站名字就是对的
    station.backer_name = "[item=rift-rail-placer] " .. tostring(custom_id)

    table.insert(children, station)
    -- 5. 创建 GUI 核心
    local core_offset = rotate_point(MASTER_LAYOUT.core, direction)
    local core = surface.create_entity {
        name = "rift-rail-core",
        position = { x = position.x + core_offset.x, y = position.y + core_offset.y },
        direction = direction,
        force = force
    }
    table.insert(children, core)

    -- 6. 创建触发器
    local col_offset = rotate_point(MASTER_LAYOUT.collider, direction)
    local collider = surface.create_entity {
        name = "rift-rail-collider",
        position = { x = position.x + col_offset.x, y = position.y + col_offset.y },
        force = force
    }
    table.insert(children, collider)

    -- 7. 创建物理堵头
    local blk_offset = rotate_point(MASTER_LAYOUT.blocker, direction)
    local blocker = surface.create_entity {
        name = "rift-rail-blocker",
        position = { x = position.x + blk_offset.x, y = position.y + blk_offset.y },
        force = force
    }
    table.insert(children, blocker)

    -- 8. 创建照明灯
    local lamp_offset = rotate_point(MASTER_LAYOUT.lamp, direction)
    local lamp = surface.create_entity {
        name = "rift-rail-lamp",
        position = { x = position.x + lamp_offset.x, y = position.y + lamp_offset.y },
        force = force
    }
    table.insert(children, lamp)

    -- [修正] 存储完整的数据结构
    storage.rift_rails[shell.unit_number] = {
        id = custom_id,                                      -- [修改] 使用自定义 ID (1, 2, 3...)
        unit_number = shell.unit_number,                     -- 保留实体 ID 用于索引

        name = tostring(custom_id),                          -- [修改] 默认名字就是 ID
        icon = { type = "item", name = "rift-rail-placer" }, -- [修改] 默认带图标

        surface = shell.surface,
        mode = "neutral",
        cybersyn_enabled = false,
        shell = shell,
        children = children,
        paired_to_id = nil
    }
end

-- [新增] 强制清理区域内的火车 (防止拆除铁轨后留下幽灵车厢)
local function clear_trains_inside(shell_entity)
    if not (shell_entity and shell_entity.valid) then return end

    -- 定义搜索范围 (以建筑中心为原点，稍微大一点点以覆盖边缘)
    local search_area = {
        left_top = { x = shell_entity.position.x - 2.5, y = shell_entity.position.y - 6.5 },
        right_bottom = { x = shell_entity.position.x + 2.5, y = shell_entity.position.y + 6.5 }
    }

    -- 查找所有类型的车辆
    local trains = shell_entity.surface.find_entities_filtered {
        area = search_area,
        type = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" }
    }

    -- 强制销毁
    for _, carriage in pairs(trains) do
        if carriage and carriage.valid then
            carriage.destroy()
        end
    end
end


-- ============================================================================
-- 拆除函数 (兼容性修复版)
-- ============================================================================
function Builder.on_destroy(event)
    local entity = event.entity
    if not (entity and entity.valid) then return end

    -- 过滤非本模组实体
    if not string.find(entity.name, "rift%-rail") then return end
    -- >>>>> [新增] 特例：碰撞器死亡是传送触发信号，绝对不能触发拆除逻辑！ <<<<<
    if entity.name == "rift-rail-collider" then
        return
    end
    -- <<<<< [新增结束] <<<<<
    local surface = entity.surface
    local center_pos = entity.position
    local target_id = nil

    -- [修正] 使用 tostring 防止因实体没有 ID 而报错
    log_debug(">>> [拆除触发] 实体: " .. entity.name .. " ID: " .. tostring(entity.unit_number))

    -- 1. 尝试通过 ID 查找数据
    if storage.rift_rails then
        if entity.name == "rift-rail-entity" then
            -- 情况 A: 直接拆除主体
            target_id = entity.unit_number
        else
            -- 情况 B: 拆除零件 -> 反向查找
            for id, data in pairs(storage.rift_rails) do
                -- [兼容性修复] 无论数据是新结构 {children={...}} 还是旧结构 {...}，都尝试获取列表
                local children_list = data.children or data

                -- 在列表中搜索
                for _, child in pairs(children_list) do
                    if child == entity then
                        target_id = id
                        break
                    end
                end

                -- [位置反查] 针对 Core 的保底逻辑
                if not target_id and entity.name == "rift-rail-core" then
                    if data.shell and data.shell.valid then
                        if data.shell.position.x == center_pos.x and data.shell.position.y == center_pos.y then
                            target_id = id
                        end
                    end
                end

                if target_id then break end
            end
        end
    end

    -- 2. 执行标准清理
    if target_id and storage.rift_rails[target_id] then
        log_debug(">>> [拆除-查表成功] ID: " .. target_id)
        local data = storage.rift_rails[target_id]

        --[[         -- >>>>> [新增] Cybersyn 数据清理 >>>>>
        -- 如果启用了 SE 兼容模式，通知它清理残留数据
        if CybersynSE and CybersynSE.on_portal_destroyed then
            CybersynSE.on_portal_destroyed(data)
        end
        -- <<<<< [新增结束] <<<<< ]]

        -- >>>>> [修正] 拆除时的配对清理逻辑 >>>>>
        if data.paired_to_id then
            local partner = nil
            -- 1. 必须遍历查找，因为 Key 是 UnitNumber，而我们要找的是 Custom ID
            for _, struct in pairs(storage.rift_rails) do
                if struct.id == data.paired_to_id then
                    partner = struct
                    break
                end
            end

            if partner then
                -- 2. 解除配对
                partner.paired_to_id = nil

                -- 3. 强制重置为无状态
                partner.mode = "neutral"

                -- >>>>> [新增修改] 清理遗留的拖船 (Tug) >>>>>
                if partner.tug and partner.tug.valid then
                    log_debug("Builder [Cleanup]: 检测到出口侧有残留拖船，正在销毁...")
                    partner.tug.destroy()
                    partner.tug = nil
                end
                -- <<<<< [修改结束] <<<<<

                -- 4. 物理清理: 删掉它的碰撞器
                if partner.shell and partner.shell.valid then
                    local colliders = partner.shell.surface.find_entities_filtered {
                        name = "rift-rail-collider",
                        position = partner.shell.position,
                        radius = 5
                    }
                    for _, c in pairs(colliders) do
                        if c.valid then c.destroy() end
                    end
                end

                -- 5. 刷新 GUI (虽然 Builder 没加载 GUI 模块，但只要数据改了，
                -- 玩家下次打开或者 GUI 自动刷新时就会显示 "未连接"，而不是报错)
            end
        end
        -- <<<<< [修正结束] <<<<<

        -- [兼容性修复] 确定子实体列表和主体
        -- 如果 data.children 存在，说明是新结构；否则假设 data 本身就是列表（旧结构）
        local list_to_destroy = data.children or data
        local shell_entity = data.shell -- 旧结构可能没有这个字段，为 nil

        -- A. 清理火车 (如果有主体引用)
        if shell_entity and shell_entity.valid then
            clear_trains_inside(shell_entity)
        else
            -- [保底] 如果找不到主体引用，手动指定范围清理火车
            local train_search_area = {
                left_top = { x = center_pos.x - 6, y = center_pos.y - 6 },
                right_bottom = { x = center_pos.x + 6, y = center_pos.y + 6 }
            }
            local trains = surface.find_entities_filtered { area = train_search_area, type = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" } }
            for _, t in pairs(trains) do t.destroy() end
        end

        -- B. 销毁所有子实体
        local count = 0
        for _, child in pairs(list_to_destroy) do
            if child and child.valid and child ~= entity then
                child.destroy()
                count = count + 1
            end
        end
        log_debug(">>> [拆除] 子实体销毁数: " .. count)

        -- C. 销毁主体 (如果 shell 引用存在)
        if shell_entity and shell_entity.valid and shell_entity ~= entity then
            shell_entity.destroy()
            log_debug(">>> [拆除] 关联主体已销毁")
        end

        -- D. 无论如何，尝试销毁该位置可能残留的主体 (针对旧数据)
        if not shell_entity and entity.name ~= "rift-rail-entity" then
            local potential_shells = surface.find_entities_filtered { name = "rift-rail-entity", position = center_pos }
            for _, s in pairs(potential_shells) do s.destroy() end
        end

        storage.rift_rails[target_id] = nil
        return
    end

    -- 3. [保底措施] 暴力扫荡
    log_debug(">>> [拆除-保底扫荡] 启动暴力清理模式...")

    -- 清火车
    local sweep_area = {
        left_top = { x = center_pos.x - 6, y = center_pos.y - 6 },
        right_bottom = { x = center_pos.x + 6, y = center_pos.y + 6 }
    }
    local trains = surface.find_entities_filtered { area = sweep_area, type = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" } }
    for _, t in pairs(trains) do t.destroy() end

    -- 清零件
    local junk = surface.find_entities_filtered {
        area = sweep_area,
        name = {
            "rift-rail-entity", "rift-rail-core", "rift-rail-station",
            "rift-rail-signal", "rift-rail-internal-rail",
            "rift-rail-collider", "rift-rail-blocker"
        }
    }

    local junk_count = 0
    for _, item in pairs(junk) do
        if item.valid and item ~= entity then
            item.destroy()
            junk_count = junk_count + 1
        end
    end
    log_debug(">>> [拆除] 暴力扫荡数: " .. junk_count)
end

return Builder
