# Rift Rail FAQ

## 中文

### 基础使用

**问：如何建立第一个 Rift Rail 连接？**

**答：**

1. 在需要连接的两个位置建造 Rift Rail。
2. 打开两个传送门的控制核心。
3. 将一个设置为入口，另一个设置为出口。
4. 在连接界面中完成配对。
5. 将铁路连接到传送门内部的轨道。
6. 让列车驶入入口传送门。

列车进入入口后，会从已连接的出口传送门出现并继续运行。

**问：入口、出口和待机模式有什么区别？**

**答：**

- **入口**：列车从这里进入并开始传送。
- **出口**：列车从这里出现。
- **待机**：暂停当前传送门的运行，不作为入口或出口使用。

**问：为什么列车没有传送？**

**答：** 请依次检查：

- 传送门是否已经完成配对。
- 一个传送门是否设置为入口，另一个是否设置为出口。
- 铁路是否连接到了传送门内部的正确轨道。
- 入口传送门是否处于待机模式。
- 目标出口是否仍然存在且有效。

### 连接与路由

**问：一个入口可以连接多个出口吗？**

**答：** 可以。一个入口最多可以连接 5 个出口；多个入口也可以连接到同一个出口。

**问：入口连接多个出口时，列车会去哪一个？**

**答：** Rift Rail 按以下顺序选择目标出口：

1. 列车时刻表中的 `riftrail-go-to-id` 信号。
2. 入口侧电路网络中的 `riftrail-go-to-id` 信号。
3. 传送门设置的默认出口。
4. 连接列表中第一个可用的出口。

只有指向有效且已连接出口的信号才会生效。

**问：如何查看传送门 ID？**

**答：** 打开传送门控制核心，ID 会显示在界面标题中。

### 玩家与列车

**问：玩家可以随列车一起传送吗？**

**答：** 可以。玩家驾驶或乘坐列车时，会随列车一起传送。

**问：手动传送玩家和随列车传送有什么区别？**

**答：** 两者是独立功能：

- 随列车传送是列车传送的一部分，不受手动传送权限设置影响。
- 控制核心中的“传送玩家”按钮用于手动传送玩家。
- 手动传送权限可以在地图设置中设为“所有玩家”“仅管理员”或“禁用”。
- 关闭手动传送不会影响列车和车内玩家的传送。

### LTN

**问：如何设置跨地表 LTN 运输？**

**答：**

1. 建立一个方向的连接，例如 `入口 A → 出口 B`。
2. 建立返回方向的连接，例如 `入口 C → 出口 D`。
3. 打开这 4 个传送门的控制核心。
4. 分别启用对应传送门上的 **LTN** 开关。

LTN 需要有效的双向路径来判断跨地表运输是否可用。Rift Rail 传送门使用通用的 LTN 网络，不需要额外设置网络 ID。

**问：为什么 LTN 不派发跨地表列车？**

**答：** 请确认：

- 两个方向的传送路径都已建立。
- 相关入口和出口上的 LTN 开关都已启用。
- 传送门不是待机模式，且连接仍然有效。
- LTN 车站和列车本身满足正常的派单条件。

### Cybersyn 2

**问：Rift Rail 支持哪些 Cybersyn 版本？**

**答：** 当前版本原生支持 **Cybersyn 2**。旧版 Cybersyn 不再支持。

**问：如何设置跨地表 Cybersyn 2 运输？**

**答：**

1. 建立一个方向的连接，例如 `入口 A → 出口 B`。
2. 建立返回方向的连接，例如 `入口 C → 出口 D`。
3. 打开这 4 个传送门的控制核心。
4. 分别启用对应传送门上的 **CS2** 开关。

CS2 需要有效的双向路径来调度跨地表列车。存在多个可用传送路径时，Rift Rail 会根据路线情况自动选择合适的路径。

**问：为什么 CS2 提示需要双向路径？**

**答：** 这通常表示当前只有单向连接，例如存在 `A → B`，但没有 `B → A`。请补建返回方向的传送路径，并确认两侧的 CS2 开关都已启用。

### 故障排查

**问：更新模组后传送门或碰撞器异常怎么办？**

**答：** 先确认没有列车正在传送，再前往 **模组设置 → 地图**，使用 Rift Rail 的“重置所有碰撞器”设置进行修复。

**问：多出口路由没有按照预期工作怎么办？**

**答：** 请检查：

