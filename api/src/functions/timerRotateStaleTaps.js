'use strict';
const { app } = require('@azure/functions');
const { getTableClient } = require('../shared/tables');
const { rotateTap } = require('./postAdminTapRotate');

const TAP_MAX_AGE_HOURS = Number(process.env.TAP_ROTATION_MAX_AGE_HOURS) || 24;

app.timer('timerRotateStaleTaps', {
  schedule: '0 0 4 * * *', // 4 am UTC daily
  handler: async (myTimer, context) => {
    context.log(`[timerRotateStaleTaps] Starting. Max TAP age: ${TAP_MAX_AGE_HOURS}h`);

    const client       = getTableClient('Assignments');
    const cutoffMs     = Date.now() - TAP_MAX_AGE_HOURS * 60 * 60 * 1000;
    let rotated = 0;
    let skipped = 0;
    let errors  = 0;

    for await (const entity of client.listEntities()) {
      if (!entity.tapIssuedAt) { skipped++; continue; }

      const age = Date.now() - new Date(entity.tapIssuedAt).getTime();
      if (age < cutoffMs) { skipped++; continue; }

      try {
        const { newTap, issuedAt } = await rotateTap(entity, context);
        await client.updateEntity(
          {
            partitionKey:   entity.partitionKey,
            rowKey:         entity.rowKey,
            tempCredential: newTap.temporaryAccessPass,
            currentTapId:   newTap.id,
            tapIssuedAt:    issuedAt,
          },
          'Merge'
        );
        context.log(`[timerRotateStaleTaps] Rotated slot ${entity.rowKey} (session ${entity.partitionKey})`);
        rotated++;
      } catch (e) {
        context.warn(`[timerRotateStaleTaps] Failed to rotate ${entity.rowKey}: ${e.message}`);
        errors++;
      }
    }

    context.log(`[timerRotateStaleTaps] Done. rotated=${rotated} skipped=${skipped} errors=${errors}`);
  },
});
