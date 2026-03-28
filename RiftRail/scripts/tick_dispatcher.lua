-- scripts/tick_dispatcher.lua
-- 【Rift Rail - 运行时调度器】
-- 功能：集中管理动态 on_tick 注册策略，避免 control.lua 继续膨胀。

local TickDispatcher = {}

---@type table|nil
local Teleport = nil

-- 记录当前是否已注册传送系统 tick，避免重复注册/重复注销
local teleport_tick_registered = false

---@param event EventData tick事件
local function on_teleport_tick(event)
    local has_work = Teleport and Teleport.on_tick and Teleport.on_tick(event)
    if not has_work then
        TickDispatcher.disable_teleport_tick()
    end
end

---@param deps table 依赖注入容器
function TickDispatcher.init(deps)
    Teleport = deps.Teleport
end

--- 启用传送系统 Tick 轮询
function TickDispatcher.enable_teleport_tick()
    if teleport_tick_registered then
        return
    end
    script.on_event(defines.events.on_tick, on_teleport_tick)
    teleport_tick_registered = true
end

--- 关闭传送系统 Tick 轮询
function TickDispatcher.disable_teleport_tick()
    if not teleport_tick_registered then
        return
    end
    script.on_event(defines.events.on_tick, nil)
    teleport_tick_registered = false
end

--- 根据当前活跃传送任务状态，自动同步 on_tick 注册状态
function TickDispatcher.sync_teleport_tick_registration()
    local has_work = Teleport and Teleport.has_active_work and Teleport.has_active_work()
    if has_work then
        TickDispatcher.enable_teleport_tick()
    else
        TickDispatcher.disable_teleport_tick()
    end
end

--- 碰撞器死亡后回调：触发传送逻辑，并同步 tick 注册状态
---@param event EventData.on_entity_died 实体死亡事件
function TickDispatcher.handle_collider_died(event)
    Teleport.on_collider_died(event)
    TickDispatcher.sync_teleport_tick_registration()
end

return TickDispatcher
