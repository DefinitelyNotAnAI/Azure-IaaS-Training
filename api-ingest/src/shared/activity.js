'use strict';
// activity.js — Records per-slot ingestion activity in Azure Table Storage.
// Used by getSignalsCheck to confirm that a participant's VM is sending signals.
//
// Table: IngestActivity
//   PartitionKey: 'ingest'        (fixed — single partition for easy listing)
//   RowKey:       slotId          (e.g. 'user01')
//   lastTelemetryAt: ISO string
//   lastSupportAt:   ISO string
//   lastActivityAt:  ISO string

const { TableClient }          = require('@azure/data-tables');
const { DefaultAzureCredential } = require('@azure/identity');

const credential = new DefaultAzureCredential({
  managedIdentityClientId: process.env.AZURE_CLIENT_ID || undefined,
});

function getTableClient() {
  const accountName = process.env.STORAGE_ACCOUNT_NAME;
  if (!accountName) throw new Error('STORAGE_ACCOUNT_NAME environment variable is not set');
  return new TableClient(
    `https://${accountName}.table.core.windows.net`,
    'IngestActivity',
    credential
  );
}

/**
 * Records that a signal was received for the given slot and plane.
 * @param {string} slotId  - e.g. 'user01'
 * @param {'telemetry'|'support'} plane
 */
async function recordActivity(slotId, plane) {
  const client = getTableClient();
  const now    = new Date().toISOString();
  const entity = {
    partitionKey:   'ingest',
    rowKey:         slotId,
    lastActivityAt: now,
  };
  if (plane === 'telemetry') entity.lastTelemetryAt = now;
  if (plane === 'support')   entity.lastSupportAt   = now;
  await client.upsertEntity(entity, 'Merge');
}

/**
 * Returns the IngestActivity row for a slot, or null if not found.
 */
async function getActivity(slotId) {
  const client = getTableClient();
  try {
    return await client.getEntity('ingest', slotId);
  } catch (e) {
    if (e.statusCode === 404) return null;
    throw e;
  }
}

module.exports = { recordActivity, getActivity };
