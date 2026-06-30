'use strict';
const { app }          = require('@azure/functions');
const { getActivity }  = require('../shared/activity');

// GET /api/signals/check?slot=userNN
// Header:  x-session-code  (shared workshop session code)
// Returns: { telemetryCount, ticketCount, lastTelemetryAt, lastSupportAt }
//
// Used by src/part1-validate.html to confirm that the participant's VM is
// emitting signals. Returns 1 for each plane if activity was seen within the
// last RECENT_THRESHOLD_MS (10 minutes); 0 otherwise.

const RECENT_THRESHOLD_MS = 10 * 60 * 1000; // 10 minutes

app.http('getSignalsCheck', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'signals/check',
  handler: async (request, context) => {
    const slot = (request.query.get('slot') || '').trim().toLowerCase();
    if (!slot) return { status: 400, jsonBody: { error: 'slot query parameter is required' } };
    if (!/^user\d{2}$/.test(slot)) {
      return { status: 400, jsonBody: { error: 'Invalid slot format — expected userNN (e.g. user01)' } };
    }

    // Require session code so participants can only check their own slot context
    const provided = (request.headers.get('x-session-code') || '').trim();
    const expected = (process.env.SESSION_CODE || '').trim();
    if (expected && provided !== expected) {
      return { status: 401, jsonBody: { error: 'Unauthorized' } };
    }

    const activity = await getActivity(slot);
    if (!activity) {
      return {
        status: 200,
        jsonBody: { telemetryCount: 0, ticketCount: 0, lastTelemetryAt: null, lastSupportAt: null, message: 'No activity recorded yet for this slot' },
      };
    }

    const now = Date.now();
    const telemetryRecent = activity.lastTelemetryAt &&
      (now - new Date(activity.lastTelemetryAt).getTime()) < RECENT_THRESHOLD_MS;
    const supportRecent = activity.lastSupportAt &&
      (now - new Date(activity.lastSupportAt).getTime()) < RECENT_THRESHOLD_MS;

    context.log(`[signals-check] slot=${slot} telemetryRecent=${telemetryRecent} supportRecent=${supportRecent}`);
    return {
      status: 200,
      jsonBody: {
        telemetryCount: telemetryRecent ? 1 : 0,
        ticketCount:    supportRecent   ? 1 : 0,
        lastTelemetryAt: activity.lastTelemetryAt || null,
        lastSupportAt:   activity.lastSupportAt   || null,
      },
    };
  },
});
