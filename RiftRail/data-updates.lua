-- Only load compatibility updates if the relevant mods are present and the corresponding setting is enabled

local has_sa = mods["space-age"]
local has_se = mods["space-exploration"]
local has_k2 = mods["Krastorio2"]
local has_se_k2 = has_se and has_k2

if has_sa then
    require("updates.sa") -- add SA integration
end

if has_se then
    require("updates.se") -- add SE integration
end

if has_k2 then
    require("updates.k2") -- add K2 integration
end

if has_se_k2 then
    require("updates.se-k2") -- add SE + Krastorio2 integration
end


