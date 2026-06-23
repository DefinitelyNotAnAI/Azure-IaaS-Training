'use strict';
const { app } = require('@azure/functions');
const { getTableClient } = require('../shared/tables');
const { verifyAccessCode } = require('../shared/auth');

app.http('postAdminAssignmentRelease', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'dashboard/assignments/{slot}/release',
  handler: async (request, context) => {
    if (!verifyAccessCode(request.headers)) {
      return { status: 401, jsonBody: { error: 'Unauthorized' } };
    }

    const slot      = request.params.slot;
    const sessionId = process.env.SESSION_ID;
    if (!sessionId) return { status: 500, jsonBody: { error: 'Server configuration error' } };

    const assignmentsClient  = getTableClient('Assignments');
    const participantsClient = getTableClient('Participants');

    let assignment;
    try {
      assignment = await assignmentsClient.getEntity(sessionId, slot);
    } catch (e) {
      if (e.statusCode === 404) return { status: 404, jsonBody: { error: `Slot '${slot}' not found` } };
      throw e;
    }

    const prevEmail = assignment.claimedByEmail;

    // Clear the slot
    await assignmentsClient.updateEntity(
      { partitionKey: sessionId, rowKey: slot, claimedByEmail: '', claimedAt: '' },
      'Merge'
    );

    // Reset the participant row if one exists
    if (prevEmail) {
      try {
        const participant = await participantsClient.getEntity(sessionId, prevEmail);
        const moduleStatuses = typeof participant.moduleStatuses === 'string'
          ? JSON.parse(participant.moduleStatuses)
          : (participant.moduleStatuses || {});
        moduleStatuses.onboarding = 'not_started';

        await participantsClient.updateEntity(
          {
            partitionKey:   sessionId,
            rowKey:         prevEmail,
            assignedSlot:   '',
            assignedRg:     '',
            assignedCidr:   '',
            assignedUpn:    '',
            tapIssuedAt:    '',
            moduleStatuses: JSON.stringify(moduleStatuses),
            lastUpdated:    new Date().toISOString(),
          },
          'Merge'
        );
      } catch (e) {
        if (e.statusCode !== 404) throw e; // 404 = no participant row yet, nothing to reset
      }
    }

    return { status: 200, jsonBody: { slot, released: true, previousEmail: prevEmail || null } };
  },
});
