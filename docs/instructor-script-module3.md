# Instructor Script — Module 3: Compute

**Duration:** ~25–30 minutes (5 min intro + 15–20 min lab including VM deploy wait + 5 min regroup)  
**Participant action:** Deploy a Windows Server 2022 VM (no public IP) into the workload subnet, then connect via Azure Bastion.  
**Prerequisite:** Module 2 peering must be **Connected** for Bastion to work.

---

## Before you open this module

- Admin dashboard: **M2 Peering = ✓** for all participants.
- Verify hub Bastion is healthy: open the Azure portal → hub-rg → BastionHost → check it shows *Provisioned*.
- Have your own screen ready to demo the VM creation wizard — specifically the Networking tab where you remove the public IP.

---

## Opening talk (5 min)

> "This is the payoff module. You've built the network — now you're going to put a workload on it. We're deploying a Windows Server VM, and the goal isn't just to deploy it — it's to deploy it the *right way* for enterprise IaaS. That means no public IP address."

### Key concept: No public IPs on workload VMs

> "In production Azure Landing Zone deployments, workload VMs never have public IPs. Direct internet exposure creates attack surface that's hard to audit and easy to misconfigure.
>
> Instead, inbound management access goes through Azure Bastion — a managed PaaS service deployed in the hub that provides browser-based RDP and SSH without opening any ports on the internet or installing a VPN client. Outbound internet traffic is routed through the hub Azure Firewall, which inspects and logs it.
>
> Today you'll create a VM with zero public internet presence. The only way in is through the hub's Bastion — which can reach your spoke because you peered it in Module 2. This is exactly what a production deployment looks like."

### Key concept: VM sizing and availability zones

> "You'll use **Standard_D2ads_v7** — 2 vCPU, 8 GiB RAM. It's a general-purpose Dadsv7-series VM available in East US 2. In production you'd right-size based on the workload's CPU/memory profile.
>
> You'll place the VM in **Availability Zone 1**. AZs are physically separate datacenters within a region — separate power, cooling, and networking. Placing VMs across multiple AZs protects against a single datacenter failure. For a single VM like today, Zone 1 is fine — but I want you to see the option during creation."

### Key concept: Managed disks

> "The OS disk will be a managed disk — Azure manages the physical storage, replication, and hardware lifecycle. You choose the SKU. We'll use **Standard_LRS** which is the cheapest. In production you'd use **Premium_SSD** for the OS disk and any performance-sensitive data disks."

---

## Lab (15–20 min)

> "The module page shows your VM name, RG, and VNet already filled in. Let's walk through creation together, then you'll wait 2–4 minutes for deployment."

### Walk-through (demo on your screen)

**Basics tab:**
- Resource group: `rg-userXX` *(pre-filled on their page)*
- VM name: `vm-userXX`
- Region: **East US**
- Availability options: **Availability Zone**, Zone: **1**
- Image: **Windows Server 2022 Datacenter: Azure Edition** *(use the search — type "2022")*
- Size: **Standard_D2ads_v7** — click "See all sizes" and search D2ads if needed
- Administrator username: **workshopadmin**
- Password: anything they'll remember for the session
- Public inbound ports: **None**

> "Set public inbound ports to None — we're not opening RDP directly from the internet. Bastion doesn't need port 3389 open on the public internet."

**Disks tab:** leave defaults (Standard SSD LRS is fine, delete disk on VM delete — check that box to avoid orphaned disks)

**Networking tab** — this is the critical one, demo carefully:
- Virtual network: **`vnet-userXX`** — must be their spoke, not the hub
- Subnet: **workload**
- **Public IP: None** — click the dropdown and select **None**
   > "This is the most important change. By default, Azure wants to create a public IP. We remove it entirely. The VM will have a private IP only."
- NIC network security group: **Basic**
   > "Basic NSG is fine for the lab — it creates a default NSG with no inbound rules, which is correct. We don't need RDP open from the internet since Bastion handles access."
- Delete NIC when VM is deleted: **check this** — good hygiene

