-- Check if space age integration is selected

local selected_integration = settings.startup["rift-rail-mod-integration"].value
if selected_integration ~= "krastorio2" then
    return -- should not load this file
end

-- initialize new crafting category
data:extend({
    {
        type = "recipe-category",
        name = "rift-rail-k2-only"
    }
})

-- new crafting category for kr-advanced-assembling-machine
local asm = data.raw["assembling-machine"]["kr-advanced-assembling-machine"]
if asm then
    asm.crafting_categories = asm.crafting_categories or {}
    table.insert(asm.crafting_categories, "rift-rail-k2-only")
end
-- set new recipe for rift-rail-placer in Krastorio2
local recipe = data.raw.recipe["rift-rail-placer"]
if recipe then
    recipe.category = "rift-rail-k2-only"
end

-- Modify Rift Rail recipe if Krastorio2 mod is active
local tech = data.raw.technology["rift-rail-tech"]
if recipe then
    recipe.ingredients = {
        { type = "item", name = "rail",                         amount = 100 },
        { type = "item", name = "kr-rare-metals",               amount = 50 },
        { type = "item", name = "kr-ai-core",                   amount = 50 },
        { type = "item", name = "kr-energy-control-unit",       amount = 50 },
        { type = "item", name = "kr-charged-matter-stabilizer", amount = 50 },
        { type = "item", name = "kr-imersium-beam",             amount = 50 },
        { type = "item", name = "kr-gps-satellite",             amount = 2 },
        { type = "item", name = "kr-matter-cube",               amount = 8 }
    }
end

-- Resarch Unit Change for Rift Rail if Krastorio2 mod is active
if tech then
    tech.prerequisites = { "kr-singularity-tech-card" }
    tech.unit = {
        count = 4000, -- change amount as needed
        ingredients = {
            { "utility-science-pack",     1 },
            { "space-science-pack",       1 },
            { "kr-matter-tech-card",      1 },
            { "kr-advanced-tech-card",    1 },
            { "kr-singularity-tech-card", 1 },
            { "production-science-pack",  1 }
        },
        time = 60 -- change time as needed
    }
end

-- disable rift-rail-placer-recycle recipe and remove item-recycling recipe
local recycling_recipes = {
    "rift-rail-placer-recycling",
    "rift-rail-station-item-recycling"
}
for _, name in pairs(recycling_recipes) do
    local recipe = data.raw.recipe[name]
    if recipe then
        recipe.enabled = false      -- canot be used anymore
        recipe.hidden = true        -- hidden form the gui
        data.raw.recipe[name] = nil -- optionally remove all
    end
end
