-- scripts/state.lua
-- 功能：提供数据查询接口，封装对 storage.rift_rails 的访问
-- 修复：支持通过自定义 ID (1, 2, 3) 查找数据

local State = {}

local DEBUG_MODE_ENABLED = settings.global["rift-rail-debug-mode"].value

-- ============================================================================
-- 存储初始化与迁移 (由 control.lua 调用)
-- ============================================================================
function State.ensure_storage()
    -- 1. 为新游戏创建完整数据结构
    if not storage.rift_rails then
        storage.rift_rails = {}
        storage.next_rift_id = 1
        -- 【新增】创建 id_map 缓存
        storage.rift_rail_id_map = {}
    end

    -- 2. 为从旧版本升级的存档补全 id_map
    if not storage.rift_rail_id_map then
        storage.rift_rail_id_map = {}
        -- 迁移逻辑将在 control.lua 的 on_configuration_changed 中执行
    end
end

-- 通过 自定义ID (Custom ID) 获取数据
-- 【性能重构】: 现在使用 id_map 缓存进行 O(1) 查询
function State.get_struct_by_id(target_id)
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
    for _, struct in pairs(storage.rift_rails) do
        if struct.id == target_id then
            -- 找到后，重建缓存
            storage.rift_rail_id_map[target_id] = struct.unit_number
            return struct
        end
    end

    return nil
end

-- 通过 实体单元编号 (Unit Number) 获取数据 (内部快速查找)
function State.get_struct_by_unit_number(unit_number)
    if storage.rift_rails and unit_number then
        return storage.rift_rails[unit_number]
    end
    return nil
end

-- 通过实体获取数据
function State.get_struct(entity)
    if not (entity and entity.valid) then
        return nil
    end

    -- 如果直接是主体
    if entity.name == "rift-rail-entity" then
        return State.get_struct_by_unit_number(entity.unit_number)
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
            return State.get_struct_by_unit_number(shells[1].unit_number)
        end
    end

    return nil
end

-- 获取所有数据 (用于下拉列表)
function State.get_all_structs()
    return storage.rift_rails or {}
end

return State
