'use strict';
const { odata } = require('@azure/data-tables');
const { getTableClient } = require('./tables');

class NoSlotsAvailableError extends Error {
  constructor() {
    super('all_slots_claimed');
    this.name = 'NoSlotsAvailableError';
    this.code = 'all_slots_claimed';
  }
}

/**
 * Atomically claims the lowest available slot for the given email.
 * Uses ETag optimistic concurrency — retries up to MAX_RETRIES on conflict.
 * Returns the full Assignments entity (with tempCredential, tapIssuedAt, etc.).
 */
async function claimSlot(sessionId, claimedByEmail) {
  const client = getTableClient('Assignments');
  const MAX_RETRIES = 3;

  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    // Fetch all unclaimed slots for this session
    const slots = [];
    const iter = client.listEntities({
      queryOptions: {
        filter: odata`PartitionKey eq ${sessionId} and claimedByEmail eq ''`,
      },
    });
    for await (const entity of iter) {
      slots.push(entity);
    }

    if (slots.length === 0) throw new NoSlotsAvailableError();

    // Sort by RowKey ascending (user01 < user02 …) and pick the first
    slots.sort((a, b) => a.rowKey.localeCompare(b.rowKey));
    const candidate = slots[0];

    try {
      const now = new Date().toISOString();
      await client.updateEntity(
        {
          partitionKey: candidate.partitionKey,
          rowKey: candidate.rowKey,
          claimedByEmail,
          claimedAt: now,
        },
        'Merge',
        { etag: candidate.etag }
      );
      // Re-fetch to get all fields (tempCredential, tapIssuedAt, etc.)
      const claimed = await client.getEntity(sessionId, candidate.rowKey);
      return claimed;
    } catch (err) {
      if (err.statusCode === 412) continue; // ETag conflict — retry
      throw err;
    }
  }

  throw new NoSlotsAvailableError();
}

module.exports = { claimSlot, NoSlotsAvailableError };
