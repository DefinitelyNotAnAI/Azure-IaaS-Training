'use strict';
const { app } = require('@azure/functions');
const { getTableClient } = require('../shared/tables');
const { verifyAccessCode } = require('../shared/auth');

app.http('postAdminAssignmentPreassign', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'admin/assignments/{slot}/preassign',
  handler: async (request, context) => {
    if (!verifyAccessCode(request.headers)) {
      return { status: 401, jsonBody: { error: 'Unauthorized' } };
    }

    const slot = request.params.slot;
    let body;
    try { body = await request.json(); } catch {
      return { status: 400, jsonBody: { error: 'Invalid JSON body' } };
    }

    const email = String(body.email || '').trim().toLowerCase();
    if (!email) return { status: 400, jsonBody: { error: 'email is required' } };

    const sessionId = process.env.SESSION_ID;
    if (!sessionId) return { status: 500, jsonBody: { error: 'Server configuration error' } };

    const client = getTableClient('Assignments');
    let entity;
    try {
      entity = await client.getEntity(sessionId, slot);
    } catch (e) {
      if (e.statusCode === 404) return { status: 404, jsonBody: { error: `Slot '${slot}' not found` } };
      throw e;
    }

    if (entity.claimedByEmail && entity.claimedByEmail !== email) {
      return { status: 409, jsonBody: { error: `Slot '${slot}' is already claimed by ${entity.claimedByEmail}` } };
    }

    await client.updateEntity(
      { partitionKey: sessionId, rowKey: slot, claimedByEmail: email, claimedAt: new Date().toISOString() },
      'Merge'
    );

    return { status: 200, jsonBody: { slot, claimedByEmail: email } };
  },
});
