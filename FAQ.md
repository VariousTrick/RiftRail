### **Q: What logistics mods are supported?**
**A:** Rift Rail currently features native integration with **LTN (Logistic Train Network)**.
*   **Note on Cybersyn:** Support for Cybersyn has been **removed** in v0.10 due to architecture conflicts.

---
**Q: Where is Cybersyn support?**
**A:** Native compatibility with Cybersyn has been **permanently removed** starting from version 0.10.2 due to architecture conflicts.
If you strictly require Cybersyn integration, you must downgrade your mod version:
*   **v0.10.1:** Last version with **N-to-M** (Many-to-Many) Cybersyn support.
*   **v0.8.2:** Last version with **1-to-1** Cybersyn support.

**⚠️ Warning:** These are legacy versions. We **DO NOT** provide maintenance, bug fixes, or support for any Cybersyn-related issues on older versions. Use them entirely at your own risk.


---

### **Core Features: N-to-M Routing**

**Q: Can I connect one Entry portal to multiple Exits? (One-to-Many)**
**A:** **Yes!** As of v0.10, you can connect an Entry portal to **up to 5** Exit portals simultaneously.

**Q: If an Entry is connected to multiple Exits, where does the train go?**
**A:** The portal decides the destination based on the following priority:
1.  **Circuit Control (Highest):** If the train schedule has a wait condition `riftrail-go-to-id > [Number]`, the train will teleport to the Exit with that specific **Unit Number ID**.
2.  **LTN Auto-Routing:** If it is an LTN train, Rift Rail will calculate the distance to the destination station and teleport to the **closest** connected Exit on that surface.
3.  **Default (Fallback):** If no instructions are given, it will teleport to the **first available** Exit in the connection list.

**Q: How do I find the "Unit Number ID" of a portal?**
**A:** Open the GUI of any portal; the ID is usually displayed in the title bar or debug info.

---
### **Logistic Train Network (LTN) Setup**

**Q: How do I set up cross-surface LTN deliveries?**
**A:** The setup logic has been updated in v0.10. To create a working route between Surface A and Surface B:

1.  **Requirement: Two-Way Path:** The LTN dispatcher requires a return path to calculate the route validity.
    *   Build `Entry A -> Exit B` (e.g., Nauvis to Vulcanus).
    *   Build `Entry C -> Exit D` (e.g., Vulcanus to Nauvis).
2.  **Enable Switches:** Open the GUI for **all 4 portals** involved and turn on the **"LTN" switch**.
3.  **Manual Activation:** Unlike previous versions, the switch now **only affects the specific building you clicked**. You must ensure it is enabled on both the Entry and Exit sides.
4.  **Universal Network (ID -1):** All Rift Rail portals are now permanently set to **Network ID -1**. They function as universal bridges for all LTN networks. The option to assign specific Network IDs to portals has been removed to simplify configuration.

---
### **问：目前支持哪些物流模组？**
**答：** Rift Rail 目前与 **LTN (Logistic Train Network)** 拥有原生集成。
*   **关于 Cybersyn：** 由于架构冲突，我们在 v0.10 版本中已**移除**了对 Cybersyn 的支持。

---
**问：Cybersyn 兼容功能去哪了？**
**答：** 由于底层架构冲突，我们从 v0.10.2 版本开始已**永久移除**了对 Cybersyn 的原生兼容。
如果您必须使用 Cybersyn 集成，请降级您的模组版本：
*   **v0.10.1:** 支持 **多对多 (N-to-M)** Cybersyn 兼容的最后一个版本。
*   **v0.8.2:** 支持 **一对一 (1-to-1)** Cybersyn 兼容的最后一个版本。

**⚠️ 警告：** 以上均为已停止维护的旧版本。作者**绝对不会**处理任何与 Cybersyn 相关的错误反馈，也不会对旧版本进行任何修复。请自行承担使用风险。

---

### **核心功能：多对多 (N-to-M) 路由**

**问：我可以将一个入口连接到多个出口吗？（一对多）**
**答：** **可以！** 从 v0.10 开始，您可以将一个入口同时连接到**最多 5 个**出口传送门。

**问：如果连了多个出口，火车会去哪一个？**
**答：** 传送门会按照以下优先级决定去向：
1.  **信号控制（最高优先级）：** 如果列车时刻表的等待条件中包含 `riftrail-go-to-id > [数字]`，列车将精准传送到 ID 为该数字的出口。
2.  **LTN 自动路由：** 如果是 LTN 列车，系统会自动计算出口与目的地的距离，并传送到同一地表上**距离最近**的那个已连接出口。
3.  **默认（保底）：** 如果没有任何指令，列车将默认传送到连接列表中的**第一个**可用出口。

**问：我怎么知道传送门的“ID”是多少？**
**答：** 打开任意传送门的 GUI，ID 通常会显示在标题栏或调试信息中。

---
### **LTN 物流网络设置**

**问：如何设置跨地表 LTN 运输？**
**答：** v0.10 更新了设置逻辑。要建立地表 A 和地表 B 之间的 LTN 通路，您需要：

1.  **硬性要求：双向往返**。LTN 调度器需要计算回程路径才能成功派单。
    *   建立 `入口 A -> 出口 B` (例如：Nauvis 到 Vulcanus)。
    *   建立 `入口 C -> 出口 D` (例如：Vulcanus 到 Nauvis)。
2.  **开启开关：** 打开这 **4 个建筑** 的 GUI，全部开启 **"LTN" 开关**。
3.  **手动激活：** 与旧版本不同，现在的开关**只影响您点击的那个建筑**。您必须分别在入口侧和出口侧都手动开启。
4.  **通用网络 (ID -1)：** 所有 Rift Rail 传送门现在固定使用 **网络 ID -1**。它们充当所有 LTN 网络的通用桥梁。为了简化配置，自定义传送门网络 ID 的功能已被移除。
