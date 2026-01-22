-- scripts/schedule.lua
-- 【Rift Rail - 时刻表处理模块】(移植自传送门 Mod v2.0)
-- 功能：专门负责在火车通过传送门后，安全、完整地转移其时刻表和中断机制。
-- 集成说明：已适配 Rift Rail 的日志系统 (init 注入)

local Schedule = {}

-- 默认空日志函数，会被 control.lua 注入的函数覆盖
local log_debug = function() end

-- 初始化函数：接收来自 control.lua 的依赖
function Schedule.init(deps)
    if deps.log_debug then
        log_debug = deps.log_debug
    end
end

-- 本地日志包装器 (适配 Rift Rail 风格)
-- 原有的 DEBUG_ENABLED 开关现在由 control.lua 中的 DEBUG_MODE 统一控制
local function log_schedule(message)
    -- 调用 control.lua 传入的 log_debug
    -- 它会自动处理 log() 和 game.print()，并带有 [RiftRail] 前缀
    if RiftRail.DEBUG_MODE_ENABLED then
        log_debug("[RiftRail:Schedule] " .. message)
    end
end

--- 核心函数：转移时刻表和中断机制
-- @param old_train LuaTrain: 即将被销毁的、进入传送门的旧火车实体
-- @param new_train LuaTrain: 在出口处新创建的火车实体
-- @param entry_portal_station_name string: 入口传送门内部火车站的完整名称
function Schedule.copy_schedule(old_train, new_train, entry_portal_station_name)
    if RiftRail.DEBUG_MODE_ENABLED then
        log_schedule("DEBUG (copy_schedule v3.0): 开始为新火车 (ID: " .. new_train.id .. ") 转移时刻表...")
    end

    if not (old_train and old_train.valid and new_train and new_train.valid) then
        return
    end

    local schedule_old = old_train.get_schedule()
    if not schedule_old then
        return
    end

    -- 获取旧时刻表的副本
    local records = schedule_old.get_records()
    if not records then
        return
    end

    local current_index = schedule_old.current
    if RiftRail.DEBUG_MODE_ENABLED then
        log_schedule("DEBUG: 初始状态 - 站点数: " .. #records .. ", 当前索引: " .. current_index)
    end

    -- ========================================================================
    -- 步骤 1: 清理临时 rail 坐标
    -- 目的：移除时刻表中所有基于 rail 坐标的临时站点
    -- 原因：rail 坐标在跨地表传送后会指向错误的地表，必须清理
    -- 注意：列车传送时停在 RiftRail 站点，不会停在 rail 坐标上
    -- ========================================================================

    for i = #records, 1, -1 do
        local record = records[i]
        if record.rail then
            -- 如果这个 rail 坐标在当前索引之前，需要调整索引
            if i < current_index then
                current_index = current_index - 1
            end

            -- 从列表中物理移除该记录
            table.remove(records, i)
        end
    end

    -- 安全钳制
    if current_index < 1 then
        current_index = 1
    end

    if #records == 0 then
        if RiftRail.DEBUG_MODE_ENABLED then
            log_schedule("DEBUG: 警告 - 时刻表被清空。")
        end
        return
    end

    if RiftRail.DEBUG_MODE_ENABLED then
        log_schedule("DEBUG: 路障清理完毕 - 剩余站点数: " .. #records .. ", 修正后索引: " .. current_index)
    end

    -- ========================================================================
    -- 步骤 2: 处理当前传送门站点
    -- ========================================================================

    local current_record = records[current_index]

    -- 只有当火车处于自动模式，且当前指向的确实是传送门时，才介入处理
    if not old_train.manual_mode and current_record and current_record.station == entry_portal_station_name then
        if current_record.temporary then
            -- [情况 A] 临时的传送门站 -> 删除
            if RiftRail.DEBUG_MODE_ENABLED then
                log_schedule("DEBUG: 当前是临时传送门站，执行删除。")
            end
            table.remove(records, current_index)

            -- 删除后索引自动指向下一条记录，只需处理越界
            if current_index > #records then
                current_index = 1
            end
        else
            -- [情况 B] 永久的传送门站 -> 跳转下一站
            current_index = (current_index % #records) + 1
            if RiftRail.DEBUG_MODE_ENABLED then
                log_schedule("DEBUG: 当前是永久传送门站，推进到下一站索引: " .. current_index)
            end
        end
    else
        if RiftRail.DEBUG_MODE_ENABLED then
            log_schedule("DEBUG: 当前不是传送门站 (或手动模式)，保持目标不变。")
        end
    end

    -- ========================================================================
    -- 步骤 3: 应用到新火车
    -- ========================================================================

    local schedule_new = new_train.get_schedule()
    if not schedule_new then
        return
    end

    if schedule_old.group then
        -- 【有车组】先设置车组，车组会自动恢复其基础时刻表
        if RiftRail.DEBUG_MODE_ENABLED then
            log_schedule("DEBUG: 检测到车组: " .. tostring(schedule_old.group) .. "，先设置车组...")
        end

        schedule_new.group = schedule_old.group

        -- 设置了车组后，车组的基础时刻表已被应用
        -- 现在需要添加被group覆盖掉的临时站点
        for i = 1, #records do
            local record = records[i]
            if record.temporary then
                record.index = { schedule_index = i }
                schedule_new.add_record(record)
                if RiftRail.DEBUG_MODE_ENABLED then
                    log_schedule("DEBUG: 添加临时站点 (索引: " .. i .. ")")
                end
            end
        end

        -- 复制中断设置
        schedule_new.set_interrupts(schedule_old.get_interrupts())
    else
        -- 【无车组】直接设置所有记录
        if RiftRail.DEBUG_MODE_ENABLED then
            log_schedule("DEBUG: 无车组，直接设置所有时刻表记录...")
        end

        schedule_new.set_records(records)
        schedule_new.set_interrupts(schedule_old.get_interrupts())
    end

    -- 命令新火车前往计算出的目标索引
    if #records > 0 then
        schedule_new.go_to_station(current_index)
        if RiftRail.DEBUG_MODE_ENABLED then
            log_schedule("DEBUG: 时刻表转移完成，最终目标 Index: " .. current_index)
        end
    end

    --[[ -- 清空旧火车时刻表
    old_train.schedule = nil ]]
end

return Schedule
