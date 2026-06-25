# Instructor Script — Module 2: VNet Peering

**Duration:** ~20 minutes (5 min intro + 10 min lab + 5 min regroup)  
**Participant action:** Create the spoke-to-hub peering (both sides). Verify *Connected* status.  
**Instructor action:** None required during normal flow — participants have `peer/action` on hub-vnet via the *Workshop Hub Peering* custom role. `peer-hub.ps1` is available as a fallback if any participant hit the permission error before the role was assigned.

---

## Before you open this module

- Admin dashboard should show all **M1 Networking = ✓**.
- Verify participants have the *Workshop Hub Peering* role on hub-vnet: `Get-AzRoleAssignment -Scope "/subscriptions/<SUBSCRIPTION_ID>/.../hub-vnet" -RoleDefinitionName 'Workshop Hub Peering'` — if the list is empty, run `infra\fix-hub-peering-rbac.ps1` now.
- Have the portal open on hub-vnet's Peerings blade on your screen to show what a Connected peering looks like.

---

## Opening talk (5 min)

> "In Module 1 you created your spoke VNet. Right now it's isolated — it can't talk to the hub, it can't reach Azure Bastion, and your VM in Module 3 won't be reachable. Module 2 fixes that by connecting your spoke to the hub through VNet peering."

### Key concept: What is VNet peering?

> "VNet peering is a direct, high-bandwidth, low-latency connection between two VNets on the Microsoft backbone — no VPN, no gateway, no public internet. Traffic between peered VNets stays inside Azure's network.
>
> Today you're creating a **hub-spoke peering**, which is the standard pattern in Azure Landing Zones. Think of the hub as the shared services platform — it has Bastion for secure access, and in production it would have a firewall for egress inspection and potentially a VPN gateway for on-premises connectivity."

### Key concept: Why two sides?

> "This is the part that trips people up. Azure VNet peering requires a peering resource on **both** VNets. You can only create a peering on VNets you have write access to.
>
> "The platform team normally controls hub-side peering changes — and in a real enterprise, you wouldn't have write access to the hub at all. For this workshop we've given you a narrow set of permissions on hub-vnet — `Microsoft.Network/virtualNetworks/peer/action` plus read, write, and delete on the peering child resources (`virtualNetworkPeerings`) — so you can complete the connection yourselves. Crucially, this does **not** let you modify the hub VNet itself (subnets, address space, etc.), only its peering links. This mirrors how a self-service landing zone portal would work.
>
> The portal creates both sides in one shot. After you click Add, status should jump straight to **Connected**."

### Key concept: Non-transitive routing

> "One important thing to know about VNet peering: it's non-transitive by default. That means if spoke-A is peered to the hub, and spoke-B is peered to the hub, spoke-A and spoke-B **cannot** talk to each other directly through the hub — unless you add User-Defined Routes that send inter-spoke traffic to a firewall in the hub for forwarding. We won't go through UDRs today, but this is why hub firewalls exist in Landing Zone designs — they make peering transitive by acting as a router."

---

## Lab (10 min)

> "On the module page you'll see your spoke VNet name and CIDR already filled in. Open the portal link and navigate to your VNet."

### Walk-through (demo on your screen)

1. **VNet → Settings → Peerings → + Add**

   The portal shows a single combined form with two sections: **Remote virtual network** (top) and **Local virtual network** (bottom). "Remote" = the hub you're peering *to*. "Local" = your own spoke.

2. **Remote virtual network summary** (top section — configures the hub side):
   - Peering link name: `hub-to-userXX` *(filled in on the module page as `step-hub-peering-name`)*
   - Peering type: **Virtual network**
   - Subscription: their workshop subscription
   - Virtual network: **hub-vnet (hub-rg)**
   - > "You have Reader access on hub-rg so it appears in the picker. You can't write to it — that's why only the instructor can create the hub-side peering from the hub."
   - Leave **Remote virtual network peering settings** at defaults — only "Allow hub-vnet to access your spoke" stays checked. Leave all gateway/forwarding options unchecked.

