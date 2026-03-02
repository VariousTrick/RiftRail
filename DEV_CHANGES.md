# RiftRail 开发变更记录

> 说明：模组未发布阶段使用本文件记录每一次改动。
> 规则：新改动统一追加到最上方（时间倒序），每次包含日期、改动文件、改动内容。

## 2026-03-01（AW桥接参数改为实体对象）

### 改动摘要
- 将 AW 兼容桥接调用参数从 `unit_number` 改为 `LuaEntity`，以支持 AW 侧完整更新反向映射。

### 具体改动
- `scripts/compat/aw.lua`
  - `remote.call("AssemblyWagon", "transfer_binding", ...)` 参数由
    - `old_car.unit_number, new_car.unit_number`
    改为
    - `old_car, new_car`。

### 备注
- 该调整用于配合 AssemblyWagon 新增的 `transfer_binding(old_wagon, new_wagon)` 接口实现。

## 2026-03-01（Informatron兼容文件归档到compat）

### 改动摘要
- 将 Informatron 适配脚本移动到 `scripts/compat` 目录，统一兼容模块结构。
- 同步更新 `control.lua` 中的加载路径，保持运行逻辑不变。

### 具体改动
- `scripts/compat/informatron.lua`
  - 由原 `scripts/informatron.lua` 迁移而来（仅路径调整）。

- `control.lua`
  - `require("scripts.informatron")` 改为 `require("scripts.compat.informatron")`。

## 2026-03-01（compat目录重构 + AW兼容接入）

### 改动摘要
- 在 `scripts` 下建立 `compat` 目录，统一管理兼容模块。
- 将 LTN 兼容模块迁移到 `scripts/compat/ltn.lua`。
- 新增 AssemblyWagon 兼容模块 `scripts/compat/aw.lua`，用于车厢传送后 old/new 映射桥接。
- 在传送主流程中加入单点兼容调用，统一覆盖 clone/create 两种创建路径。

### 具体改动
- `scripts/compat/ltn.lua`
  - 由原 `scripts/ltn_compat.lua` 迁移而来（文件路径调整）。

- `scripts/compat/aw.lua`（新文件）
  - 新增 `AW.init(deps)`：缓存 `script.active_mods["AssemblyWagon"]` 状态。
  - 新增 `AW.on_car_replaced(old_car, new_car)`：
    - 仅在 AssemblyWagon 已启用且 `old/new` 均为 `assembly-wagon` 时执行。
    - 检查 `remote.interfaces["AssemblyWagon"].transfer_binding` 是否存在。
    - 使用 `pcall(remote.call, ...)` 调用接口并在调试模式下记录失败日志。

- `control.lua`
  - `require("scripts.ltn_compat")` 改为 `require("scripts.compat.ltn")`。
  - 新增 `local AWCompat = require("scripts.compat.aw")`。
  - 启动时调用 `AWCompat.init({ log_debug = log_debug })`。
  - 向 `Teleport.init(...)` 注入 `AwCompat = AWCompat`。

- `scripts/teleport.lua`
  - 新增依赖字段 `AwCompat` 并在 `Teleport.init(deps)` 中接收。
  - 在 `new_car` 创建成功后、`car.destroy()` 前调用：
    - `AwCompat.on_car_replaced(car, new_car)`
  - 该调用点统一适配 clone/create 路径，无需在多处分支重复判断。

### 备注
- 目前仅完成 RiftRail 侧兼容桥接；AssemblyWagon 侧 `remote interface` 后续再接。
