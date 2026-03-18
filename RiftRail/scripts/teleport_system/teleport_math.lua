-- scripts/teleport_system/teleport_math.lua
-- 传送门专属物理与几何计算模块
-- 承载所有纯计算逻辑：朝向判断、速度符号、意图向量等
---@diagnostic disable: need-check-nil

local TeleportMath = {}

-- =================================================================================
-- 【Rift Rail 专用几何参数】
-- =================================================================================
-- 将偏移量调整为偶数 (0)，对准铁轨中心，防止生成失败
-- 基于 "车厢生成在建筑中心 (y=0)" 的设定
TeleportMath.GEOMETRY = {
	[0] = { -- North (出口在下方 Y+)
		spawn_offset = { x = 0, y = 0 },
		direction = defines.direction.south,
		leadertrain_offset = { x = 0, y = 4.0 },
		velocity_mult = { x = 0, y = 1 },
		collider_offset = { x = 0, y = -2 },
		check_area_rel = { lt = { x = -1, y = 0 }, rb = { x = 1, y = 10 } },
	},
	[4] = { -- East (出口在左方 X-)
		spawn_offset = { x = 0, y = 0 },
		direction = defines.direction.west,
		leadertrain_offset = { x = -4.0, y = 0 },
		velocity_mult = { x = -1, y = 0 },
		collider_offset = { x = 2, y = 0 },
		check_area_rel = { lt = { x = -10, y = -1 }, rb = { x = 0, y = 1 } },
	},
	[8] = { -- South (出口在上方 Y-)
		spawn_offset = { x = 0, y = 0 },
		direction = defines.direction.north,
		leadertrain_offset = { x = 0, y = -4.0 },
		velocity_mult = { x = 0, y = -1 },
		collider_offset = { x = 0, y = 2 },
		check_area_rel = { lt = { x = -1, y = -10 }, rb = { x = 1, y = 0 } },
	},
	[12] = { -- West (出口在右方 X+)
		spawn_offset = { x = 0, y = 0 },
		direction = defines.direction.east,
		leadertrain_offset = { x = 4.0, y = 0 },
		velocity_mult = { x = 1, y = 0 },
		collider_offset = { x = -2, y = 0 },
		check_area_rel = { lt = { x = 0, y = -1 }, rb = { x = 10, y = 1 } },
	},
}

-- =================================================================================
-- 速度方向计算函数 (基于铁轨端点距离)
-- =================================================================================
--- 计算列车相对于一个参考点的逻辑方向。
---@param train LuaTrain 要计算的列车 / The train to calculate
---@param select_portal PortalData 参考传送门 / Reference portal
---@return integer 1 代表逻辑正向 (Front更远), -1 代表逻辑反向 (Back更远)。/ 1 for forward, -1 for backward
function TeleportMath.calculate_speed_sign(train, select_portal)
	-- 安全检查：如果输入无效，默认返回正向
	if not (train and train.valid and select_portal) then
		return 1
	end

	-- 使用缓存，并为旧存档/克隆体提供懒加载
	local origin_pos = select_portal.blocker_position

	-- 如果缓存不存在 (旧存档)，则计算一次并写回
	if not origin_pos then
		local shell = select_portal.shell
		-- 再次安全检查，防止 shell 失效
		if not (shell and shell.valid) then
			return 1
		end

		local shell_pos = shell.position
		local shell_dir = shell.direction
		local blocker_relative_pos = { x = 0, y = -6 }

		local rotated_offset
		if shell_dir == 0 then
			rotated_offset = { x = blocker_relative_pos.x, y = blocker_relative_pos.y }
		elseif shell_dir == 4 then
			rotated_offset = { x = -blocker_relative_pos.y, y = blocker_relative_pos.x }
		elseif shell_dir == 8 then
			rotated_offset = { x = -blocker_relative_pos.x, y = -blocker_relative_pos.y }
		else
			rotated_offset = { x = blocker_relative_pos.y, y = -blocker_relative_pos.x }
		end

		origin_pos = { x = shell_pos.x + rotated_offset.x, y = shell_pos.y + rotated_offset.y }
		select_portal.blocker_position = origin_pos -- 将计算结果写回缓存
	end

	local rail_front = train.front_end and train.front_end.rail
	local rail_back = train.back_end and train.back_end.rail

	if rail_front and rail_back then
		-- 计算距离平方 (dx^2 + dy^2), 避免开方运算
		local df_x = rail_front.position.x - origin_pos.x
		local df_y = rail_front.position.y - origin_pos.y
		local dist_sq_f = (df_x * df_x) + (df_y * df_y)

		local db_x = rail_back.position.x - origin_pos.x
		local db_y = rail_back.position.y - origin_pos.y
		local dist_sq_b = (db_x * db_x) + (db_y * db_y)

		-- API定义: 正速度驶向 front_end, 负速度驶向 back_end
		-- 如果后端(Back)离参考点更远，说明列车需要向后端行驶才能"远离"，即需要负速度。
		if dist_sq_b > dist_sq_f then
			return -1 -- 后端更远 -> 逻辑反向
		end
		-- 在所有其他情况下 (前端更远，或两端距离相等)，都判定为逻辑正向。
		-- 这可以完美处理单节车厢(距离相等)时需要正向启动的问题。
		return 1
	end

	-- 异常情况 (无法获取铁轨端点)，返回默认正向
	return 1
