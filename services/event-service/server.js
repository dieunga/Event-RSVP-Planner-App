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
const PORT = process.env.PORT || 3002;
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

// ── Kafka producer ──
const kafka = new Kafka({ clientId: 'event-service', brokers: KAFKA_BROKERS });
const producer = kafka.producer();
let kafkaReady = false;

(async () => {
  try {
    await producer.connect();
    kafkaReady = true;
    console.log('Kafka producer connected');
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
      CREATE TABLE IF NOT EXISTS events (
        id VARCHAR(36) PRIMARY KEY,
        user_id VARCHAR(36) NOT NULL,
        name VARCHAR(255) NOT NULL,
        date DATE NOT NULL,
        time VARCHAR(10),
        location VARCHAR(255) NOT NULL,
        category VARCHAR(50) DEFAULT 'Social',
        capacity INT,
        description TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    console.log('Events table ready');
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
    const userData = await response.json();
    req.user = userData;
    next();
  } catch (err) {
    console.error('Auth validation error:', err);
    return res.status(503).json({ error: 'Auth service unavailable' });
  }
}

// ── Cache helpers ──
const CACHE_TTL = 300; // 5 minutes

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

async function invalidateCache(userId) {
  try {
    await redis.del(`events:${userId}`);
    await redis.del('events:all');
  } catch (e) { /* ignore */ }
}

// ── Health check ──
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'event-service' });
});

// ── Get all events for the authenticated user ──
app.get('/api/events', authenticate, async (req, res) => {
  try {
    const cached = await getCached(`events:${req.user.userId}`);
    if (cached) return res.json(cached);

    const [rows] = await pool.execute(
      'SELECT * FROM events WHERE user_id = ? ORDER BY created_at DESC',
      [req.user.userId]
    );

    await setCache(`events:${req.user.userId}`, rows);
    res.json(rows);
  } catch (err) {
    console.error('Get events error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Get a single event ──
app.get('/api/events/:id', authenticate, async (req, res) => {
  try {
    const [rows] = await pool.execute(
      'SELECT * FROM events WHERE id = ? AND user_id = ?',
      [req.params.id, req.user.userId]
    );
    if (rows.length === 0) {
      return res.status(404).json({ error: 'Event not found' });
    }
    res.json(rows[0]);
  } catch (err) {
    console.error('Get event error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Create event ──
app.post('/api/events', authenticate, async (req, res) => {
  try {
    const { name, date, time, location, category, capacity, description } = req.body;
    if (!name || !date || !location) {
      return res.status(400).json({ error: 'Name, date, and location are required' });
    }

    const id = uuidv4();
    await pool.execute(
      `INSERT INTO events (id, user_id, name, date, time, location, category, capacity, description)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [id, req.user.userId, name, date, time || null, location, category || 'Social', capacity || null, description || null]
    );

    const event = { id, user_id: req.user.userId, name, date, time, location, category, capacity, description, created_at: new Date().toISOString() };

    await invalidateCache(req.user.userId);
    await publishEvent('event-created', { eventId: id, userId: req.user.userId, name, date, timestamp: new Date().toISOString() });

    // Send confirmation email via Lambda
    const NOTIFY_URL = process.env.NOTIFY_URL;
    if (NOTIFY_URL && req.user.email) {
      fetch(`${NOTIFY_URL}/notify`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ userEmail: req.user.email, event }),
      }).catch(err => console.warn('Notify Lambda error:', err.message));
    }

    res.status(201).json(event);
  } catch (err) {
    console.error('Create event error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Update event ──
app.put('/api/events/:id', authenticate, async (req, res) => {
  try {
    const { name, date, time, location, category, capacity, description } = req.body;

    const [existing] = await pool.execute(
      'SELECT * FROM events WHERE id = ? AND user_id = ?',
      [req.params.id, req.user.userId]
    );
    if (existing.length === 0) {
      return res.status(404).json({ error: 'Event not found' });
    }

    await pool.execute(
      `UPDATE events SET name = ?, date = ?, time = ?, location = ?, category = ?, capacity = ?, description = ?
       WHERE id = ? AND user_id = ?`,
      [name, date, time || null, location, category || 'Social', capacity || null, description || null, req.params.id, req.user.userId]
    );

    await invalidateCache(req.user.userId);
    await publishEvent('event-updated', { eventId: req.params.id, userId: req.user.userId, timestamp: new Date().toISOString() });

    res.json({ message: 'Event updated' });
  } catch (err) {
    console.error('Update event error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Delete event ──
app.delete('/api/events/:id', authenticate, async (req, res) => {
  try {
    const [existing] = await pool.execute(
      'SELECT * FROM events WHERE id = ? AND user_id = ?',
      [req.params.id, req.user.userId]
    );
    if (existing.length === 0) {
      return res.status(404).json({ error: 'Event not found' });
    }

    await pool.execute('DELETE FROM events WHERE id = ? AND user_id = ?', [req.params.id, req.user.userId]);

    await invalidateCache(req.user.userId);
    await publishEvent('event-deleted', { eventId: req.params.id, userId: req.user.userId, timestamp: new Date().toISOString() });

    res.json({ message: 'Event deleted' });
  } catch (err) {
    console.error('Delete event error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Start server ──
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Event service running on port ${PORT}`);
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
