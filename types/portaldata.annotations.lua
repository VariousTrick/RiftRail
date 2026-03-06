---@meta

-- 开发期类型注解（仅供 LuaLS 使用，不参与运行时）
-- 说明：该文件不要在 control.lua/data.lua 中 require。

---@class Position
---@field x number
---@field y number

---@class PortalChildData
---@field entity LuaEntity|nil
---@field relative_pos Position|nil

---@class PortalConnectionRef
---@field custom_id integer
---@field unit_number uint

---@class PortalIcon
---@field type string
---@field name string

---@class PortalData
---@field id integer
---@field unit_number uint
---@field name string
---@field prefix string|nil
---@field icon PortalIcon|nil
---@field mode string
---@field shell LuaEntity|nil
---@field surface LuaSurface
---@field children PortalChildData[]|nil
---@field target_ids table<integer, PortalConnectionRef>|nil
---@field source_ids table<integer, PortalConnectionRef>|nil
---@field default_exit_id integer|nil
---@field waiting_target_exit_id integer|nil
---@field waiting_car LuaEntity|nil
---@field entry_car LuaEntity|nil
---@field exit_car LuaEntity|nil
---@field is_teleporting boolean|nil
---@field collider_needs_rebuild boolean|nil
---@field locked_exit_unit_number uint|nil
---@field locking_entry_id uint|nil
---@field old_train_id uint|nil
---@field saved_schedule_index integer|nil
---@field saved_manual_mode boolean|nil
---@field cached_teleport_speed number|nil
---@field cached_speed_sign integer|nil
---@field placement_interval integer|nil
---@field cached_geo table|nil
---@field cached_spawn_pos Position|nil
---@field cached_check_area BoundingBox|nil
---@field cached_place_query table|nil
---@field blocker_position Position|nil
---@field gui_map table<uint, LuaPlayer[]>|nil
---@field leadertrain LuaEntity|nil
---@field ltn_enabled boolean|nil
---@field cybersyn_enabled boolean|nil
---@field paired_to_id integer|nil
