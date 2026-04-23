<?php
require 'config.php';

// Load API endpoint if available 
$notify_api_url = '';
if (file_exists('api_config.php')) {
    require_once 'api_config.php';
}

// Check if the user is logged in. If not, kick them to the login page.
if (!isset($_SESSION['user_id'])) {
    header("Location: /login.php");
    exit;
}

//Extract just the name from the email for display
$display_name = explode('@', $_SESSION['user_email'])[0];
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Soirée — Event Manager</title>
  <link rel="stylesheet" href="styles.css" />
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,300;0,400;0,500;0,600;1,300;1,400&family=Josefin+Sans:wght@300;400;500&display=swap" rel="stylesheet" />
</head>
<body>

  <!-- HEADER -->
  <header class="site-header">
    <div class="header-inner">
      <div class="logo">
        <span class="logo-mark">◆</span>
        <span class="logo-text">Soirée</span>
      </div>
      <nav class="header-nav">
        <button class="nav-btn active" data-view="events">Events</button>
        <button class="nav-btn" data-view="rsvps">RSVPs</button>
      </nav>
      <div class="header-user">
        <span class="user-name" id="userName"><?php echo htmlspecialchars($display_name); ?></span>
        <a href="logout.php" style="color: var(--text-secondary); text-decoration: none; font-size: 12px; margin-left: 10px;">Logout</a>
      </div>
      <button class="btn-primary" id="openCreateModal">+ New Event</button>
    </div>
  </header>

  <!-- HERO STRIP -->
  <section class="hero-strip">
    <div class="hero-inner">
      <p class="hero-eyebrow">Your Private Collection</p>
      <h1 class="hero-title">Curate the<br /><em>Extraordinary</em></h1>
      <div class="hero-stats" id="heroStats">
        <div class="stat">
          <span class="stat-number" id="statEvents">0</span>
          <span class="stat-label">Events</span>
        </div>
        <div class="stat-divider"></div>
        <div class="stat">
          <span class="stat-number" id="statRsvps">0</span>
          <span class="stat-label">RSVPs</span>
        </div>
        <div class="stat-divider"></div>
        <div class="stat">
          <span class="stat-number" id="statUpcoming">0</span>
          <span class="stat-label">Upcoming</span>
        </div>
      </div>
    </div>
    <div class="hero-ornament"></div>
  </section>

  <!-- MAIN CONTENT -->
  <main class="main-content">

    <!-- EVENTS VIEW -->
    <section class="view active" id="view-events">
      <div class="section-header">
        <h2 class="section-title">All Events</h2>
        <div class="filter-bar">
          <button class="filter-btn active" data-filter="all">All</button>
          <button class="filter-btn" data-filter="upcoming">Upcoming</button>
          <button class="filter-btn" data-filter="past">Past</button>
        </div>
      </div>
      <div class="events-grid" id="eventsGrid">
        <!-- Event cards injected here -->
        <div class="empty-state" id="emptyEvents">
          <div class="empty-icon">◇</div>
          <p class="empty-title">No events yet</p>
          <p class="empty-sub">Create your first event to get started.</p>
          <button class="btn-primary" onclick="document.getElementById('openCreateModal').click()">+ New Event</button>
        </div>
      </div>
    </section>

    <!-- RSVPS VIEW -->
    <section class="view" id="view-rsvps">
      <div class="section-header">
        <h2 class="section-title">All RSVPs</h2>
      </div>
      <div class="rsvp-table-wrap" id="rsvpTableWrap">
        <div class="empty-state" id="emptyRsvps">
          <div class="empty-icon">◇</div>
          <p class="empty-title">No RSVPs yet</p>
          <p class="empty-sub">RSVPs will appear here once guests register.</p>
        </div>
        <table class="rsvp-table" id="rsvpTable" style="display:none">
          <thead>
            <tr>
              <th>Guest</th>
              <th>Email</th>
              <th>Event</th>
              <th>Status</th>
              <th>Date</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody id="rsvpTableBody"></tbody>
        </table>
      </div>
    </section>

  </main>

  <!-- ===================== MODALS ===================== -->

  <!-- CREATE EVENT MODAL -->
  <div class="modal-overlay" id="createEventModal">
    <div class="modal">
      <div class="modal-header">
        <h3 class="modal-title">New Event</h3>
        <button class="modal-close" data-close="createEventModal">✕</button>
      </div>
      <div class="modal-body">
        <div class="form-group">
          <label class="form-label">Event Name <span class="req">*</span></label>
          <input type="text" class="form-input" id="evtName" placeholder="e.g. Spring Gala 2025" />
        </div>
        <div class="form-row">
          <div class="form-group">
            <label class="form-label">Date <span class="req">*</span></label>
            <input type="date" class="form-input" id="evtDate" />
          </div>
          <div class="form-group">
            <label class="form-label">Time <span class="req">*</span></label>
            <input type="time" class="form-input" id="evtTime" />
          </div>
        </div>
        <div class="form-group">
          <label class="form-label">Location <span class="req">*</span></label>
          <input type="text" class="form-input" id="evtLocation" placeholder="e.g. The Grand Ballroom, New York" />
        </div>
        <div class="form-row">
          <div class="form-group">
            <label class="form-label">Category</label>
            <select class="form-input" id="evtCategory">
              <option value="Social">Social</option>
              <option value="Corporate">Corporate</option>
              <option value="Wedding">Wedding</option>
              <option value="Conference">Conference</option>
              <option value="Birthday">Birthday</option>
              <option value="Other">Other</option>
            </select>
          </div>
          <div class="form-group">
            <label class="form-label">Capacity</label>
            <input type="number" class="form-input" id="evtCapacity" placeholder="e.g. 150" min="1" />
          </div>
        </div>
        <div class="form-group">
          <label class="form-label">Description</label>
          <textarea class="form-input form-textarea" id="evtDescription" placeholder="Describe your event…"></textarea>
        </div>
        <p class="form-error" id="createError"></p>
      </div>
      <div class="modal-footer">
        <button class="btn-ghost" data-close="createEventModal">Cancel</button>
        <button class="btn-primary" id="saveEventBtn">Create Event</button>
      </div>
    </div>
  </div>

  <!-- EVENT DETAIL MODAL -->
  <div class="modal-overlay" id="eventDetailModal">
    <div class="modal modal-wide">
      <div class="modal-header">
        <div>
          <span class="modal-eyebrow" id="detailCategory"></span>
          <h3 class="modal-title" id="detailName"></h3>
        </div>
        <button class="modal-close" data-close="eventDetailModal">✕</button>
      </div>
      <div class="modal-body">
        <div class="detail-meta">
          <div class="detail-meta-item">
            <span class="detail-meta-icon">📅</span>
            <span id="detailDate"></span>
          </div>
          <div class="detail-meta-item">
            <span class="detail-meta-icon">📍</span>
            <span id="detailLocation"></span>
          </div>
          <div class="detail-meta-item">
            <span class="detail-meta-icon">👥</span>
            <span id="detailCapacity"></span>
          </div>
        </div>
        <p class="detail-description" id="detailDescription"></p>

        <div class="rsvp-progress-bar-wrap">
          <div class="rsvp-progress-label">
            <span>RSVP Capacity</span>
            <span id="detailProgressText"></span>
          </div>
          <div class="rsvp-progress-track">
            <div class="rsvp-progress-fill" id="detailProgressFill"></div>
          </div>
        </div>

        <div class="rsvp-section">
          <h4 class="rsvp-section-title">Add RSVP</h4>
          <div class="form-row">
            <div class="form-group">
              <label class="form-label">Guest Name <span class="req">*</span></label>
              <input type="text" class="form-input" id="rsvpName" placeholder="Full name" />
            </div>
            <div class="form-group">
              <label class="form-label">Email <span class="req">*</span></label>
              <input type="email" class="form-input" id="rsvpEmail" placeholder="email@example.com" />
            </div>
          </div>
          <div class="form-row">
            <div class="form-group">
              <label class="form-label">Status</label>
              <select class="form-input" id="rsvpStatus">
                <option value="Attending">Attending</option>
                <option value="Maybe">Maybe</option>
                <option value="Declined">Declined</option>
              </select>
            </div>
            <div class="form-group" style="display:flex;align-items:flex-end;">
              <button class="btn-primary" style="width:100%;" id="addRsvpBtn">Add Guest</button>
            </div>
          </div>
          <p class="form-error" id="rsvpError"></p>
        </div>

        <div class="rsvp-guest-list">
          <h4 class="rsvp-section-title">Guest List <span class="guest-count" id="guestCount"></span></h4>
          <div id="guestListBody"></div>
        </div>
      </div>
      <div class="modal-footer">
        <button class="btn-danger" id="deleteEventBtn">Delete Event</button>
        <button class="btn-ghost" data-close="eventDetailModal">Close</button>
      </div>
    </div>
  </div>

  <!-- TOAST -->
  <div class="toast" id="toast"></div>

  <!-- app.js is for API-driven mode, not used in this localStorage-based version -->
  <!-- <script src="app.js"></script> -->
  
  <script>
    const USER_EMAIL   = '<?php echo htmlspecialchars($_SESSION["user_email"], ENT_QUOTES); ?>';
    const NOTIFY_API   = '<?php echo htmlspecialchars($notify_api_url, ENT_QUOTES); ?>';

    // ============================================================
    // DATA LAYER
    // ============================================================
    var events = JSON.parse(localStorage.getItem('soiree_events') || '[]');
    var rsvps  = JSON.parse(localStorage.getItem('soiree_rsvps')  || '[]');
    var activeEventId = null;
    var currentFilter = 'all';

    function save() {
      localStorage.setItem('soiree_events', JSON.stringify(events));
      localStorage.setItem('soiree_rsvps',  JSON.stringify(rsvps));
    }

    function uid() {
      return Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
    }

    // ============================================================
    // STATS
    // ============================================================
    function updateStats() {
      const now = new Date();
      const upcoming = events.filter(e => new Date(e.date + 'T' + (e.time || '00:00')) >= now).length;
      document.getElementById('statEvents').textContent   = events.length;
      document.getElementById('statRsvps').textContent    = rsvps.filter(r => r.status === 'Attending').length;
      document.getElementById('statUpcoming').textContent = upcoming;
    }

    // ============================================================
    // EVENTS RENDERING
    // ============================================================
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

      let filtered = events;
      if (currentFilter === 'upcoming') filtered = events.filter(isUpcoming);
      if (currentFilter === 'past')     filtered = events.filter(e => !isUpcoming(e));

      if (filtered.length === 0) {
        grid.innerHTML = `
          <div class="empty-state" id="emptyEvents" style="display:flex">
            <div class="empty-icon">◇</div>
            <p class="empty-title">No events yet</p>
            <p class="empty-sub">Create your first event to get started.</p>
            <button class="btn-primary" onclick="document.getElementById('openCreateModal').click()">+ New Event</button>
          </div>`;
        return;
      }

      grid.innerHTML = filtered.map(e => {
        const eventRsvps   = rsvps.filter(r => r.eventId === e.id);
        const attending    = eventRsvps.filter(r => r.status === 'Attending').length;
        const cap          = e.capacity ? parseInt(e.capacity) : null;
        const pct          = cap ? Math.min(100, Math.round(attending / cap * 100)) : null;
        const upcoming     = isUpcoming(e);
        return `
          <div class="event-card ${upcoming ? '' : 'past'}" data-id="${e.id}" tabindex="0">
            <div class="card-top">
              <div class="card-badges">
                <span class="badge badge-category">${e.category || 'Event'}</span>
                ${upcoming ? '<span class="badge badge-upcoming">Upcoming</span>' : '<span class="badge badge-past">Past</span>'}
              </div>
              <button class="card-menu-btn" data-id="${e.id}" title="Open">→</button>
            </div>
            <h3 class="card-title">${e.name}</h3>
            <div class="card-meta">
              <span class="card-meta-item">📅 ${formatDate(e.date, e.time)}</span>
              <span class="card-meta-item">📍 ${e.location}</span>
            </div>
            ${e.description ? `<p class="card-desc">${e.description.slice(0,100)}${e.description.length>100?'…':''}</p>` : ''}
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

    // ============================================================
    // RSVP TABLE
    // ============================================================
    function renderRsvpTable() {
      const table = document.getElementById('rsvpTable');
      const body  = document.getElementById('rsvpTableBody');
      const empty = document.getElementById('emptyRsvps');

      if (rsvps.length === 0) {
        table.style.display = 'none';
        empty.style.display = 'flex';
        return;
      }
      empty.style.display = 'none';
      table.style.display = 'table';

      body.innerHTML = rsvps.map(r => {
        const event = events.find(e => e.id === r.eventId);
        return `
          <tr>
            <td>${r.name}</td>
            <td class="td-muted">${r.email}</td>
            <td>${event ? event.name : '<em>Deleted</em>'}</td>
            <td><span class="status-pill status-${r.status.toLowerCase()}">${r.status}</span></td>
            <td class="td-muted">${new Date(r.createdAt).toLocaleDateString('en-US',{month:'short',day:'numeric',year:'numeric'})}</td>
            <td>
              <button class="tbl-btn tbl-btn-danger" data-rsvpid="${r.id}">Remove</button>
            </td>
          </tr>
        `;
      }).join('');

      body.querySelectorAll('.tbl-btn-danger').forEach(btn => {
        btn.addEventListener('click', () => {
          rsvps = rsvps.filter(r => r.id !== btn.dataset.rsvpid);
          save(); renderRsvpTable(); updateStats();
          toast('RSVP removed');
        });
      });
    }

    // ============================================================
    // EVENT DETAIL MODAL
    // ============================================================
    function openDetail(id) {
      activeEventId = id;
      const e = events.find(ev => ev.id === id);
      if (!e) return;

      document.getElementById('detailCategory').textContent  = e.category || 'Event';
      document.getElementById('detailName').textContent      = e.name;
      document.getElementById('detailDate').textContent      = formatDate(e.date, e.time);
      document.getElementById('detailLocation').textContent  = e.location;
      document.getElementById('detailDescription').textContent = e.description || '';

      const cap      = e.capacity ? parseInt(e.capacity) : null;
      const attending = rsvps.filter(r => r.eventId === id && r.status === 'Attending').length;
      document.getElementById('detailCapacity').textContent =
        cap ? `${attending} / ${cap} attending` : `${attending} attending`;

      const pct = cap ? Math.min(100, Math.round(attending / cap * 100)) : 0;
      document.getElementById('detailProgressFill').style.width = cap ? pct + '%' : '0%';
      document.getElementById('detailProgressText').textContent  = cap ? `${pct}%` : 'No limit set';

      document.getElementById('rsvpName').value  = '';
      document.getElementById('rsvpEmail').value = '';
      document.getElementById('rsvpStatus').value = 'Attending';
      document.getElementById('rsvpError').textContent = '';

      renderGuestList(id);
      openModal('eventDetailModal');
    }

    function renderGuestList(eventId) {
      const body  = document.getElementById('guestListBody');
      const count = document.getElementById('guestCount');
      const list  = rsvps.filter(r => r.eventId === eventId);
      count.textContent = list.length ? `(${list.length})` : '';

      if (list.length === 0) {
        body.innerHTML = '<p class="no-guests">No guests yet. Add the first RSVP above.</p>';
        return;
      }
      body.innerHTML = list.map(r => `
        <div class="guest-row">
          <div class="guest-avatar">${r.name.charAt(0).toUpperCase()}</div>
          <div class="guest-info">
            <span class="guest-name">${r.name}</span>
            <span class="guest-email">${r.email}</span>
          </div>
          <span class="status-pill status-${r.status.toLowerCase()}">${r.status}</span>
          <button class="guest-remove" data-rid="${r.id}" title="Remove">✕</button>
        </div>
      `).join('');

      body.querySelectorAll('.guest-remove').forEach(btn => {
        btn.addEventListener('click', () => {
          rsvps = rsvps.filter(r => r.id !== btn.dataset.rid);
          save(); renderGuestList(eventId); openDetail(eventId);
          renderRsvpTable(); updateStats(); renderEvents();
          toast('Guest removed');
        });
      });
    }

    // ============================================================
    // MODAL HELPERS
    // ============================================================
    function openModal(id)  { document.getElementById(id).classList.add('active'); }
    function closeModal(id) { document.getElementById(id).classList.remove('active'); }

    document.querySelectorAll('[data-close]').forEach(btn => {
      btn.addEventListener('click', () => closeModal(btn.dataset.close));
    });
    document.querySelectorAll('.modal-overlay').forEach(overlay => {
      overlay.addEventListener('click', e => {
        if (e.target === overlay) overlay.classList.remove('active');
      });
    });

    // ============================================================
    // CREATE EVENT
    // ============================================================
    document.getElementById('openCreateModal').addEventListener('click', () => {
      ['evtName','evtDate','evtTime','evtLocation','evtDescription','evtCapacity']
        .forEach(id => { document.getElementById(id).value = ''; });
      document.getElementById('evtCategory').value = 'Social';
      document.getElementById('createError').textContent = '';
      openModal('createEventModal');
    });

    document.getElementById('saveEventBtn').addEventListener('click', () => {
      const name     = document.getElementById('evtName').value.trim();
      const date     = document.getElementById('evtDate').value;
      const time     = document.getElementById('evtTime').value;
      const location = document.getElementById('evtLocation').value.trim();
      const err      = document.getElementById('createError');

      if (!name || !date || !location) {
        err.textContent = 'Please fill in Name, Date, and Location.';
        return;
      }
      err.textContent = '';

      const event = {
        id:          uid(),
        name,
        date,
        time,
        location,
        category:    document.getElementById('evtCategory').value,
        capacity:    document.getElementById('evtCapacity').value || null,
        description: document.getElementById('evtDescription').value.trim(),
        createdAt:   new Date().toISOString()
      };
      events.unshift(event);
      save(); renderEvents(); updateStats();
      closeModal('createEventModal');
      toast('Event created!');

      // Trigger Lambda notification email
      if (NOTIFY_API) {
        fetch(NOTIFY_API, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ userEmail: USER_EMAIL, event })
        }).catch(() => {}); // silent fail — don't block UX
      }
    });

    // ============================================================
    // ADD RSVP
    // ============================================================
    document.getElementById('addRsvpBtn').addEventListener('click', () => {
      const name   = document.getElementById('rsvpName').value.trim();
      const email  = document.getElementById('rsvpEmail').value.trim();
      const status = document.getElementById('rsvpStatus').value;
      const err    = document.getElementById('rsvpError');

      if (!name || !email) { err.textContent = 'Name and email are required.'; return; }
      if (!/\S+@\S+\.\S+/.test(email)) { err.textContent = 'Please enter a valid email.'; return; }
      if (rsvps.find(r => r.eventId === activeEventId && r.email.toLowerCase() === email.toLowerCase())) {
        err.textContent = 'This email is already registered for this event.'; return;
      }
      const e = events.find(ev => ev.id === activeEventId);
      const cap = e && e.capacity ? parseInt(e.capacity) : null;
      if (cap && status === 'Attending') {
        const attending = rsvps.filter(r => r.eventId === activeEventId && r.status === 'Attending').length;
        if (attending >= cap) { err.textContent = 'Event is at full capacity.'; return; }
      }
      err.textContent = '';

      rsvps.push({ id: uid(), eventId: activeEventId, name, email, status, createdAt: new Date().toISOString() });
      save();
      document.getElementById('rsvpName').value  = '';
      document.getElementById('rsvpEmail').value = '';
      renderGuestList(activeEventId);
      openDetail(activeEventId);
      renderRsvpTable(); updateStats(); renderEvents();
      toast('RSVP added!');
    });

    // ============================================================
    // DELETE EVENT
    // ============================================================
    document.getElementById('deleteEventBtn').addEventListener('click', () => {
      if (!confirm('Delete this event and all its RSVPs?')) return;
      events = events.filter(e => e.id !== activeEventId);
      rsvps  = rsvps.filter(r => r.eventId !== activeEventId);
      save(); renderEvents(); renderRsvpTable(); updateStats();
      closeModal('eventDetailModal');
      toast('Event deleted');
    });

    // ============================================================
    // NAV & FILTERS
    // ============================================================
    document.querySelectorAll('.nav-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
        document.getElementById('view-' + btn.dataset.view).classList.add('active');
        if (btn.dataset.view === 'rsvps') renderRsvpTable();
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

    // ============================================================
    // TOAST
    // ============================================================
    function toast(msg) {
      const t = document.getElementById('toast');
      t.textContent = msg;
      t.classList.add('show');
      setTimeout(() => t.classList.remove('show'), 2800);
    }

    // ============================================================
    // INIT
    // ============================================================
    renderEvents();
    updateStats();
  </script>
</body>
</html>
