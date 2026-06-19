## Hands-on lab model (locked)

The workshop uses Microsoft Learn content with a **mixed lab type by module**, because Microsoft authors these exercises differently — networking/storage config as **click-through simulations**, VM creation as a **real lab**. A fully uniform lab type is therefore not possible. Decision recorded in [implementation-plan.md](implementation-plan.md) §1 and §12.

- **Baseline = simulations.** Module 1 (Networking) and Module 3 (Storage) are **click-through simulations**: no Azure sign-in, no Learn sandbox, no personal MSA, zero prerequisites. They run on any locked-down corporate machine.
- **Optional real-Azure upgrade = Module 2 (Compute).** Creating a VM is a real lab; participants run it in a **Microsoft Learn sandbox** signed in with a **personal MSA** (see §12.1). This is the only module that needs sign-in/sandbox.
- **Universal fallback = watch-along.** If a participant can't activate a sandbox (or for any module under time pressure), the instructor performs the exercise live while participants follow using the app's `watching_only` status.

## Networking — Module 1 (simulation)
- https://learn.microsoft.com/en-us/training/modules/configure-virtual-networks/9-simulation-create-networks
- Module root (context): https://learn.microsoft.com/en-us/training/modules/configure-virtual-networks/

## Compute — Module 2 (real Azure, sandbox / optional upgrade)
- https://learn.microsoft.com/en-us/training/modules/create-windows-virtual-machine-in-azure/

## Storage — Module 3 (simulation)
- https://learn.microsoft.com/en-us/training/modules/configure-blob-storage/9-simulation-blobs
- Module root (context): https://learn.microsoft.com/en-us/training/modules/configure-blob-storage/

## Optional / Reference
- https://learn.microsoft.com/en-us/azure/virtual-network/quickstart-create-virtual-network
- https://learn.microsoft.com/en-us/azure/storage/common/storage-account-create
- https://learn.microsoft.com/en-us/training/paths/az-104-manage-virtual-networks/

## Platform & Architecture framing (reference diagram)
- https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/ (Azure landing zone conceptual architecture: management group hierarchy + hub-spoke)