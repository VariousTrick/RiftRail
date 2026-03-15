-- scripts/state.lua
-- 功能：提供数据查询接口，封装对 storage.rift_rails 的访问
-- 修复：支持通过自定义 ID (1, 2, 3) 查找数据

local State = {}

-- ============================================================================
-- 存储初始化与补全 (架构解耦重构版)
-- ============================================================================

--- [阶段一：创世手册]
--- 仅在 script.on_init (新开档) 时调用一次。
--- 它是全模组数据结构的"唯一真理蓝图"。不需要判断，直接暴力声明。
function State.setup_new_game()
    storage.rift_rails = {}
    storage.next_rift_id = 1
    storage.rift_rail_id_map = {}

    storage.collider_to_portal = {}
    storage.collider_map = {}
    storage.active_teleporter_list = {}
    storage.active_teleporters = {} -- 添加了缺失的字典缓存
    storage.rift_rail_player_settings = {} -- 玩家 GUI 设置

    -- LTN 兼容数据
    storage.rift_rail_ltn_routing_table = {}
    storage.rr_ltn_pools = {}
    storage.ltn_stops = {}

    -- CS2 兼容数据
    storage.rr_cs2_handoff_by_old_train_id = {}
    storage.rr_cs2_old_train_by_delivery_id = {}
    storage.rr_cs2_route_cache = { by_surface = {} }
    storage.rr_cs2_route_cache_dirty = true

    -- 初始化所有的全局生命周期标记
    storage.collider_migration_done = true
    storage.rift_rail_teleport_cache_calculated = true
    storage.rift_rail_cs2_toggle_migrated = true
    storage.rift_rail_cybersyn_fully_purged = false -- 默认未清理过
end

--- [阶段二：老兵补丁]
--- 仅在 script.on_configuration_changed (配置/版本变更) 时调用。
--- 负责检查旧存档在升级后，是否缺失了新版本引入的最外层根表，并安全补齐。
function State.patch_missing_root_tables()
    if not storage.rift_rails then storage.rift_rails = {} end
    if not storage.next_rift_id then storage.next_rift_id = 1 end
    if not storage.rift_rail_id_map then storage.rift_rail_id_map = {} end

    if not storage.collider_to_portal then storage.collider_to_portal = {} end
    if not storage.collider_map then storage.collider_map = {} end
    if not storage.active_teleporter_list then storage.active_teleporter_list = {} end
    if not storage.active_teleporters then storage.active_teleporters = {} end
    if not storage.rift_rail_player_settings then storage.rift_rail_player_settings = {} end

    -- LTN 兼容数据兜底
    if not storage.rift_rail_ltn_routing_table then storage.rift_rail_ltn_routing_table = {} end
    if not storage.rr_ltn_pools then storage.rr_ltn_pools = {} end
    if not storage.ltn_stops then storage.ltn_stops = {} end

    -- CS2 兼容数据兜底
    if not storage.rr_cs2_handoff_by_old_train_id then storage.rr_cs2_handoff_by_old_train_id = {} end
    if not storage.rr_cs2_old_train_by_delivery_id then storage.rr_cs2_old_train_by_delivery_id = {} end
    if not storage.rr_cs2_route_cache then storage.rr_cs2_route_cache = { by_surface = {} } end
    if storage.rr_cs2_route_cache_dirty == nil then storage.rr_cs2_route_cache_dirty = true end

    -- 生命周期标记防空兜底
    if storage.collider_migration_done == nil then storage.collider_migration_done = false end
    if storage.rift_rail_teleport_cache_calculated == nil then storage.rift_rail_teleport_cache_calculated = false end
end

-- ============================================================================
-- 【性能重构】: 现在使用 id_map 缓存进行 O(1) 查询
function State.get_portaldata_by_id(target_id)
    if not (storage.rift_rails and storage.rift_rail_id_map and target_id) then
        return nil
    end

    -- 1. 从缓存中快速获取 unit_number
    local unit_number = storage.rift_rail_id_map[target_id]

    -- 2. 如果缓存命中，直接返回数据
    if unit_number then
        return storage.rift_rails[unit_number]
    end

    -- 3. [保底逻辑] 如果缓存未命中 (理论上不应发生)，则遍历查找一次
    for _, portaldata in pairs(storage.rift_rails) do
        if portaldata.id == target_id then
            -- 找到后，重建缓存
            storage.rift_rail_id_map[target_id] = portaldata.unit_number
            return portaldata
        end
    end

    return nil
end

-- 通过 实体单元编号 (Unit Number) 获取数据 (内部快速查找)
function State.get_portaldata_by_unit_number(unit_number)
    if storage.rift_rails and unit_number then
        return storage.rift_rails[unit_number]
    end
    return nil
end

-- 通过实体获取数据
function State.get_portaldata(entity)
    if not (entity and entity.valid) then
        return nil
    end

    -- 如果直接是主体
    if entity.name == "rift-rail-entity" then
        return State.get_portaldata_by_unit_number(entity.unit_number)
    end

    -- 如果是 GUI 核心 (rift-rail-core)
    if entity.name == "rift-rail-core" then
        -- 1. 尝试位置匹配 (最快)
        local surface = entity.surface
        local pos = entity.position
        local shells = surface.find_entities_filtered({
            name = "rift-rail-entity",
            position = pos,
            radius = 0.5, --稍微放宽一点半径防止浮点误差
        })
        if shells and shells[1] and shells[1].valid then
            return State.get_portaldata_by_unit_number(shells[1].unit_number)
        end
    end

    -- 如果以上快速查找都失败，则遍历所有 portaldata 的 children 列表
    -- 这是查找任何子实体 (如 station, signal, rail 等) 的最终保底方案
    if storage.rift_rails then
        for unit_num, data in pairs(storage.rift_rails) do
            if data.children then
                for _, child_data in pairs(data.children) do
                    if child_data.entity == entity then
                        -- 找到了！返回它所属的父级 portaldata
                        return data
                    end
                end
            end
        end
    end

    return nil
end

-- 获取所有数据 (用于下拉列表)
function State.get_all_portaldatas()
    return storage.rift_rails or {}
end

return State
