// config.js — Per-delivery settings. Edit the fields below for each session.
// This file is served to the browser and committed to the repo — never put secrets here.
// Served no-cache (see staticwebapp.config.json) so late edits are not masked by the CDN.

window.APP_CONFIG = {

  // ── Per-delivery fields (edit these for each session) ───────────────────────
  sessionId:   'contoso-2026-01-01',           // Table PartitionKey — change per delivery
  sessionName: 'Contoso Azure IaaS Hackathon',
  sessionDate: 'January 1, 2026',
  sessionCode: 'CHANGE-ME',                    // Shared with participants — rotate per delivery

  // ── Data layer endpoints (set by azd deployment, shared across all participants) ──
  // Leave empty until the shared data layer is deployed.
  ingestionEndpoint:  '',   // e.g. 'https://workshop-ingest-XXXX.azurewebsites.net'
  fabricWorkspaceUrl: '',   // e.g. 'https://app.fabric.microsoft.com/groups/XXXX'

  // ── Hackathon structure ──────────────────────────────────────────────────────
  // Three parts that make up the day-long hackathon. Each part's modules list
  // drives the top-level progress bar. Adjust module keys here to add/remove steps.
  hackathonParts: [
    {
      id:      'part1',
      label:   'Part 1 — Infrastructure',
      page:    'index.html',
      modules: ['onboarding', 'module1', 'module3', 'part1_validate'],
    },
    {
      id:      'part2',
      label:   'Part 2 — Data Layer',
      page:    'part2-signals.html',
      modules: ['part2_signals', 'part2_kql', 'part2_correlation', 'part2_dataagent'],
    },
    {
      id:      'part3',
      label:   'Part 3 — AI Agent',
      page:    'part3-scaffold.html',
      modules: ['part3_scaffold', 'part3_prompts', 'part3_validate'],
    },
  ],

  // ── Module definitions ───────────────────────────────────────────────────────
  // All trackable module keys. The progress bar aggregates by hackathonParts above.
  modules: {
    // Part 1 — Infrastructure
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
      optional:      true,                     // instructor-led; not a tracked blocker
    },
    module3: {
      label:         'Module 3 — Compute',
      portalSection: 'virtualmachines',
    },
    part1_validate: {
      label:         'Validate Signals',
      portalSection: null,
    },
    bonus: {
      label:         'Bonus — Storage',
      portalSection: 'storageaccounts',
      optional:      true,
    },
    // Part 2 — Data Layer
    part2_signals: {
      label:         'Confirm Signals',
      portalSection: null,
    },
    part2_kql: {
      label:         'KQL Correlation',
      portalSection: null,
    },
    part2_correlation: {
      label:         'Correlation View',
      portalSection: null,
    },
    part2_dataagent: {
      label:         'Data Agent',
      portalSection: null,
    },
    // Part 3 — AI Agent
    part3_scaffold: {
      label:         'Agent Scaffold',
      portalSection: null,
    },
    part3_prompts: {
      label:         'Agent Prompts',
      portalSection: null,
    },
    part3_validate: {
      label:         'Self-Validation',
      portalSection: null,
    },
    // Wrap-up (end of day)
    wrapup: {
      label:         'Wrap-up',
      portalSection: null,
    },
  },

  // ── Reference links (instructor pre-reading) ─────────────────────────────────
  references: {
    // Part 1 — Infrastructure
    alz:          'https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/',
    vnetPeering:  'https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-peering-overview',
    hubSpoke:     'https://learn.microsoft.com/en-us/azure/architecture/networking/architecture/hub-spoke',
    vmCreate:     'https://learn.microsoft.com/en-us/azure/virtual-machines/windows/quick-create-portal',
    storage:      'https://learn.microsoft.com/en-us/azure/storage/common/storage-account-create',
    // Part 2 — Data Layer
    fabric:       'https://learn.microsoft.com/en-us/fabric/real-time-intelligence/',
    eventhouse:   'https://learn.microsoft.com/en-us/fabric/real-time-intelligence/eventhouse',
    lakehouse:    'https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-overview',
    kql:          'https://learn.microsoft.com/en-us/azure/data-explorer/kusto/query/',
    fabricAgent:  'https://learn.microsoft.com/en-us/fabric/fundamentals/copilot-fabric-data-agent',
    // Part 3 — AI Agent
    foundry:      'https://learn.microsoft.com/en-us/azure/ai-foundry/what-is-azure-ai-foundry',
    foundryAgent: 'https://learn.microsoft.com/en-us/azure/ai-foundry/concepts/agents',
  },
};
