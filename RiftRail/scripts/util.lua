-- scripts/util.lua
-- 【Rift Rail - 工具库】
-- 功能：提供通用实体操作、向量计算及兼容性强的物品/流体转移功能。
-- 来源：基于传送门 Mod Util 模块适配，已强化调试日志。

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
	log_debug("[Util] " .. message)
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
	return pos.x >= rect.left_top.x and pos.x <= rect.right_bottom.x and pos.y >= rect.left_top.y and
	pos.y <= rect.right_bottom.y
end

-- 获取车辆所属的火车ID (安全获取)
function Util.get_rolling_stock_train_id(rolling_stock)
	if rolling_stock and rolling_stock.valid and rolling_stock.train and rolling_stock.train.valid then
		return rolling_stock.train.id
	end
	return nil
end

---------------------------------------------------------------------------
-- 2. 底层内容转移 (SE兼容核心)
---------------------------------------------------------------------------

-- 将源库存的物品移动到目标库存 (SE 风格：塞不进去就掉地上)
function Util.se_move_inventory_items(source_inv, destination_inv)
	if not (source_inv and source_inv.valid and destination_inv and destination_inv.valid) then
		return
	end

	-- log_util("DEBUG: 正在转移库存物品，格子数: " .. #source_inv)

	for i = 1, #source_inv do
		local stack = source_inv[i]
		if stack and stack.valid_for_read then
			-- 尝试转移堆叠
			if not destination_inv[i].transfer_stack(stack) then
				-- 如果无法直接转移 (例如目标格子有东西)，尝试 insert
				destination_inv.insert(stack)
			end
		end
	end

	-- 如果源库存还有残留 (说明目标满了)，则掉落在地上
	if not source_inv.is_empty() then
		local entity = destination_inv.entity_owner
		if entity and entity.valid then
			log_util("!! 警告: 目标物品栏已满，部分物品将被丢弃在实体位置: " .. serpent.line(entity.position))
			for i = 1, #source_inv do
				if source_inv[i].valid_for_read then
					entity.surface.spill_item_stack({
						position = entity.position,
						stack = source_inv[i],
						enable_looted = true,
						force = entity.force,
						allow_belts = false,
					})
				end
			end
		end
	end
	source_inv.clear()
end

-- 转移燃烧室 (燃料 + 燃烧进度 + 废料)
function Util.se_transfer_burner(source_entity, destination_entity)
	if source_entity.burner and destination_entity.burner then
		log_util("DEBUG: 检测到燃烧室，正在转移燃料与燃烧进度...")

		-- 转移燃烧进度
		if source_entity.burner.currently_burning then
			destination_entity.burner.currently_burning = source_entity.burner.currently_burning.name
			destination_entity.burner.remaining_burning_fuel = source_entity.burner.remaining_burning_fuel
		end

		-- 转移燃料槽和废料槽
		if source_entity.burner.inventory then
			Util.se_move_inventory_items(source_entity.burner.inventory, destination_entity.burner.inventory)
			if source_entity.burner.burnt_result_inventory then
				Util.se_move_inventory_items(source_entity.burner.burnt_result_inventory,
					destination_entity.burner.burnt_result_inventory)
			end
		end
	end
end

---------------------------------------------------------------------------
-- 3. 高级内容转移 (整合逻辑)
---------------------------------------------------------------------------

-- 转移流体 (支持多个流体盒)
function Util.transfer_fluids(source_entity, destination_entity)
	if not (source_entity and source_entity.valid and destination_entity and destination_entity.valid) then
		return
	end

	-- 检查是否有流体盒
	if not (source_entity.fluids_count and source_entity.fluids_count > 0) then
		return
	end

	log_util("DEBUG: 开始转移流体，流体盒数量: " .. source_entity.fluids_count)

	for i = 1, source_entity.fluids_count do
		-- 使用 pcall 防止因流体类型不匹配导致的崩溃
		local success, err_msg = pcall(function()
			local fluid = source_entity.get_fluid(i)
			if fluid then
				-- log_util("DEBUG: 转移第 " .. i .. " 号流体: " .. fluid.name .. " 数量: " .. fluid.amount)
				destination_entity.set_fluid(i, fluid)
			end
		end)

		if not success then
			log_util("!! 严重错误: 在复制第 " .. i .. " 个流体容器时失败！错误: " .. tostring(err_msg))
		end
	end
end

-- 转移装备网格 (模块装甲/车辆装备)
function Util.transfer_equipment_grid(source_entity, destination_entity)
	if not (source_entity and source_entity.valid and destination_entity and destination_entity.valid) then
		return
	end

	if source_entity.grid and destination_entity.grid then
		log_util("DEBUG: 发现装备网格，开始转移装备...")
		for _, item_stack in pairs(source_entity.grid.equipment) do
			if item_stack then
				destination_entity.grid.put({ name = item_stack.name, position = item_stack.position })
			end
		end
	end
end

-- 转移所有物品栏 (智能判断类型)
function Util.transfer_all_inventories(source_entity, destination_entity)
	log_util("DEBUG: 开始转移实体所有物品栏 (ID: " .. source_entity.unit_number .. " -> " .. destination_entity.unit_number .. ")")

	if not (source_entity and source_entity.valid and destination_entity and destination_entity.valid) then
		log_util("错误: 源或目标实体无效，无法转移物品。")
		return
	end

	-- 方案A: 尝试通用接口 get_inventories (适用于大多数 Mod 实体)
	local success, inventories_or_error = pcall(function()
		return source_entity.get_inventories(source_entity)
	end)

	if success and inventories_or_error then
		log_util("DEBUG: [方案A] 通用接口 get_inventories 调用成功，正在通过索引匹配转移...")
		local source_inventories = inventories_or_error
		local dest_inventories = destination_entity.get_inventories(destination_entity)

		if dest_inventories then
			for i, source_inv in pairs(source_inventories) do
				if source_inv and dest_inventories[i] then
					Util.se_move_inventory_items(source_inv, dest_inventories[i])
				end
			end
			return -- 方案A成功，直接返回
		end
	else
		log_util("DEBUG: [方案A] 通用接口不可用，转入 [方案B] 类型判断...")
	end

	-- 方案B: 根据类型手动处理 (SE后备方案，针对特定车厢类型)
	local entity_type = source_entity.type
	log_util("DEBUG: [方案B] 实体类型为: " .. entity_type)

	if entity_type == "cargo-wagon" then
		local source_inv = source_entity.get_inventory(defines.inventory.cargo_wagon)
		local dest_inv = destination_entity.get_inventory(defines.inventory.cargo_wagon)
		Util.se_move_inventory_items(source_inv, dest_inv)
	elseif entity_type == "locomotive" then
		Util.se_transfer_burner(source_entity, destination_entity)
	elseif entity_type == "artillery-wagon" then
		local source_inv = source_entity.get_inventory(defines.inventory.artillery_wagon_ammo)
		local dest_inv = destination_entity.get_inventory(defines.inventory.artillery_wagon_ammo)
		Util.se_move_inventory_items(source_inv, dest_inv)
	elseif entity_type == "fluid-wagon" then
		if defines.inventory.fluid_wagon then
			local source_inv = source_entity.get_inventory(defines.inventory.fluid_wagon)
			if source_inv then
				Util.se_move_inventory_items(source_inv, destination_entity.get_inventory(defines.inventory.fluid_wagon))
			end
		end
	else
		log_util("警告: 未知的实体类型 '" .. entity_type .. "'，无法确定如何转移物品。")
	end
end

-- 转移物品栏过滤器 (例如货车中间键设定的过滤)
function Util.transfer_inventory_filters(source_entity, destination_entity, inventory_index)
	if not (source_entity and source_entity.valid and destination_entity and destination_entity.valid) then
		return
	end

	local source_inv = source_entity.get_inventory(inventory_index)
	local dest_inv = destination_entity.get_inventory(inventory_index)

	if not (source_inv and dest_inv) then
		return
	end

	-- 1. 转移格子过滤器
	if source_inv.is_filtered() then
		log_util("DEBUG: 检测到过滤器，正在复制过滤设置...")
		for i = 1, #dest_inv do
			local filter = source_inv.get_filter(i)
			if filter then
				dest_inv.set_filter(i, filter)
			end
		end
		dest_inv.filter_mode = source_inv.filter_mode
	end

	-- 2. 转移红色限制条 (Inventory Bar)
	local pcall_success, supports_bar = pcall(function()
		return destination_entity.supports_inventory_bar()
	end)
	if pcall_success and supports_bar == true then
		pcall(function()
			local bar = source_entity.get_inventory_bar(inventory_index)
			destination_entity.set_inventory_bar(inventory_index, bar)
			-- log_util("DEBUG: 物品限制条已同步: " .. bar)
		end)
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
