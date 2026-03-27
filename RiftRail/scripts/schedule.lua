-- scripts/schedule.lua
-- 【Rift Rail - 时刻表处理模块】(移植自传送门 Mod v2.0)
-- 功能：专门负责在火车通过传送门后，安全、完整地转移其时刻表和中断机制。
-- 集成说明：已适配 Rift Rail 的日志系统 (init 注入)

local Schedule = {}

local log_debug = function() end

-- 初始化函数：接收来自 control.lua 的依赖
function Schedule.init(deps)
    if deps.log_debug then
        log_debug = deps.log_debug
    end
end

-- 本地日志包装器
local function log_schedule(message)
    if RiftRail.DEBUG_MODE_ENABLED then
        log_debug("[RiftRail:Schedule] " .. message)
    end
end

--- 核心函数：转移时刻表和中断机制
---@param old_train LuaTrain: 即将被销毁的、进入传送门的旧火车实体
---@param new_train LuaTrain: 在出口处新创建的火车实体
---@param entry_portal_station_name string: 入口传送门内部火车站的完整名称
---@param override_index integer|nil: 可选参数，强制设置新火车的目标索引（用于特殊情况）
---@param saved_manual_mode boolean|nil: 可选参数，传入旧火车的手动模式状态（用于特殊情况）
function Schedule.copy_schedule(old_train, new_train, entry_portal_station_name, override_index, saved_manual_mode)
    if RiftRail.DEBUG_MODE_ENABLED then
        log_schedule("DEBUG: 开始为新火车 (ID: " .. new_train.id .. ") 转移时刻表...")
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

    local current_index = override_index or schedule_old.current
    if RiftRail.DEBUG_MODE_ENABLED then
        log_schedule("DEBUG: 初始状态 - 站点数: " .. #records .. ", 当前索引: " .. current_index .. (override_index and " [使用了传入的正确指针]" or ""))
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

    local is_manual = old_train.manual_mode
    if saved_manual_mode ~= nil then
        is_manual = saved_manual_mode
    end

    -- 只有当火车处于自动模式，且当前指向的确实是传送门时，才介入处理
    if not is_manual and current_record and current_record.station == entry_portal_station_name then
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

    -- 收集原有的合法临时站名（不带 rail 的临时站）
    -- 在挂载并触发引擎刚性插入"假中断"前获取快照，作为后续护符
    local safe_interrupt_names = {}
    for i = 1, #records do
        local record = records[i]
        if record.temporary and not record.rail and record.station then
            safe_interrupt_names[record.station] = true
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

    return safe_interrupt_names
end

--- 轻量版指针拨正：传送过程中每节车厢拼接后调用。
--- 检测当前时刻表指针是否落在了因缺货强插的假中断临时站上，如果是，
--- 则向后扫描找到第一个合法的真实站点并跳转过去。
--- 不修改 records 表（避免触发引擎重新评估并立即重插），仅移动指针。
---
---@param train LuaTrain 已拼接的出口列车
---@param entry_station_name string 传送门入口站名（此站不算假中断，跳过它但不视为垃圾）
---@param safe_set table 允许保留的临时命名站白名单
---@return boolean 是否执行了指针跳转
function Schedule.snap_pointer_past_interrupt(train, entry_station_name, safe_set)
    if not (train and train.valid) then
        return false
    end

    local sched = train.get_schedule()
    if not sched then
        return false
    end

    local records = sched.get_records()
    if not records or #records == 0 then
        return false
    end

    local current_index = sched.current
    local current_record = records[current_index]

    -- 判断当前站是否为假中断临时站
    local function is_fake_interrupt(record)
        if not (record and record.temporary and not record.rail and record.station) then
            return false
        end
        if record.station == entry_station_name then
            return false
        end
        if safe_set and safe_set[record.station] then
            return false
        end
        return true
    end

    if not is_fake_interrupt(current_record) then
        return false
    end

    -- 向后扫描，找到第一个非假中断的真实站点
    local n = #records
    local target_index = nil
    for offset = 1, n do
        local probe = (current_index - 1 + offset) % n + 1
        local record = records[probe]
        if not is_fake_interrupt(record) then
            target_index = probe
            break
        end
    end

    if not target_index then
        return false
    end

    sched.go_to_station(target_index)
    return true
end

--- 清洗函数：在列车全部车厢合并完毕（货物补满）后调用。
--- 遍历当前时刻表，识别并移除因缺货误判而由引擎强塞的假中断临时站点。
--- 判别标准：`temporary = true` 且 `rail == nil`（有 rail 坐标的是 LTN 的合法路轨，不动）。
---
---@param train LuaTrain 已合并完毕的满编列车实体
---@param entry_station_name string 传送门入口站的名字（保护此站不被误删）
---@param safe_set table 传送前已存在的临时命名站白名单
---@return boolean 是否执行了清洗并重写了时刻表
function Schedule.cleanup_interrupt_garbage(train, entry_station_name, safe_set)
    if not (train and train.valid) then
        return false
    end

    local sched = train.get_schedule()
    if not sched then
        return false
    end

    local records = sched.get_records()
    if not records or #records == 0 then
        return false
    end

    local current_index = sched.current
    local removed_count = 0

    -- 判断当前站是否为假中断临时站
    local function is_fake_interrupt(record)
        if not (record and record.temporary and not record.rail and record.station) then
            return false
        end
        if record.station == entry_station_name then
            return false
        end
        if safe_set and safe_set[record.station] then
            return false
        end
        return true
    end

    -- 倒序遍历，避免 table.remove 执行后数组下标前移导致跳跃漏查
    for i = #records, 1, -1 do
        local record = records[i]
        -- 判别条件：是由引擎生成的假中断站（不在白名单中）
        if is_fake_interrupt(record) then
            table.remove(records, i)
            removed_count = removed_count + 1
            -- 只有当被删的站严格在当前指针之前，指针才需要向前移动以保持对齐。
            -- 若被删的站正好是 current 本身（i == current_index），删除后原下一站填位至同一索引，
            -- current 不变即可正确指向真实目标，无需 -1。
            if i < current_index then
                current_index = current_index - 1
            end
        end
    end

    if removed_count == 0 then
        return false
    end

    -- 安全钳制：防止索引越界
    if current_index < 1 then
        current_index = 1
    end
    if current_index > #records then
        current_index = 1
    end

    -- 将净化后的时刻表覆盖回列车（触发引擎重新评估中断条件，此时货满不再误判）
    sched.set_records(records)
    sched.go_to_station(current_index)

    if RiftRail.DEBUG_MODE_ENABLED then
        log_schedule("[cleanup] 清洗完毕，移除了 " .. removed_count .. " 个假中断临时站，当前指针: " .. current_index)
    end

    return true
end

return Schedule
