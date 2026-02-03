-- Check if easy-mode is selected

local selected_integration = settings.startup["rift-rail-mod-integration"].value
if selected_integration ~= "easy-mode" then
    return -- should not load this file
end


-- Modify Rift Rail recipe if easy-mode mod is active
local recipe = data.raw.recipe["rift-rail-placer"]
if recipe then
    recipe.ingredients = {
        { type = "item", name = "rail", amount = 2 }
    }
end

-- Resarch Unit Change for Rift Rail if easy-mode mod is active
local tech = data.raw.technology["rift-rail-tech"]
if tech then
    tech.prerequisites = { "automation-science-pack" }
    tech.unit = {
        count = 1, -- change amount as needed
        ingredients = {
            { "automation-science-pack", 1 }
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