**Management tab:**
- Enable **Microsoft Defender for Cloud — Free** (optional but worth showing as a concept)
   > "Defender for Cloud free tier gives you security recommendations and threat detection on the VM at no extra cost. In production you'd enable Defender for Servers Plan 2 for deep integration."

**Review + Create → Create**

> "Deployment takes 2–4 minutes. While it runs, let's talk about what's happening behind the scenes."

### While VM is deploying — narrate

> "Azure is allocating physical compute in Availability Zone 1 in East US. It's:
> 1. Creating a managed OS disk and copying the Windows Server 2022 image to it
> 2. Creating a virtual NIC and assigning a private IP from your workload subnet
> 3. Attaching the NIC and disk to the compute, then powering it on
> 4. Running the Windows Sysprep/OOBE process
>
> You can watch the deployment events in the notification bell. You'll see resources created one by one."

---

## Connecting via Bastion (5 min)

Once the VM shows **Running**:

> "Click **Connect** → **Connect via Bastion** from the VM blade."

Walk through:
1. Click **Connect** on the VM overview
2. Select **Bastion** tab (not RDP, not SSH)
3. Enter username: `workshopadmin`, password: whatever they set
4. Click **Connect** — a new browser tab opens with an RDP session

> "Notice: no VPN, no RDP client, no public IP. Your browser is connecting to the Azure Bastion service in the hub over HTTPS port 443. Bastion is reaching your VM over the peering via private IP. This is exactly how enterprise teams access IaaS VMs."

### Connectivity test — ping the hub

> "Once you're in, open a Command Prompt and run: `ping 10.0.2.1`"
>
> "10.0.2.1 is the first usable address in the hub's shared-services subnet. If you get replies, your VM can reach the hub — the peering is working, routing is working, end to end."

> "If ping times out — check that your peering is **Connected** in Module 2, and check that the NSG on your workload subnet doesn't have a Deny rule for ICMP. The default NSG won't block ping from within the VNet."

---

## While participants connect — things to watch for

- **"Bastion tab is greyed out / says 'Not configured'"** — Bastion is in hub-rg, not in their RG. They need to scroll down to **Bastion** from the VM's Connect options and use the hub Bastion (it's automatically available because of the peering). If the option is missing, the peering may not be Connected.
- **"Connection times out"** — most likely the Module 2 peering isn't Connected yet. Check admin dashboard and the peering status.
- **"I set public IP to Standard instead of None"** — not a problem for the lab but explain why we'd remove it in production. Optionally have them disassociate it.
- **"Ping to 10.0.2.1 fails"** — check effective routes on the NIC (`VM → Networking → Network Interface → Effective routes`). Should show a route for 10.0.0.0/16 via VNet peering.

---

## Regroup (5 min)

> "Click **Complete** on the module page once you've connected to your VM via Bastion."

Wait for **M3 Compute = ✓** on the admin dashboard before moving to wrap-up.

### Regroup discussion questions

> "Before we close this out:
>
> - How would you resize this VM without deleting and re-creating it?
> - *(Answer: VM → Size → change size → resize. The VM must be stopped first for some size families.)*
>
> - If you wanted to snapshot the OS disk and roll back to this clean state after installing software, how would you do that?
> - *(Answer: VM → Disks → OS disk → Create snapshot. Or use Azure Backup for a full recovery point.)*
>
> - What's the difference between stopping a VM in the portal versus 'Stop' from inside the guest OS?
> - *(Answer: stopping from the portal deallocates the compute — you stop paying for CPU/RAM. Stopping from inside the guest still keeps the VM allocated and still billing.)*"

### Transition to wrap-up

> "You've done all three modules — VNet, peering, and a VM running with no public IP accessed through Bastion. Head to the Wrap-up page and I'll see you there for a brief summary and where to go next."

---

## Post-lab instructor clean-up notes

After the session, remind participants that:
- The VMs are still running and **incurring cost** — the instructor will tear down the environment using `teardown-cohort.ps1` after the session.
- They should export any notes or screenshots they want before teardown.

```powershell
cd C:\Repos\Azure-IaaS-Training
.\infra\export-cohort.ps1   # export participant data first
.\infra\teardown-cohort.ps1  # delete participant VMs, VNets, peerings
```
