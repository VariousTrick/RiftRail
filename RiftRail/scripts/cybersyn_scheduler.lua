-- scripts/cybersyn_scheduler.lua
-- Rift Rail 专用调度器 (仅在无 SE 环境下工作)
-- 功能：拦截 Cybersyn 调度，强行插入传送门站点以支持跨地表物流

local CybersynScheduler = {}

-- 日志函数 (读取全局设置)
local function log_debug(msg)
	if settings.global["rift-rail-debug-mode"] and settings.global["rift-rail-debug-mode"].value then
		game.print("[RR调度] " .. msg)
		log("[RR调度] " .. msg)
	end
end

-- 如果启用了 Space Exploration，本模块直接失效 (交给 SE 处理)
if script.active_mods["space-exploration"] then
	return CybersynScheduler
end

local pending_trains = {}

-- 辅助：从组件中获取车站实体
local function get_station(struct)
	if struct.children then
		for _, child in pairs(struct.children) do
			if child and child.valid and child.name == "rift-rail-station" then
				return child
			end
		end
	end
	return nil
end

-- 辅助：计算距离平方
local function get_distance(pos1, pos2)
	local dx = pos1.x - pos2.x
	local dy = pos1.y - pos2.y
	return dx * dx + dy * dy
end

-- 核心算法：寻找最近的传送门
local function find_portal_station(source_surface_index, target_surface_index, origin_position)
	local portals = storage.rift_rails
	if not portals then
		return nil
	end

	local best_portal = nil
	local min_dist = math.huge

	for _, portal in pairs(portals) do
		local station = get_station(portal)
		-- 检查条件：
		-- 1. 位于源地表
		-- 2. 车站实体有效
		-- 3. 已经配对
		-- 4. Cybersyn 开关已打开
		if portal.surface.index == source_surface_index and station and station.valid and portal.paired_to_id and portal.cybersyn_enabled then
			-- 检查对侧是否在目标地表
			local partner = nil
			for _, p in pairs(portals) do
				if p.id == portal.paired_to_id then
					partner = p
					break
				end
			end

			if partner and partner.surface.index == target_surface_index then
				local dist = get_distance(portal.shell.position, origin_position)
				if dist < min_dist then
					min_dist = dist
					best_portal = portal
				end
			end
		end
	end

	if best_portal then
		local st = get_station(best_portal)
		return st.backer_name
	end
	return nil
end

-- 插入函数 (1:1 复刻 Cybersyn 逻辑)
local function insert_cybersyn_stop_sequence(new_records, original_records, target_station_data, station_type_name,
											 train_surface_index)
	if not (target_station_data and target_station_data.entity_stop and target_station_data.entity_stop.valid) then
		return
	end

	local stop_entity = target_station_data.entity_stop
	local rail = stop_entity.connected_rail
	local backer_name = stop_entity.backer_name
	local target_surface_index = stop_entity.surface.index

	-- 1. 尝试插入 Rail 导航记录 (仅当目标在同地表时)
	-- 如果目标在异地表，Factorio 无法寻路，所以只插入车站名，让列车传送过去后再寻路
	if rail and target_surface_index == train_surface_index then
		table.insert(new_records, {
			rail = rail,
			rail_direction = stop_entity.connected_rail_direction,
			temporary = true,
			wait_conditions = { { type = "time", compare_type = "and", ticks = 1 } },
		})
	end

	-- 2. 插入 Station 操作记录 (装货/卸货)
	local found = false
	for _, rec in pairs(original_records) do
		if rec.station == backer_name then
			table.insert(new_records, rec)
			found = true
			break
		end
	end
end

