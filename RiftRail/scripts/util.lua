-- scripts/util.lua
-- 【Rift Rail - 工具库】
-- 功能：提供通用实体操作、向量计算及兼容性强的物品/流体转移功能。
-- [修改] 移除所有第三方代码引用

local Util = {}

-- 默认日志函数，会被 init 注入覆盖
local log_debug = function(msg)
    log(msg)
end

function Util.init(deps)
    if deps.log_debug then
        log_debug = deps.log_debug
    end
end

-- 本地日志包装 (统一前缀)
local function log_util(message)
    if RiftRail.DEBUG_MODE_ENABLED then
        log_debug("[RiftRail:Util] " .. message)
    end
end

---------------------------------------------------------------------------
-- 1. 向量与几何计算
---------------------------------------------------------------------------

-- 向量相加
function Util.vectors_add(a, b)
    return { x = a.x + b.x, y = a.y + b.y }
end

-- 判断坐标是否在矩形区域内
function Util.position_in_rect(rect, pos)
    if not (rect and rect.left_top and rect.right_bottom and pos) then
        return false
    end
    return pos.x >= rect.left_top.x and pos.x <= rect.right_bottom.x and pos.y >= rect.left_top.y and pos.y <= rect.right_bottom.y
end

-- 获取车辆所属的火车ID (安全获取)
function Util.get_rolling_stock_train_id(rolling_stock)
    if rolling_stock and rolling_stock.valid and rolling_stock.train and rolling_stock.train.valid then
        return rolling_stock.train.id
    end
    return nil
end

