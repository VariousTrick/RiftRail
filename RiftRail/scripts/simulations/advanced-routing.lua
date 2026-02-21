require("__core__/lualib/story")
local surface = game.surfaces[1]

-- 【1. 搭建官方黑白相间棋盘地板】
local tiles = {}
for x = -60, 60 do
    for y = -30, 30 do
        -- 核心算法：X+Y 是偶数铺暗格，奇数铺亮格
        local tile_name = ((math.floor(x) + math.floor(y)) % 2 == 0) and "lab-dark-1" or "lab-dark-2"
        table.insert(tiles, { name = tile_name, position = { x, y } })
    end
end
surface.set_tiles(tiles)

-- 销毁多余的肉身
for _, character in pairs(surface.find_entities_filtered({ type = "character" })) do
    character.destroy()
end

-- 【2. 摄像师就位 & 开启上帝模式】
local player = game.simulation.create_test_player({ name = "TestPlayer" })
game.simulation.camera_player = player
game.simulation.camera_zoom = 0.5

-- 直接指定绝对物理坐标，这就是镜头永远钉死的位置！
game.simulation.camera_position = { -14, 0 }

-- 销毁肉身实体，玩家瞬间变成无碰撞、无体积的幽灵摄像机！
if player.character then
    player.character.destroy()
end

-- 【3. 拍蓝图 & 强行建造】
local my_blueprint =
    "0eNqlmP+O4iAQx9+Fv60p0J/m7kk2xmCLSraCodRds/HdD2jXesreDbsbs0nb4TPTgRm+9ANtu4GftJAGrT6QaJTs0erlA/ViL1nn7kl25GiFtNiZRDPRJaeONVyj6wIJ2fJ3tMLXRWiAtb0zItf1AnFphBF8dOEvLhs5HLcWt8KL+5HJxFugk+rtGCUd2jlb5gt0QaskW+aW3grNm/Fx5sJ4gJIb1FiqTHqjTs9MOhIfeNgO7g0bL5DhvUEBDxQWtgt39EIf46YBanajNoM+83bMPAtwyUR9jD0AzW/Q3mVjfxgnNJDjIDOU3wKKpGBkCUXmYGQFRZZgZA1F1mAkTsHzA58gjMFQ+BRhAobCJwnfVdJDr0lG02c8+SLmBTozLabStRkwbN+7IVpvjqp1Lvi7MJZnb0w+CbqGgsqA5Y3pZ32nkL6E51o8sG6XtILtlSV/kcZkWpgYQC7i05hMecTPDfC/eZRGX/5KJA4nElzWybRmIO9awaEUDK3hUAyFkhTc0DEJQYsQFP8QGowUXNtJDWZSMLMEMzMwE7yeCHiHTMDLiRTw5QRmlnE7OQQ5l1KnGnVURpx5oOEuaTmnk0u27fimU3vRG9H0m7eDsNdHdRZyj1Y71vV8gZQW1tnURNKlG9+oTmnfSNydOqvdX1WlZZ2WOM2ymuDK2VmILZyt/89Gn8Lw46gfRXuvNlXzyk2yG/goOkcrayQ3Qp6tf2XblB81X2Gv75pXj2/U4DQwrl1ygkb4ZkTSL43IvdH6an+BXNdxqgkwfTSNU00QJI5TTRDk3FsapvcqeXO7XkAz/XyVuVK+myA5dF0oIBon4yDvmEWqOAgzjxRxEGbxHQVC/78r0RIomT4V09OBKA9Rq7jjIYWoMFpHHA/pd06HWRp5kHs8g4bCznBc+wdkIiNxLQmCpHEtCYLM4loSBJnHdQAIsojsABBmGdkBIMwq8hQHYdbfPsTlPz/DUXv0WNuybA68HbrpM9MsZ9w1qe4MPI43SrfTR69bPb84AfH78RXW2Lp7Y8JsGiVb/w7jQHM5+RIXuhl8TNbliWm+mR4w2fqb0yDndyd0bzbzV7PJ8iy0GXxju0ujD8Ful0YlVvRcPcnG6lXGpy9mnKJCv9CkOR560z/jNuLIvwra7riv1rhwambt0+tSYx/PHw7tTHHdj627IE7N5RVJ8yzD1+sfnbK6xA=="
surface.create_entities_from_blueprint_string({
    string = my_blueprint,
    position = { 0, 0 },
    force = "player",
    player = player,
})

for _, ghost in pairs(surface.find_entities_filtered({ type = "entity-ghost" })) do
    ghost.revive({ raise_built = true })
end

local placers = surface.find_entities_filtered({ name = "rift-rail-placer-entity" })
for _, placer in pairs(placers) do
    if remote.interfaces["RiftRail_Tips"] then
        remote.call("RiftRail_Tips", "force_build", placer)
    end
end

-- 【4. 几何学排序：找出 1, 2, 3 号门】
local portals = surface.find_entities_filtered({ name = "rift-rail-entity" })
if #portals < 3 then
    return
end -- 安全防线

table.sort(portals, function(a, b)
    return a.position.x < b.position.x
end)
local entry = portals[1]

