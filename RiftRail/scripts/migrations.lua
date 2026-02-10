-- migrations.lua
-- Rift Rail - 数据迁移任务集中管理
-- 功能：处理模组版本更新时的存档数据结构升级
-- 说明：本文件由 on_configuration_changed 调用，每次配置变更时运行
--       具体迁移任务通过内部条件判断确保"只在需要时执行"

local Migrations = {}

-- ============================================================================
-- 依赖注入
-- ============================================================================
local State, log_debug, CybersynSE, LTN

function Migrations.init(deps)
    State = deps.State
    log_debug = deps.log_debug
    CybersynSE = deps.CybersynSE
    LTN = deps.LTN
end

-- ============================================================================
-- [迁移任务 1] v0.1 -> v0.2: 构建 id_map 缓存
-- ============================================================================
-- 目的：为旧存档补充 custom_id -> unit_number 的快速查找表
-- 触发条件：storage.rift_rails 非空，但 id_map 为空
function Migrations.build_id_map()
    if storage.rift_rails and next(storage.rift_rails) ~= nil and next(storage.rift_rail_id_map) == nil then
        log_debug("[Migration] 检测到旧存档，正在构建 id_map 缓存...")
        for unit_number, portaldata in pairs(storage.rift_rails) do
            storage.rift_rail_id_map[portaldata.id] = unit_number
        end
    end
end

-- ============================================================================
-- [迁移任务 2] v0.2 -> v0.3: 修复 children 列表结构
-- ============================================================================
-- 目的：为子实体列表补充相对坐标信息，支持克隆/传送功能
-- 触发条件：检测到 children[1] 是裸实体对象（而非 table）
function Migrations.fix_children_relative_pos()
    if storage.rift_rails then
        for _, portaldata in pairs(storage.rift_rails) do
            -- 判断是否为需要修复的旧数据：检查第一个 child 是否是实体对象，而不是 table
            if portaldata.children and #portaldata.children > 0 and portaldata.children[1].valid then
                log_debug("[Migration] 正在修复建筑 ID " .. portaldata.id .. " 的 children 列表...")
                local new_children = {}
                if portaldata.shell and portaldata.shell.valid then
                    local center_pos = portaldata.shell.position
                    for _, child_entity in pairs(portaldata.children) do
                        if child_entity and child_entity.valid then
                            table.insert(new_children, {
                                entity = child_entity,
                                relative_pos = {
                                    x = child_entity.position.x - center_pos.x,
                                    y = child_entity.position.y - center_pos.y,
                                },
                            })
                        end
                    end
                    portaldata.children = new_children
                end
            end
        end
    end
end

-- ============================================================================
-- [迁移任务 3] v0.3 -> v0.4: 键名重构
-- ============================================================================
-- 目的：将 carriage_ahead/behind 重命名为 exit_car/entry_car
-- 触发条件：检测到旧键名存在
function Migrations.rename_carriage_to_car()
    if storage.rift_rails then
        log_debug("[Migration] 开始执行存储键名迁移 (carriage -> car)...")
        for _, portaldata in pairs(storage.rift_rails) do
            -- 迁移 carriage_ahead -> exit_car
            -- 检查：如果旧键存在，且新键不存在 (防止重复迁移)
            if portaldata.carriage_ahead and not portaldata.exit_car then
                portaldata.exit_car = portaldata.carriage_ahead
                portaldata.carriage_ahead = nil -- [关键] 删除旧键，完成迁移
            end

            -- 迁移 carriage_behind -> entry_car
            if portaldata.carriage_behind and not portaldata.entry_car then
                portaldata.entry_car = portaldata.carriage_behind
                portaldata.carriage_behind = nil -- [关键] 删除旧键
            end
        end
    end
end

-- ============================================================================
-- [迁移任务 4] v0.4 -> v0.5: 构建活跃传送列表
-- ============================================================================
-- 目的：为 GC 优化创建数组结构的活跃传送器列表
-- 触发条件：active_teleporter_list 不存在
function Migrations.build_active_teleporter_list()
    if not storage.active_teleporter_list then
        storage.active_teleporter_list = {}
        if storage.active_teleporters then
            for _, portaldata in pairs(storage.active_teleporters) do
                table.insert(storage.active_teleporter_list, portaldata)
            end
            table.sort(storage.active_teleporter_list, function(a, b)
                return a.unit_number < b.unit_number
            end)
        end
    end
end

-- ============================================================================
-- [迁移任务 5] LTN 旧版连接清理（一次性）
-- ============================================================================
-- 目的：清理旧版 LTN 远程调用留下的残留数据
-- 触发条件：标志位 storage.rift_rail_ltn_remote_purged 不存在
function Migrations.purge_ltn_legacy()
    if not storage.rift_rail_ltn_remote_purged then
        log_debug("[Migration] 正在清理旧版 LTN 连接...")
        if LTN.purge_legacy_connections then
            LTN.purge_legacy_connections()
        end
        storage.rift_rail_ltn_remote_purged = true
    end
end

