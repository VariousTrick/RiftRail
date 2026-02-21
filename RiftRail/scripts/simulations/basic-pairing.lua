-- scripts/simulations/basic-pairing.lua

require("__core__/lualib/story")
local surface = game.surfaces[1]

-- 【1. 搭建官方黑白相间棋盘地板】
local tiles = {}
for x = -40, 40 do
    for y = -30, 20 do
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
-- 呼叫主模组，强行把这个玩家的摄像头关了！
if remote.interfaces["RiftRail_Tips"] then
    remote.call("RiftRail_Tips", "disable_camera_preview", player.index)
end

game.simulation.camera_player = player
game.simulation.camera_zoom = 0.65
game.simulation.camera_position = { 0, -7 }

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

-- 【4. 找出 1, 2, 3 号门】
local portals = surface.find_entities_filtered({ name = "rift-rail-entity" })
if #portals < 3 then
    return
end

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

local GUI_POS = { 20, 60 }
-- 【5. 好戏开场：基础配对与多线连接教学】
tip_story_init({
    {
        -- 第 0 幕：给火车拉手刹
        {
            name = "start",
            condition = story_elapsed_check(0),
            action = function()
                local trains = game.train_manager.get_trains({ surface = surface })
                if trains and trains[1] then
                    trains[1].manual_mode = true
                end
            end,
        },

        -- 第 1 幕：镜头锁定并打开 1 号门 GUI (第 1 秒)
        {
            condition = story_elapsed_check(1),
            action = function()
                if remote.interfaces["RiftRail_Tips"] then
                    remote.call("RiftRail_Tips", "open_portal_gui_by_unit", player.index, entry.unit_number)
                    remote.call("RiftRail_Tips", "pin_gui_to_location", player.index, GUI_POS)
                end
            end,
        },

        -- 第 2 幕：选中列表第 1 项（2号门）
        {
            condition = story_elapsed_check(1.5),
            action = function()
                if remote.interfaces["RiftRail_Tips"] then
                    remote.call("RiftRail_Tips", "simulate_gui_selection", player.index, 1)
                    remote.call("RiftRail_Tips", "pin_gui_to_location", player.index, GUI_POS)
                end
            end,
        },

        -- 第 3 幕：执行配对
        {
            condition = story_elapsed_check(1),
            action = function()
                if remote.interfaces["RiftRail_Tips"] then
                    -- 1. 底层执行配对（这会导致 GUI 刷新并跑回中间）
                    remote.call("RiftRail_Tips", "pair_portals_by_unit", player.index, entry.unit_number, exit_top.unit_number)

                    -- 2. 趁画面还没渲染，光速拽回左上角！
                    remote.call("RiftRail_Tips", "pin_gui_to_location", player.index, GUI_POS)

                    -- 3. 画出激光线
                    rendering.draw_line({
                        color = { r = 0, g = 1, b = 1 },
                        width = 2,
                        from = entry,
                        to = exit_top,
                        surface = surface,
                        time_to_live = 120,
                    })
                end
            end,
        },

        -- 第 4 幕：选中列表第 3 项（包含分隔符后的 3 号门）
        {
            condition = story_elapsed_check(1.5),
            action = function()
                if remote.interfaces["RiftRail_Tips"] then
                    remote.call("RiftRail_Tips", "simulate_gui_selection", player.index, 3)
                    remote.call("RiftRail_Tips", "pin_gui_to_location", player.index, GUI_POS)
                end
            end,
        },

        -- 第 5 幕：再次配对，展示一对多能力！
        {
            condition = story_elapsed_check(1),
            action = function()
                if remote.interfaces["RiftRail_Tips"] then
                    remote.call("RiftRail_Tips", "pair_portals_by_unit", player.index, entry.unit_number, exit_bottom.unit_number)
                    remote.call("RiftRail_Tips", "pin_gui_to_location", player.index, GUI_POS)
                    rendering.draw_line({
                        color = { r = 0, g = 1, b = 1 },
                        width = 2,
                        from = entry,
                        to = exit_bottom,
                        surface = surface,
                        time_to_live = 120,
                    })
                end
            end,
        },

        -- 第 6 幕：关闭 GUI，松开手刹，发车！
        {
            condition = story_elapsed_check(1.5),
            action = function()
                if player.gui.screen.rift_rail_main_frame then
                    player.gui.screen.rift_rail_main_frame.destroy()
                end

                local trains = game.train_manager.get_trains({ surface = surface })
                if trains and trains[1] then
                    trains[1].manual_mode = false
                end
            end,
        },

        -- 留白 3 秒让玩家欣赏火车传送，然后自动循环
        {
            condition = story_elapsed_check(3),
        },
    },
})
