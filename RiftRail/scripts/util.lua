-- scripts/util.lua
-- 【Rift Rail - 工具库】
-- 功能：提供通用实体操作、向量计算及兼容性强的物品/流体转移功能。
-- [修改] 移除所有第三方代码引用

local Util = {}

local log_debug = function(msg)
    log(msg)
end
---@type table
local TeleportMath = nil

function Util.init(deps)
    if deps.log_debug then
        log_debug = deps.log_debug
    end
    TeleportMath = deps.TeleportMath
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

-- 坐标偏移：返回基准坐标应用偏移后的新坐标
function Util.add_offset(base, offset)
    return { x = base.x + offset.x, y = base.y + offset.y }
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

-- 重建所有碰撞器 (用于修复位置错误的碰撞器，并升级 ID 架构)
function Util.rebuild_all_colliders()
    -- 0. 确保全局字典存在 (核心！)
    

    -- 1. 【焦土】销毁全图所有的旧碰撞器 + 清理旧字典记录
    for _, surface in pairs(game.surfaces) do
        local old_colliders = surface.find_entities_filtered({ name = "rift-rail-collider" })
        for _, c in pairs(old_colliders) do
            if c.valid then
                -- [新增] 销户：防止字典里残留无效的 ID
                if c.unit_number then
                    storage.collider_to_portal[c.unit_number] = nil
                end
                c.destroy()
            end
        end
    end

    -- 2. 【重生】在正确位置重新生成
    if storage.rift_rails then
        for _, portaldata in pairs(storage.rift_rails) do
            if portaldata.shell and portaldata.shell.valid then
                -- [新增] 先清理 children 列表 (不管后面是否创建成功，旧的引用都必须删)
                if not portaldata.children then
                    portaldata.children = {}
                end
                for i = #portaldata.children, 1, -1 do
                    local child_data = portaldata.children[i]
                    -- 检查是否是旧的 collider (此时它们已经是 invalid 的了，因为第1步全删了)
                    if child_data.entity and (not child_data.entity.valid or child_data.entity.name == "rift-rail-collider") then
                        table.remove(portaldata.children, i)
                    end
                end

                -- 只有入口和中立需要碰撞器
                if portaldata.mode == "entry" or portaldata.mode == "neutral" then
                    local dir = portaldata.shell.direction
                    local offset = { x = 0, y = 0 }

                    -- 偏移量计算
                    if dir == 0 then
                        offset = { x = 0, y = -2 }
                    elseif dir == 4 then
                        offset = { x = 2, y = 0 }
                    elseif dir == 8 then
                        offset = { x = 0, y = 2 }
                    elseif dir == 12 then
                        offset = { x = -2, y = 0 }
                    end

                    -- 获取新创建的 collider 实体
                    local new_collider = portaldata.surface.create_entity({
                        name = "rift-rail-collider",
                        position = { x = portaldata.shell.position.x + offset.x, y = portaldata.shell.position.y + offset.y },
                        force = portaldata.shell.force,
                    })

                    -- [核心修改] 只有创建成功才进行注册
                    if new_collider then
                        -- A. 【上户口】注册 ID 到全局字典
                        if new_collider.unit_number then
                            storage.collider_to_portal[new_collider.unit_number] = portaldata.unit_number
                        end

                        -- B. 注册引用到 children
                        table.insert(portaldata.children, {
                            entity = new_collider,
                            relative_pos = offset,
                        })

                        -- 重建碰撞器的同时，必须重建它家的坐标缓存！
                        local cached_spawn, cached_area = TeleportMath.calculate_teleport_cache(portaldata.shell.position, portaldata.shell.direction)
                        portaldata.cached_spawn_pos = cached_spawn
                        portaldata.cached_check_area = cached_area
                        
                        -- 只拯救处于瘫痪状态的建筑
                        if portaldata.state == 3 then -- Teleport.STATE.REBUILDING
                            portaldata.state = 0 -- Teleport.STATE.DORMANT
                        end
                    end
                end
            end
        end
    end
end

return Util
