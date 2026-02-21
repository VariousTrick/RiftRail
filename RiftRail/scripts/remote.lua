-- scripts/remote.lua
local Remote = {}

-- 1. 提前声明依赖变量，供该文件内的所有函数使用
local State
local Logic
local Builder
local GUI
local log_debug

function Remote.init(params)
    -- 2. 接收从 control.lua 注入的依赖
    State = params.State
    Logic = params.Logic
    Builder = params.Builder
    GUI = params.GUI
    log_debug = params.log_debug

    -- ============================================================================
    -- Remote Interface
    -- ============================================================================

    -- 3. 注册 RiftRail 主接口
    remote.add_interface("RiftRail", {
        get_train_departing_event = function()
            return RiftRail.Events.TrainDeparting
        end,
        get_train_arrived_event = function()
            return RiftRail.Events.TrainArrived
        end,
        update_portal_name = function(player_index, portal_id, new_name)
            Logic.update_name(player_index, portal_id, new_name)
        end,

        pair_portals = function(player_index, source_id, target_id)
            Logic.pair_portals(player_index, source_id, target_id)
        end,

        unpair_portals = function(player_index, portal_id)
            Logic.unpair_portals(player_index, portal_id)
        end,

        set_portal_mode = function(player_index, portal_id, mode)
            Logic.set_mode(player_index, portal_id, mode)
        end,

        set_default_exit = function(...)
            Logic.set_default_exit(...)
        end,

        set_ltn_enabled = function(player_index, portal_id, enabled)
            Logic.set_ltn_enabled(player_index, portal_id, enabled)
        end,

        -- 玩家传送逻辑：传送到当前建筑外部，而非配对目标
        teleport_player = function(player_index, portal_id)
            Logic.teleport_player(player_index, portal_id)
        end,

        open_remote_view_by_target = function(player_index, target_id)
            Logic.open_remote_view_by_target(player_index, target_id)
        end,

        -- 用于出口端批量断开所有连接的入口
        unpair_all_from_exit = function(player_index, portal_id)
            Logic.unpair_all_from_exit(player_index, portal_id)
        end,

        -- 精准解绑接口
        unpair_portals_specific = function(player_index, source_id, target_id)
            Logic.unpair_portals_specific(player_index, source_id, target_id)
        end,
    })

    -- 4. 注册 RiftRail_Tips 沙盒/提示接口
    remote.add_interface("RiftRail_Tips", {
        pair_portals = function(player_index, source_id, target_id)
            Logic.pair_portals(player_index, source_id, target_id)
        end,

        -- 专门为沙盒演示（或外部强制调用）开的建造后门
        force_build = function(placer_entity)
            -- 1. 基本的安全防线
            if not (placer_entity and placer_entity.valid) then
                return
            end

            -- 2. 伪造 event 包装盒
            -- 因为 Builder.on_built 只认 event.entity，我们投其所好
            local fake_event = {
                entity = placer_entity,
                -- 如果以后修改代码，需要用到时间戳，这里也可以加一句 tick = game.tick
            }

            -- 3. 直接把伪造好的数据塞进核心处理函数！
            Builder.on_built(fake_event)
        end,

        -- 专供沙盒测试的配对接口（支持传入 unit_number）
        pair_portals_by_unit = function(player_index, source_unit, target_unit)
            -- 1. 先用 unit_number 查出真实的 portaldata
            local source_data = State.get_portaldata_by_unit_number(source_unit)
            local target_data = State.get_portaldata_by_unit_number(target_unit)

            -- 2. 如果查到了，提取出真正的 custom_id 交给核心逻辑去配对
            if source_data and target_data then
                Logic.pair_portals(player_index, source_data.id, target_data.id)
            end
        end,

        -- 专供沙盒：静默重置传送门状态
        reset_portal_logic = function(player_index, unit_number)
            local p_data = State.get_portaldata_by_unit_number(unit_number)
            if p_data then
                Logic.unpair_portals(player_index, p_data.id)
                p_data.default_exit_id = nil
            end
        end,

        -- 专供沙盒：强行打开指定实体的 GUI
        open_portal_gui_by_unit = function(player_index, unit_number)
            local player = game.get_player(player_index)
            local portal_data = State.get_portaldata_by_unit_number(unit_number)

            if player and portal_data and portal_data.shell and portal_data.shell.valid then
                -- 1. 照常调用 GUI 构建逻辑
                GUI.build_or_update(player, portal_data.shell)

                -- 2. 【沙盒特供“黑魔法”】
                -- 刚建完，立马把它抓住，解除居中，钉在左上角！
                local frame = player.gui.screen.rift_rail_main_frame
                if frame and frame.valid then
                    frame.auto_center = false
                    frame.location = pos or { 0, 0 }
                end
            end
        end,

        -- 专供沙盒：模拟玩家在下拉列表中选中了某一项
        simulate_gui_selection = function(player_index, target_index)
            local player = game.get_player(player_index)
            if not player then
                return
            end

            local main_frame = player.gui.screen.rift_rail_main_frame
            if not (main_frame and main_frame.valid) then
                return
            end

            -- 递归遍历寻找你的下拉列表组件
            local function find_dropdown(element)
                if element.name == "rift_rail_target_dropdown" then
                    return element
                end
                for _, child in pairs(element.children) do
                    local found = find_dropdown(child)
                    if found then
                        return found
                    end
                end
                return nil
            end

            local dropdown = find_dropdown(main_frame)

            if dropdown and dropdown.items and #dropdown.items >= target_index then
                -- 1. 强行改变选中项的序号
                dropdown.selected_index = target_index

                -- 2. 播放系统的 UI 点击音效，增加真实感
                player.play_sound({ path = "utility/gui_click" })

                -- 3. 伪造一个事件，丢给你的内部逻辑，让它去更新旁边的“配对”按钮和摄像头预览！
                local fake_event = {
                    element = dropdown,
                    player_index = player.index,
                }

                if GUI and GUI.handle_selection_state_changed then
                    GUI.handle_selection_state_changed(fake_event)
                end

                -- 引擎还没渲染画面，我们立刻抓住刚刚在正中间重生的新窗口，强行改坐标！
                local new_frame = player.gui.screen.rift_rail_main_frame
                if new_frame and new_frame.valid then
                    new_frame.auto_center = false
                    new_frame.location = pos or { 0, 0 } -- 如果剧本没传 pos，则用 0, 0 兜底
                end
            end
        end,

        -- 专供沙盒：强行关闭测试玩家的摄像头预览
        disable_camera_preview = function(player_index)
            storage.rift_rail_player_settings = storage.rift_rail_player_settings or {}
            storage.rift_rail_player_settings[player_index] = { show_preview = false }
        end,

        -- 专供沙盒：将 GUI 钉在指定位置
        -- pos: {x, y} 格式的坐标表
        pin_gui_to_location = function(player_index, pos)
            local player = game.get_player(player_index)
            if not (player and player.valid) then
                return
            end

            local frame = player.gui.screen.rift_rail_main_frame
            if frame and frame.valid then
                frame.auto_center = false
                -- 如果传了 pos 就用 pos，否则默认 0,0
                frame.location = pos or { 0, 0 }
            end
        end,
    })
end

return Remote
