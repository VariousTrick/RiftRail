---@meta
---@diagnostic disable: undefined-global, inject-field, duplicate-set-field

-- Factorio API 基础注解（开发期使用）
-- 说明：这是最小可用子集，用于让 LuaLS 识别常见运行时类型。

---@alias uint integer

---@class BoundingBox
---@field left_top table
---@field right_bottom table

---@class SignalID
---@field type string
---@field name string
---@field quality? string

---@class LuaObject
---@field valid? boolean

---@class LuaEntity: LuaObject
---@field unit_number uint|nil
---@field name string
---@field type string
---@field position Position
---@field surface LuaSurface
---@field force LuaForce
---@field train LuaTrain|nil
---@field orientation number
---@field health number
---@field quality string|nil
---@field grid LuaEquipmentGrid|nil
---@field burner LuaBurner|nil
---@field fluids_count integer|nil
---@field energy number|nil
---@field backer_name string|nil
---@field destructible boolean
---@field tags table|nil
---@field object_name string|nil
---@field ghost_name string|nil
---@field opened LuaEntity|LuaGuiElement|nil
---@field state integer|nil
---@field manual_mode boolean|nil
---@field speed number|nil
---@field direction defines.direction
---@field shell LuaEntity|nil
---@field children table|nil
---@field train_stop LuaEntity|nil
---@field schedule LuaSchedule|nil
---@field front_end LuaTrainEnd|nil
---@field back_end LuaTrainEnd|nil
---@field remains_when_mined string|nil
---@field remains_when_built string|nil
---@field remains_when_died string|nil
---@field trains_limit integer|nil
---@field id integer|nil
---@field wait_conditions table|nil
---@field condition table|nil
---@field constant integer|nil
---@field first_signal SignalID|nil
---@field inventory LuaInventory|nil
---@field burnt_result_inventory LuaInventory|nil
---@field currently_burning LuaEntityPrototype|nil
---@field remaining_burning_fuel number|nil
---@field shield number|nil
---@field ghost boolean|nil
---@field equipment LuaEquipment[]|nil
---@field icon table|nil
---@field prefix string|nil
---@field target_ids table|nil
---@field source_ids table|nil
---@field waiting_car LuaEntity|nil
---@field waiting_target_exit_id integer|nil
---@field entry_car LuaEntity|nil
---@field exit_car LuaEntity|nil
---@field old_train_id integer|nil
---@field saved_schedule_index integer|nil
---@field saved_manual_mode boolean|nil
---@field cached_teleport_speed number|nil
---@field cached_speed_sign integer|nil
---@field cached_place_query table|nil
---@field cached_spawn_pos Position|nil
---@field cached_check_area BoundingBox|nil
---@field cached_geo table|nil
---@field blocker_position Position|nil
---@field placement_interval integer|nil
---@field locked_exit_unit_number uint|nil
---@field locking_entry_id uint|nil
---@field is_teleporting boolean|nil
---@field collider_needs_rebuild boolean|nil
---@field gui_map table|nil
---@field leadertrain LuaEntity|nil
---@field ltn_enabled boolean|nil
---@field cybersyn_enabled boolean|nil
---@field default_exit_id integer|nil
---@field destroy fun()
---@field clone fun(spec: table): LuaEntity|nil
---@field rotate fun(): boolean
---@field get_connected_rolling_stock fun(direction: defines.rail_direction|integer): LuaEntity|nil
---@field disconnect_rolling_stock fun(direction: defines.rail_direction|integer)
---@field get_signal fun(signal: SignalID, red: integer|nil, green: integer|nil): number
---@field copy_settings fun(entity: LuaEntity)

---@class LuaEntityPrototype
---@field name string

---@class LuaForce

---@class LuaTrainLocomotives
---@field front_movers LuaEntity[]
---@field back_movers LuaEntity[]

