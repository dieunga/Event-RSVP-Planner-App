const express = require('express');
const mysql = require('mysql2/promise');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');
const Redis = require('ioredis');
const { Kafka } = require('kafkajs');

const app = express();
app.use(express.json());
app.use(cors());

// ── Config from environment ──
const PORT = process.env.PORT || 3003;
const DB_HOST = process.env.DB_HOST || 'localhost';
const DB_USER = process.env.DB_USER || 'admin';
const DB_PASS = process.env.DB_PASS || 'admin123';
const DB_NAME = process.env.DB_NAME || 'webdb';
const REDIS_HOST = process.env.REDIS_HOST || 'localhost';
const REDIS_PORT = process.env.REDIS_PORT || 6379;
const KAFKA_BROKERS = (process.env.KAFKA_BROKERS || 'localhost:9092').split(',');
const AUTH_SERVICE_URL = process.env.AUTH_SERVICE_URL || 'http://auth-service:3001';

// ── Redis client for caching ──
const redis = new Redis({
  host: REDIS_HOST,
  port: REDIS_PORT,
  retryStrategy: (times) => Math.min(times * 100, 3000),
  lazyConnect: true,
});

redis.on('error', (err) => {
  console.warn('Redis connection error:', err.message);
});

(async () => {
  try { await redis.connect(); console.log('Redis connected'); }
  catch (e) { console.warn('Redis not available, continuing without cache'); }
})();

// ── Kafka ──
const kafka = new Kafka({ clientId: 'rsvp-service', brokers: KAFKA_BROKERS });
const producer = kafka.producer();
const consumer = kafka.consumer({ groupId: 'rsvp-service-group' });
let kafkaReady = false;

(async () => {
  try {
    await producer.connect();
    kafkaReady = true;
    console.log('Kafka producer connected');

    // Listen for event-deleted to cascade-delete RSVPs
    await consumer.connect();
    await consumer.subscribe({ topic: 'event-deleted', fromBeginning: false });
    await consumer.run({
      eachMessage: async ({ message }) => {
        try {
          const data = JSON.parse(message.value.toString());
          if (data.eventId) {
            await pool.execute('DELETE FROM rsvps WHERE event_id = ?', [data.eventId]);
            await invalidateCache(data.eventId);
            console.log(`Cascade deleted RSVPs for event ${data.eventId}`);
          }
        } catch (e) {
          console.error('Kafka consumer error:', e.message);
        }
      },
    });
    console.log('Kafka consumer listening on event-deleted');
  } catch (e) {
    console.warn('Kafka not available, continuing without it:', e.message);
  }
})();

async function publishEvent(topic, message) {
  if (!kafkaReady) return;
  try {
    await producer.send({ topic, messages: [{ value: JSON.stringify(message) }] });
  } catch (e) {
    console.warn('Kafka publish failed:', e.message);
  }
}

// ── MySQL connection pool ──
const pool = mysql.createPool({
  host: DB_HOST,
  user: DB_USER,
  password: DB_PASS,
  database: DB_NAME,
  waitForConnections: true,
  connectionLimit: 10,
});

// ── Initialize database tables ──
async function initDB() {
  const conn = await pool.getConnection();
  try {
    await conn.execute(`
      CREATE TABLE IF NOT EXISTS rsvps (
        id VARCHAR(36) PRIMARY KEY,
        event_id VARCHAR(36) NOT NULL,
        name VARCHAR(100) NOT NULL,
        email VARCHAR(150) NOT NULL,
        status ENUM('Attending', 'Maybe', 'Declined') DEFAULT 'Attending',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_event_id (event_id)
      )
    `);
    console.log('RSVPs table ready');
  } finally {
    conn.release();
  }
}

// ── Auth middleware ──
async function authenticate(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Authentication required' });
  }

  try {
    const response = await fetch(`${AUTH_SERVICE_URL}/api/auth/validate`, {
      headers: { Authorization: authHeader },
    });
    if (!response.ok) {
      return res.status(401).json({ error: 'Invalid session' });
    }
    req.user = await response.json();
    next();
  } catch (err) {
    console.error('Auth validation error:', err);
    return res.status(503).json({ error: 'Auth service unavailable' });
  }
}

// ── Cache helpers ──
const CACHE_TTL = 300;

async function getCached(key) {
  try {
    const data = await redis.get(key);
    return data ? JSON.parse(data) : null;
  } catch (e) { return null; }
}

async function setCache(key, data) {
  try {
    await redis.setex(key, CACHE_TTL, JSON.stringify(data));
  } catch (e) { /* ignore */ }
}

