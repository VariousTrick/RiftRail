-- add recipe for satellit

data:extend({
    {
        type = "recipe",
        name = "satellit",
        enabled = false,
        energy_required = 30,
        ingredients =
        {
            { type = "item", name = "low-density-structure", amount = 100 },
            { type = "item", name = "processing-unit",       amount = 100 },
            { type = "item", name = "rocket-fuel",           amount = 50 },
            { type = "item", name = "solar-panel",           amount = 100 },
            { type = "item", name = "accumulator",           amount = 100 },
            { type = "item", name = "radar",                 amount = 5 }
        },
        results = { { type = "item", name = "satellit", amount = 1 } },
    }
})


--[[
-- disable rift-rail-placer-recycle recipe and remove item-recycling recipe
local recycling_recipes = {
    "satellit-recycle",
}
for _, name in pairs(recycling_recipes) do
    local recipe = data.raw.recipe[name]
    if recipe then
        recipe.enabled = false      -- canot be used anymore
        recipe.hidden = true        -- hidden form the gui
        data.raw.recipe[name] = nil -- optionally remove all
    end
end
]]