-- 处理单列火车
local function process_train(train)
	if not (train and train.valid and train.schedule and train.schedule.records) then
		return
	end

	-- 【互斥检查】
	-- 如果发现了 RiftRail 自己的站，或者 Railjump 的站(chuansongmen)，说明已经被处理过了，直接退出
	for _, record in pairs(train.schedule.records) do
		if record.station then
			if string.find(record.station, "rift%-rail") or string.find(record.station, "chuansongmen") then
				return
			end
		end
	end

	-- 读取 Cybersyn 数据
	local status, c_train = pcall(remote.call, "cybersyn", "read_global", "trains", train.id)
	if not (status and c_train and c_train.manifest) then
		return
	end

	-- 如果是加油状态 (7=前往加油, 8=加油中)，暂不处理
	if c_train.status == 7 or c_train.status == 8 then
		return
	end

	local p_st = remote.call("cybersyn", "read_global", "stations", c_train.p_station_id)
	local r_st = remote.call("cybersyn", "read_global", "stations", c_train.r_station_id)
	local dep = remote.call("cybersyn", "read_global", "depots", c_train.depot_id)

	if not (p_st and r_st and dep) then
		return
	end

	local s_D = dep.entity_stop.surface.index
	local s_P = p_st.entity_stop.surface.index
	local s_R = r_st.entity_stop.surface.index

	if s_D == s_P and s_P == s_R then
		return
	end -- 同地表任务，无需处理

	log_debug(">>> 检测到跨地表任务，开始注入时刻表 <<<")

	local current_train_surface = train.front_stock.surface.index
	local new_records = {}
	local original_records = train.schedule.records
	local current_pos = train.front_stock.position

	-- 1. D -> P (车库去供货站)
	if s_D ~= s_P then
		local portal_name = find_portal_station(s_D, s_P, current_pos)
		if portal_name then
			table.insert(new_records,
				{ station = portal_name, temporary = true, wait_conditions = { { type = "time", ticks = 0 } } })
		end
	end

	-- 2. 插入 P (供货站)
	insert_cybersyn_stop_sequence(new_records, original_records, p_st, "P", current_train_surface)

	-- 3. P -> R (供货站去请求站)
	if s_P ~= s_R then
		local portal_name = find_portal_station(s_P, s_R, p_st.entity_stop.position)
		if portal_name then
			table.insert(new_records,
				{ station = portal_name, temporary = true, wait_conditions = { { type = "time", ticks = 0 } } })
		end
	end

	-- 4. 插入 R (请求站)
	insert_cybersyn_stop_sequence(new_records, original_records, r_st, "R", current_train_surface)

	-- 5. R -> D (请求站回车库)
	if s_R ~= s_D then
		local portal_name = find_portal_station(s_R, s_D, r_st.entity_stop.position)
		if portal_name then
			table.insert(new_records,
				{ station = portal_name, temporary = true, wait_conditions = { { type = "time", ticks = 0 } } })
		end
	end

	-- 6. D (回库记录)
	if original_records[#original_records] then
		table.insert(new_records, original_records[#original_records])
	end

	-- 应用修改
	if #new_records > 0 then
		local s_manifest = c_train.manifest
		local schedule = train.schedule
		schedule.records = new_records
		schedule.current = 1
		train.schedule = schedule
		train.manual_mode = false

		-- 写回 Manifest，但不写回 Status (保持原状，防止卡死)
		remote.call("cybersyn", "write_global", s_manifest, "trains", train.id, "manifest")

		-- 更新站点 ID 引用
		if c_train.p_station_id then
			remote.call("cybersyn", "write_global", c_train.p_station_id, "trains", train.id, "p_station_id")
		end
		if c_train.r_station_id then
			remote.call("cybersyn", "write_global", c_train.r_station_id, "trains", train.id, "r_station_id")
		end
		if c_train.depot_id then
			remote.call("cybersyn", "write_global", c_train.depot_id, "trains", train.id, "depot_id")
		end

		log_debug("时刻表注入完成。")
		-- [已移除] 警报清除代码 (因为 Cybersyn 官方已修复)
	end
end

-- Tick 循环：处理待处理队列
function CybersynScheduler.on_tick()
	if not next(pending_trains) then
		return
	end
	for id, train in pairs(pending_trains) do
		if train and train.valid then
			process_train(train)
		end
		pending_trains[id] = nil
	end
end

-- 事件监听：捕获时刻表变更
script.on_event(defines.events.on_train_schedule_changed, function(event)
	if event.train and event.train.valid and not event.player_index then
		-- 只有在 Cybersyn 生成了标准时刻表 (至少2站: P和R) 时才介入
		if event.train.schedule and #event.train.schedule.records >= 2 then
			pending_trains[event.train.id] = event.train
		end
	end
end)

return CybersynScheduler
