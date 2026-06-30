'use strict';
// schema.js — Validates and stamps shared correlation dimensions on incoming payloads.
//
// Shared correlation dimensions (present on both Telemetry and Tickets records):
//   slotId, timestamp, ingestedAt, region, service (telemetry) / customerTenant (tickets)
//
// These dimensions are what Part 2 KQL joins and Part 3 agent queries use to
// correlate system behaviour (telemetry) with customer experience (support tickets).

const REQUIRED_TELEMETRY = ['service', 'operation', 'region', 'latencyMs'];
const REQUIRED_SUPPORT   = ['ticketId', 'customerTenant', 'description'];

function validateTelemetry(body) {
  for (const field of REQUIRED_TELEMETRY) {
    if (body[field] === undefined || body[field] === null || String(body[field]).trim() === '') {
      return `Missing required field: ${field}`;
    }
  }
  if (isNaN(Number(body.latencyMs))) return 'latencyMs must be a number';
  return null;
}

function validateSupport(body) {
  for (const field of REQUIRED_SUPPORT) {
    if (body[field] === undefined || body[field] === null || String(body[field]).trim() === '') {
      return `Missing required field: ${field}`;
    }
  }
  return null;
}

function stampTelemetry(body, slotId) {
  const now = new Date().toISOString();
  return {
    slotId,
    timestamp:     body.timestamp      || now,
    ingestedAt:    now,
    service:       String(body.service        || '').trim().substring(0, 64),
    operation:     String(body.operation      || '').trim().substring(0, 64),
    region:        String(body.region         || '').trim().substring(0, 32),
    latencyMs:     Math.max(0, Math.round(Number(body.latencyMs)    || 0)),
    errorCount:    Math.max(0, Math.round(Number(body.errorCount)   || 0)),
    throughput:    Math.max(0, Math.round(Number(body.throughput)   || 0)),
    isAnomaly:     body.isAnomaly    === true || body.isAnomaly    === 'true',
    incidentId:    String(body.incidentId     || '').trim().substring(0, 64),
    correlationId: String(body.correlationId  || '').trim().substring(0, 64),
  };
}

function stampSupport(body, slotId) {
  const now = new Date().toISOString();
  return {
    slotId,
    ticketId:       String(body.ticketId       || '').trim().substring(0, 64),
    timestamp:      body.timestamp      || now,
    ingestedAt:     now,
    customerTenant: String(body.customerTenant || '').trim().substring(0, 64),
    description:    String(body.description    || '').trim().substring(0, 2000),
    category:       String(body.category       || '').trim().substring(0, 64),
    incidentId:     String(body.incidentId     || '').trim().substring(0, 64),
    isNoise:        body.isNoise  === true || body.isNoise  === 'true',
  };
}

module.exports = { validateTelemetry, validateSupport, stampTelemetry, stampSupport };