3. **Local virtual network summary** (bottom section — configures your spoke side):
   - Peering link name: `userXX-to-hub` *(filled in on the module page as `step-peering-name`)*
   - Leave **Local virtual network peering settings** at defaults — only "Allow your spoke to access hub-vnet" stays checked.

4. **Click Add** — status should show **Connected** within a few seconds

   > "Both sides are created simultaneously. You should see Connected almost immediately — if you see Initiated, give it 10–15 seconds and refresh."

### While participants work — things to watch for

- **"I can't find hub-vnet in the picker"** — they need to switch subscription scope in the picker, or they may have searched by name when they need to browse by resource group (hub-rg).
- **"Should the remote peering link name match something?"** — yes, it's the name that will appear on hub-vnet's peering list. Tell them to use `hub-to-userXX` as shown on the page.
- **"My peering shows Disconnected/Failed"** — check if they accidentally created a duplicate peering. Have them delete it and retry.
- **"I get a permission error / 'does not have permission to perform peer/action'"** — the `Workshop Hub Peering` role wasn't assigned yet. Run `infra\fix-hub-peering-rbac.ps1 -SubscriptionId <SUBSCRIPTION_ID> -Slot userXX` for just that participant, then have them F5 and retry.
- **"Can I proceed to Module 3 before it's Connected?"** — yes they can create the VM, but they won't be able to connect via Bastion until peering is Connected.

---

## Instructor: monitoring (no action needed in normal flow)

Participants now have the *Workshop Hub Peering* custom role on hub-vnet (`peer/action` plus `virtualNetworkPeerings` read/write/delete), so both peering sides are created together when they click Add. Watch the admin dashboard — the M2 Peering column should light up as participants click Complete.

If any participant reports a permission error ("does not have permission to perform peer/action"):

```powershell
cd <repo-root>
# Fix one participant:
.\infra\fix-hub-peering-rbac.ps1 -SubscriptionId <SUBSCRIPTION_ID> -Slot user05

# Or fix all 30 at once (safe to re-run — idempotent):
.\infra\fix-hub-peering-rbac.ps1 -SubscriptionId <SUBSCRIPTION_ID>
```

The fallback `peer-hub.ps1` script remains available if you need to create hub-side peerings manually (e.g. a participant's peering got into a broken state):

```powershell
.\infra\peer-hub.ps1 -SessionId contoso-2026-01-01 -Slot user05
```

---

## Regroup (5 min)

> "Click **Complete** when your peering shows **Connected**."

Wait for the admin dashboard **M2 Peering = ✓** count to stabilize before continuing.

### Regroup discussion questions

> "A couple of things to think about while we regroup:
>
> - After peering connected, did anyone look at the **Routes** tab of their VNet? What new routes appeared?
> - *(Answer: a new route for 10.0.0.0/16 via VNet peering — Azure automatically propagates hub reachability to your spoke's routing table.)*
>
> - What would you need to add if you wanted a VM in your spoke to be able to reach the internet — but have that traffic inspected by a firewall in the hub?
> - *(Answer: a User-Defined Route on the workload subnet with 0.0.0.0/0 → hub firewall private IP, plus IP forwarding enabled on the firewall NIC.)*"

### Transition

> "Your spoke is now connected to the hub. Azure Bastion in the hub can now reach anything in your workload subnet. In Module 3 you'll deploy a VM into that subnet — with no public IP — and use Bastion to connect to it. Let's go."

---

## Common peering troubleshooting reference

| Symptom | Likely cause | Fix |
|---|---|---|
| "does not have permission to peer" error | `Workshop Hub Peering` role not yet assigned | Run `fix-hub-peering-rbac.ps1 -Slot userXX` then F5 |
| Status stays *Initiated* after 30s | Rare race condition | Refresh; if still Initiated, run `peer-hub.ps1 -Slot userXX` |
| Status is *Disconnected* | One side was deleted | Delete both sides and re-create |
| Can't find hub-vnet in picker | Wrong subscription scope in picker | Switch to show all subscriptions / all RGs |
| Peering created but Bastion can't reach VM | Peering is Connected but UDR is blocking | Check effective routes on VM NIC |