-- ============================================================================
-- [迁移任务 6] LTN 路由表系统填充（一次性）
-- ============================================================================
-- 目的：为新版 LTN 路由表系统初始化数据
-- 触发条件：标志位 storage.rift_rail_ltn_table_migrated 不存在
function Migrations.build_ltn_routing_table()
    if not storage.rift_rail_ltn_table_migrated then
        log_debug("[Migration] 正在为 LTN 路由表系统填充数据...")
        if LTN.rebuild_routing_table_from_storage then
            LTN.rebuild_routing_table_from_storage()
        end
        -- 设置标志位，防止下次更新时重复运行
        storage.rift_rail_ltn_table_migrated = true
    end
end

-- ============================================================================
-- [迁移任务 7] v0.8.0 Cybersyn 架构重构
-- ============================================================================
-- 目的：清理旧版连接数据，为 SE 环境重建 Cybersyn 连接
-- 触发条件：storage.rift_rails 存在 且 Cybersyn 模组已安装
function Migrations.cybersyn_v080_refactor()
    if storage.rift_rails and remote.interfaces["cybersyn"] then
        log_debug("[Migration] v0.8.0 Cybersyn 架构重构...")

        -- 1. 无条件清理所有旧版连接数据
        if CybersynSE.purge_legacy_connections then
            CybersynSE.purge_legacy_connections()
        end

        -- 2. 仅在 SE 环境下，执行重建 (Rebuild)
        if script.active_mods["space-exploration"] then
            local migration_performed = false
            for _, portal in pairs(storage.rift_rails) do
                if portal.shell and portal.shell.valid and portal.cybersyn_enabled and portal.paired_to_id then
                    local partner = State.get_portaldata_by_id(portal.paired_to_id)
                    if partner and partner.shell and partner.shell.valid then
                        -- 静默重建
                        CybersynSE.update_connection(portal, partner, true, nil, true)
                        migration_performed = true
                    end
                end
            end
            if migration_performed then
                game.print({ "messages.rift-rail-migration-v080-success" })
            end
        else
            -- 3. 如果没有 SE，强制关闭所有 Cybersyn 开关（防止状态残留）
            for _, portal in pairs(storage.rift_rails) do
                portal.cybersyn_enabled = false
            end
            game.print({ "messages.rift-rail-migration-v080-warning" })
        end
    end
end

-- ============================================================================
-- [迁移任务 8] v0.9.0-v0.10.1 多对多架构统一迁移
-- ============================================================================
-- 目的：
--   1. v0.9.0: 出口 paired_to_id -> source_ids（多对一）
--   2. v0.10.0: 入口 paired_to_id -> target_ids（一对多）
--   3. v0.10.1: 在值结构中缓存 unit_number（性能优化）
--   4. 清理中立模式的旧配对数据
-- 触发条件：storage.rift_rails 存在
function Migrations.unified_multi_pairing()
    if storage.rift_rails then
        log_debug("[Migration] 开始执行多对多架构统一迁移 (v0.9.0-v0.10.1)...")

        local neutral_paired_count = 0
        for _, portal in pairs(storage.rift_rails) do
            -- [新增] 中立模式旧配对清理
            if portal.mode == "neutral" and portal.paired_to_id then
                neutral_paired_count = neutral_paired_count + 1
                portal.paired_to_id = nil
            end

            -- ============================================================
            -- [Part 1] 处理出口：paired_to_id -> source_ids（v0.9.0 网格化架构）
            -- 旧逻辑：出口通过 paired_to_id 指向唯一的入口
            -- 新逻辑：出口通过 source_ids 记录所有来源，paired_to_id 应为 nil
            -- ============================================================
            if portal.mode == "exit" then
                -- 1. 结构初始化：确保所有出口都有 source_ids 表
                if not portal.source_ids then
                    portal.source_ids = {}
                end

                -- 2. 数据转换：将旧的单一配对转换为带缓存的来源列表
                if portal.paired_to_id then
                    local source = State.get_portaldata_by_id(portal.paired_to_id)
                    if source and source.shell and source.shell.valid then
                        -- 直接创建带缓存的完整结构（整合 v0.10.1）
                        portal.source_ids[portal.paired_to_id] = {
                            custom_id = portal.paired_to_id,
                            unit_number = source.shell.unit_number
                        }
                        log_debug("[Migration] 转换出口 ID " ..
                            portal.id .. ": 旧配对(" .. portal.paired_to_id .. ") -> source_ids (带缓存)")
                    end

                    -- [关键] 清空出口的配对指针，标志着它正式转为多对一被动模式
                    portal.paired_to_id = nil
                end

                -- 3. 升级现有 source_ids 结构（v0.10.1 实体ID缓存）
                -- 处理已存在但格式为旧版的 source_ids（值为 true 或缺少 unit_number）
                for source_id, source_info in pairs(portal.source_ids) do
                    if source_info == true or (type(source_info) == "table" and not source_info.unit_number) then
                        local source = State.get_portaldata_by_id(source_id)
                        if source and source.shell and source.shell.valid then
                            portal.source_ids[source_id] = {
                                custom_id = source_id,
                                unit_number = source.shell.unit_number
                            }
                            log_debug("[Migration] 出口 ID " .. portal.id .. " 升级 source_ids[" .. source_id .. "] 为缓存结构")
                        end
                    end
                end
            end

            -- ============================================================
            -- [Part 2] 处理入口：paired_to_id -> target_ids（v0.10.0 一对多架构）
            -- 旧逻辑：入口通过 paired_to_id 指向唯一的出口
            -- 新逻辑：入口通过 target_ids 可以指向多个出口
            -- ============================================================
            if portal.mode == "entry" then
                -- 1. 结构初始化：确保所有入口都有 target_ids 表
                if not portal.target_ids then
                    portal.target_ids = {}
                end

                -- 2. 数据转换：将旧的单一配对转换为带缓存的目标列表
                if portal.paired_to_id then
                    local target = State.get_portaldata_by_id(portal.paired_to_id)
                    if target and target.shell and target.shell.valid then
                        -- 直接创建带缓存的完整结构（整合 v0.10.1）
                        portal.target_ids[portal.paired_to_id] = {
                            custom_id = portal.paired_to_id,
                            unit_number = target.shell.unit_number
                        }
                        log_debug("[Migration] 转换入口 ID " ..
                            portal.id .. ": 旧配对(" .. portal.paired_to_id .. ") -> target_ids (带缓存)")
                    end

                    -- [关键] 清空旧字段，完成数据结构升级
                    portal.paired_to_id = nil
                end

                -- 3. 升级现有 target_ids 结构（v0.10.1 实体ID缓存）
                -- 处理已存在但格式为旧版的 target_ids（值为 true 或缺少 unit_number）
                for target_id, target_info in pairs(portal.target_ids) do
                    if target_info == true or (type(target_info) == "table" and not target_info.unit_number) then
                        local target = State.get_portaldata_by_id(target_id)
                        if target and target.shell and target.shell.valid then
                            portal.target_ids[target_id] = {
                                custom_id = target_id,
                                unit_number = target.shell.unit_number
                            }
                            log_debug("[Migration] 入口 ID " .. portal.id .. " 升级 target_ids[" .. target_id .. "] 为缓存结构")
                        end
                    end
                end
            end
        end

        if neutral_paired_count > 0 then
            log_debug("[Migration] 清理中立配对: " .. neutral_paired_count .. " 个")
            game.print({ "messages.rift-rail-migration-neutral-pairs-cleared", neutral_paired_count })
        end
        log_debug("[Migration] 多对多架构统一迁移完成。")
    end
