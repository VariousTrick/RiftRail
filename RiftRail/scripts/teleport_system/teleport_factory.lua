-- scripts/teleport_system/teleport_factory.lua
-- 传送门车厢生成工厂模块
-- 承载所有与创建/克隆替身车厢相关的逻辑，是传送流程的"造车车间"
---@diagnostic disable: need-check-nil, undefined-global, undefined-field, param-type-mismatch

local TeleportFactory = {}

-- 依赖注入的外部模块引用
local Math = nil
local log_debug = function(...) end

---@param deps table 依赖表 / Dependency table
function TeleportFactory.init(deps)
    Math      = deps.Math
    log_debug = deps.log_debug
end

-- =================================================================================
-- 司机转移函数 (处理玩家和NPC两种情况)
-- =================================================================================
local function transfer_driver(old_entity, new_entity)
    if not (old_entity and old_entity.valid and new_entity and new_entity.valid) then
        return
    end

    local driver = old_entity.get_driver()
    if driver then
        old_entity.set_driver(nil)
        if driver.object_name == "LuaPlayer" then
            new_entity.set_driver(driver)
        elseif driver.valid and driver.teleport then
            driver.teleport(new_entity.position, new_entity.surface)
            new_entity.set_driver(driver)
        end
    end
end

-- =================================================================================
-- 【智能生成决策 v5.0】 - 无状态大一统纯数学零拷贝克隆
-- =================================================================================
-- 废弃了“首车探针”，直接利用已知的 Factorio C++ 底层规律（平行不变，垂直顺时针90度）
-- 将天然吸附方向与理论完美方向作几何比对，差180度即在源头提前翻车。
---@param car LuaEntity 要传送的旧车厢 / Old carriage to teleport
---@param entry_portaldata PortalData 入口数据 / Entry portal data
---@param exit_portaldata PortalData 出口数据 / Exit portal data
---@param spawn_pos Position 出口生成坐标 / Spawn position
---@param geo table 几何数据 / Geometry data
---@return LuaEntity|nil 新车厢实体 / New carriage entity
function TeleportFactory.spawn_next_car_intelligently(car, entry_portaldata, exit_portaldata, spawn_pos, geo)
    local entry_dir = entry_portaldata.shell.direction
    local exit_dir = exit_portaldata.shell.direction

    -- 1. 获取两门方向，计算理论完美朝向
    local expected_ori, _ = Math.calculate_arrival_orientation(entry_dir, geo.direction, car.orientation)

    -- 2. 推演底层引擎“强行吸附”出的原始天然朝向 (Natural Clone Orientation)
    local is_parallel = (entry_dir == exit_dir) or ((entry_dir + 8) % 16 == exit_dir)
    local natural_ori = car.orientation
    if not is_parallel then
        -- 如果是 90 度交错，Factorio 引擎死规律：强制顺时针旋转 90 度 (+0.25)
        natural_ori = (car.orientation + 0.25) % 1.0
    end

    -- 3. 判断是否发生了 180 度倒挂 (计算圆满度差值)
    local diff = math.abs(natural_ori - expected_ori)
    if diff > 0.5 then
        diff = 1.0 - diff
    end -- 解决 360 度循环溢出 (例如 0.9和0.1差0.2)

    local needs_rotation = false
    if diff > 0.25 then
        needs_rotation = true
    end

    if RiftRail.DEBUG_MODE_ENABLED then
        log_debug("--------------------------------------------------")
        log_debug("[RiftRail:Factory] 纯数学零拷贝克隆参数")
        log_debug(string.format("[RiftRail:Factory] 入口面向: %d, 出口面向: %d, 入口车厢原始朝向: %.2f", entry_dir, exit_dir, car.orientation))
        log_debug(string.format("[RiftRail:Factory] 轨道形态: %s", is_parallel and "平行轨道 (平移)" or "90度直角交点轨道 (+0.25)"))
        log_debug(string.format("[RiftRail:Factory] 最终判决机制 -> 在源产地反转车厢: %s", tostring(needs_rotation)))
        log_debug("--------------------------------------------------")
    end

    -- 4. 执行断开与旋转调头 (仅当引擎天然方向和期望方向颠倒时触发)
    if needs_rotation then
        -- 彻底断开这节老车厢的前后连挂，防止旋转时拉扯整个车组甚至发生致命物理碰撞
        car.disconnect_rolling_stock(defines.rail_direction.front)
        car.disconnect_rolling_stock(defines.rail_direction.back)

        local rotated_successfully = car.rotate()
        if not rotated_successfully then
            if RiftRail.DEBUG_MODE_ENABLED then
                log_debug("[RiftRail:Factory] 致命警告：车厢在入口强制原地旋转失败！传送强制阻断。")
            end
            return nil
        end
    end

    -- 5. 放下心防，执行绝对零拷贝克隆！
    local new_car = car.clone({
        surface = exit_portaldata.surface,
        position = spawn_pos,
        force = car.force,
        create_build_effect_smoke = false,
    })

    if not new_car then
        if RiftRail.DEBUG_MODE_ENABLED then
            log_debug("[RiftRail:Factory] 致命警告：克隆引擎 API 返回空值，可能底层吸附碰撞导致失败。")
        end
        return nil
    end

    -- 6. 手动转移司机 (Factorio API 的 clone 唯一不复制的就是里面的真实玩家或副驾)
    transfer_driver(car, new_car)

    return new_car
end

return TeleportFactory
