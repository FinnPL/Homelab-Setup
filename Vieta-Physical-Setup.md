# Vieta Physical Setup

The **Vieta** site lives in a single 10" mini-rack. This page documents the hardware, the rack layout, the power/cooling, and the 3D-printed mounts that hold it together.
For the logical architecture (Talos, ArgoCD, networking, GitOps), see the [main README](./README.md).

## The rack

A **Tecmojo 10" 9U**, with the logo covered over with vinyl for a cleaner look (idea borrowed from
[u/traviss8 on r/minilab](https://www.reddit.com/r/minilab/comments/1tzhg7l/oh_yeah_its_all_comin_together/)).

<table>
  <tr>
    <td><img src="docs/Vieta-Front.png" alt="Vieta rack, front" height="480" /></td>
    <td><img src="docs/Vieta-Back.png" alt="Vieta rack, back" height="480" /></td>
  </tr>
  <tr>
    <td align="center"><em>Front</em></td>
    <td align="center"><em>Back</em></td>
  </tr>
</table>

---

## Bill of materials

### Compute

| Component | Role | Qty |
| --- | --- | --- |
| Intel NUC (7th gen) | Proxmox host (Talos CP and other VMs, LXC)  | 1 |
| Raspberry Pi 4 | Talos Workers | 3 |
| Raspberry Pi 3 | **Out-of-band**: Tailscale entry for recovery if the cluster goes down | 2 |

### Network

| Component | Role | Qty |
| --- | --- | --- |
| UniFi Cloud Gateway Ultra (UCG-Ultra) | Router, UniFi controller | 1 |
| UniFi USW Flex 2.5G 8 PoE | Core switch, fed by the 210 W PSU, powers the USW Ultra over PoE | 1 |
| UniFi USW Ultra | Athena switch, powers the Pi cluster over PoE | 1 |
| Keystone patch panel | Front patch panel for clean cabling | 1 |

### Power & cooling

| Component | Role | Qty |
| --- | --- | --- |
| Digitus 1U PDU | Rack power distribution | 1 |
| 210 W external PSU | Powers the USW Flex 2.5G 8 PoE | 1 |
| Noctua 80 mm fan | Rear active cooling across the Pi cluster | 2 |
| Waveshare PoE HAT (E) | PoE for the Pis | 5 |


---

## Rack layout

| U | Unit |
| --- | --- |
| 1 | UCG-Ultra |
| 2 | USW Flex 2.5G 8 PoE |
| 3 | Keystone patch panel |
| 4 | USW Ultra |
| 5–6 | Pi cluster: 3x Pi4 + 2x Pi3 in the snap-in system (2U) |
| 7–8 | Intel NUC in the snap-in system (2U) |
| 9 | Free |


---

## Planned additions

- **JetKVM (PoE version)** still trying to get hold of one; it'll sit next to the NUC.
- **Spare 1U → NTP?** Leaning toward a GPS-disciplined oscillator for a NTP server with holdover. Inspired by [DIY Atomic Clock mini rack (#315)](https://github.com/geerlingguy/mini-rack/issues/315).

---

## 3D-printed parts

All 10" rack prints from MakerWorld, printed in ASA:

- [USW Flex 2.5G 8 PoE mount](https://makerworld.com/en/models/1024496-usw-flex-2-5g-8-poe-10-inch-rack-mount)
- [USW Ultra mount](https://makerworld.com/en/models/773130-unifi-usw-ultra-10-inch-rack-mount)
- [USW Ultra 210 W PSU mount](https://makerworld.com/en/models/1295688-unifi-usw-ultra-210w-power-supply-10-rack-mount)
- [UCG-Max 1U mount](https://makerworld.com/en/models/1175026-10in-mini-rack-ucg-max-1u-mount) (fits the UCG-Ultra)
- [8-bay Raspberry Pi cluster snap-in system](https://makerworld.com/en/models/2314737-rack-snap-in-system-8-bay-raspberry-pi-cluster)
- [2U Intel NUC mount](https://makerworld.com/en/models/2437633-10-inch-server-rack-2u-intel-nuc-6cay)
- [2U 80 mm fan blank panel (bridged remix)](https://makerworld.com/en/models/2062371-10-inch-2u-80mm-fan-blank-panel-bridged-remix)
- [Keystone patch panel ("Bonanza")](https://makerworld.com/en/models/2875409-10-inch-rack-patch-panel-keystone-bonanza)
- [USB labels for the Pis](https://makerworld.com/en/models/2408572-usb-label)
