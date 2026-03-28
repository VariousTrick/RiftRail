-- RiftRail - data-final-fixes.lua
-- 目的：当安装了 LTN (LogisticTrainNetwork) 时，LTN 会为所有 train-stop 原型设置 next_upgrade。
-- 但内部车站 rift-rail-station 被设计为不可挖掘 (minable=nil)，如果存在 next_upgrade 会触发引擎约束错误。
-- 这里在最终修复阶段将 rift-rail-station 的 next_upgrade 显式清除，避免冲突。


-- Kux-SlimInserters 会在 data-updates 阶段批量缩小 container 的 selection_box。
-- rift-rail-core 基于 wooden-chest（container），会被连带影响，导致点击核心时难以打开 GUI。
-- 仅在检测到 Kux-SlimInserters 时恢复 rift-rail-core 的原始可选区域。
local KUX_SLIM_INSERTERS_INSTALLED = (mods and mods["Kux-SlimInserters"]) ~= nil
if KUX_SLIM_INSERTERS_INSTALLED then
    local core = data.raw["container"] and data.raw["container"]["rift-rail-core"]
    if core then
        core.selection_box = { { -2, -2 }, { 2, 2 } }
    end
end

-- 检测是否安装了 LTN（可选，主要用于日志），清除逻辑无论是否安装都安全
local LTN_INSTALLED = (mods and mods["LogisticTrainNetwork"]) ~= nil
if LTN_INSTALLED then
    local station = data.raw["train-stop"] and data.raw["train-stop"]["rift-rail-station"]
    if station then
        if station.next_upgrade ~= nil then
            station.next_upgrade = nil
        end
    end
end

if data.raw.recipe["rift-rail-placer-recycling"] then
    data.raw.recipe["rift-rail-placer-recycling"] = nil
end

if data.raw.recipe["rift-rail-station-item-recycling"] then
    data.raw.recipe["rift-rail-station-item-recycling"] = nil
end