end

-- =================================================================================
-- 【极度昂贵：只调用一次】获取 AI 的绝对物理意图向量
-- =================================================================================
---@param train LuaTrain 要分析的列车 / The train to analyze
---@return table|nil 绝对物理意图向量 {x=number, y=number} / Absolute physical intent vector
---@note 这个函数非常昂贵，应该只在时刻表改变时调用一次，并将结果缓存起来供后续使用
function TeleportMath.get_ai_intent_vector(train)
	local path = train.path
	local rails = path and path.rails
	-- 如果没有路径，或者到了最后一截，返回 nil 走兜底
	if not rails or #rails < 2 then
		return nil
	end

	-- 用路径上前两截铁轨的坐标差，算出一个永远指向前方的绝对向量
	return {
		x = rails[2].position.x - rails[1].position.x,
		y = rails[2].position.y - rails[1].position.y,
	}
end

-- =================================================================================
-- 【极度廉价：拼接时调用】用缓存的意图向量，计算当前应给的符号
-- =================================================================================
---@param train LuaTrain 要分析的列车 / The train to analyze
---@param intent_vector table|nil 绝对物理意图向量 {x=number, y=number} / Absolute physical intent vector
---@param portaldata PortalData 传送门数据 / Portal data
---@return integer 速度符号 (1 或 -1) / Speed sign (1 or -1)
function TeleportMath.calculate_sign_from_intent(train, intent_vector, portaldata)
	-- 如果没取到意图向量，直接用"物理堵头"兜底推离
	if not intent_vector or (intent_vector.x == 0 and intent_vector.y == 0) then
		return TeleportMath.calculate_speed_sign(train, portaldata)
	end

	local front_rail = train.front_end and train.front_end.rail
	local back_rail = train.back_end and train.back_end.rail
	if not (front_rail and back_rail) then
		return TeleportMath.calculate_speed_sign(train, portaldata)
	end

	-- 取当前车身向量 (0 表格开销)
	local v_train_x = front_rail.position.x - back_rail.position.x
	local v_train_y = front_rail.position.y - back_rail.position.y

	if v_train_x == 0 and v_train_y == 0 then
		local car = train.carriages[1]
		if car then
			local angle = car.orientation * 2 * math.pi
			v_train_x = math.sin(angle)
			v_train_y = -math.cos(angle)
		end
	end

	-- 点积判断当前参考系下该给的正负号
	local dot = (v_train_x * intent_vector.x) + (v_train_y * intent_vector.y)
	return dot >= 0 and 1 or -1
end

-- =================================================================================
-- 【纯函数】计算车厢在出口生成的朝向 (Orientation 0.0-1.0)
-- =================================================================================
---@param entry_shell_dir integer|defines.direction 入口传送门朝向 / Entry portal direction
---@param exit_geo_dir integer|defines.direction 出口传送门朝向 / Exit portal direction
---@param current_ori number 当前车厢朝向 / Current carriage orientation
---@return number 目标朝向 / Target orientation
---@return boolean 是否顺向 / Is nose-in
function TeleportMath.calculate_arrival_orientation(entry_shell_dir, exit_geo_dir, current_ori)
	-- 1. 将入口建筑朝向转为 Orientation (0-1)
	local entry_shell_ori = entry_shell_dir / 16.0

	-- 2. 判断车厢是"顺着进"还是"倒着进"
	-- 计算角度差 (处理 0.0/1.0 的环形边界)
	local diff = math.abs(current_ori - entry_shell_ori)
	if diff > 0.5 then
		diff = 1.0 - diff
	end

	-- 判定阈值 (0.125 = 45度，小于45度夹角视为顺向)
	local is_nose_in = diff < 0.125

	-- 3. 计算出口基准朝向
	local exit_base_ori = exit_geo_dir / 16.0
	local target_ori = exit_base_ori

	-- 4. 根据进出关系修正最终朝向
	if not is_nose_in then
		-- 逆向进入 -> 逆向离开 (翻转 180 度即 +0.5)
		target_ori = (target_ori + 0.5) % 1.0
	end

	-- 增加第二个返回值 is_nose_in
	return target_ori, is_nose_in
end

return TeleportMath
