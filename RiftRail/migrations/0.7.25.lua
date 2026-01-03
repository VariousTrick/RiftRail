-- migrations/0.7.25.lua
-- 为所有已存在的 Rift Rail 建筑添加车站和核心之间的信号线连接

-- 检查 storage 是否存在
if not storage then
    return
end

-- 检查是否有已存在的传送门建筑
if not storage.rift_rails then
    return
end

-- 遍历所有传送门建筑
local connected_count = 0
local failed_count = 0

for unit_number, portaldata in pairs(storage.rift_rails) do
    -- 查找车站和核心实体
    local station_entity = nil
    local core_entity = nil
    
    if portaldata.children then
        for _, child_data in pairs(portaldata.children) do
            local child = child_data.entity
            if child and child.valid then
                if child.name == "rift-rail-station" then
                    station_entity = child
                elseif child.name == "rift-rail-core" then
                    core_entity = child
                end
            end
        end
    end
    
    -- 如果找到了车站和核心，连接信号线
    if station_entity and core_entity then
        -- 连接红色信号线
        local success_red = pcall(function()
            core_entity.get_wire_connector(defines.wire_connector_id.circuit_red, true).connect_to(
                station_entity.get_wire_connector(defines.wire_connector_id.circuit_red, true),
                false,
                defines.wire_origin.script
            )
        end)
        
        -- 连接绿色信号线
        local success_green = pcall(function()
            core_entity.get_wire_connector(defines.wire_connector_id.circuit_green, true).connect_to(
                station_entity.get_wire_connector(defines.wire_connector_id.circuit_green, true),
                false,
                defines.wire_origin.script
            )
        end)
        
        if success_red and success_green then
            connected_count = connected_count + 1
        else
            failed_count = failed_count + 1
        end
    else
        failed_count = failed_count + 1
    end
end

-- 输出迁移结果到日志
if connected_count > 0 then
    log("[RiftRail Migration 0.7.25] 成功为 " .. connected_count .. " 个传送门建筑连接信号线")
end

if failed_count > 0 then
    log("[RiftRail Migration 0.7.25] 有 " .. failed_count .. " 个传送门建筑跳过或失败")
end
