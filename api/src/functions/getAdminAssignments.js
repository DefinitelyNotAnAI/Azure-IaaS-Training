'use strict';
const { app } = require('@azure/functions');
const { getTableClient } = require('../shared/tables');
const { verifyAccessCode } = require('../shared/auth');

app.http('getAdminAssignments', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'dashboard/assignments',
  handler: async (request, context) => {
    if (!verifyAccessCode(request.headers)) {
      return { status: 401, jsonBody: { error: 'Unauthorized' } };
    }

    const sessionId = process.env.SESSION_ID;
    if (!sessionId) return { status: 500, jsonBody: { error: 'Server configuration error' } };

    const client = getTableClient('Assignments');
    const rows = [];
    for await (const entity of client.listEntities({
      queryOptions: { filter: `PartitionKey eq '${sessionId}'` },
    })) {
      rows.push({
        slot:            entity.rowKey,
        assignedRg:      entity.assignedRg,
        assignedCidr:    entity.assignedCidr,
        assignedUpn:     entity.assignedUpn,
        claimedByEmail:  entity.claimedByEmail || '',
        claimedAt:       entity.claimedAt      || '',
        tapIssuedAt:     entity.tapIssuedAt    || '',
        tempCredential:  entity.tempCredential || '',
      });
    }

    // Sort by slot name (user01, user02, ...)
    rows.sort((a, b) => a.slot.localeCompare(b.slot));
    return { status: 200, jsonBody: rows };
  },
});