- `riftrail-go-to-id` 信号是否使用了正确的传送门 ID。
- 目标出口是否已经连接到当前入口。
- 列车时刻表信号是否覆盖了入口电路信号。
- 如果没有有效信号，默认出口是否已经设置且仍然可用。

---

## English

### Basic Usage

**Q: How do I create my first Rift Rail connection?**

**A:**

1. Build Rift Rail portals at the two locations you want to connect.
2. Open both portal control cores.
3. Set one portal to Entry mode and the other to Exit mode.
4. Pair the portals through the connection interface.
5. Connect the railway to the internal portal tracks.
6. Send a train through the Entry portal.

The train will appear at the connected Exit portal and continue its journey.

**Q: What is the difference between Entry, Exit, and Standby mode?**

**A:**

- **Entry**: Trains enter here and begin teleporting.
- **Exit**: Trains appear here.
- **Standby**: Pauses the portal and disables its Entry/Exit operation.

**Q: Why is my train not teleporting?**

**A:** Check the following:

- The portals are paired.
- One portal is set to Entry and the other to Exit.
- The railway is connected to the correct internal tracks.
- The Entry portal is not in Standby mode.
- The destination Exit portal still exists and is valid.

### Connections and Routing

**Q: Can one Entry portal connect to multiple Exits?**

**A:** Yes. One Entry can connect to up to 5 Exits, and multiple Entries can connect to the same Exit.

**Q: Which Exit is selected when an Entry has multiple connections?**

**A:** Rift Rail selects the destination in this order:

1. The `riftrail-go-to-id` signal in the train schedule.
2. The `riftrail-go-to-id` signal on the Entry-side circuit network.
3. The configured default Exit.
4. The first available Exit in the connection list.

Signals only take effect when they point to a valid connected Exit.

**Q: How do I find a portal ID?**

**A:** Open the portal control core. The ID is shown in the interface title.

### Players and Trains

**Q: Can players travel with a train?**

**A:** Yes. Players driving or riding in a train travel with the train.

**Q: What is the difference between manual player teleportation and train teleportation?**

**A:** They are separate features:

- Players inside trains travel with the train and are not affected by the manual teleport permission setting.
- The **Teleport Player** button in the control core provides manual player teleportation.
- Manual teleportation can be set to **All players**, **Admins only**, or **Disabled** in the map settings.
- Disabling manual teleportation does not affect trains or players travelling inside them.

### LTN

**Q: How do I set up cross-surface LTN deliveries?**

**A:**

1. Build a connection in one direction, such as `Entry A → Exit B`.
2. Build a return connection, such as `Entry C → Exit D`.
3. Open the control cores of all four portals.
4. Enable the **LTN** switch on each relevant portal.

LTN requires a valid two-way path to determine whether cross-surface deliveries are available. Rift Rail portals use a universal LTN network and do not require a separate network ID.

**Q: Why is LTN not dispatching trains across surfaces?**

**A:** Confirm that:

- Routes exist in both directions.
- The LTN switch is enabled on the relevant Entry and Exit portals.
- The portals are not in Standby mode and their connections are valid.
- The LTN stations and train meet the normal dispatch requirements.

### Cybersyn 2

**Q: Which Cybersyn versions are supported?**

**A:** The current version natively supports **Cybersyn 2**. Classic Cybersyn is no longer supported.

**Q: How do I set up cross-surface Cybersyn 2 deliveries?**

**A:**

1. Build a connection in one direction, such as `Entry A → Exit B`.
2. Build a return connection, such as `Entry C → Exit D`.
3. Open the control cores of all four portals.
4. Enable the **CS2** switch on each relevant portal.

CS2 requires a valid two-way path to dispatch cross-surface trains. When multiple transfer paths are available, Rift Rail automatically selects a suitable route.

**Q: Why does CS2 warn that a two-way path is required?**

**A:** This usually means that only one direction exists, such as `A → B` without `B → A`. Build the return route and make sure the CS2 switches on both sides are enabled.

### Troubleshooting

**Q: What should I do if portals or colliders behave incorrectly after an update?**

**A:** Make sure no train is currently teleporting. Then open **Mod Settings → Map** and use Rift Rail's **Reset All Colliders** setting.

**Q: Why is multi-Exit routing not selecting the expected destination?**

**A:** Check the following:

- The `riftrail-go-to-id` signal uses the correct portal ID.
- The destination Exit is connected to the current Entry.
- A train schedule signal takes priority over an Entry-side circuit signal.
- If no valid signal is present, the default Exit is configured and still available.
