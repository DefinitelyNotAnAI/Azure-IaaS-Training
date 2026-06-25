// config.js — Per-delivery settings. Edit the fields below for each session.
// This file is served to the browser and committed to the repo — never put secrets here.
// Served no-cache (see staticwebapp.config.json) so late edits are not masked by the CDN.

window.APP_CONFIG = {

  // ── Per-delivery fields (edit these for each session) ───────────────────────
  sessionId:   'contoso-2026-01-01',           // Table PartitionKey — change per delivery
  sessionName: 'Contoso Azure IaaS Workshop',
  sessionDate: 'January 1, 2026',
  sessionCode: 'CHANGE-ME',                    // Shared with participants — rotate per delivery

  // ── Module definitions ───────────────────────────────────────────────────────
  // Tracked modules: onboarding → module1 → module2 → module3
  modules: {
    onboarding: {
      label:         'Sign In',
      portalSection: 'overview',
    },
    module1: {
      label:         'Module 1 — Networking',
      portalSection: 'virtualnetworks',        // used to build portal deep-links
    },
    module2: {
      label:         'Module 2 — Peering',
      portalSection: 'peerings',
    },
    module3: {
      label:         'Module 3 — Compute',
      portalSection: 'virtualmachines',
    },
    bonus: {
      label:         'Bonus — Storage',
      portalSection: 'storageaccounts',
    },
  },

  // ── Reference links (instructor pre-reading) ─────────────────────────────────
  references: {
    alz:          'https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/',
    vnetPeering:  'https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-peering-overview',
    hubSpoke:     'https://learn.microsoft.com/en-us/azure/architecture/networking/architecture/hub-spoke',
    vmCreate:     'https://learn.microsoft.com/en-us/azure/virtual-machines/windows/quick-create-portal',
    storage:      'https://learn.microsoft.com/en-us/azure/storage/common/storage-account-create',
  },
};
