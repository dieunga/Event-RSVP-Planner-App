// ============================================================
// Soirée - Frontend Application (API-driven)
// ============================================================

const API_BASE = '';  // Same origin, proxied by nginx

// ── Auth helpers ──
function getToken() { return localStorage.getItem('soiree_token'); }
function getUserEmail() { return localStorage.getItem('soiree_email') || 'User'; }

function authHeaders() {
  return {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${getToken()}`,
  };
}

function requireAuth() {
  if (!getToken()) {
    window.location.href = '/login.html';
    return false;
  }
  return true;
}

function logout() {
  fetch(`${API_BASE}/api/auth/logout`, {
    method: 'POST',
    headers: authHeaders(),
  }).finally(() => {
    localStorage.removeItem('soiree_token');
    localStorage.removeItem('soiree_email');
    localStorage.removeItem('soiree_userId');
    window.location.href = '/login.html';
  });
}

// ── Data ──
let events = [];
let rsvps = [];
let activeEventId = null;
let currentFilter = 'all';

// ── API calls ──
async function fetchEvents() {
  try {
    const res = await fetch(`${API_BASE}/api/events`, { headers: authHeaders() });
    if (res.status === 401) { logout(); return; }
    if (!res.ok) throw new Error('Failed to fetch events');
    events = await res.json();
  } catch (err) {
    console.error('fetchEvents error:', err);
    events = [];
  }
}

async function fetchRsvps() {
  try {
    const res = await fetch(`${API_BASE}/api/rsvps`, { headers: authHeaders() });
    if (res.status === 401) { logout(); return; }
    if (!res.ok) throw new Error('Failed to fetch RSVPs');
    rsvps = await res.json();
  } catch (err) {
    console.error('fetchRsvps error:', err);
    rsvps = [];
  }
}

async function fetchEventRsvps(eventId) {
  try {
    const res = await fetch(`${API_BASE}/api/rsvps/event/${eventId}`, { headers: authHeaders() });
    if (!res.ok) throw new Error('Failed to fetch event RSVPs');
    return await res.json();
  } catch (err) {
    console.error('fetchEventRsvps error:', err);
    return [];
  }
}

async function createEvent(eventData) {
  const res = await fetch(`${API_BASE}/api/events`, {
    method: 'POST',
    headers: authHeaders(),
    body: JSON.stringify(eventData),
  });
  if (!res.ok) {
    const data = await res.json();
    throw new Error(data.error || 'Failed to create event');
  }
  return await res.json();
}

async function deleteEvent(eventId) {
  const res = await fetch(`${API_BASE}/api/events/${eventId}`, {
    method: 'DELETE',
    headers: authHeaders(),
  });
  if (!res.ok) throw new Error('Failed to delete event');
}

async function createRsvp(rsvpData) {
  const res = await fetch(`${API_BASE}/api/rsvps`, {
    method: 'POST',
    headers: authHeaders(),
    body: JSON.stringify(rsvpData),
  });
  if (!res.ok) {
    const data = await res.json();
    throw new Error(data.error || 'Failed to create RSVP');
  }
  return await res.json();
}

async function deleteRsvp(rsvpId) {
  const res = await fetch(`${API_BASE}/api/rsvps/${rsvpId}`, {
    method: 'DELETE',
    headers: authHeaders(),
  });
  if (!res.ok) throw new Error('Failed to delete RSVP');
}

// ── Stats ──
function updateStats() {
  const now = new Date();
  const upcoming = events.filter(e => new Date(e.date + 'T' + (e.time || '00:00')) >= now).length;
  document.getElementById('statEvents').textContent = events.length;
  document.getElementById('statRsvps').textContent = rsvps.filter(r => r.status === 'Attending').length;
  document.getElementById('statUpcoming').textContent = upcoming;
}

// ── Events rendering ──
function formatDate(dateStr, timeStr) {
  const d = new Date(dateStr + 'T' + (timeStr || '00:00'));
  return d.toLocaleDateString('en-US', { weekday:'short', month:'long', day:'numeric', year:'numeric' })
       + (timeStr ? ' · ' + d.toLocaleTimeString('en-US', { hour:'numeric', minute:'2-digit' }) : '');
}

function isUpcoming(e) {
  return new Date(e.date + 'T' + (e.time || '00:00')) >= new Date();
}

function renderEvents() {
  const grid = document.getElementById('eventsGrid');
  const empty = document.getElementById('emptyEvents');

  let filtered = events;
  if (currentFilter === 'upcoming') filtered = events.filter(isUpcoming);
  if (currentFilter === 'past') filtered = events.filter(e => !isUpcoming(e));

  if (filtered.length === 0) {
    grid.innerHTML = '';
    empty.style.display = 'flex';
    return;
  }
  empty.style.display = 'none';

  grid.innerHTML = filtered.map(e => {
    const eventRsvps = rsvps.filter(r => r.event_id === e.id);
    const attending = eventRsvps.filter(r => r.status === 'Attending').length;
    const cap = e.capacity ? parseInt(e.capacity) : null;
    const pct = cap ? Math.min(100, Math.round(attending / cap * 100)) : null;
    const upcoming = isUpcoming(e);
    return `
      <div class="event-card ${upcoming ? '' : 'past'}" data-id="${e.id}" tabindex="0">
        <div class="card-top">
          <div class="card-badges">
            <span class="badge badge-category">${e.category || 'Event'}</span>
            ${upcoming ? '<span class="badge badge-upcoming">Upcoming</span>' : '<span class="badge badge-past">Past</span>'}
          </div>
          <button class="card-menu-btn" data-id="${e.id}" title="Open">→</button>
        </div>
        <h3 class="card-title">${escapeHtml(e.name)}</h3>
        <div class="card-meta">
          <span class="card-meta-item">📅 ${formatDate(e.date, e.time)}</span>
          <span class="card-meta-item">📍 ${escapeHtml(e.location)}</span>
        </div>
        ${e.description ? `<p class="card-desc">${escapeHtml(e.description.slice(0,100))}${e.description.length>100?'…':''}</p>` : ''}
        <div class="card-footer">
          <div class="card-rsvp-info">
            <span class="rsvp-count">${attending} attending</span>
            ${cap ? `<span class="rsvp-cap">/ ${cap}</span>` : ''}
          </div>
          ${cap ? `<div class="mini-bar"><div class="mini-bar-fill" style="width:${pct}%"></div></div>` : ''}
        </div>
      </div>
    `;
  }).join('');

  grid.querySelectorAll('.event-card').forEach(card => {
    card.addEventListener('click', () => openDetail(card.dataset.id));
    card.addEventListener('keydown', e => { if(e.key==='Enter') openDetail(card.dataset.id); });
  });
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

// ── RSVP Table ──
function renderRsvpTable() {
  const table = document.getElementById('rsvpTable');
  const body = document.getElementById('rsvpTableBody');
  const empty = document.getElementById('emptyRsvps');

  if (rsvps.length === 0) {
    table.style.display = 'none';
    empty.style.display = 'flex';
    return;
  }
  empty.style.display = 'none';
  table.style.display = 'table';

  body.innerHTML = rsvps.map(r => {
    const event = events.find(e => e.id === r.event_id);
    return `
      <tr>
        <td>${escapeHtml(r.name)}</td>
        <td class="td-muted">${escapeHtml(r.email)}</td>
        <td>${event ? escapeHtml(event.name) : '<em>Deleted</em>'}</td>
        <td><span class="status-pill status-${r.status.toLowerCase()}">${r.status}</span></td>
        <td class="td-muted">${new Date(r.created_at).toLocaleDateString('en-US',{month:'short',day:'numeric',year:'numeric'})}</td>
        <td>
          <button class="tbl-btn tbl-btn-danger" data-rsvpid="${r.id}">Remove</button>
        </td>
      </tr>
    `;
  }).join('');

  body.querySelectorAll('.tbl-btn-danger').forEach(btn => {
    btn.addEventListener('click', async () => {
      try {
        await deleteRsvp(btn.dataset.rsvpid);
        rsvps = rsvps.filter(r => r.id !== btn.dataset.rsvpid);
        renderRsvpTable(); updateStats();

      } catch (err) {

      }
    });
  });
}

// ── Event Detail Modal ──
let currentEventRsvps = [];

async function openDetail(id) {
  activeEventId = id;
  const e = events.find(ev => ev.id === id);
  if (!e) return;

  document.getElementById('detailCategory').textContent = e.category || 'Event';
  document.getElementById('detailName').textContent = e.name;
  document.getElementById('detailDate').textContent = formatDate(e.date, e.time);
  document.getElementById('detailLocation').textContent = e.location;
  document.getElementById('detailDescription').textContent = e.description || '';

  currentEventRsvps = await fetchEventRsvps(id);

  const cap = e.capacity ? parseInt(e.capacity) : null;
  const attending = currentEventRsvps.filter(r => r.status === 'Attending').length;
  document.getElementById('detailCapacity').textContent =
    cap ? `${attending} / ${cap} attending` : `${attending} attending`;

  const pct = cap ? Math.min(100, Math.round(attending / cap * 100)) : 0;
  document.getElementById('detailProgressFill').style.width = cap ? pct + '%' : '0%';
  document.getElementById('detailProgressText').textContent = cap ? `${pct}%` : 'No limit set';

  document.getElementById('rsvpName').value = '';
  document.getElementById('rsvpEmail').value = '';
  document.getElementById('rsvpStatus').value = 'Attending';
  document.getElementById('rsvpError').textContent = '';

  renderGuestList();
  openModal('eventDetailModal');
}

function renderGuestList() {
  const body = document.getElementById('guestListBody');
  const count = document.getElementById('guestCount');
  count.textContent = currentEventRsvps.length ? `(${currentEventRsvps.length})` : '';

  if (currentEventRsvps.length === 0) {
    body.innerHTML = '<p class="no-guests">No guests yet. Add the first RSVP above.</p>';
    return;
  }
  body.innerHTML = currentEventRsvps.map(r => `
    <div class="guest-row">
      <div class="guest-avatar">${r.name.charAt(0).toUpperCase()}</div>
      <div class="guest-info">
        <span class="guest-name">${escapeHtml(r.name)}</span>
        <span class="guest-email">${escapeHtml(r.email)}</span>
      </div>
      <span class="status-pill status-${r.status.toLowerCase()}">${r.status}</span>
      <button class="guest-remove" data-rid="${r.id}" title="Remove">✕</button>
    </div>
  `).join('');

  body.querySelectorAll('.guest-remove').forEach(btn => {
    btn.addEventListener('click', async () => {
      try {
        await deleteRsvp(btn.dataset.rid);
        currentEventRsvps = currentEventRsvps.filter(r => r.id !== btn.dataset.rid);
        rsvps = rsvps.filter(r => r.id !== btn.dataset.rid);
        renderGuestList();
        updateStats(); renderEvents();

      } catch (err) {

      }
    });
  });
}

// ── Modal helpers ──
function openModal(id) { document.getElementById(id).classList.add('active'); }
function closeModal(id) { document.getElementById(id).classList.remove('active'); }

// ── Toast ──
function toast(msg) {}

// ── Initialize on page load ──
document.addEventListener('DOMContentLoaded', async () => {
  if (!requireAuth()) return;

  // Set user name
  const displayName = getUserEmail().split('@')[0];
  document.getElementById('userName').textContent = displayName;

  // Wire up logout
  document.getElementById('logoutLink').addEventListener('click', (e) => {
    e.preventDefault();
    logout();
  });

  // Load data
  await Promise.all([fetchEvents(), fetchRsvps()]);
  renderEvents();
  updateStats();

  // ── Modal close buttons ──
  document.querySelectorAll('[data-close]').forEach(btn => {
    btn.addEventListener('click', () => closeModal(btn.dataset.close));
  });
  document.querySelectorAll('.modal-overlay').forEach(overlay => {
    overlay.addEventListener('click', e => {
      if (e.target === overlay) overlay.classList.remove('active');
    });
  });

  // ── Create event ──
  document.getElementById('openCreateModal').addEventListener('click', () => {
    ['evtName','evtDate','evtTime','evtLocation','evtDescription','evtCapacity']
      .forEach(id => { document.getElementById(id).value = ''; });
    document.getElementById('evtCategory').value = 'Social';
    document.getElementById('createError').textContent = '';
    openModal('createEventModal');
  });

  document.getElementById('saveEventBtn').addEventListener('click', async () => {
    const name = document.getElementById('evtName').value.trim();
    const date = document.getElementById('evtDate').value;
    const time = document.getElementById('evtTime').value;
    const location = document.getElementById('evtLocation').value.trim();
    const err = document.getElementById('createError');

    if (!name || !date || !location) {
      err.textContent = 'Please fill in Name, Date, and Location.';
      return;
    }
    err.textContent = '';

    try {
      const event = await createEvent({
        name,
        date,
        time,
        location,
        category: document.getElementById('evtCategory').value,
        capacity: document.getElementById('evtCapacity').value || null,
        description: document.getElementById('evtDescription').value.trim(),
      });
      events.unshift(event);
      renderEvents(); updateStats();
      closeModal('createEventModal');

    } catch (err2) {
      err.textContent = err2.message;
    }
  });

  // ── Add RSVP ──
  document.getElementById('addRsvpBtn').addEventListener('click', async () => {
    const name = document.getElementById('rsvpName').value.trim();
    const email = document.getElementById('rsvpEmail').value.trim();
    const status = document.getElementById('rsvpStatus').value;
    const err = document.getElementById('rsvpError');

    if (!name || !email) { err.textContent = 'Name and email are required.'; return; }
    if (!/\S+@\S+\.\S+/.test(email)) { err.textContent = 'Please enter a valid email.'; return; }
    err.textContent = '';

    try {
      const rsvp = await createRsvp({ eventId: activeEventId, name, email, status });
      currentEventRsvps.push(rsvp);
      rsvps.push(rsvp);
      document.getElementById('rsvpName').value = '';
      document.getElementById('rsvpEmail').value = '';
      renderGuestList();
      updateStats(); renderEvents();

    } catch (err2) {
      err.textContent = err2.message;
    }
  });

  // ── Delete Event ──
  document.getElementById('deleteEventBtn').addEventListener('click', async () => {
    if (!confirm('Delete this event and all its RSVPs?')) return;
    try {
      await deleteEvent(activeEventId);
      events = events.filter(e => e.id !== activeEventId);
      rsvps = rsvps.filter(r => r.event_id !== activeEventId);
      renderEvents(); renderRsvpTable(); updateStats();
      closeModal('eventDetailModal');

    } catch (err) {

    }
  });

  // ── Nav & Filters ──
  document.querySelectorAll('.nav-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
      document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
      document.getElementById('view-' + btn.dataset.view).classList.add('active');
      if (btn.dataset.view === 'rsvps') {
        await fetchRsvps();
        renderRsvpTable();
      }
    });
  });

  document.querySelectorAll('.filter-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      currentFilter = btn.dataset.filter;
      renderEvents();
    });
  });
});
