---@meta

-- 开发期模块接口注解（仅供 LuaLS 使用，不参与运行时）

---@class GuiModule
---@field build_or_update fun(player: LuaPlayer, entity: LuaEntity)

---@class LtnModule
---@field on_portal_mode_changed fun(portaldata: PortalData, old_mode: string)|nil
---@field update_connection fun(source: PortalData, target: PortalData, should_connect: boolean, player: LuaPlayer|nil, enabled: boolean, extra: any|nil, source_is_entry: boolean|nil)|nil
---@field update_station_name_in_routes fun(unit_number: uint, station_name: string)|nil

---@class StateModule
---@field ensure_storage fun()
---@field get_portaldata_by_id fun(target_id: integer): PortalData|nil
---@field get_portaldata_by_unit_number fun(unit_number: uint): PortalData|nil
---@field get_portaldata fun(entity: LuaEntity): PortalData|nil
---@field get_all_portaldatas fun(): table<uint, PortalData>

---@class UtilModule
---@field init fun(deps: table)
---@field add_offset fun(base: Position, offset: Position): Position
---@field position_in_rect fun(rect: BoundingBox, pos: Position): boolean
---@field get_rolling_stock_train_id fun(rolling_stock: LuaEntity): uint|nil
---@field clone_inventory_contents fun(source_inv: LuaInventory, destination_inv: LuaInventory)
---@field clone_burner_state fun(source_entity: LuaEntity, destination_entity: LuaEntity)
---@field clone_all_inventories fun(old_entity: LuaEntity, new_entity: LuaEntity)
---@field clone_fluid_contents fun(old_entity: LuaEntity, new_entity: LuaEntity)
---@field clone_grid fun(old_entity: LuaEntity, new_entity: LuaEntity)
---@field signal_to_richtext fun(signal_id: SignalID): string
---@field rebuild_all_colliders fun()
---@field calculate_teleport_cache fun(position: Position, direction: defines.direction): Position, BoundingBox

---@class LogicModule
---@field init fun(deps: LogicDeps)
---@field refresh_station_limit fun(portaldata: PortalData)
---@field update_name fun(player_index: uint, portal_id: integer, new_string: string)
---@field set_mode fun(player_index: uint|nil, portal_id: integer, mode: string, skip_sync: boolean|nil)
---@field pair_portals fun(player_index: uint, source_id: integer, target_id: integer)
---@field unpair_portals fun(player_index: uint|nil, portal_id: integer)
---@field open_remote_view_by_target fun(player_index: uint, target_id: integer)
---@field set_ltn_enabled fun(player_index: uint, portal_id: integer, enabled: boolean)
---@field teleport_player fun(player_index: uint, portal_id: integer)
---@field unpair_all_from_exit fun(player_index: uint, portal_id: integer)
---@field unpair_portals_specific fun(player_index: uint|nil, source_id: integer, target_id: integer)
---@field set_default_exit fun(player_index: uint, entry_unit_number: uint, target_exit_id: integer)
---@field on_entity_renamed fun(event: EventData)

---@class ScheduleModule
---@field copy_schedule fun(old_train: LuaTrain, new_train: LuaTrain, station_name: string, saved_index: integer|nil, saved_manual_mode: boolean|nil)

---@class AwCompatModule
---@field on_car_replaced fun(old_car: LuaEntity, new_car: LuaEntity)|nil

---@class LtnCompatModule
---@field on_teleport_end fun(train: LuaTrain, old_train_id: uint|nil)|nil

---@class TeleportDeps
---@field State StateModule
---@field Util UtilModule
---@field Schedule ScheduleModule
---@field LtnCompat LtnCompatModule|nil
---@field AwCompat AwCompatModule|nil
---@field log_debug fun(msg: string)|nil
---@field Events table|nil

---@class LogicDeps
---@field State StateModule
---@field GUI GuiModule
---@field LTN LtnModule|nil
---@field log_debug fun(msg: string)|nil