end

-- ============================================================================
-- [迁移任务 9] v0.10.0 物流连接重置
-- ============================================================================
-- 目的：暴力清洗 Cybersyn/LTN 连接，重新评估并重建
-- 触发条件：storage.rift_rails 存在
function Migrations.logistics_reset()
    if storage.rift_rails then
        log_debug("[Migration] 开始执行物流连接重置 (Purge & Re-evaluate)...")

        -- 1. [Cybersyn] 全局暴力清洗 (核弹洗地)
        -- 直接清除 Cybersyn 数据库中所有关于 RiftRail 的记录，无视内部状态
        if CybersynSE and CybersynSE.purge_legacy_connections then
            CybersynSE.purge_legacy_connections()
        end

        -- 2. [重建] 遍历现有数据，重新注册合法的连接
        for _, portal in pairs(storage.rift_rails) do
            if portal.mode == "entry" and portal.target_ids then
                for target_id, _ in pairs(portal.target_ids) do
                    local partner = State.get_portaldata_by_id(target_id)
                    if partner then
                        -- [LTN] LTN 没有暴力清洗功能，所以保持"先断开后连接"的传统逻辑
                        -- 使用静默模式，避免在迁移时向玩家发送消息
                        if LTN then
                            LTN.update_connection(portal, partner, false, nil, nil, true)
                        end

                        -- [重建连接]
                        -- 只有当开关开启，且符合新版"双向握手"规则时，才会真正注册成功
                        if portal.cybersyn_enabled then
                            if CybersynSE then
                                -- 注意：这里不再调用 false，因为上面已经全局清洗过了
                                CybersynSE.update_connection(portal, partner, true, nil, true)
                            end
                        end
                        if portal.ltn_enabled then
                            if LTN then
                                LTN.update_connection(portal, partner, true, nil, nil, true)
                            end
                        end
                    end
                end
            end
        end
        log_debug("[Migration] 物流连接重置完成。")
    end
end

-- ============================================================================
-- 主入口：按顺序执行所有迁移任务
-- ============================================================================
function Migrations.run_all()
    -- 基础结构迁移（v0.1-v0.5）
    Migrations.build_id_map()
    Migrations.fix_children_relative_pos()
    Migrations.rename_carriage_to_car()
    Migrations.build_active_teleporter_list()

    -- 物流系统迁移
    Migrations.purge_ltn_legacy()
    Migrations.build_ltn_routing_table()
    Migrations.cybersyn_v080_refactor()

    -- 多对多架构迁移
    Migrations.unified_multi_pairing()
    Migrations.logistics_reset()
end

return Migrations
