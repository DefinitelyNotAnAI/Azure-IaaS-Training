'use strict';
// eventhub.js — Thin wrapper around EventHubProducerClient.
// Uses DefaultAzureCredential (UAMI in production, az login locally).
// Clients are cached per hub name to avoid re-creating per request.

const { EventHubProducerClient } = require('@azure/event-hubs');
const { DefaultAzureCredential }  = require('@azure/identity');

const credential = new DefaultAzureCredential({
  managedIdentityClientId: process.env.AZURE_CLIENT_ID || undefined,
});

const _producers = {};

function getProducer(hubName) {
  if (_producers[hubName]) return _producers[hubName];
  const namespace = process.env.EVENT_HUB_NAMESPACE;
  if (!namespace) throw new Error('EVENT_HUB_NAMESPACE environment variable is not set');
  _producers[hubName] = new EventHubProducerClient(namespace, hubName, credential);
  return _producers[hubName];
}

/**
 * Sends a single event payload to the named Event Hub.
 * The payload is serialised as JSON in the event body.
 */
async function sendEvent(hubName, payload) {
  const producer = getProducer(hubName);
  const batch    = await producer.createBatch();
  const added    = batch.tryAdd({ body: payload, contentType: 'application/json' });
  if (!added) throw new Error(`Event too large for Event Hub '${hubName}'`);
  await producer.sendBatch(batch);
}

module.exports = { sendEvent };
