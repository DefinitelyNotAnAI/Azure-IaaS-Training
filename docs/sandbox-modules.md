## Hands-on lab model

All workshop modules use **real Azure** — each participant is assigned an isolated resource group, a unique VNet CIDR, and an Entra ID user with a Temporary Access Pass (TAP). There are no Microsoft Learn simulations and no shared sandboxes. Labs run in an instructor-provisioned MCAPS external tenant subscription.

- **Slot allocation.** At check-in the app assigns each participant a slot (`user01`–`user30`). Each slot has a pre-created resource group (`userNN-rg`), a VNet CIDR (`10.N.N.0/24`), and a dedicated Entra user (`userNN@<tenant>`). The TAP is issued on slot claim and rotated on a timer.
- **Instructor provisioning.** Run `infra/seed-cohort.ps1` before the session to create users, assign RBAC, and issue initial TAPs. Run `infra/hub-spoke.bicep` or equivalent to deploy the hub VNet and per-slot resource groups beforehand.
- **Universal fallback = watch-along.** The instructor performs the exercise live; participants follow using the app's `watching_only` status. Use this for any participant whose slot claim fails or who has portal access issues.

## Module lab summary

| Module | App label | What participants do | Real Azure requirement |
|--------|-----------|----------------------|------------------------|
| Module 1 | Networking | Create a spoke VNet + subnet in their assigned resource group using the CIDR provided | Contributor on assigned RG |
| Module 2 | Peering | Create a spoke-to-hub VNet peering (both sides) from the portal's combined Add peering form | *Workshop Hub Peering* custom role on hub-vnet + Contributor on assigned RG |
| Module 3 | Compute | Deploy a Windows VM in the workload subnet; connect via Azure Bastion | Contributor on assigned RG; peering must be Connected |
| Bonus | Storage | Create a storage account in the assigned RG | Contributor on assigned RG |

## AZ-104 reference reading (background, not the lab)

These Microsoft Learn modules provide conceptual background aligned with each workshop lab. They are **reference reading only** — the actual hands-on exercises are custom workshop labs in the pre-assigned resource groups, not these Learn units.

### Networking (Module 1)

| Topic | Reference |
|-------|-----------|
| Virtual Networks & Subnets | [configure-virtual-networks](https://learn.microsoft.com/en-us/training/modules/configure-virtual-networks/) |
| Network Security Groups | [configure-network-security-groups](https://learn.microsoft.com/en-us/training/modules/configure-network-security-groups/) |

### Peering (Module 2)

| Topic | Reference |
|-------|-----------|
| VNet Peering (hub/spoke) | [configure-vnet-peering](https://learn.microsoft.com/en-us/training/modules/configure-vnet-peering/) |

### Compute (Module 3)

| Topic | Reference |
|-------|-----------|
| Create a Virtual Machine | [intro-to-azure-virtual-machines](https://learn.microsoft.com/en-us/training/modules/intro-to-azure-virtual-machines/) |

### Storage (Bonus)

| Topic | Reference |
|-------|-----------|
| Blob Storage containers & tiers | [configure-blob-storage](https://learn.microsoft.com/en-us/training/modules/configure-blob-storage/) |

## Platform & Architecture framing (Module 0 — instructor lecture, no lab)

- [Azure landing zone conceptual architecture](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/) — management group hierarchy + hub-spoke
- [Hub-spoke network topology in Azure](https://learn.microsoft.com/en-us/azure/architecture/networking/architecture/hub-spoke)
