-- scripts/stats.lua
-- 功能：传送门运营统计数据管理
-- 通过监听 TrainArrived 事件，直接通过引用更新 portaldata.stats 计数器

local Stats = {}

local State

function Stats.init(deps)
    log_debug = deps.log_debug
    State     = deps.State
end

-- 每次传送完成时，更新入口的发送计数器和出口的接收计数器
function Stats.on_train_arrived(event)
    -- 注意：Factorio 的 raise_event 会将 table 参数做深拷贝且不允许循环引用！
    -- 所以我们现在只在事件 payload 里安全传递轻量级的 ID，
    -- 然后直接通过 unit_number 去 State 里把真实的本体捞出来修改。
    local ep = event.entry_unit_number and State.get_portaldata_by_unit_number(event.entry_unit_number)
    if ep and ep.stats then
        ep.stats.trains_sent = ep.stats.trains_sent + 1
        ep.stats.last_sent_tick = game.tick
    end

    local xp = event.exit_unit_number and State.get_portaldata_by_unit_number(event.exit_unit_number)
    if xp and xp.stats then
        xp.stats.trains_received = xp.stats.trains_received + 1
        xp.stats.last_received_tick = game.tick
    end
end

return Stats
