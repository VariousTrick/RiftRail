-- scripts/teleport_system/teleport_factory.lua
-- 传送门车厢生成工厂模块
-- 承载所有与创建/克隆替身车厢相关的逻辑，是传送流程的"造车车间"
---@diagnostic disable: need-check-nil, undefined-global, undefined-field, param-type-mismatch

local TeleportFactory = {}

-- 依赖注入的外部模块引用
local Util = nil
local Math = nil
local log_debug = function(...) end

---@param deps table 依赖表 / Dependency table
function TeleportFactory.init(deps)
	if deps.Util then
		Util = deps.Util
	end
	if deps.Math then
		Math = deps.Math
	end
	if deps.log_debug then
		log_debug = deps.log_debug
	end
end

-- =================================================================================
-- 司机转移函数 (处理玩家和NPC两种情况)
-- =================================================================================
local function transfer_driver(old_entity, new_entity)
	if not (old_entity and old_entity.valid and new_entity and new_entity.valid) then
		return
	end

	local driver = old_entity.get_driver()
	if driver then
		old_entity.set_driver(nil)
		if driver.object_name == "LuaPlayer" then
			new_entity.set_driver(driver)
		elseif driver.valid and driver.teleport then
			driver.teleport(new_entity.position, new_entity.surface)
			new_entity.set_driver(driver)
		end
	end
end

-- =================================================================================
-- 【克隆工厂 v3.0 - 旋转克隆】 - 统一处理所有平行传送
-- =================================================================================
---@param old_entity LuaEntity 原车厢实体 / Old carriage entity
---@param surface LuaSurface 目标地表 / Target surface
---@param position Position 目标坐标 / Target position
---@param needs_rotation boolean 是否需要在克隆前进行原地180度旋转 / Whether needs rotation
---@return LuaEntity|nil 新车厢实体 / New carriage entity
local function spawn_via_clone(old_entity, surface, position, needs_rotation)
	if not (old_entity and old_entity.valid) then
		return nil
	end

	-- 步骤 1: 如果需要，执行"断开->旋转"
	if needs_rotation then
		-- 物理隔离，为旋转做准备
		old_entity.disconnect_rolling_stock(defines.rail_direction.front)
		old_entity.disconnect_rolling_stock(defines.rail_direction.back)

		-- 尝试原地掉头
		local rotated_successfully = old_entity.rotate()

		if not rotated_successfully then
			-- 极端情况：由于铁轨扭曲等原因，原地旋转失败。
			-- 优雅地失败，让主逻辑降级到 create_entity。
			if RiftRail.DEBUG_MODE_ENABLED then
				log_debug("[RiftRail:Factory] 警告：车厢在入口原地旋转失败，将尝试使用 create_entity 降级处理。")
			end
			return nil -- 返回 nil，主逻辑会知道需要使用备用方案
		end
	end

	-- 步骤 2: 极速克隆
	-- 无论是旋转过的还是没旋转的，都直接克隆
	local new_entity = old_entity.clone({
		surface = surface,
		position = position,
		force = old_entity.force,
		create_build_effect_smoke = false,
	})

	if not new_entity then
		-- 克隆失败，可能是出口在最后一刻被堵住
		-- 不需要做任何回滚，主逻辑会在下一tick重新尝试
		return nil
	end

	-- 步骤 3: 手动转移司机 (clone 唯一不复制的东西)
	transfer_driver(old_entity, new_entity)

	return new_entity
end

-- =================================================================================
-- 【克隆工厂】生成替身车厢并转移所有属性
-- =================================================================================
---@param old_entity LuaEntity 原车厢实体 / Old carriage entity
---@param surface LuaSurface 目标地表 / Target surface
---@param position Position 目标坐标 / Target position
---@param orientation number 目标朝向(0.0-1.0) / Target orientation (0.0-1.0)
---@return LuaEntity|nil 新车厢实体 / New carriage entity
local function spawn_cloned_car(old_entity, surface, position, orientation)
	if not (old_entity and old_entity.valid) then
		return nil
	end

	-- 1. 创建实体 (Factorio 2.0 API: 支持 quality 和 orientation)
	local new_entity = surface.create_entity({
		name = old_entity.name,
		position = position,
		orientation = orientation,
		force = old_entity.force,
		quality = old_entity.quality,
		snap_to_train_stop = false, -- 建议设为 false 以提高位置精确度
		snap_to_grid = false,
		create_build_effect_smoke = false,
		raise_built = true,
	})

	if not new_entity then
		if RiftRail.DEBUG_MODE_ENABLED then
			log_debug("[RiftRail:Factory] 克隆工厂: 创建实体失败 " .. old_entity.name)
		end
		return nil
	end

	-- 使用 copy_settings 一键同步配置 (颜色、名字、过滤器、红叉、中断等)
	new_entity.copy_settings(old_entity)

	-- 2. 基础属性同步
	new_entity.health = old_entity.health

	-- 3. 内容转移 (调用 Util)
	Util.clone_all_inventories(old_entity, new_entity)
	Util.clone_fluid_contents(old_entity, new_entity)
	Util.clone_grid(old_entity, new_entity)

	-- 4. 司机转移 (特殊处理)
	transfer_driver(old_entity, new_entity)

	return new_entity
end

-- =================================================================================
-- 【智能生成决策 v4.0】 - 封装所有创建逻辑的主函数
-- =================================================================================
-- 这个函数是传送的核心大脑，它会决定使用最高效的方式创建下一节车厢。
---@param car LuaEntity 要传送的旧车厢 / Old carriage to teleport
---@param entry_portaldata PortalData 入口数据 / Entry portal data
---@param exit_portaldata PortalData 出口数据 / Exit portal data
---@param spawn_pos Position 出口生成坐标 / Spawn position
---@param geo table 几何数据 / Geometry data
---@return LuaEntity|nil 新车厢实体 / New carriage entity
function TeleportFactory.spawn_next_car_intelligently(car, entry_portaldata, exit_portaldata, spawn_pos, geo)
	local new_car = nil

	-- 首先，判断入口和出口铁轨是否平行
	local entry_dir = entry_portaldata.shell.direction
	local exit_dir = exit_portaldata.shell.direction
	local is_parallel = (entry_dir == exit_dir) or ((entry_dir + 8) % 16 == exit_dir)

	if is_parallel then
		-- 铁轨平行，尝试使用 clone
		local needs_rotation = (entry_dir == exit_dir) -- 建筑同向时，需要旋转
		if RiftRail.DEBUG_MODE_ENABLED then
            log_debug("[RiftRail:Factory] 优化: 铁轨平行，尝试使用 clone()。" .. (needs_rotation and " (需要旋转)" or " (无需旋转)"))
		end
		new_car = spawn_via_clone(car, exit_portaldata.surface, spawn_pos, needs_rotation)
	end

	-- 降级/备用路径：如果不是平行，或者 clone 失败（比如旋转失败），则使用传统方法
	if not new_car then
		if is_parallel and RiftRail.DEBUG_MODE_ENABLED then
			log_debug("[RiftRail:Factory] Clone 路径失败，降级至 create_entity 进行传送。")
		end
		local target_ori, _ = Math.calculate_arrival_orientation(entry_dir, geo.direction, car.orientation)
		new_car = spawn_cloned_car(car, exit_portaldata.surface, spawn_pos, target_ori)
	end

	return new_car
end

return TeleportFactory
