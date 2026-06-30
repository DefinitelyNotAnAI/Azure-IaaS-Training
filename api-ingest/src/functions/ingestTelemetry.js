'use strict';
const { app }             = require('@azure/functions');
const { resolveSlot }     = require('../shared/auth');
const { validateTelemetry, stampTelemetry } = require('../shared/schema');
const { sendEvent }       = require('../shared/eventhub');
const { recordActivity }  = require('../shared/activity');

// POST /api/ingest/telemetry
// Header:  x-team-key  (per-slot ingestion key, resolves to slotId)
// Body:    { service, operation, region, latencyMs, [errorCount], [throughput],
//            [isAnomaly], [incidentId], [correlationId], [timestamp] }
// Returns: 202 Accepted

app.http('ingestTelemetry', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'ingest/telemetry',
  handler: async (request, context) => {
    const slotId = resolveSlot(request.headers);
    if (!slotId) {
      return { status: 401, jsonBody: { error: 'Invalid or missing x-team-key' } };
    }

    let body;
    try { body = await request.json(); } catch {
      return { status: 400, jsonBody: { error: 'Invalid JSON body' } };
    }

    const validationError = validateTelemetry(body);
    if (validationError) {
      return { status: 400, jsonBody: { error: validationError } };
    }

    const payload = stampTelemetry(body, slotId);
    const hubName = process.env.EVENT_HUB_TELEMETRY_NAME || 'telemetry';

    await sendEvent(hubName, payload);
    recordActivity(slotId, 'telemetry').catch(e =>
      context.warn(`[ingest-telemetry] activity record failed: ${e.message}`)
    );

    context.log(`[ingest-telemetry] slot=${slotId} service=${payload.service} op=${payload.operation} latencyMs=${payload.latencyMs} isAnomaly=${payload.isAnomaly}`);
    return { status: 202 };
  },
});
