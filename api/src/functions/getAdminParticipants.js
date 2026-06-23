'use strict';
const { app } = require('@azure/functions');
const { getTableClient } = require('../shared/tables');
const { verifyAccessCode } = require('../shared/auth');

app.http('getAdminParticipants', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'admin/participants',
  handler: async (request, context) => {
    if (!verifyAccessCode(request.headers)) {
      return { status: 401, jsonBody: { error: 'Unauthorized' } };
    }

    const sessionId = process.env.SESSION_ID;
    if (!sessionId) return { status: 500, jsonBody: { error: 'Server configuration error' } };

    const participantsClient = getTableClient('Participants');
    const assignmentsClient  = getTableClient('Assignments');

    // Load all participants for this session
    const participants = [];
    for await (const entity of participantsClient.listEntities({
      queryOptions: { filter: `PartitionKey eq '${sessionId}'` },
    })) {
      participants.push(entity);
    }

    // Load all assignments for join
    const assignments = new Map();
    for await (const entity of assignmentsClient.listEntities({
      queryOptions: { filter: `PartitionKey eq '${sessionId}'` },
    })) {
      assignments.set(entity.rowKey, entity);
    }

    const result = participants.map((p) => {
      const assignment = p.assignedSlot ? assignments.get(p.assignedSlot) : null;
      const moduleStatuses = typeof p.moduleStatuses === 'string'
        ? JSON.parse(p.moduleStatuses)
        : (p.moduleStatuses || {});

      return {
        email:           p.rowKey,
        displayName:     p.displayName,
        participantId:   p.participantId,
        assignedSlot:    p.assignedSlot    || '',
        assignedRg:      p.assignedRg      || '',
        assignedCidr:    p.assignedCidr    || '',
        assignedUpn:     p.assignedUpn     || '',
        tapIssuedAt:     assignment ? assignment.tapIssuedAt : '',
        tempCredential:  assignment ? assignment.tempCredential : '',
        moduleStatuses,
        currentModule:   p.currentModule   || '',
        currentStatus:   p.currentStatus   || '',
        portalSignedInAt: p.portalSignedInAt || '',
        lastUpdated:     p.lastUpdated      || '',
      };
    });

    return { status: 200, jsonBody: result };
  },
});
