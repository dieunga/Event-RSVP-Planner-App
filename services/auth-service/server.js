const express = require('express');
const mysql = require('mysql2/promise');
const bcrypt = require('bcryptjs');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');
const Redis = require('ioredis');
const { Kafka } = require('kafkajs');

const app = express();
app.use(express.json());
app.use(cors());

// ── Config from environment ──
const PORT = process.env.PORT || 3001;
const DB_HOST = process.env.DB_HOST || 'localhost';
const DB_USER = process.env.DB_USER || 'admin';
const DB_PASS = process.env.DB_PASS || 'admin123';
const DB_NAME = process.env.DB_NAME || 'webdb';
const REDIS_HOST = process.env.REDIS_HOST || 'localhost';
const REDIS_PORT = process.env.REDIS_PORT || 6379;
const KAFKA_BROKERS = (process.env.KAFKA_BROKERS || 'localhost:9092').split(',');

// ── Redis client for session storage ──
const redis = new Redis({
  host: REDIS_HOST,
  port: REDIS_PORT,
  retryStrategy: (times) => Math.min(times * 100, 3000),
  lazyConnect: true,
});

redis.on('error', (err) => {
  console.warn('Redis connection error (sessions will work without cache):', err.message);
});

(async () => {
  try { await redis.connect(); console.log('Redis connected'); }
  catch (e) { console.warn('Redis not available, continuing without it'); }
})();

// ── Kafka producer ──
const kafka = new Kafka({ clientId: 'auth-service', brokers: KAFKA_BROKERS });
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
      CREATE TABLE IF NOT EXISTS users (
        id VARCHAR(36) PRIMARY KEY,
        email VARCHAR(150) NOT NULL UNIQUE,
        password VARCHAR(255) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    console.log('Users table ready');
  } finally {
    conn.release();
  }
}

// ── Session helpers using Redis ──
const SESSION_TTL = 86400; // 24 hours

async function createSession(userId, email) {
  const token = uuidv4();
  const sessionData = JSON.stringify({ userId, email });
  try {
    await redis.setex(`session:${token}`, SESSION_TTL, sessionData);
  } catch (e) {
    console.warn('Redis session store failed, using in-memory fallback');
    inMemorySessions.set(token, { userId, email, expires: Date.now() + SESSION_TTL * 1000 });
  }
  return token;
}

async function getSession(token) {
  try {
    const data = await redis.get(`session:${token}`);
    if (data) return JSON.parse(data);
  } catch (e) {
    // Fallback to in-memory
    const session = inMemorySessions.get(token);
    if (session && session.expires > Date.now()) return session;
    if (session) inMemorySessions.delete(token);
  }
  return null;
}

async function destroySession(token) {
  try {
    await redis.del(`session:${token}`);
  } catch (e) {
    inMemorySessions.delete(token);
  }
}

const inMemorySessions = new Map();

// ── Health check ──
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'auth-service' });
});

// ── Signup ──
app.post('/api/auth/signup', async (req, res) => {
  try {
    const { email, password } = req.body;
    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required' });
    }
    if (password.length < 8) {
      return res.status(400).json({ error: 'Password must be at least 8 characters' });
    }

    const [existing] = await pool.execute('SELECT id FROM users WHERE email = ?', [email]);
    if (existing.length > 0) {
      return res.status(409).json({ error: 'Email is already registered' });
    }

    const hashedPassword = await bcrypt.hash(password, 12);
    const userId = uuidv4();
    await pool.execute('INSERT INTO users (id, email, password) VALUES (?, ?, ?)', [userId, email, hashedPassword]);

    await publishEvent('user-registered', { userId, email, timestamp: new Date().toISOString() });

    res.status(201).json({ message: 'Account created successfully' });
  } catch (err) {
    console.error('Signup error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Login ──
app.post('/api/auth/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required' });
    }

    const [users] = await pool.execute('SELECT id, email, password FROM users WHERE email = ?', [email]);
    if (users.length === 0) {
      return res.status(401).json({ error: 'Invalid email or password' });
    }

    const user = users[0];
    const valid = await bcrypt.compare(password, user.password);
    if (!valid) {
      return res.status(401).json({ error: 'Invalid email or password' });
    }

    const token = await createSession(user.id, user.email);

    await publishEvent('user-login', { userId: user.id, email: user.email, timestamp: new Date().toISOString() });

    res.json({ token, email: user.email, userId: user.id });
  } catch (err) {
    console.error('Login error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Validate session (used by other microservices) ──
app.get('/api/auth/validate', async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'No token provided' });
    }

    const token = authHeader.split(' ')[1];
    const session = await getSession(token);
    if (!session) {
      return res.status(401).json({ error: 'Invalid or expired session' });
    }

    res.json({ userId: session.userId, email: session.email });
  } catch (err) {
    console.error('Validate error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Logout ──
app.post('/api/auth/logout', async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith('Bearer ')) {
      const token = authHeader.split(' ')[1];
      await destroySession(token);
    }
    res.json({ message: 'Logged out successfully' });
  } catch (err) {
    console.error('Logout error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Start server ──
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Auth service running on port ${PORT}`);
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
