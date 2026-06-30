'use strict';
const { app }            = require('@azure/functions');
const { resolveSlot }    = require('../shared/auth');
const { validateSupport, stampSupport } = require('../shared/schema');
const { sendEvent }      = require('../shared/eventhub');
const { recordActivity } = require('../shared/activity');

// POST /api/ingest/support
// Header:  x-team-key  (per-slot ingestion key, resolves to slotId)
// Body:    { ticketId, customerTenant, description, [category],
//            [incidentId], [isNoise], [timestamp] }
// Returns: 202 Accepted

app.http('ingestSupport', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'ingest/support',
  handler: async (request, context) => {
    const slotId = resolveSlot(request.headers);
    if (!slotId) {
      return { status: 401, jsonBody: { error: 'Invalid or missing x-team-key' } };
    }

    let body;
    try { body = await request.json(); } catch {
      return { status: 400, jsonBody: { error: 'Invalid JSON body' } };
    }

    const validationError = validateSupport(body);
    if (validationError) {
      return { status: 400, jsonBody: { error: validationError } };
    }

    const payload = stampSupport(body, slotId);
    const hubName = process.env.EVENT_HUB_SUPPORT_NAME || 'support';

    await sendEvent(hubName, payload);
    recordActivity(slotId, 'support').catch(e =>
      context.warn(`[ingest-support] activity record failed: ${e.message}`)
    );

    context.log(`[ingest-support] slot=${slotId} ticketId=${payload.ticketId} tenant=${payload.customerTenant} incidentId=${payload.incidentId}`);
    return { status: 202 };
  },
});
