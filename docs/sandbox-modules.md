## Hands-on lab model (locked)

The workshop uses Microsoft Learn content. All three modules use **real Azure portal exercises** — there are no account-free click-through simulations. All exercises require an Azure subscription. Decision recorded in [implementation-plan.md](implementation-plan.md) §1 and §12.

- **All modules = real Azure, subscription required.** Modules 1, 2, and 3 all require an active Azure subscription (trial, MSDN, corporate, or MCAPS external tenant — no customer data / no production workloads). Confirmed 2026-06-19.
- **Recommended vehicle for large groups (30–100).** Use the MCAPS external tenant subscription: assign participants the Reader role on a pre-deployed resource group. They explore real deployed resources in the portal without creating or modifying anything.
- **Universal fallback = watch-along.** The instructor performs the exercise live; participants follow using the app's `watching_only` status. This is the safe default for any participant without subscription access.

## Networking — Module 1 (real Azure, subscription required)
- Exercise unit: https://learn.microsoft.com/en-us/training/modules/configure-virtual-networks/9-simulation-create-networks
- Module root: https://learn.microsoft.com/en-us/training/modules/configure-virtual-networks/

## Compute — Module 2 (real Azure, own subscription required)
- Exercise unit: https://learn.microsoft.com/en-us/training/modules/intro-to-azure-virtual-machines/3-create-a-vm
- Module root: https://learn.microsoft.com/en-us/training/modules/intro-to-azure-virtual-machines/

> **Note:** The old URL (`create-windows-virtual-machine-in-azure`) now redirects to a quickstart docs article. The replacement module (`intro-to-azure-virtual-machines`) requires **your own Azure subscription** — there is no free Microsoft Learn sandbox for VM creation. Participants need an active Azure subscription (trial, MSDN, or corporate) to complete the exercise. The watch-along fallback (`watching_only`) remains the intended path for participants without one.

## Storage — Module 3 (real Azure, subscription required)
- Exercise unit: https://learn.microsoft.com/en-us/training/modules/configure-blob-storage/9-simulation-blobs
- Module root: https://learn.microsoft.com/en-us/training/modules/configure-blob-storage/

## Optional / Reference
- https://learn.microsoft.com/en-us/azure/virtual-network/quickstart-create-virtual-network
- https://learn.microsoft.com/en-us/azure/storage/common/storage-account-create
- https://learn.microsoft.com/en-us/training/paths/az-104-manage-virtual-networks/

## AZ-104 module exercise URLs (reference)

All exercises below require an Azure subscription. URL slugs containing "simulation" are Microsoft's internal naming convention and do not indicate account-free access — a sign-in and subscription are required to complete them.

### Networking

| Topic | Exercise unit | Module root |
|-------|--------------|-------------|
| Virtual Networks & Subnets | [`configure-virtual-networks/9-simulation-create-networks`](https://learn.microsoft.com/en-us/training/modules/configure-virtual-networks/9-simulation-create-networks) | [configure-virtual-networks](https://learn.microsoft.com/en-us/training/modules/configure-virtual-networks/) |
| Network Security Groups | [`configure-network-security-groups/7-simulation-create-network-groups`](https://learn.microsoft.com/en-us/training/modules/configure-network-security-groups/7-simulation-create-network-groups) | [configure-network-security-groups](https://learn.microsoft.com/en-us/training/modules/configure-network-security-groups/) |
| VNet Peering (hub/spoke) | [`configure-vnet-peering/6-simulation-peering`](https://learn.microsoft.com/en-us/training/modules/configure-vnet-peering/6-simulation-peering) | [configure-vnet-peering](https://learn.microsoft.com/en-us/training/modules/configure-vnet-peering/) |

### Compute

| Topic | Exercise unit | Module root |
|-------|--------------|-------------|
| Create a Virtual Machine | [`intro-to-azure-virtual-machines/3-create-a-vm`](https://learn.microsoft.com/en-us/training/modules/intro-to-azure-virtual-machines/3-create-a-vm) | [intro-to-azure-virtual-machines](https://learn.microsoft.com/en-us/training/modules/intro-to-azure-virtual-machines/) |

### Storage

| Topic | Exercise unit | Module root |
|-------|--------------|-------------|
| Blob Storage containers & tiers | [`configure-blob-storage/9-simulation-blobs`](https://learn.microsoft.com/en-us/training/modules/configure-blob-storage/9-simulation-blobs) | [configure-blob-storage](https://learn.microsoft.com/en-us/training/modules/configure-blob-storage/) |

## Platform & Architecture framing (reference diagram)
- https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/ (Azure landing zone conceptual architecture: management group hierarchy + hub-spoke)