## Frequently Asked Questions (FAQ)

### **Q: How do I use Rift Rail with logistic mods like LTN or Cybersyn?**
**A:** Rift Rail acts as a bridge, creating pathways between surfaces. LTN and Cybersyn are the dispatchers that decide which train takes which path. You must enable the integration for each portal via its GUI.

---

### **Logistic Train Network (LTN)**

**Q: How do I set up cross-surface deliveries with LTN?**
**A:** It's simple:
1.  **Enable the Switch:** Open the GUI of any paired portal and turn on the "LTN" switch. The connection is bidirectional, so you only need to do this on one side.
2.  **Mode Insensitive:** LTN integration works regardless of whether the portal is in Entry, Exit, or Neutral mode.but if teleport train must in Entry
3.  **(Optional) Network ID:** You can assign different portal pairs to different LTN Network IDs in the portal's GUI, just like you would with normal LTN stops.

**Q: What is the "Teleported Cleanup Station" in the mod settings?**
**A:** It's a station temporarily inserted after teleportation, implemented using **Harag's** se-ltn-glue mod, thanks. This feature requires you to create a station with the same name as in the mod settings; trains will first go to this station after teleportation.

---

### **Cybersyn**

**Q: How do I set up cross-surface deliveries with Cybersyn?**
**A:** Please read carefully, as Cybersyn integration has specific requirements:

1.  **Requirement: Space Exploration:** Cybersyn compatibility **REQUIRES the Space Exploration mod**. It will not function in non-SE environments.
2.  **Enable the Switch:** Open the GUI of a portal and turn on the "Cybersyn" switch.
3.  **Asymmetric Configuration:** Rift Rail portals are one-way. To create a functional two-way route for Cybersyn, you must build **at least one Entry portal in EACH direction**.
    *   **Example:** For a route between Nauvis and Nauvis Orbit, you need:
        *   An **Entry** portal on Nauvis targeting Nauvis Orbit.
        *   **AND** another **Entry** portal on Nauvis Orbit targeting Nauvis.
4.  **No More Same Names:** With the new architecture, you **do not** need to give paired portals the same name. Cybersyn will automatically find the closest available Entry portal.

---

### **Troubleshooting**

**Q: My train is stuck in front of a portal or reports "No Path". What's wrong?**
**A:** Check the following:

**For LTN:**
*   Is the "LTN" switch enabled on the portals?
*   Is there a valid, powered portal path between the two surfaces?

**For Cybersyn:**
*   Is the **Space Exploration** mod installed and active?
*   Is the "Cybersyn" switch enabled?
*   Is the portal set to **Entry** mode? Cybersyn only uses Entry portals for routing.
*   **Most Common Issue:** Have you built a **return Entry portal** on the target surface? Cybersyn requires a two-way path to be available.

---
## 常见问题解答 (FAQ)

### **问：我该如何将裂隙铁路与 LTN 或 Cybersyn 等物流模组配合使用？**
**答：** 裂隙铁路扮演着“桥梁”的角色，负责在地表之间建立通道。LTN 和 Cybersyn 则是“调度员”，负责决定哪辆火车走哪条通道。您必须在每个传送门的 GUI 中为它们启用相应的集成开关。

---

### **物流列车网络 (LTN)**

**问：如何使用 LTN 设置跨地表运输？**
**答：** 非常简单：
1.  **开启开关：** 打开任意一个已配对的传送门的 GUI，打开 "LTN" 开关。连接是双向的，所以您只需在一侧操作即可。
2.  **模式不敏感：** LTN 集成与传送门的模式（入口、出口、中立）无关，均可正常工作。
3.  **（可选）网络ID：** 您可以在传送门的 GUI 中为不同的传送门对分配不同的 LTN 网络 ID，就像对待普通的 LTN 站点一样。

**问：模组设置中的“传送后清理站”是什么？**
**答：** 它是一个在传送后被临时插入的站点，实现方式来自于**Harag**的se-ltn-glue模组，感谢。该功能需要自己建立一个和模组设置中的名字一致的车站,列车在传送后会先去往这个车站。

---

### **Cybersyn**

**问：如何使用 Cybersyn 设置跨地表运输？**
**答：** 请仔细阅读，因为 Cybersyn 的集成有特定要求：

1.  **硬性要求：太空探索：** Cybersyn 兼容性**需要安装 Space Exploration (SE) 模组**。在非 SE 环境下，此功能无法使用。
2.  **开启开关：** 打开传送门的 GUI，打开 "Cybersyn" 开关。
3.  **非对称配置：** 裂隙传送门是单向的。为了给 Cybersyn 建立一个可用的双向路由，您必须在**每一个方向**都建立**至少一个“入口”传送门**。
    *   **例如：** 要建立 Nauvis 和 Nauvis Orbit 之间的线路，您需要：
        *   一个在 Nauvis 上，目标指向 Nauvis Orbit 的**入口**传送门。
        *   **并且** 另一个在 Nauvis Orbit 上，目标指向 Nauvis 的**入口**传送门。
4.  **无需同名：** 在新架构下，您**不再需要**给配对的传送门起相同的名字。Cybersyn 会自动在所有可用的入口中选择最近的一个。

---

### **问题排查**

**问：我的火车卡在传送门前，或者提示“无路径”，怎么办？**
**答：** 请检查以下几点：

**对于 LTN：**
*   传送门上的 "LTN" 开关是否已开启？
*   两个地表之间是否存在有效的、已通电的传送门路径？

**对于 Cybersyn：**
*   **Space Exploration** 模组是否已安装并激活？
*   "Cybersyn" 开关是否已开启？
*   传送门是否设置为了**入口 (Entry)** 模式？Cybersyn 只会使用入口进行寻路。
*   **最常见的问题：** 您是否在目标地表上建立了**一个用于返回的入口传送门**？Cybersyn 要求必须存在双向路径。
