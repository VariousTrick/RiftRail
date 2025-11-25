-- scripts/state.lua
-- 功能：提供数据查询接口，封装对 storage.rift_rails 的访问
-- 修复：支持通过自定义 ID (1, 2, 3) 查找数据

local State = {}

-- 通过 自定义ID (Custom ID) 获取数据
-- 这里的 target_id 是显示的那个短 ID (如 1, 2, 3)
function State.get_struct_by_id(target_id)
    if not (storage.rift_rails and target_id) then return nil end

    -- 遍历查找
    for unit_number, struct in pairs(storage.rift_rails) do
        if struct.id == target_id then
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
    if not (entity and entity.valid) then return nil end

    -- 如果直接是主体
    if entity.name == "rift-rail-entity" then
        return State.get_struct_by_unit_number(entity.unit_number)
    end

    -- 如果是 GUI 核心 (rift-rail-core)
    if entity.name == "rift-rail-core" then
        -- 1. 尝试位置匹配 (最快)
        local surface = entity.surface
        local pos = entity.position
        local shells = surface.find_entities_filtered {
            name = "rift-rail-entity",
            position = pos,
            radius = 0.5 --稍微放宽一点半径防止浮点误差
        }
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
