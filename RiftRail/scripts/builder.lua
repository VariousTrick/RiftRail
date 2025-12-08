-- scripts/builder.lua v0.0.10
-- 功能：移除所有多余的方向映射，直接使用 Factorio 标准 16方向制 (0, 4, 8, 12)

local Builder = {}

local log_debug = function() end

function Builder.init(deps)
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
-- 构建函数 (核心修改：支持蓝图恢复与标签读取)
-- ============================================================================
function Builder.on_built(event)
	local entity = event.entity
	-- [修改] 既接受放置器(手放)，也接受主体(蓝图/机器人)
	if not (entity and entity.valid) then
		return
	end
	if entity.name ~= "rift-rail-placer-entity" and entity.name ~= "rift-rail-entity" then
		return
	end

	if not storage.rift_rails then
		storage.rift_rails = {}
	end

	-- 生成新 ID (无论手放还是蓝图，都视为新建筑)
	if not storage.next_rift_id then
		storage.next_rift_id = 1
	end
	local custom_id = storage.next_rift_id
	storage.next_rift_id = storage.next_rift_id + 1

	local surface = entity.surface
	local force = entity.force
	local direction = entity.direction

	-- [新增] 准备恢复数据 (从蓝图标签读取)
	local tags = event.tags or {}
	local recovered_mode = tags.rr_mode or "neutral"           -- 恢复模式，默认为 neutral
	local recovered_name = tags.rr_name or tostring(custom_id) -- 恢复名字，默认为 ID
	local recovered_icon = tags.rr_icon                        -- 恢复图标 (可能为 nil)

	-- [关键] 分流处理：确定主体 (Shell) 和 位置
	local shell = nil
	local position = nil

	if entity.name == "rift-rail-placer-entity" then
		-- >>> 情况 A: 玩家手放放置器 >>>
		-- 保持原有的网格对齐逻辑
		local raw_position = entity.position
		position = {
			x = math.floor(raw_position.x / 2) * 2 + 1,
			y = math.floor(raw_position.y / 2) * 2 + 1,
		}

		log_debug("构建(手放)... 方向: " .. direction)
		entity.destroy() -- 销毁手中的放置器实体

		-- 创建全新的主体
		shell = surface.create_entity({
			name = "rift-rail-entity",
			position = position,
			direction = direction,
			force = force,
		})
	else
		-- >>> 情况 B: 蓝图/机器人建造 >>>
		-- 实体本身就是主体 (Shell)，直接使用
		log_debug("构建(蓝图)... 方向: " .. direction .. " 恢复模式: " .. recovered_mode)
		shell = entity
		position = shell.position
		-- 不需要销毁 entity，也不需要 create shell
	end

	if not shell then
		return
	end
	-- shell.destructible = false
	-- 让 shell 保持默认的可破坏状态，这样虫子能咬它，你也能修它。

	local children = {}

	-- 2. 创建铁轨 (逻辑不变)
	local rail_dir = get_rail_dir(direction)
	for _, p in pairs(MASTER_LAYOUT.rails) do
		local offset = rotate_point(p, direction)
		local rail = surface.create_entity({
			name = "rift-rail-internal-rail",
			position = { x = position.x + offset.x, y = position.y + offset.y },
			direction = rail_dir,
			force = force,
		})
		table.insert(children, rail)
	end

	-- 3. 创建信号灯 (逻辑不变)
	for _, s in pairs(MASTER_LAYOUT.signals) do
		local offset = rotate_point(s, direction)
		local sig_dir = direction
		if s.flip then
			sig_dir = (direction + 8) % 16
		end
		local signal = surface.create_entity({
			name = "rift-rail-signal",
			position = { x = position.x + offset.x, y = position.y + offset.y },
			direction = sig_dir,
			force = force,
		})
		table.insert(children, signal)
	end

	-- 4. 创建车站 (修改：应用恢复的名字)
	local st_offset = rotate_point(MASTER_LAYOUT.station, direction)
	local station = surface.create_entity({
		name = "rift-rail-station",
		position = { x = position.x + st_offset.x, y = position.y + st_offset.y },
		direction = direction,
		force = force,
	})

	-- 拼接车站显示名称 (逻辑参考 Logic.lua)
	local master_icon = "[item=rift-rail-placer] "
	local user_icon_str = ""
	if recovered_icon then
		user_icon_str = "[" .. recovered_icon.type .. "=" .. recovered_icon.name .. "] "
	end
	station.backer_name = master_icon .. user_icon_str .. recovered_name

	table.insert(children, station)

	-- 5. 创建 GUI 核心 (逻辑不变)
	local core_offset = rotate_point(MASTER_LAYOUT.core, direction)
	local core = surface.create_entity({
		name = "rift-rail-core",
		position = { x = position.x + core_offset.x, y = position.y + core_offset.y },
		direction = direction,
		force = force,
	})
	table.insert(children, core)

	-- 6. 创建触发器 (修改：根据恢复的模式决定是否生成)
	-- 如果是入口(entry) 或 默认(neutral)，则生成碰撞器；出口(exit)则不生成
	if recovered_mode == "entry" or recovered_mode == "neutral" then
		local col_offset = rotate_point(MASTER_LAYOUT.collider, direction)
		local collider = surface.create_entity({
			name = "rift-rail-collider",
			position = { x = position.x + col_offset.x, y = position.y + col_offset.y },
			force = force,
		})
		table.insert(children, collider)
	end

	-- 7. 创建物理堵头 (逻辑不变)
	local blk_offset = rotate_point(MASTER_LAYOUT.blocker, direction)
	local blocker = surface.create_entity({
		name = "rift-rail-blocker",
		position = { x = position.x + blk_offset.x, y = position.y + blk_offset.y },
		force = force,
	})
	table.insert(children, blocker)

	-- 8. 创建照明灯 (逻辑不变)
	local lamp_offset = rotate_point(MASTER_LAYOUT.lamp, direction)
	local lamp = surface.create_entity({
		name = "rift-rail-lamp",
		position = { x = position.x + lamp_offset.x, y = position.y + lamp_offset.y },
		force = force,
	})
	table.insert(children, lamp)

	-- 批量设置内部组件属性
	for _, child in pairs(children) do
		if child.valid then
			-- 特例：碰撞器必须是"脆皮"，否则火车撞上去不会触发传送
			if child.name == "rift-rail-collider" then
				child.destructible = true
			else
				-- 其他所有组件(铁轨、信号、核心、灯)设为无敌
				-- 效果：免疫伤害、不显示血条、不会误伤
				child.destructible = false
			end
		end
	end

	-- [修改] 存储数据 (应用恢复的属性)
	storage.rift_rails[shell.unit_number] = {
		id = custom_id,
		unit_number = shell.unit_number,

		name = recovered_name, -- 使用恢复的名字
		icon = recovered_icon, -- 使用恢复的图标
		mode = recovered_mode, -- 使用恢复的模式

		surface = shell.surface,
		cybersyn_enabled = false,
		shell = shell,
		children = children,
		paired_to_id = nil, -- 新建/复制的建筑默认不配对
	}
