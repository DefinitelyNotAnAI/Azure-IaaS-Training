'use strict';
const { app } = require('@azure/functions');
const { getTableClient } = require('../shared/tables');
const { verifySessionCode } = require('../shared/auth');
const { claimSlot, NoSlotsAvailableError } = require('../shared/claim');

app.http('postParticipant', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'participants',
  handler: async (request, context) => {
    if (!verifySessionCode(request.headers)) {
      return { status: 401, jsonBody: { error: 'Unauthorized' } };
    }

    let body;
    try { body = await request.json(); } catch {
      return { status: 400, jsonBody: { error: 'Invalid JSON body' } };
    }

    const email       = String(body.email || '').trim().toLowerCase();
    const displayName = String(body.displayName || '').trim();

    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return { status: 400, jsonBody: { error: 'Invalid email' } };
    }
    if (!displayName || displayName.length < 2) {
      return { status: 400, jsonBody: { error: 'displayName must be at least 2 characters' } };
    }

    const sessionId = process.env.SESSION_ID;
    if (!sessionId) {
      context.error('SESSION_ID env var is not set');
      return { status: 500, jsonBody: { error: 'Server configuration error' } };
    }

    const participantsClient  = getTableClient('Participants');
    const assignmentsClient   = getTableClient('Assignments');

    // Check for existing participant (sticky resume)
    let existing = null;
    try {
      existing = await participantsClient.getEntity(sessionId, email);
    } catch (e) {
      if (e.statusCode !== 404) throw e;
    }

    if (existing && existing.assignedSlot) {
      let assignment = null;
      try {
        assignment = await assignmentsClient.getEntity(sessionId, existing.assignedSlot);
      } catch (e) {
        if (e.statusCode !== 404) throw e;
      }
      if (assignment) {
        return { status: 200, jsonBody: buildResponse(existing, assignment) };
      }
    }

    // Claim a new slot
    let assignment;
    try {
      assignment = await claimSlot(sessionId, email);
    } catch (e) {
      if (e instanceof NoSlotsAvailableError) {
        return {
          status: 409,
          jsonBody: { code: 'all_slots_claimed', error: 'All workshop slots are taken. Please see the instructor.' },
        };
      }
      throw e;
    }

    const now           = new Date().toISOString();
    const participantId = (existing && existing.participantId) || crypto.randomUUID();
    const moduleStatuses = existing
      ? existing.moduleStatuses
      : JSON.stringify({ onboarding: 'started', module1: 'not_started', module2: 'not_started', module3: 'not_started', wrapup: 'not_started' });

    const participantRow = {
      partitionKey:    sessionId,
      rowKey:          email,
      participantId,
      displayName,
      assignedSlot:    assignment.rowKey,
      assignedRg:      assignment.assignedRg,
      assignedCidr:    assignment.assignedCidr,
      assignedUpn:     assignment.assignedUpn,
      tapIssuedAt:     assignment.tapIssuedAt,
      moduleStatuses,
      feedback:        existing ? (existing.feedback || '') : '',
      lastUpdated:     now,
    };

    await participantsClient.upsertEntity(participantRow, 'Replace');

    return { status: 200, jsonBody: buildResponse(participantRow, assignment) };
  },
});

function buildResponse(participant, assignment) {
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
    participantId:  participant.participantId,
    email:          participant.rowKey,
    displayName:    participant.displayName,
    assignedSlot:   assignment.rowKey,
    assignedRg:     assignment.assignedRg,
    assignedCidr:   assignment.assignedCidr,
    assignedUpn:    assignment.assignedUpn,
    tempCredential: assignment.tempCredential,
    tapIssuedAt:    assignment.tapIssuedAt,
    moduleStatuses,
    portalDeepLink,
  };
}
