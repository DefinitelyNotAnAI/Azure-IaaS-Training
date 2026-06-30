// admin.js — Instructor dashboard

(function () {
  'use strict';

  // ── Hackathon part definitions ─────────────────────────────────────────────
  // Derived from APP_CONFIG.hackathonParts at runtime so the dashboard stays
  // in sync with config.js automatically. Falls back to the hardcoded list.
  function getParts() {
    var cfg = (window.APP_CONFIG || {}).hackathonParts;
    if (cfg && Array.isArray(cfg)) return cfg;
    return [
      { id: 'part1', label: 'Part 1 — Infrastructure', modules: ['onboarding', 'module1', 'module3', 'part1_validate'] },
      { id: 'part2', label: 'Part 2 — Data Layer',     modules: ['part2_signals', 'part2_kql', 'part2_correlation', 'part2_dataagent'] },
      { id: 'part3', label: 'Part 3 — AI Agent',       modules: ['part3_scaffold', 'part3_prompts', 'part3_validate'] },
    ];
  }

  const STATUS_LABELS = {
    not_started:   'Not started',
    started:       'Started',
    complete:      'Complete',
    need_help:     'Need Help',
    watching_only: 'Watching Along',
  };

  let refreshTimer = null;
  let currentCode  = null;

  // ── API helpers ────────────────────────────────────────────────────────────

  async function apiFetch(path, options) {
    const res = await fetch(path, Object.assign({ headers: { 'x-access-code': currentCode } }, options));
    if (res.status === 401) return { _unauthorized: true };
    if (!res.ok) throw new Error('API ' + res.status + ' ' + path);
    return res.json();
  }

  async function fetchParticipants() {
    return apiFetch('/api/dashboard/participants');
  }

  async function fetchAssignments() {
    return apiFetch('/api/dashboard/assignments');
  }

  async function preassignSlot(slot, email) {
    return apiFetch('/api/dashboard/assignments/' + encodeURIComponent(slot) + '/preassign', {
      method: 'POST',
      headers: { 'x-access-code': currentCode, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email }),
    });
  }

  async function releaseSlot(slot) {
    return apiFetch('/api/dashboard/assignments/' + encodeURIComponent(slot) + '/release', { method: 'POST' });
  }

  async function rotateTap(slot) {
    return apiFetch('/api/dashboard/assignments/' + encodeURIComponent(slot) + '/rotate-tap', { method: 'POST' });
  }

  // ── Utilities ──────────────────────────────────────────────────────────────

  function parseStatuses(raw) {
    if (!raw) return {};
    if (typeof raw === 'object') return raw;
    try { return JSON.parse(raw); } catch (_) { return {}; }
  }

  function escapeHtml(str) {
    return String(str || '').replace(/[&<>"']/g, function (c) {
      return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c];
    });
  }

  function timeAgo(iso) {
    if (!iso) return '—';
    const diff = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
    if (diff < 60)   return diff + 's ago';
    if (diff < 3600) return Math.floor(diff / 60) + 'm ago';
    return Math.floor(diff / 3600) + 'h ago';
  }
  // Aggregate status for a part: worst-first (need_help > started > not_started),
  // but complete only if all modules are complete.
  function partStatus(statuses, modules) {
    var vals = modules.map(function (m) { return statuses[m] || 'not_started'; });
    if (vals.some(function (v) { return v === 'need_help'; })) return 'need_help';
    if (vals.every(function (v) { return v === 'complete'; })) return 'complete';
    if (vals.some(function (v) { return v !== 'not_started'; })) return 'started';
    return 'not_started';
  }

  // Count how many modules in a part are complete (for the sub-label in each cell)
  function partProgress(statuses, modules) {
    return modules.filter(function (m) { return (statuses[m] || '') === 'complete'; }).length;
  }
  // ── Renderers ──────────────────────────────────────────────────────────────

  function renderReadinessGauge(participants) {
    const container = document.getElementById('readiness-gauge');
    if (!container) return;

    const total    = participants.length;
    const onboard  = participants.filter(function (p) {
      return (parseStatuses(p.moduleStatuses).onboarding || '') === 'complete';
    }).length;
    const helpCount = participants.filter(function (p) {
      return Object.values(parseStatuses(p.moduleStatuses)).includes('need_help');
    }).length;

    const pct = total ? Math.round(onboard / total * 100) : 0;
    container.innerHTML =
      '<div class="gauge-bar"><div class="gauge-fill" style="width:' + pct + '%"></div></div>' +
      '<div class="gauge-labels">' +
        '<span><strong>' + onboard + ' / ' + total + '</strong> signed in</span>' +
        (helpCount ? '<span class="help-flag">⚠ ' + helpCount + ' need help</span>' : '') +
      '</div>';
  }

  function renderRegroupSummary(participants) {
    const container = document.getElementById('regroup-summary');
    if (!container) return;
    container.innerHTML = '';

    getParts().forEach(function (part) {
      var counts = { complete: 0, started: 0, need_help: 0, not_started: 0 };
      participants.forEach(function (p) {
        var agg = partStatus(parseStatuses(p.moduleStatuses), part.modules);
        counts[agg] = (counts[agg] || 0) + 1;
      });
      var card = document.createElement('div');
      card.className = 'regroup-card';
      card.innerHTML =
        '<h3>' + escapeHtml(part.label) + '</h3>' +
        '<div class="regroup-counts">' +
          '<div class="regroup-count-block"><div class="regroup-count count-complete">' + counts.complete + '</div><div class="count-label">Complete</div></div>' +
          '<div class="regroup-count-block"><div class="regroup-count count-started">' + counts.started + '</div><div class="count-label">In Progress</div></div>' +
          '<div class="regroup-count-block"><div class="regroup-count count-need_help">' + counts.need_help + '</div><div class="count-label">Need Help</div></div>' +
          '<div class="regroup-count-block"><div class="regroup-count" style="color:#605e5c">' + counts.not_started + '</div><div class="count-label">Not started</div></div>' +
        '</div>';
      container.appendChild(card);
    });
  }

  function renderParticipantTable(participants, filterStatus) {
    const tbody = document.getElementById('participants-tbody');
    if (!tbody) return;

    const filtered = filterStatus
      ? participants.filter(function (p) { return p.currentStatus === filterStatus; })
      : participants;

    if (filtered.length === 0) {
      tbody.innerHTML =
        '<tr><td colspan="6" style="text-align:center;color:#605e5c;padding:1.5rem">' +
        (participants.length === 0 ? 'No participants yet.' : 'No participants match the filter.') +
        '</td></tr>';
      return;
    }

    const parts = getParts();

    // Sort: need_help first, then by furthest part completed, then by name
    var sorted = filtered.slice().sort(function (a, b) {
      var sa = parseStatuses(a.moduleStatuses);
      var sb = parseStatuses(b.moduleStatuses);
      var aHelp = parts.some(function (pt) { return partStatus(sa, pt.modules) === 'need_help'; });
      var bHelp = parts.some(function (pt) { return partStatus(sb, pt.modules) === 'need_help'; });
      if (aHelp !== bHelp) return aHelp ? -1 : 1;
      var aComplete = parts.filter(function (pt) { return partStatus(sa, pt.modules) === 'complete'; }).length;
      var bComplete = parts.filter(function (pt) { return partStatus(sb, pt.modules) === 'complete'; }).length;
      if (aComplete !== bComplete) return bComplete - aComplete;
      return (a.displayName || '').localeCompare(b.displayName || '');
    });

    tbody.innerHTML = '';
    sorted.forEach(function (p) {
      const statuses = parseStatuses(p.moduleStatuses);
      const tr = document.createElement('tr');

      const hasNeedHelp = parts.some(function (pt) { return partStatus(statuses, pt.modules) === 'need_help'; });
      if (hasNeedHelp) tr.style.background = '#fff4ce';

      const partCells = parts.map(function (pt) {
        var agg   = partStatus(statuses, pt.modules);
        var done  = partProgress(statuses, pt.modules);
        var total = pt.modules.length;
        var label = STATUS_LABELS[agg] || agg;
        var sub   = (agg !== 'not_started' && agg !== 'complete')
          ? '<br><small style="color:#605e5c;font-size:0.75rem">' + done + '/' + total + ' steps</small>'
          : '';
        return '<td><span class="status-dot dot-' + agg + '"></span>' + escapeHtml(label) + sub + '</td>';
      }).join('');

      tr.innerHTML =
        '<td>' + escapeHtml(p.displayName) + '<br><small style="color:#605e5c">' + escapeHtml(p.email) + '</small></td>' +
        '<td>' + escapeHtml(p.assignedSlot || '—') + '</td>' +
        partCells +
        '<td>' + timeAgo(p.lastUpdated) + '</td>';
      tbody.appendChild(tr);
    });
  }

  function renderAssignmentsTable(assignments) {
    const tbody = document.getElementById('assignments-tbody');
    if (!tbody) return;

    if (!assignments.length) {
      tbody.innerHTML = '<tr><td colspan="7" style="text-align:center;color:#605e5c;padding:1.5rem">No assignments loaded.</td></tr>';
      return;
    }

    tbody.innerHTML = '';
    assignments.forEach(function (a) {
      const claimed   = !!a.claimedByEmail;
      const tr        = document.createElement('tr');
      const tapAge    = a.tapIssuedAt ? timeAgo(a.tapIssuedAt) : '—';
      const statusCell = claimed
        ? '<span style="color:#107c10">Claimed</span> — ' + escapeHtml(a.claimedByEmail)
        : '<span style="color:#605e5c">Unclaimed</span>';

      const preassignForm = claimed ? '' :
        '<form class="inline-form" data-action="preassign" data-slot="' + escapeHtml(a.slot) + '">' +
          '<input type="email" placeholder="email@company.com" class="input-sm" required />' +
          '<button type="submit" class="btn-inline">Pre-assign</button>' +
        '</form>';

      const actions = claimed
        ? '<button class="btn-inline btn-danger" data-action="release" data-slot="' + escapeHtml(a.slot) + '">Release</button> ' +
          '<button class="btn-inline" data-action="rotate-tap" data-slot="' + escapeHtml(a.slot) + '">Rotate TAP</button>'
        : preassignForm;

      tr.innerHTML =
        '<td>' + escapeHtml(a.slot) + '</td>' +
        '<td>' + escapeHtml(a.assignedRg) + '</td>' +
        '<td>' + escapeHtml(a.assignedCidr) + '</td>' +
        '<td>' + statusCell + '</td>' +
        '<td>' + tapAge + '</td>' +
        '<td>' + actions + '</td>';
      tbody.appendChild(tr);
    });

    // Wire actions
    tbody.querySelectorAll('[data-action="release"]').forEach(function (btn) {
      btn.addEventListener('click', async function () {
        if (!confirm('Release slot ' + btn.dataset.slot + '?')) return;
        try {
          await releaseSlot(btn.dataset.slot);
          await loadDashboard(null, 'assignments');
        } catch (e) { alert('Release failed: ' + e.message); }
      });
    });
    tbody.querySelectorAll('[data-action="rotate-tap"]').forEach(function (btn) {
      btn.addEventListener('click', async function () {
        try {
          await rotateTap(btn.dataset.slot);
          await loadDashboard(null, 'assignments');
        } catch (e) { alert('Rotate TAP failed: ' + e.message); }
      });
    });
    tbody.querySelectorAll('form[data-action="preassign"]').forEach(function (form) {
      form.addEventListener('submit', async function (e) {
        e.preventDefault();
        const email = form.querySelector('input').value.trim();
        if (!email) return;
        try {
          await preassignSlot(form.dataset.slot, email);
          await loadDashboard(null, 'assignments');
        } catch (e) { alert('Pre-assign failed: ' + e.message); }
      });
    });
  }

  // ── Dashboard lifecycle ────────────────────────────────────────────────────

  let activeTab = 'participants';

  async function loadDashboard(filterStatus, tab) {
    if (tab) activeTab = tab;
    const statusEl = document.getElementById('refresh-status');
    if (statusEl) statusEl.textContent = 'Refreshing…';

    try {
      const participants = await fetchParticipants();
      if (participants._unauthorized) { showAccessGate('Invalid access code.'); return; }

      renderReadinessGauge(participants);
      renderRegroupSummary(participants);

      const countEl = document.getElementById('participant-count');
      if (countEl) countEl.textContent = participants.length + ' participants';

      if (activeTab === 'participants') {
        renderParticipantTable(participants, filterStatus || null);
      } else if (activeTab === 'assignments') {
        const assignments = await fetchAssignments();
        if (!assignments._unauthorized) renderAssignmentsTable(assignments);
      }

      if (statusEl) statusEl.textContent = 'Updated ' + new Date().toLocaleTimeString();
    } catch (err) {
      if (statusEl) statusEl.textContent = 'Error loading data';
      console.error('[admin] fetch error', err);
    }
  }

  function showAccessGate(errorMsg) {
    document.getElementById('access-gate').style.display = 'block';
    document.getElementById('dashboard-section').style.display = 'none';
    const errEl = document.getElementById('access-error');
    if (errEl) errEl.textContent = errorMsg || '';
    currentCode = null;
    stopAutoRefresh();
  }

  function showDashboard() {
    document.getElementById('access-gate').style.display = 'none';
    document.getElementById('dashboard-section').style.display = 'block';
  }

  function startAutoRefresh() {
    stopAutoRefresh();
    refreshTimer = setInterval(function () {
      const sel = document.getElementById('filter-status');
      loadDashboard(sel ? sel.value : null);
    }, 30000);
  }

  function stopAutoRefresh() {
    if (refreshTimer) { clearInterval(refreshTimer); refreshTimer = null; }
  }

  // ── Init ───────────────────────────────────────────────────────────────────

  document.addEventListener('DOMContentLoaded', function () {
    const snEl = document.getElementById('session-name-header');
    if (snEl) snEl.textContent = window.APP_CONFIG.sessionName;

    document.getElementById('access-form').addEventListener('submit', async function (e) {
      e.preventDefault();
      const code = document.getElementById('access-code-input').value.trim();
      if (!code) return;
      currentCode = code;
      showDashboard();
      await loadDashboard(null, 'participants');
      const autoEl = document.getElementById('auto-refresh-toggle');
      if (!autoEl || autoEl.checked) startAutoRefresh();
    });

    document.getElementById('refresh-btn').addEventListener('click', function () {
      if (!currentCode) return;
      const sel = document.getElementById('filter-status');
      loadDashboard(sel ? sel.value : null);
    });

    document.getElementById('filter-status').addEventListener('change', function () {
      if (currentCode) loadDashboard(this.value || null);
    });

    document.getElementById('auto-refresh-toggle').addEventListener('change', function () {
      if (this.checked && currentCode) startAutoRefresh();
      else stopAutoRefresh();
    });

    // Tab switching
    document.querySelectorAll('.tab-btn').forEach(function (btn) {
      btn.addEventListener('click', function () {
        document.querySelectorAll('.tab-btn').forEach(function (b) { b.classList.remove('active'); });
        btn.classList.add('active');
        const tabName = btn.dataset.tab;
        document.querySelectorAll('.tab-panel').forEach(function (p) {
          p.style.display = p.id === 'tab-' + tabName ? '' : 'none';
        });
        if (currentCode) loadDashboard(null, tabName);
      });
    });
  });

}());