local exits = { portals[2], portals[3] }
table.sort(exits, function(a, b)
    return a.position.y < b.position.y
end)
local exit_top = exits[1]
local exit_bottom = exits[2]

-- 下一次传送目标（2 或 3），以及上一次监测到的火车 ID
local next_target = 3 -- 记录第一次传送后要修改成的目标数值
local last_train_id = nil -- 用于记录上一秒火车的 ID，用来对比是否发生了传送
local id_change_count = 0 -- 专门记录 ID 变化的次数

-- 【5. 好戏开场：时间轴剧本】
tip_story_init({
    {
        -- 第 1 幕：瞬间亮起全息 ID 标识（第 0 秒执行）
        {
            condition = story_elapsed_check(0),
            action = function()
                -- 在第一帧，安全地获取火车并设置为手动模式
                local trains = game.train_manager.get_trains({ surface = surface })
                local demo_train = trains and trains[1]
                if demo_train then
                    demo_train.manual_mode = true
                end

                rendering.draw_text({
                    text = { "tips.entry-id-1" },
                    surface = surface,
                    target = entry,
                    target_offset = { 0, -3 },
                    color = { r = 0, g = 1, b = 0 },
                    scale = 1.5,
                    alignment = "center",
                })
                rendering.draw_text({
                    text = { "tips.exit-id-2" },
                    surface = surface,
                    target = exit_top,
                    target_offset = { 0, -3 },
                    color = { r = 1, g = 0.8, b = 0 },
                    scale = 1.5,
                    alignment = "center",
                })
                rendering.draw_text({
                    text = { "tips.exit-id-3" },
                    surface = surface,
                    target = exit_bottom,
                    target_offset = { 0, -3 },
                    color = { r = 1, g = 0.8, b = 0 },
                    scale = 1.5,
                    alignment = "center",
                })
            end,
        },

        -- 第 2 幕：场景载入 1 秒后，配对 1 和 2
        {
            condition = story_elapsed_check(1),
            action = function()
                rendering.draw_line({
                    color = { r = 0, g = 1, b = 1, a = 0.5 },
                    width = 2,
                    from = entry,
                    to = exit_top,
                    surface = surface,
                    time_to_live = 60, -- 激光线持续 1 秒,Laser line lasts 1s
                })
                if remote.interfaces["RiftRail_Tips"] then
                    remote.call("RiftRail_Tips", "pair_portals_by_unit", player.index, entry.unit_number, exit_top.unit_number)
                end
            end,
        },

        -- 第 3 幕：再过 1 秒后（即第 2 秒），配对 1 和 3
        -- [EN] Act 3: After another 1s (at 2s), pair 1 and 3
        {
            condition = story_elapsed_check(2),
            action = function()
                rendering.draw_line({
                    color = { r = 0, g = 1, b = 1, a = 0.5 },
                    width = 2,
                    from = entry,
                    to = exit_bottom,
                    surface = surface,
                    time_to_live = 60, -- 激光线持续 1 秒
                })
                if remote.interfaces["RiftRail_Tips"] then
                    remote.call("RiftRail_Tips", "pair_portals_by_unit", player.index, entry.unit_number, exit_bottom.unit_number)
                end
            end,
        },

        -- 第 4 幕：再过 1 秒（即第 3 秒），所有配对完成后，发车！
        {
            condition = story_elapsed_check(3),
            action = function()
                local trains = game.train_manager.get_trains({ surface = surface })
                local demo_train = trains and trains[1]

                if demo_train and demo_train.carriages[1] then
                    player.opened = demo_train.carriages[1]

                    demo_train.manual_mode = false
                end
            end,
        },

        -- 第 5 幕：通过车厢计数实现精准的时刻表修改，并弹出跟随文字特效
        {
            condition = story_elapsed_check(15),
            update = function()
                local trains = game.train_manager.get_trains({ surface = surface })
                local current_train = trains[1]

                if current_train then
                    if not last_train_id then
                        last_train_id = current_train.id

                        -- 触发器：ID 发生了变化
                    elseif last_train_id ~= current_train.id then
                        last_train_id = current_train.id
                        id_change_count = id_change_count + 1 -- 记下一次变化

                        -- 如果变化了 2 次，说明两节车厢都传送完毕且重新拼接好了！
                        if id_change_count >= 2 then
                            local sch = current_train.schedule
                            if sch and sch.records[1] and sch.records[1].wait_conditions[1] then
                                sch.records[1].wait_conditions[1].condition.constant = next_target
                                current_train.schedule = sch

                                -- 用 rendering 绑定车头，文字会跟着火车跑！
                                local head_car = current_train.carriages[1]
                                if head_car then
                                    rendering.draw_text({
                                        text = { "tips.internal-signal-switched", next_target },
                                        surface = surface,
                                        target = head_car,
                                        target_offset = { 0, -2 },
                                        color = { r = 0, g = 1, b = 0 }, -- 纯绿色
                                        scale = 1.5,
                                        alignment = "center",
                                        time_to_live = 120, -- 存活 120 帧（2秒）后自动消散
                                    })
                                end

                                -- 状态翻转，并将计数器清零，准备迎接下一次传送
                                next_target = (next_target == 3) and 2 or 3
                                id_change_count = 0
                            end
                        end
                    end
                end
            end,
        },
    },
})