---@class LuaTrain: LuaObject
---@field id uint
---@field schedule LuaSchedule|nil
---@field manual_mode boolean
---@field speed number
---@field max_forward_speed number
---@field max_backward_speed number
---@field weight number
---@field carriages LuaEntity[]
---@field locomotives LuaTrainLocomotives
---@field cargo_wagons LuaEntity[]
---@field fluid_wagons LuaEntity[]
---@field state defines.train_state|integer
---@field front_stock LuaEntity|nil
---@field back_stock LuaEntity|nil
---@field station LuaEntity|nil
---@field has_path boolean
---@field path_end_rail LuaEntity|nil
---@field path_end_stop LuaEntity|nil
---@field passengers LuaPlayer[]
---@field riding_state table|nil
---@field killed_players table<uint, uint>
---@field kill_count uint
---@field path table|nil
---@field signal LuaEntity|nil
---@field group string
---@field front_end LuaTrainEnd|nil
---@field back_end LuaTrainEnd|nil
---@field object_name string
---@field go_to_station fun(index: integer)
---@field get_schedule fun(): LuaSchedule
function LuaTrain:go_to_station(index) end
function LuaTrain:get_item_count(item) end
function LuaTrain:get_contents() end
function LuaTrain:remove_item(stack) end
function LuaTrain:insert(stack) end
function LuaTrain:clear_items_inside() end
function LuaTrain:recalculate_path(force) end
function LuaTrain:get_fluid_count(fluid) end
function LuaTrain:get_fluid_contents() end
function LuaTrain:remove_fluid(fluid) end
function LuaTrain:insert_fluid(fluid) end
function LuaTrain:clear_fluids_inside() end
function LuaTrain:get_rails() end
function LuaTrain:get_rail_end(direction) end
function LuaTrain:get_schedule() end

---@class LuaTrainEnd
---@field rail LuaEntity|nil
---@field direction defines.rail_direction|integer

---@class LuaSchedule
---@field current integer
---@field records table[]
---@field get_records fun(): table[]
---@field add_record fun(record: table)
---@field set_records fun(records: table[])
---@field set_current fun(index: integer)
---@field set_interrupts fun(interrupts: table)
---@field get_interrupts fun(): table
---@field go_to_station fun(index: integer)
---@field group string

---@class LuaSurfaceCreateEntityParam
---@field name string
---@field position Position
---@field direction defines.direction|integer|nil
---@field force LuaForce|string|nil
---@field quality string|nil
---@field orientation number|nil
---@field raise_built boolean|nil
---@field create_build_effect_smoke boolean|nil
---@field snap_to_grid boolean|nil
---@field snap_to_train_stop boolean|nil
---@field fast_replace boolean|nil
---@field target LuaEntity|Position|nil
---@field source LuaEntity|Position|nil
---@field cause LuaEntity|LuaForce|string|nil

---@class LuaSurfaceCanPlaceEntityParam
---@field name string
---@field position Position
---@field direction defines.direction|integer|nil
---@field force LuaForce|string|nil
---@field build_check_type integer|nil
---@field forced boolean|nil
---@field inner_name string|nil

---@class LuaSurfaceEntitySearchFilters
---@field area BoundingBox|nil
---@field position Position|nil
---@field radius number|nil
---@field name string|string[]|nil
---@field type string|string[]|nil
---@field force LuaForce|string|nil
---@field limit integer|nil

