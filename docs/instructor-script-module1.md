# Instructor Script — Module 1: Networking

**Duration:** ~20–25 minutes (5 min intro + 10–15 min lab + 5 min regroup)  
**Participant action:** Create a VNet with a workload subnet in their assigned resource group.

---

## Before you open this module

- Confirm all participants have signed in on `index.html` and can see their **RG** and **CIDR** in the assignment banner.
- Check the admin dashboard — all rows should show **Sign In = ✓** before proceeding.
- Have the portal open on your own screen to demo the VNet creation flow.

---

## Opening talk (5 min)

> "Welcome to Module 1. Everything in Azure IaaS starts with a Virtual Network — it's the private address space your resources live in, and it's the foundation for everything we'll build today. Before we click anything, I want to give you 2 minutes of context so you understand *why* we're doing this the way we're doing it."

### Key concept: Spoke VNets in an Azure Landing Zone

> "In a real enterprise Azure environment, you wouldn't have one giant shared VNet. You'd use an Azure Landing Zone pattern — a hub-and-spoke topology where each workload team gets their own isolated spoke VNet.
>
> Today, each of you is simulating that workload team. You each have:
> - A **dedicated resource group** — isolated by RBAC, so you can only see your own resources
> - A **dedicated CIDR block** — a non-overlapping address range from the 10.10.0.0/8 space
>
> The hub VNet at **10.0.0.0/16** already exists — that's the shared services network I manage as the instructor. It has Azure Bastion deployed, which you'll use to connect to your VM in Module 3.
>
> Your job in this module is to carve out your spoke — create the VNet and the first subnet inside it."

### Key concept: Subnets

> "Inside your VNet, you'll create one subnet called **workload**. In production you'd typically have multiple subnets for different tiers — web, app, data — each with its own NSG. Today we're keeping it simple with one.
>
> The subnet size: you'll use the first **/26** of your CIDR. A /26 gives you 64 addresses (59 usable after Azure reserves 5). That's plenty for a workload subnet."

### Briefly mention: system routes

> "Once you create the VNet, Azure automatically attaches default system routes — rules that say 'traffic to this address range goes here'. You don't have to configure anything. In Module 2 we'll add a peering and you'll see a new route appear automatically."

---

## Lab (10–15 min)

> "Alright — look at the banner at the top of your screen. You can see your RG and your CIDR. Open the portal link and let's go."

### Walk-through (demo on your screen)

1. **+ Create → Virtual network**

2. **Basics tab** — *Instance details* section:
   - Resource group: already scoped to their RG
   - Virtual network name: `vnet-userXX` *(they'll see their own slot name populated on the page)*
   - Region: **East US 2** — "Match the hub. Peering between regions works, but costs more and adds latency."

3. **Security tab** (click Next) — leave everything unchecked:
   - Virtual network encryption: unchecked
   - Azure Bastion: unchecked
   - Azure Firewall: unchecked
   - Azure DDoS Network Protection: unchecked
   - > "We're not deploying Bastion into each spoke — that would be expensive and redundant. There's one Bastion in the hub, and once we peer in Module 2, it'll reach all of your VMs."

4. **Address space tab** (click Next):
   - The portal pre-creates a default address block — click the **pencil icon** next to it and set the starting address to their CIDR base address with the correct prefix size
   - A **default** subnet is auto-created inside the block — click its **pencil icon** and update:
     - Name: `workload`
     - Starting address: same as the block's starting address
     - Size: `/26`
   - Click **Save** to confirm the subnet
   - > "If your CIDR is 10.10.5.0/24, set the address space starting address to 10.10.5.0 with size /24, then set the workload subnet starting address to 10.10.5.0 with size /26."

5. **Review + Create → Create**
   - > "Deployment is fast — under 30 seconds for a VNet."

### While participants work — things to watch for

- **"I can't find my resource group"** — remind them to use the portal link in the banner which is already scoped to their RG.
- **"What's my /26?"** — guide them: take their /24 base address, keep the first three octets, set the last to 0 with /26. E.g. 10.10.5.0/24 → 10.10.5.0/26.
- **"The VNet name is already taken"** — shouldn't happen (each RG is isolated), but if it does, check they're in their own RG.
- **"Should I add more subnets?"** — "Not today, but in production you'd typically add gateway, AzureFirewall, AzureBastionHost, app, and data subnets."

---

## Regroup (5 min)

> "Click **Complete** on the module page when your VNet is created. I can see your progress on the admin dashboard."

Wait until the admin dashboard shows all rows as **M1 Networking = ✓** (or most are done — don't hold 30 people for 1 straggler indefinitely).

### Regroup discussion questions

> "Before we move on — a few quick questions:
>
> - What did you notice on the **Routes** tab of your new VNet? Azure created a route for your VNet's address space, 0.0.0.0/0 to the internet. Where do you think that internet route goes once we peer to a hub with a firewall?
> - *(Answer: in production you'd add a UDR to override the 0.0.0.0/0 system route and send it to the hub firewall's private IP instead.)*
>
> - What would happen if two participants had overlapping CIDRs and tried to peer to the same hub?
> - *(Answer: peering would fail — Azure requires non-overlapping address spaces on peered VNets.)*"

### Transition

> "Great. In Module 2 we're going to connect your spoke to the hub — but you're only going to create one half of that connection. I'll handle the other half. Let's go."

---

## Instructor actions for Module 2 prep

No instructor action required during normal flow. Participants now hold the *Workshop Hub Peering* custom role on hub-vnet, which grants `peer/action` plus `virtualNetworkPeerings` read/write/delete — enough for the portal's combined **Add peering** form to create **both** the spoke→hub and hub→spoke links in one step. Peerings should reach **Connected** without you touching `peer-hub.ps1`.

`peer-hub.ps1` is available as a fallback only if a participant hits a permission error or their peering gets stuck in **Initiated**:

```powershell
cd C:\Repos\Azure-IaaS-Training
.\infra\peer-hub.ps1 -SessionId <SESSION_ID>              # all slots
.\infra\peer-hub.ps1 -SessionId <SESSION_ID> -Slot user07  # single straggler
```

*(See Module 2 script for troubleshooting guidance.)*
