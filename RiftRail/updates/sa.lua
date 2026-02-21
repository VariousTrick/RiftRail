-- Check if space age integration is selected
local selected_integration = settings.startup["rift-rail-mod-integration"].value
if selected_integration ~= "space-age" then
    return -- should not load this file
end

-- initialize new crafting category
data:extend({
    {
        type = "recipe-category",
        name = "assembler3-crafting"
    }
})

-- new crafting category for assembling-machine-3
local assembler3 = data.raw["assembling-machine"]["assembling-machine-3"]
assembler3.crafting_categories = assembler3.crafting_categories or {}
table.insert(assembler3.crafting_categories, "assembler3-crafting")

-- set new recipe for rift-rail-placer in space age
local recipe = data.raw.recipe["rift-rail-placer"]
if recipe then
    recipe.ingredients = {
        { type = "item", name = "rail",              amount = 100 },
        { type = "item", name = "quantum-processor", amount = 50 },
        { type = "item", name = "superconductor",    amount = 50 },
        { type = "item", name = "supercapacitor",    amount = 25 },
        { type = "item", name = "tungsten-plate",    amount = 50 },
        { type = "item", name = "carbon-fiber",      amount = 50 },
        { type = "item", name = "satellit",          amount = 1 }
    }

    -- recipe requires assembler 3 to craft and space
    recipe.category = "assembler3-crafting"
    recipe.surface_conditions = {
        {
            property = "gravity",
            min = 0,
            max = 0
        }
    }
    recipe.enabled = false
end

-- change rift-rail-tech technology to require space age science packs
local tech = data.raw.technology["rift-rail-tech"]
if tech then
    tech.prerequisites = { "promethium-science-pack" }
    tech.unit = {
        count = 2500, -- set amount of science packs required
        ingredients = {
            { "promethium-science-pack",      1 },
            { "cryogenic-science-pack",       1 },
            { "electromagnetic-science-pack", 1 },
            { "metallurgic-science-pack",     1 },
            { "space-science-pack",           1 },
            { "utility-science-pack",         1 }
        },
        time = 60 -- set time per science pack
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
