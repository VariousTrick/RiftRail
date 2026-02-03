-- Modify Rift Rail recipe if Space Exploration and Krastorio2 mod is active

local selected_integration = settings.startup["rift-rail-mod-integration"].value
if selected_integration ~= "se-k2" then
    return -- should not load this file
end


--recipe change for Rift Rail if Space Exploration mod is active
local recipe = data.raw.recipe["rift-rail-placer"]
if recipe then
    recipe.ingredients = {
        { type = "item", name = "se-space-rail",            amount = 100 },
        { type = "item", name = "kr-matter-cube",           amount = 50 },
        { type = "item", name = "kr-gps-satellite",         amount = 2 },
        { type = "item", name = "kr-energy-control-unit",   amount = 50 },
        { type = "item", name = "se-naquium-plate",         amount = 50 },
        { type = "item", name = "kr-ai-core",               amount = 50 },
        { type = "item", name = "se-superconductive-cable", amount = 100 },
        { type = "item", name = "se-naquium-tessaract",     amount = 8 },
        { type = "item", name = "se-nanomaterial",          amount = 100 }
    }
end


-- Technology Change for Rift Rail if Space Exploration mod is active
local tech = data.raw.technology["rift-rail-tech"]
if tech then
    tech.prerequisites = {
        "se-space-rail",
        "se-naquium-tessaract"
    }
    tech.unit = {
        -- Resarch Unit Change for Rift Rail if Space Exploration mod is active
        count = 3500, -- change amount as needed
        ingredients = {
            { "se-rocket-science-pack",       1 },
            { "se-astronomic-science-pack-4", 1 },
            { "se-biological-science-pack-4", 1 },
            { "se-energy-science-pack-4",     1 },
            { "se-material-science-pack-4",   1 },
            { "se-deep-space-science-pack-2", 1 }
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