async function invalidateCache(eventId) {
  try {
    await redis.del(`rsvps:${eventId}`);
    await redis.del('rsvps:all');
  } catch (e) { /* ignore */ }
}

// ── Health check ──
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'rsvp-service' });
});

// ── Get RSVPs for an event ──
app.get('/api/rsvps/event/:eventId', authenticate, async (req, res) => {
  try {
    const cached = await getCached(`rsvps:${req.params.eventId}`);
    if (cached) return res.json(cached);

    const [rows] = await pool.execute(
      'SELECT * FROM rsvps WHERE event_id = ? ORDER BY created_at DESC',
      [req.params.eventId]
    );

    await setCache(`rsvps:${req.params.eventId}`, rows);
    res.json(rows);
  } catch (err) {
    console.error('Get RSVPs error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Get all RSVPs (for the RSVP table view) ──
app.get('/api/rsvps', authenticate, async (req, res) => {
  try {
    const [rows] = await pool.execute(
      `SELECT r.*, e.name as event_name FROM rsvps r
       LEFT JOIN events e ON r.event_id = e.id
       WHERE e.user_id = ?
       ORDER BY r.created_at DESC`,
      [req.user.userId]
    );
    res.json(rows);
  } catch (err) {
    console.error('Get all RSVPs error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Create RSVP ──
app.post('/api/rsvps', authenticate, async (req, res) => {
  try {
    const { eventId, name, email, status } = req.body;
    if (!eventId || !name || !email) {
      return res.status(400).json({ error: 'Event ID, name, and email are required' });
    }

    // Check for duplicate email on same event
    const [dup] = await pool.execute(
      'SELECT id FROM rsvps WHERE event_id = ? AND LOWER(email) = LOWER(?)',
      [eventId, email]
    );
    if (dup.length > 0) {
      return res.status(409).json({ error: 'This email is already registered for this event' });
    }

    const id = uuidv4();
    await pool.execute(
      'INSERT INTO rsvps (id, event_id, name, email, status) VALUES (?, ?, ?, ?, ?)',
      [id, eventId, name, email, status || 'Attending']
    );

    const rsvp = { id, event_id: eventId, name, email, status: status || 'Attending', created_at: new Date().toISOString() };

    await invalidateCache(eventId);
    await publishEvent('rsvp-created', { rsvpId: id, eventId, name, email, status, timestamp: new Date().toISOString() });

    res.status(201).json(rsvp);
  } catch (err) {
    console.error('Create RSVP error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Update RSVP status ──
app.put('/api/rsvps/:id', authenticate, async (req, res) => {
  try {
    const { status } = req.body;
    const [existing] = await pool.execute('SELECT * FROM rsvps WHERE id = ?', [req.params.id]);
    if (existing.length === 0) {
      return res.status(404).json({ error: 'RSVP not found' });
    }

    await pool.execute('UPDATE rsvps SET status = ? WHERE id = ?', [status, req.params.id]);
    await invalidateCache(existing[0].event_id);

    res.json({ message: 'RSVP updated' });
  } catch (err) {
    console.error('Update RSVP error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Delete RSVP ──
app.delete('/api/rsvps/:id', authenticate, async (req, res) => {
  try {
    const [existing] = await pool.execute('SELECT * FROM rsvps WHERE id = ?', [req.params.id]);
    if (existing.length === 0) {
      return res.status(404).json({ error: 'RSVP not found' });
    }

    await pool.execute('DELETE FROM rsvps WHERE id = ?', [req.params.id]);
    await invalidateCache(existing[0].event_id);
    await publishEvent('rsvp-deleted', { rsvpId: req.params.id, eventId: existing[0].event_id, timestamp: new Date().toISOString() });

    res.json({ message: 'RSVP deleted' });
  } catch (err) {
    console.error('Delete RSVP error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Start server ──
app.listen(PORT, '0.0.0.0', () => {
  console.log(`RSVP service running on port ${PORT}`);
});

(async function initWithRetry() {
  for (let attempt = 1; attempt <= 15; attempt++) {
    try {
      await initDB();
      return;
    } catch (err) {
      const delay = Math.min(5000 * attempt, 30000);
      console.warn(`DB init attempt ${attempt}/15 failed: ${err.message}. Retrying in ${delay}ms...`);
      await new Promise(r => setTimeout(r, delay));
    }
  }
  console.error('Failed to initialize database after 15 attempts, exiting.');
  process.exit(1);
})();