end

-- [新增] 强制清理区域内的火车 (防止拆除铁轨后留下幽灵车厢)
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
-- 拆除函数 (兼容性修复版)
-- ============================================================================
function Builder.on_destroy(event)
	local entity = event.entity
	if not (entity and entity.valid) then
		return
	end

	-- 过滤非本模组实体
	if not string.find(entity.name, "rift%-rail") then
		return
	end
	-- 特例：碰撞器死亡是传送触发信号，绝对不能触发拆除逻辑！
	if entity.name == "rift-rail-collider" then
		return
	end

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

				if target_id then
					break
				end
			end
		end
	end

	-- 2. 执行标准清理
	if target_id and storage.rift_rails[target_id] then
		log_debug(">>> [拆除-查表成功] ID: " .. target_id)
		local data = storage.rift_rails[target_id]

		-- 拆除时的配对清理逻辑
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

				-- 清理遗留的拖船 (Tug)
				if partner.tug and partner.tug.valid then
					log_debug("Builder [Cleanup]: 检测到出口侧有残留拖船，正在销毁...")
					partner.tug.destroy()
					partner.tug = nil
				end

				-- 4. 物理清理: 删掉它的碰撞器
				if partner.shell and partner.shell.valid then
					local colliders = partner.shell.surface.find_entities_filtered({
						name = "rift-rail-collider",
						position = partner.shell.position,
						radius = 5,
					})
					for _, c in pairs(colliders) do
						if c.valid then
							c.destroy()
						end
					end
				end

				-- 5. 刷新 GUI (虽然 Builder 没加载 GUI 模块，但只要数据改了，
				-- 玩家下次打开或者 GUI 自动刷新时就会显示 "未连接"，而不是报错)
			end
		end

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
				right_bottom = { x = center_pos.x + 6, y = center_pos.y + 6 },
			}
			local trains = surface.find_entities_filtered({ area = train_search_area, type = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" } })
			for _, t in pairs(trains) do
				t.destroy()
			end
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
			local potential_shells = surface.find_entities_filtered({ name = "rift-rail-entity", position = center_pos })
			for _, s in pairs(potential_shells) do
				s.destroy()
			end
		end

		storage.rift_rails[target_id] = nil
		return
	end

	-- 3. [保底措施] 暴力扫荡
	log_debug(">>> [拆除-保底扫荡] 启动暴力清理模式...")

	-- 清火车
	local sweep_area = {
		left_top = { x = center_pos.x - 6, y = center_pos.y - 6 },
		right_bottom = { x = center_pos.x + 6, y = center_pos.y + 6 },
	}
	local trains = surface.find_entities_filtered({ area = sweep_area, type = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" } })
	for _, t in pairs(trains) do
		t.destroy()
	end

	-- 清零件
	local junk = surface.find_entities_filtered({
		area = sweep_area,
		name = {
			"rift-rail-entity",
			"rift-rail-core",
			"rift-rail-station",
			"rift-rail-signal",
			"rift-rail-internal-rail",
			"rift-rail-collider",
			"rift-rail-blocker",
		},
	})

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