---------------------------------------------------------------------------
-- 2. 底层内容转移
---------------------------------------------------------------------------
-- =========================================================================
-- 核心物品栏转移函数 (重构版：使用 set_stack)
-- 功能：将一个物品栏的内容 1:1 克隆到另一个，完美保留位置布局、耐久度和元数据。
-- @param source_inv 源物品栏
-- @param destination_inv 目标物品栏
-- =========================================================================
function Util.move_inventory_items(source_inv, destination_inv)
    if not (source_inv and destination_inv) then
        return
    end

    -- 安全检查：获取两者的最小容量 (理论上同种实体的容量是一样的)
    -- 防止万一模组冲突导致两边大小不一致时报错
    local limit = math.min(#source_inv, #destination_inv)

    -- 遍历每一个格子
    for i = 1, limit do
        local source_stack = source_inv[i]
        local dest_stack = destination_inv[i]

        -- 只有当源格子有东西时 (valid_for_read) 才执行操作
        if source_stack.valid_for_read then
            -- 使用 set_stack 替代 insert
            -- 这会直接把源格子的内存数据（包括蓝图内容、弹药量、耐久度等）
            -- 拷贝到目标格子的【相同位置】
            dest_stack.set_stack(source_stack)
        end
    end

    -- 转移完成后，清空源物品栏
    source_inv.clear()
end

-- =========================================================================
-- 燃烧室内容转移函数
-- 功能：转移燃料、燃烧进度和废料。
-- @param source_entity 源实体
-- @param destination_entity 目标实体
-- =========================================================================
function Util.transfer_burner_contents(source_entity, destination_entity)
    if not (source_entity and source_entity.valid and destination_entity and destination_entity.valid) then
        return
    end

    -- 直接访问 .burner 属性，而不是调用不存在的 get_burner() 函数
    local burner_a = source_entity.burner
    local burner_b = destination_entity.burner

    if not (burner_a and burner_b) then
        return
    end
    if RiftRail.DEBUG_MODE_ENABLED then
        log_util("DEBUG: 检测到燃烧室，正在转移燃料与燃烧进度...")
    end

    -- 1. 转移燃料库存
    if burner_a.inventory then
        Util.move_inventory_items(burner_a.inventory, burner_b.inventory)
    end

    -- 2. 转移废料库存 (例如核燃料棒烧完的乏燃料)
    if burner_a.burnt_result_inventory then
        Util.move_inventory_items(burner_a.burnt_result_inventory, burner_b.burnt_result_inventory)
    end

    -- 3. 转移燃烧进度
    if burner_a.currently_burning then
        burner_b.remaining_burning_fuel = burner_a.remaining_burning_fuel
    end
end

---------------------------------------------------------------------------
-- 3. 高级内容转移 (整合逻辑)
---------------------------------------------------------------------------

-- 转移流体
function Util.transfer_fluids(source_entity, destination_entity)
    if not (source_entity and source_entity.valid and destination_entity and destination_entity.valid) then
        return
    end

    -- 检查是否有流体盒
    if not (source_entity.fluids_count and source_entity.fluids_count > 0) then
        return
    end

    if RiftRail.DEBUG_MODE_ENABLED then
        log_util("DEBUG: 开始转移流体，流体盒数量: " .. source_entity.fluids_count)
    end

    -- 循环
    for i = 1, source_entity.fluids_count do
        -- 获取流体
        local fluid = source_entity.get_fluid(i)

        -- 不检查过滤器，不使用 pcall，直接写入
        if fluid then
            -- 写入流体
            destination_entity.set_fluid(i, fluid)
        end
    end
end

-- 转移装备网格 (模块装甲/车辆装备)
function Util.transfer_equipment_grid(source_entity, destination_entity)
    if not (source_entity and source_entity.valid and destination_entity and destination_entity.valid) then
        return
    end

    local grid_a = source_entity.grid
    local grid_b = destination_entity.grid
    if not (grid_a and grid_b) then
        return
    end

    if RiftRail.DEBUG_MODE_ENABLED then
        log_util("DEBUG: 发现装备网格，开始转移装备...")
    end
    for _, item in pairs(grid_a.equipment) do
        if item and item.valid then
            local new_item = grid_b.put({
                name = item.name,
                position = item.position,
                quality = item.quality,
            })

            if new_item then
                if item.shield and item.shield > 0 then
                    new_item.shield = item.shield
                end
                if item.energy and item.energy > 0 then
                    new_item.energy = item.energy
                end
                if item.burner and new_item.burner then
                    Util.transfer_burner_contents(item, new_item)
                end
            else
                if RiftRail.DEBUG_MODE_ENABLED then
                    log_util("!! 警告: 无法在目标网格位置创建装备: " .. item.name)
                end
            end
        end
    end
end

-- 转移所有物品栏 (智能判断类型 - 调整顺序版：先判断类型，后尝试通用接口)
function Util.transfer_all_inventories(source_entity, destination_entity)
    if RiftRail.DEBUG_MODE_ENABLED then
        log_util("DEBUG: 开始转移实体所有物品栏 (ID: " .. source_entity.unit_number .. " -> " .. destination_entity.unit_number .. ")")
    end

    if not (source_entity and source_entity.valid and destination_entity and destination_entity.valid) then
        if RiftRail.DEBUG_MODE_ENABLED then
            log_util("错误: 源或目标实体无效，无法转移物品。")
        end
        return
    end

    local entity_type = source_entity.type
    if RiftRail.DEBUG_MODE_ENABLED then
        log_util("DEBUG: 正在检查实体类型 (Type: " .. entity_type .. ")...")
    end

    if entity_type == "cargo-wagon" then
        if RiftRail.DEBUG_MODE_ENABLED then
            log_util("DEBUG: 匹配到货运车厢，执行标准转移。")
        end
        local source_inv = source_entity.get_inventory(defines.inventory.cargo_wagon)
        local dest_inv = destination_entity.get_inventory(defines.inventory.cargo_wagon)
        Util.move_inventory_items(source_inv, dest_inv)
        Util.transfer_inventory_filters(source_entity, destination_entity, defines.inventory.cargo_wagon)
    elseif entity_type == "locomotive" then
        if RiftRail.DEBUG_MODE_ENABLED then
            log_util("DEBUG: 匹配到机车，执行燃烧室与燃料转移。")
        end
        Util.transfer_burner_contents(source_entity, destination_entity)
        Util.transfer_inventory_filters(source_entity, destination_entity, defines.inventory.fuel)
    elseif entity_type == "artillery-wagon" then
        if RiftRail.DEBUG_MODE_ENABLED then
            log_util("DEBUG: 匹配到火炮车厢，执行弹药转移。")
        end
        local source_inv = source_entity.get_inventory(defines.inventory.artillery_wagon_ammo)
        local dest_inv = destination_entity.get_inventory(defines.inventory.artillery_wagon_ammo)
        Util.move_inventory_items(source_inv, dest_inv)
        Util.transfer_inventory_filters(source_entity, destination_entity, defines.inventory.artillery_wagon_ammo)
    elseif entity_type == "fluid-wagon" then
        -- 显式调用流体转移函数
        if RiftRail.DEBUG_MODE_ENABLED then
            log_util("DEBUG: 匹配到流体车厢，执行流体转移。")
        end
        Util.transfer_fluids(source_entity, destination_entity)
    else
        -- 尝试获取主物品栏作为通用后备方案
        local source_inv = source_entity.get_main_inventory()
        local dest_inv = destination_entity.get_main_inventory()
        if source_inv and dest_inv then
            if RiftRail.DEBUG_MODE_ENABLED then
                log_util("DEBUG: 未匹配到特定类型，执行通用主物品栏转移。")
            end
            -- 调用我们新的函数
            Util.move_inventory_items(source_inv, dest_inv)
        end
    end
end

-- 转移物品栏过滤器 (修复版)
function Util.transfer_inventory_filters(source_entity, destination_entity, inventory_index)
    if not (source_entity and source_entity.valid and destination_entity and destination_entity.valid) then
        return
    end

    local source_inv = source_entity.get_inventory(inventory_index)
    local dest_inv = destination_entity.get_inventory(inventory_index)

    if not (source_inv and dest_inv) then
        return
    end

    -- 1. 复制中间键设定的槽位过滤器
    if source_inv.is_filtered() then
        if RiftRail.DEBUG_MODE_ENABLED then
            log_util("DEBUG: 检测到过滤器，正在复制过滤设置...")
        end
        -- 既然两节车厢是同一种类型，物品栏大小通常一致，直接遍历
        for i = 1, #dest_inv do
            local filter = source_inv.get_filter(i)
            if filter then
                dest_inv.set_filter(i, filter)
            end
        end
        -- 删除 dest_inv.filter_mode = source_inv.filter_mode
        -- 因为物品栏(Inventory)没有这个属性，它是实体(Entity)才有的，且货车不需要它。
    end

    -- 2. 复制红叉限制 (Bar)
    -- supports_bar 是 Inventory 的方法，不是 Entity 的
    if dest_inv.supports_bar() then
        local bar = source_inv.get_bar() -- Inventory.get_bar() 不需要参数
        if bar then
            dest_inv.set_bar(bar)
        end
    end
end

---------------------------------------------------------------------------
-- 4. 其他辅助工具
---------------------------------------------------------------------------

-- 将 SignalID 转换为富文本字符串 (用于 GUI 显示)
function Util.signal_to_richtext(signal_id)
    if not (signal_id and signal_id.type and signal_id.name) then
        return ""
    end
    return "[" .. signal_id.type .. "=" .. signal_id.name .. "]"
end

return Util
