'use strict';
const crypto = require('crypto');

function timingSafeCompare(a, b) {
  const aBuf = Buffer.from(String(a));
  const bBuf = Buffer.from(String(b));
  // Always run the comparison even on length mismatch to avoid timing leak
  const len = Math.max(aBuf.length, bBuf.length);
  const aPad = Buffer.concat([aBuf, Buffer.alloc(len - aBuf.length)]);
  const bPad = Buffer.concat([bBuf, Buffer.alloc(len - bBuf.length)]);
  const equal = crypto.timingSafeEqual(aPad, bPad);
  return equal && aBuf.length === bBuf.length;
}

function verifySessionCode(headers) {
  const provided = (headers.get ? headers.get('x-session-code') : headers['x-session-code']) || '';
  const expected = process.env.SESSION_CODE || '';
  if (!provided || !expected) return false;
  return timingSafeCompare(provided.trim(), expected.trim());
}

function verifyAccessCode(headers) {
  const provided = (headers.get ? headers.get('x-access-code') : headers['x-access-code']) || '';
  const expected = process.env.ADMIN_ACCESS_CODE || '';
  if (!provided || !expected) return false;
  return timingSafeCompare(provided.trim(), expected.trim());
}

module.exports = { verifySessionCode, verifyAccessCode };
