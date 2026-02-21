-- scripts/informatron.lua
local Info = {}

-- 1. 定义左侧菜单树 (图纸)
function Info.menu(player_index)
    return {
        -- 注意：根目录通常使用接口名称，子目录我们用 rr_ 前缀
        rr_pairing = 1,
        rr_routing = 1,
        rr_ltn = 1,
        rr_faq = 1,
    }
end

-- 2. 定义页面内容 (导游)
function Info.page_content(page_name, player_index, element)
    if page_name == "rift_rail_informatron" then
        element.add({ type = "label", name = "text_1", caption = { "rift_rail_informatron.page_main_text_1" } })
        element.add({ type = "label", name = "text_2", caption = { "rift_rail_informatron.page_main_text_2" } })
    elseif page_name == "rr_pairing" then
        element.add({ type = "label", name = "text_1", caption = { "rift_rail_informatron.page_pairing_text_1" } })
    elseif page_name == "rr_routing" then
        element.add({ type = "label", name = "text_1", caption = { "rift_rail_informatron.page_routing_text_1" } })
        element.add({ type = "label", name = "text_2", caption = { "rift_rail_informatron.page_routing_text_2" } })
    elseif page_name == "rr_ltn" then
        element.add({ type = "label", name = "text_1", caption = { "rift_rail_informatron.page_ltn_text_1" } })
    elseif page_name == "rr_faq" then
        element.add({ type = "label", name = "text_1", caption = { "rift_rail_informatron.page_faq_text_1" } })
    end

    for _, child in pairs(element.children) do
        if child.type == "label" then
            child.style.single_line = false
            child.style.maximal_width = 800
            child.style.bottom_margin = 8
        end
    end
end

-- 3. 注册安全接口 (修复参数传递)
function Info.setup_interface()
    remote.add_interface("rift_rail_informatron", {
        -- Informatron 会传过来一个 data 表，我们在这里把它拆解开，再传给我们的函数
        informatron_menu = function(data)
            return Info.menu(data.player_index)
        end,
        informatron_page_content = function(data)
            return Info.page_content(data.page_name, data.player_index, data.element)
        end,
    })
end

return Info