---@class LuaSurface: LuaObject
---@field name? string
---@field index? uint
---@field map_gen_settings? table
---@field generate_with_lab_tiles? boolean
---@field always_day? boolean
---@field daytime? number
---@field darkness? number
---@field wind_speed? number
---@field wind_orientation? number
---@field wind_orientation_change? number
---@field peaceful_mode? boolean
---@field no_enemies_mode? boolean
---@field freeze_daytime? boolean
---@field ticks_per_day? uint
---@field dusk? number
---@field dawn? number
---@field evening? number
---@field morning? number
---@field daytime_parameters? table
---@field solar_power_multiplier? number
---@field min_brightness? number
---@field brightness_visual_weights? table
---@field show_clouds? boolean
---@field has_global_electric_network? boolean
---@field platform? table|nil
---@field planet? table|nil
---@field deletable? boolean
---@field global_effect? table|nil
---@field pollutant_type? table|nil
---@field localised_name? table|string|nil
---@field ignore_surface_conditions? boolean
---@field pollution_statistics? table
---@field global_electric_network_statistics? table|nil
---@field object_name? string
---@field create_entity? fun(spec: LuaSurfaceCreateEntityParam): LuaEntity|nil
---@field count_entities_filtered? fun(spec: LuaSurfaceEntitySearchFilters): integer
---@field can_place_entity? fun(spec: LuaSurfaceCanPlaceEntityParam): boolean
---@field find_entities_filtered? fun(spec: LuaSurfaceEntitySearchFilters): LuaEntity[]
---@param spec LuaSurfaceCreateEntityParam
---@return LuaEntity|nil
function LuaSurface:create_entity(spec) end
---@param spec LuaSurfaceEntitySearchFilters
---@return integer
function LuaSurface:count_entities_filtered(spec) end
---@param spec LuaSurfaceCanPlaceEntityParam
---@return boolean
function LuaSurface:can_place_entity(spec) end
---@param spec table
---@return boolean
function LuaSurface:can_fast_replace(spec) end
---@param name string
---@param position Position
---@return LuaEntity|nil
function LuaSurface:find_entity(name, position) end
---@param area BoundingBox
---@return LuaEntity[]
function LuaSurface:find_entities(area) end
---@param spec LuaSurfaceEntitySearchFilters
---@return LuaEntity[]
function LuaSurface:find_entities_filtered(spec) end
---@param name string
---@param position Position
---@param radius number
---@param precision number
---@param force_to_tile_center boolean|nil
---@return Position|nil
function LuaSurface:find_non_colliding_position(name, position, radius, precision, force_to_tile_center) end
---@param name string
---@param search_space BoundingBox
---@param precision number
---@param force_to_tile_center boolean|nil
---@return Position|nil
function LuaSurface:find_non_colliding_position_in_box(name, search_space, precision, force_to_tile_center) end
---@param position Position
---@return number
function LuaSurface:get_pollution(position) end
---@param position Position
---@param amount number
function LuaSurface:set_pollution(position, amount) end
---@param x integer|Position
---@param y integer|nil
---@return LuaTile
function LuaSurface:get_tile(x, y) end
---@param message any
---@param print_settings table|nil
function LuaSurface:print(message, print_settings) end
---@param sound_specification table
function LuaSurface:play_sound(sound_specification) end
---@return table<string, integer>
function LuaSurface:get_resource_counts() end
---@return number
function LuaSurface:get_total_pollution() end
---@param source Position
---@param amount number
---@param prototype string|nil
function LuaSurface:pollute(source, amount, prototype) end
function LuaSurface:clear_pollution() end
---@return fun():integer, ChunkPosition
function LuaSurface:get_chunks() end
---@param chunk_position ChunkPosition
---@return boolean
function LuaSurface:is_chunk_generated(chunk_position) end
---@param position Position
---@param radius integer|nil
function LuaSurface:request_to_generate_chunks(position, radius) end
function LuaSurface:force_generate_chunk_requests() end
---@param chunk_position ChunkPosition
---@param status integer
function LuaSurface:set_chunk_generated_status(chunk_position, status) end

---@alias LuaSurface.can_place_entity_param LuaSurfaceCanPlaceEntityParam

---@class ChunkPosition
---@field x integer
---@field y integer

---@class LuaTile: LuaObject
---@field position Position
---@field name string

---@class LuaInventory
---@field valid boolean
function LuaInventory:clear() end

---@class LuaEquipmentGrid
---@field equipment LuaEquipment[]
function LuaEquipmentGrid:put(spec) end

---@class LuaEquipment
---@field valid boolean
---@field type string
---@field name string
---@field ghost_name string|nil
---@field position Position
---@field quality string|nil
---@field shield number|nil
---@field energy number|nil
---@field burner LuaBurner|nil

---@class LuaBurner
---@field inventory LuaInventory|nil
---@field burnt_result_inventory LuaInventory|nil
---@field currently_burning LuaEntityPrototype|nil
---@field remaining_burning_fuel number|nil

---@class LuaPlayer: LuaObject
---@field opened LuaEntity|LuaGuiElement|nil
---@field zoom number
---@field gui table
---@field connected boolean|nil
function LuaPlayer:set_controller(spec) end
function LuaPlayer:teleport(position, surface) end
function LuaPlayer:print(msg) end

---@class LuaGuiElement: LuaObject
---@field name string
---@field tags table

---@class EventData
---@field entity LuaEntity|nil
---@field cause LuaEntity|nil
---@field tick integer|nil
---@field tags table|nil

---@class defines
---@field direction defines.direction
---@field rail_direction defines.rail_direction
---@field train_state defines.train_state
---@field inventory defines.inventory
---@field controllers defines.controllers
---@field wire_connector_id defines.wire_connector_id

---@class defines.direction
---@field north integer
---@field east integer
---@field south integer
---@field west integer

---@class defines.rail_direction
---@field front integer
---@field back integer

---@class defines.train_state
---@field on_the_path integer

---@class defines.inventory
---@field cargo_wagon integer
---@field artillery_wagon_ammo integer

---@class defines.controllers
---@field remote integer

---@class defines.wire_connector_id
---@field circuit_red integer
---@field circuit_green integer

---@class script
---@field active_mods table<string, boolean>
function script.raise_event(id, data) end

---@class settings
---@field global table<string, { value: any }>

---@class game
---@field connected_players LuaPlayer[]
---@field surfaces LuaSurface[]
function game.get_player(index) end
function game.print(msg) end

---@type defines
defines = defines
---@type script
script = script
---@type settings
settings = settings
---@type game
game = game
