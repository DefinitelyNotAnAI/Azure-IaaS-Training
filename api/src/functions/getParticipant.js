'use strict';
const { app } = require('@azure/functions');
const { getTableClient } = require('../shared/tables');
const { verifySessionCode } = require('../shared/auth');

app.http('getParticipant', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'participants/{email}',
  handler: async (request, context) => {
    if (!verifySessionCode(request.headers)) {
      return { status: 401, jsonBody: { error: 'Unauthorized' } };
    }

    const email = decodeURIComponent(request.params.email || '').trim().toLowerCase();
    if (!email) return { status: 400, jsonBody: { error: 'Email is required' } };

    const sessionId = process.env.SESSION_ID;
    if (!sessionId) {
      context.error('SESSION_ID is not set');
      return { status: 500, jsonBody: { error: 'Server configuration error' } };
    }

    const participantsClient = getTableClient('Participants');
    const assignmentsClient  = getTableClient('Assignments');

    let participant;
    try {
      participant = await participantsClient.getEntity(sessionId, email);
    } catch (e) {
      if (e.statusCode === 404) return { status: 404, jsonBody: { error: 'Participant not found for this session' } };
      throw e;
    }

    if (!participant.assignedSlot) {
      return { status: 404, jsonBody: { error: 'Participant has no slot assignment' } };
    }

    let assignment;
    try {
      assignment = await assignmentsClient.getEntity(sessionId, participant.assignedSlot);
    } catch (e) {
      if (e.statusCode === 404) return { status: 404, jsonBody: { error: 'Assignment row not found' } };
      throw e;
    }

    const sub    = process.env.SUBSCRIPTION_ID;
    const domain = process.env.WORKSHOP_TENANT_DOMAIN;
    const rg     = assignment.assignedRg;

    const portalDeepLink = (sub && domain)
      ? `https://portal.azure.com/#@${domain}/resource/subscriptions/${sub}/resourceGroups/${rg}/overview`
      : null;

    const moduleStatuses = typeof participant.moduleStatuses === 'string'
      ? JSON.parse(participant.moduleStatuses)
      : participant.moduleStatuses;

    return {
      status: 200,
      jsonBody: {
        participantId:  participant.participantId,
        displayName:    participant.displayName,
        assignedSlot:   assignment.rowKey,
        assignedRg:     assignment.assignedRg,
        assignedCidr:   assignment.assignedCidr,
        assignedUpn:    assignment.assignedUpn,
        tempCredential: assignment.tempCredential,
        tapIssuedAt:    assignment.tapIssuedAt,
        moduleStatuses,
        portalDeepLink,
      },
    };
  },
});
