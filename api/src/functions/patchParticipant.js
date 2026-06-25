'use strict';
const { app } = require('@azure/functions');
const { getTableClient } = require('../shared/tables');
const { verifySessionCode } = require('../shared/auth');

const VALID_MODULES  = new Set(['onboarding', 'module1', 'module2', 'module3', 'wrapup']);
const VALID_STATUSES = new Set(['not_started', 'started', 'complete', 'need_help', 'watching_only']);

app.http('patchParticipant', {
  methods: ['PATCH'],
  authLevel: 'anonymous',
  route: 'participants/{email}',
  handler: async (request, context) => {
    if (!verifySessionCode(request.headers)) {
      return { status: 401, jsonBody: { error: 'Unauthorized' } };
    }

    const email = decodeURIComponent(request.params.email || '').trim().toLowerCase();
    if (!email) return { status: 400, jsonBody: { error: 'Email is required' } };

    let body;
    try { body = await request.json(); } catch {
      return { status: 400, jsonBody: { error: 'Invalid JSON body' } };
    }

    const sessionId = process.env.SESSION_ID;
    if (!sessionId) return { status: 500, jsonBody: { error: 'Server configuration error' } };

    const participantsClient = getTableClient('Participants');
    let participant;
    try {
      participant = await participantsClient.getEntity(sessionId, email);
    } catch (e) {
      if (e.statusCode === 404) return { status: 404, jsonBody: { error: 'Participant not found' } };
      throw e;
    }

    const now = new Date().toISOString();
    const updates = { partitionKey: sessionId, rowKey: email, lastUpdated: now };

    if (body.module !== undefined && body.status !== undefined) {
      const moduleKey = String(body.module);
      const status    = String(body.status);

      if (!VALID_MODULES.has(moduleKey))  return { status: 400, jsonBody: { error: `Invalid module: ${moduleKey}` } };
      if (!VALID_STATUSES.has(status))    return { status: 400, jsonBody: { error: `Invalid status: ${status}` } };

      const moduleStatuses = typeof participant.moduleStatuses === 'string'
        ? JSON.parse(participant.moduleStatuses)
        : (participant.moduleStatuses || {});

      moduleStatuses[moduleKey] = status;
      updates.moduleStatuses = JSON.stringify(moduleStatuses);
      updates.currentModule  = moduleKey;
      updates.currentStatus  = status;

      if (moduleKey === 'onboarding' && status === 'complete') {
        updates.portalSignedInAt = now;
      }
    } else if (body.feedback !== undefined) {
      updates.feedback = String(body.feedback).trim().substring(0, 1000);
    } else {
      return { status: 400, jsonBody: { error: 'Body must contain {module, status} or {feedback}' } };
    }

    await participantsClient.updateEntity(updates, 'Merge');
    return { status: 204 };
  },
});
