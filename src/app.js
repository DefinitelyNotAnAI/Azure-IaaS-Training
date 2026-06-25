// app.js — Participant state management
// Calls /api/participants for check-in, resume, and status patches.

(function () {
  'use strict';

  const STORAGE_KEY    = 'iaas-workshop-participant';
  const TAP_KEY        = 'iaas-workshop-tap';   // sessionStorage — cleared when tab closes
  const TRACKED_MODULES = ['onboarding', 'module1', 'module2', 'module3', 'wrapup'];
  const STATUS_LABELS  = {
    not_started:   'Not started',
    started:       'Started',
    complete:      'Complete',
    need_help:     'Need Help',
    watching_only: 'Watching Along',
  };

  // ── Utilities ──────────────────────────────────────────────────────────────

  function normalizeEmail(email) {
    return email.trim().toLowerCase();
  }

  function defaultStatuses() {
    return {
      onboarding: 'not_started',
      module1:    'not_started',
      module2:    'not_started',
      module3:    'not_started',
      wrapup:     'not_started',
    };
  }

  // ── Participant persistence ────────────────────────────────────────────────

  function loadParticipant() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return null;
      const p = JSON.parse(raw);
      if (!p.sessionId || p.sessionId !== window.APP_CONFIG.sessionId) return null;
      return p;
    } catch (_) { return null; }
  }

  function saveParticipant(data) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
  }

  function clearParticipant() {
    localStorage.removeItem(STORAGE_KEY);
    sessionStorage.removeItem(TAP_KEY);
  }

  function requireParticipant() {
    const p = loadParticipant();
    if (!p) { window.location.href = 'index.html'; return null; }
    return p;
  }

  // TAP stored in sessionStorage (tab-local, not persisted across browser restarts)
  function saveTap(tap) {
    if (tap) sessionStorage.setItem(TAP_KEY, tap);
  }

  function loadTap() {
    return sessionStorage.getItem(TAP_KEY) || null;
  }

  // ── API helpers ────────────────────────────────────────────────────────────

  function apiHeaders(extra) {
    return Object.assign(
      { 'Content-Type': 'application/json', 'x-session-code': window.APP_CONFIG.sessionCode },
      extra
    );
  }

  // ── Check-in / resume ──────────────────────────────────────────────────────

  async function onCheckin(email, displayName) {
    const normalizedEmail = normalizeEmail(email);

    const res = await fetch('/api/participants', {
      method: 'POST',
      headers: apiHeaders(),
      body: JSON.stringify({ email: normalizedEmail, displayName: displayName.trim() }),
    });

    if (!res.ok) {
      const data = await res.json().catch(function () { return {}; });
      const err  = new Error(data.error || 'Check-in failed');
      err.status = res.status;
      err.code   = data.code;
      throw err;
    }

    const data = await res.json();
    return _applyServerResponse(data);
  }

  async function resumeByEmail(email) {
    const normalizedEmail = normalizeEmail(email);

    const res = await fetch('/api/participants/' + encodeURIComponent(normalizedEmail), {
      headers: { 'x-session-code': window.APP_CONFIG.sessionCode },
    });

    if (res.status === 404) {
      const err = new Error('No registration found for this email in the current session.');
      err.status = 404;
      throw err;
    }
    if (!res.ok) {
      const data = await res.json().catch(function () { return {}; });
      throw new Error(data.error || 'Resume failed');
    }

    const data = await res.json();
    return _applyServerResponse(data);
  }

  function _applyServerResponse(data) {
    const existing = loadParticipant();
    const participant = Object.assign(existing || {}, {
      email:          data.email || (existing && existing.email) || '',
      displayName:    data.displayName,
      participantId:  data.participantId,
      assignedSlot:   data.assignedSlot,
      assignedRg:     data.assignedRg,
      assignedCidr:   data.assignedCidr,
      assignedUpn:    data.assignedUpn,
      tapIssuedAt:    data.tapIssuedAt,
      portalRgUrl:    data.portalDeepLink,
      moduleStatuses: data.moduleStatuses || defaultStatuses(),
      sessionId:      window.APP_CONFIG.sessionId,
      lastUpdated:    new Date().toISOString(),
    });
    // Preserve email from response if available, else from payload
    if (data.email) participant.email = data.email;
    saveParticipant(participant);
    if (data.tempCredential) saveTap(data.tempCredential);
    return { participant: participant, tempCredential: data.tempCredential };
  }

  // ── Status updates ─────────────────────────────────────────────────────────

  function updateModuleStatus(moduleKey, status) {
    const p = loadParticipant();
    if (!p) return;

    if (!p.moduleStatuses) p.moduleStatuses = defaultStatuses();
    p.moduleStatuses[moduleKey] = status;
    p.currentModule  = moduleKey;
    p.currentStatus  = status;
    p.lastUpdated    = new Date().toISOString();
    saveParticipant(p);

    renderStatusRow(moduleKey);
    renderProgressBar();

    fetch('/api/participants/' + encodeURIComponent(p.email), {
      method: 'PATCH',
      headers: apiHeaders(),
      body: JSON.stringify({ module: moduleKey, status: status }),
    }).catch(function (err) { console.warn('[workshop] status patch failed', err); });
  }

  function saveFeedback(feedback) {
    const p = loadParticipant();
    if (!p) return;
    p.feedback    = String(feedback).trim().substring(0, 1000);
    p.lastUpdated = new Date().toISOString();
    saveParticipant(p);

    fetch('/api/participants/' + encodeURIComponent(p.email), {
      method: 'PATCH',
      headers: apiHeaders(),
      body: JSON.stringify({ feedback: p.feedback }),
    }).catch(function (err) { console.warn('[workshop] feedback patch failed', err); });
  }

  // ── Portal link helpers ────────────────────────────────────────────────────

  function getSlotNumber() {
    const p = loadParticipant();
    if (!p || !p.assignedSlot) return null;
    return parseInt(p.assignedSlot.replace('user', ''), 10);
  }

  function buildPortalResourceUrl(provider, resourceType, resourceName) {
    const p = loadParticipant();
    if (!p || !p.portalRgUrl) return 'https://portal.azure.com';
    const base = p.portalRgUrl.replace(/\/overview$/, '');
    return base + '/providers/' + provider + '/' + resourceType + '/' + resourceName + '/overview';
  }

  // ── Renderers ──────────────────────────────────────────────────────────────

  function renderStatusRow(moduleKey) {
    const container = document.getElementById('status-row');
    if (!container) return;

    const p       = loadParticipant();
    const current = p ? ((p.moduleStatuses || {})[moduleKey] || 'not_started') : 'not_started';

    const buttons = [
      { value: 'started',       label: 'Started' },
      { value: 'complete',      label: 'Complete' },
      { value: 'need_help',     label: 'Need Help' },
      { value: 'watching_only', label: 'Watching Along' },
    ];

    const row = document.createElement('div');
    row.className = 'status-buttons';

    buttons.forEach(function (b) {
      const btn = document.createElement('button');
      btn.className = 'status-btn status-' + b.value + (current === b.value ? ' active' : '');
      btn.textContent = b.label;
      btn.setAttribute('aria-pressed', current === b.value ? 'true' : 'false');
      btn.addEventListener('click', function () { updateModuleStatus(moduleKey, b.value); });
      row.appendChild(btn);
    });

    container.innerHTML = '';
    container.appendChild(row);

    if (current !== 'not_started') {
      const lbl = document.createElement('p');
      lbl.className = 'status-current';
      lbl.textContent = 'Your status: ' + (STATUS_LABELS[current] || current);
      container.appendChild(lbl);
    }
  }

  function renderProgressBar() {
    const bar = document.getElementById('progress-bar');
    if (!bar) return;

    const p = loadParticipant();
    const segments = [
      { key: 'onboarding', label: 'Sign In' },
      { key: 'module1',    label: 'Networking' },
      { key: 'module2',    label: 'Peering' },
      { key: 'module3',    label: 'Compute' },
    ];

    bar.innerHTML = '';
    segments.forEach(function (seg) {
      const status = p ? ((p.moduleStatuses || {})[seg.key] || 'not_started') : 'not_started';
      const div    = document.createElement('div');
      div.className   = 'progress-segment status-bg-' + status;
      div.textContent = seg.label;
      div.title       = seg.label + ': ' + (STATUS_LABELS[status] || status);
      bar.appendChild(div);
    });
  }

  function renderParticipantInfo() {
    const p = loadParticipant();

    const nameEl = document.getElementById('participant-name');
    if (nameEl && p) nameEl.textContent = p.displayName;

    const resetEl = document.getElementById('change-participant');
    if (resetEl) {
      resetEl.addEventListener('click', function (e) {
        e.preventDefault();
        clearParticipant();
        window.location.href = 'index.html';
      });
    }
  }

  function renderAssignmentBanner() {
    const banner = document.getElementById('assignment-banner');
    if (!banner) return;

    const p = loadParticipant();
    if (!p || !p.assignedRg) { banner.style.display = 'none'; return; }

    var rgEl   = document.getElementById('banner-rg');
    var cidrEl = document.getElementById('banner-cidr');
    var linkEl = document.getElementById('banner-portal-link');

    if (rgEl)   rgEl.textContent = p.assignedRg;
    if (cidrEl) cidrEl.textContent = p.assignedCidr;
    if (linkEl && p.portalRgUrl) linkEl.href = p.portalRgUrl;

    banner.style.display = 'flex';
  }

  function renderWrapupSummary() {
    const list = document.getElementById('module-status-list');
    if (!list) return;

    const p     = loadParticipant();
    const items = [
      { key: 'onboarding', label: 'Sign In' },
      { key: 'module1',    label: 'Module 1 — Networking' },
      { key: 'module2',    label: 'Module 2 — Peering' },
      { key: 'module3',    label: 'Module 3 — Compute' },
      { key: 'wrapup',     label: 'Wrap-up' },
    ];

    list.innerHTML = '';
    items.forEach(function (item) {
      const status = p ? ((p.moduleStatuses || {})[item.key] || 'not_started') : 'not_started';
      const li = document.createElement('li');
      li.innerHTML =
        '<span>' + item.label + '</span>' +
        '<span class="status-badge badge-' + status + '">' + (STATUS_LABELS[status] || status) + '</span>';
      list.appendChild(li);
    });
  }

  // ── Page init ──────────────────────────────────────────────────────────────

  document.addEventListener('DOMContentLoaded', function () {
    var snEl = document.getElementById('session-name');
    if (snEl) snEl.textContent = window.APP_CONFIG.sessionName;
    var sdEl = document.getElementById('session-date');
    if (sdEl) sdEl.textContent = window.APP_CONFIG.sessionDate;

    renderParticipantInfo();
    renderProgressBar();
  });

  // ── Public API ─────────────────────────────────────────────────────────────
  window.WorkshopApp = {
    loadParticipant:        loadParticipant,
    saveParticipant:        saveParticipant,
    clearParticipant:       clearParticipant,
    requireParticipant:     requireParticipant,
    loadTap:                loadTap,
    onCheckin:              onCheckin,
    resumeByEmail:          resumeByEmail,
    updateModuleStatus:     updateModuleStatus,
    saveFeedback:           saveFeedback,
    getSlotNumber:          getSlotNumber,
    buildPortalResourceUrl: buildPortalResourceUrl,
    renderStatusRow:        renderStatusRow,
    renderProgressBar:      renderProgressBar,
    renderParticipantInfo:  renderParticipantInfo,
    renderAssignmentBanner: renderAssignmentBanner,
    renderWrapupSummary:    renderWrapupSummary,
    normalizeEmail:         normalizeEmail,
  };

}());
