-- scripts/util.lua
-- 【Rift Rail - 工具库】
-- 功能：提供通用实体操作、向量计算及兼容性强的物品/流体转移功能。
-- [修改] 移除所有第三方代码引用

local Util = {}

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

return Util
