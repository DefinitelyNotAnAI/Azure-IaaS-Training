'use strict';
const { app } = require('@azure/functions');
const { getTableClient } = require('../shared/tables');
const { getGraphClient } = require('../shared/graph');
const { verifyAccessCode } = require('../shared/auth');

app.http('postAdminTapRotate', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'admin/assignments/{slot}/rotate-tap',
  handler: async (request, context) => {
    if (!verifyAccessCode(request.headers)) {
      return { status: 401, jsonBody: { error: 'Unauthorized' } };
    }

    const slot      = request.params.slot;
    const sessionId = process.env.SESSION_ID;
    if (!sessionId) return { status: 500, jsonBody: { error: 'Server configuration error' } };

    const client = getTableClient('Assignments');
    let assignment;
    try {
      assignment = await client.getEntity(sessionId, slot);
    } catch (e) {
      if (e.statusCode === 404) return { status: 404, jsonBody: { error: `Slot '${slot}' not found` } };
      throw e;
    }

    const { newTap, issuedAt } = await rotateTap(assignment, context);

    await client.updateEntity(
      {
        partitionKey:   sessionId,
        rowKey:         slot,
        tempCredential: newTap.temporaryAccessPass,
        currentTapId:   newTap.id,
        tapIssuedAt:    issuedAt,
      },
      'Merge'
    );

    return {
      status: 200,
      jsonBody: { slot, tapIssuedAt: issuedAt, message: 'TAP rotated successfully' },
    };
  },
});

async function rotateTap(assignment, context) {
  const graph   = getGraphClient();
  const userId  = assignment.assignedUserObjectId;
  const oldTapId = assignment.currentTapId;

  if (!userId) throw new Error(`assignedUserObjectId missing on slot ${assignment.rowKey}`);

  // Revoke the old TAP (best effort — may already be expired)
  if (oldTapId) {
    try {
      await graph.api(`/users/${userId}/authentication/temporaryAccessPassMethods/${oldTapId}`).delete();
    } catch (e) {
      context.warn(`[rotate-tap] Could not revoke old TAP ${oldTapId}: ${e.message}`);
    }
  }

  // Issue a new 8-hour multi-use TAP
  const issuedAt = new Date().toISOString();
  const newTap   = await graph
    .api(`/users/${userId}/authentication/temporaryAccessPassMethods`)
    .post({ lifetimeInMinutes: 480, isUsableOnce: false });

  context.log(`[rotate-tap] Rotated TAP for slot ${assignment.rowKey} (user ${userId})`);
  return { newTap, issuedAt };
}

module.exports = { rotateTap };
