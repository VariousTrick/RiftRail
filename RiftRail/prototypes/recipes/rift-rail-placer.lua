-- Recipe for Rift Rail Placer

data:extend({
    {
        type = "recipe",
        name = "rift-rail-placer",
        enabled = false,
        energy_required = 30,
        ingredients = {
            { type = "item", name = "rail",                        amount = 100 },
            { type = "item", name = "radar",                       amount = 2 },
            { type = "item", name = "processing-unit",             amount = 50 },
            { type = "item", name = "steel-plate",                 amount = 150 },
            { type = "item", name = "energy-shield-mk2-equipment", amount = 5 },
        },
        results = { { type = "item", name = "rift-rail-placer", amount = 2 } },
    },
})
