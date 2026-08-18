// /api/backfill.js
// Incremental full backfill: Firestore -> READ-MIRROR Supabase.
//
// Triggered by a Vercel cron. Because serverless functions have short time
// limits, this endpoint processes ONE table per invocation and records progress
// in the mirror's own `settings` row (id = "backfill_state"). Contents (the big
// table) are processed in chunks of 1000 using a createdAt cursor.
//
// When Firestore reads are quota-blocked (RESOURCE_EXHAUSTED) each table simply
// fails and the state stays put; as soon as reads recover, the next cron tick
// continues automatically. No manual waiting needed.
//
// A 6h "done" marker prevents re-reading everything on every tick.

const admin = require('firebase-admin');
const fs = require('fs');
const os = require('os');
const path = require('path');

const MIRROR_URL = 'https://qluwnxsmnxvvqoiejtbr.supabase.co';
const MIRROR_ANON =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFsdXdueHNtbnh2dnFvaWVqdGJyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcwMDAzNTEsImV4cCI6MjEwMjU3NjM1MX0.lYGxH02Kb0qS2Lm46Mc5lQoOyd7VR1-6WWSBA2TXfr8';

const TABLE_ORDER = [
  'folders',
  'contents',
  'users',
  'assistant_access',
  'content_assistant_access',
  'notes',
  'notifications',
  'admin_notifications',
  'notices',
  'feedbacks',
  'student_activities',
  'login_attempts',
  'login_history',
  'web_sessions',
  'conversations',
  'messages',
  'app_updates',
  'ai_api_keys',
];

const CAMEL_TO_COL = {
  role: 'role', email: 'email', name: 'name', blocked: 'blocked', verified: 'verified',
  freeTrialActive: 'free_trial_active',
  locked: 'locked', invisible: 'invisible', updating: 'updating',
  groupLink: 'group_link', inheritGroup: 'inherit_group',
  folderId: 'folder_id', parentContentId: 'parent_content_id',
  title: 'title', type: 'type', url: 'url', youtubeUrl: 'youtube_url',
  order: 'order',
  sessionId: 'session_id', uid: 'uid', status: 'status', webBrowser: 'web_browser',
  userEmail: 'user_email', userRole: 'user_role', androidDeviceId: 'android_device_id',
  deviceId: 'device_id', deviceModel: 'device_model', timestamp: 'timestamp',
  read: 'read', message: 'message', userName: 'user_name',
  fileType: 'file_type', addedBy: 'added_by',
  paidAccess: 'paid_access', price: 'price',
  version: 'version', link: 'link', startedAt: 'started_at',
  userId: 'user_id', contentId: 'content_id',
  apiKey: 'api_key', baseUrl: 'base_url', model: 'model', provider: 'provider', isActive: 'is_active',
  content: 'content', lectureName: 'lecture_name', updatedAt: 'updated_at',
  lastMessage: 'last_message', conversationId: 'conversation_id',
};

const TOP_LEVEL_COLS = {
  users: ['role', 'email', 'name', 'blocked', 'verified', 'freeTrialActive'],
  folders: ['name', 'locked', 'invisible', 'updating', 'groupLink', 'inheritGroup'],
  assistant_access: ['uid', 'folderId'],
  content_assistant_access: ['userId', 'folderId', 'contentId'],
  notes: ['uid', 'content', 'lectureName', 'updatedAt'],
  notifications: ['uid', 'read', 'message', 'userName', 'type'],
  admin_notifications: ['read', 'message', 'type'],
  notices: ['title', 'fileType', 'addedBy'],
  feedbacks: ['uid', 'status', 'viewed', 'message', 'reply'],
  student_activities: ['uid', 'startedAt'],
  login_attempts: ['uid', 'deviceId', 'deviceModel', 'timestamp'],
  login_history: ['uid', 'device', 'ip', 'timestamp'],
  web_sessions: ['sessionId', 'uid', 'status', 'webBrowser', 'userEmail', 'userRole', 'androidDeviceId'],
  conversations: ['uid', 'title', 'lastMessage', 'updatedAt'],
  messages: ['conversationId', 'role', 'content', 'timestamp'],
  app_updates: ['version', 'link'],
  ai_api_keys: ['apiKey', 'baseUrl', 'model', 'provider', 'isActive'],
};

function sanitize(v) {
  if (v instanceof admin.firestore.Timestamp) return v.toDate().toISOString();
  if (v instanceof admin.firestore.GeoPoint) return { lat: v.latitude, lng: v.longitude };
  if (Array.isArray(v)) return v.map(sanitize);
  if (v && typeof v === 'object') {
    const o = {};
    for (const [k, x] of Object.entries(v)) o[k] = sanitize(x);
    return o;
  }
  return v;
}

function buildRow(table, id, data, extra) {
  const row = { id, data: sanitize(data || {}) };
  for (const f of TOP_LEVEL_COLS[table] || []) {
    let v = data?.[f];
    if ((v === undefined || v === null) && extra?.[f] !== undefined) v = extra[f];
    const col = CAMEL_TO_COL[f] || f;
    row[col] = v === undefined || v === null ? null
      : (v instanceof admin.firestore.Timestamp ? v.toDate().toISOString() : v);
  }
  return row;
}

async function getServiceRoleKey() {
  const res = await fetch(`${MIRROR_URL}/rest/v1/settings?id=eq.read_mirror&limit=1`, {
    headers: { apikey: MIRROR_ANON, Authorization: `Bearer ${MIRROR_ANON}` },
  });
  if (!res.ok) throw new Error(`read_mirror fetch ${res.status}`);
  const rows = await res.json();
  const key = rows?.[0]?.data?.serviceRoleKey;
  if (!key) throw new Error('service role key not found in read_mirror');
  return key;
}

async function upsertRows(table, rows, key) {
  const headers = {
    apikey: key,
    Authorization: `Bearer ${key}`,
    'Content-Type': 'application/json',
    Prefer: 'resolution=merge-duplicates',
  };
  for (let i = 0; i < rows.length; i += 500) {
    const chunk = rows.slice(i, i + 500);
    const res = await fetch(`${MIRROR_URL}/rest/v1/${table}?on_conflict=id`, {
      method: 'POST',
      headers,
      body: JSON.stringify(chunk),
    });
    if (!res.ok) {
      const txt = await res.text().catch(() => '');
      throw new Error(`upsert ${table} ${res.status}: ${txt.slice(0, 200)}`);
    }
  }
  return rows.length;
}

async function getState(key) {
  const res = await fetch(`${MIRROR_URL}/rest/v1/settings?id=eq.backfill_state&limit=1`, {
    headers: { apikey: key, Authorization: `Bearer ${key}` },
  });
  if (!res.ok) throw new Error(`state fetch ${res.status}`);
  const rows = await res.json();
  return rows?.[0]?.data || {};
}

async function setState(key, data) {
  await fetch(`${MIRROR_URL}/rest/v1/settings?on_conflict=id`, {
    method: 'POST',
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
      Prefer: 'resolution=merge-duplicates',
    },
    body: JSON.stringify({ id: 'backfill_state', data: sanitize(data) }),
  });
}

let saJson = null;
function getAdmin() {
  if (admin.apps.length) return admin;
  const base64 = process.env.FIREBASE_SA_BASE64;
  if (base64) saJson = JSON.parse(Buffer.from(base64, 'base64').toString('utf8'));
  else saJson = JSON.parse(fs.readFileSync(process.env.FIREBASE_SA_PATH || path.join(os.homedir(), 'ddd', 'prepora-c2d23-firebase-adminsdk-fbsvc-abc12817e5.json'), 'utf8'));
  return admin.initializeApp({ credential: admin.credential.cert(saJson) });
}

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  if (req.method === 'OPTIONS') return res.status(200).end();

  try {
    const db = getAdmin().firestore();
    const key = await getServiceRoleKey();
    const state = await getState(key);
    const now = Date.now();

    // Done marker: skip for 6h after a full pass.
    if (state.lastCompletedAt && now - new Date(state.lastCompletedAt).getTime() < 6 * 3600 * 1000) {
      return res.status(200).json({ ok: true, skipped: true });
    }

    // Process as many tables as fit in the invocation time budget (serverless
    // functions have short time limits). State resumes on the next run.
    const BUDGET_MS = 8000;
    const startedAt = Date.now();
    const processed = [];

    while (Date.now() - startedAt < BUDGET_MS) {
      let idx = Math.max(0, Math.min(state.tableIndex || 0, TABLE_ORDER.length - 1));
      if (idx >= TABLE_ORDER.length) {
        state.lastCompletedAt = new Date().toISOString();
        state.tableIndex = 0;
        state.contentsCursor = null;
        await setState(key, state);
        processed.push('DONE');
        break;
      }
      const table = TABLE_ORDER[idx];

      if (table === 'contents') {
        // Chunked by createdAt cursor.
        const cursor = state.contentsCursor || null;
        let q = db.collectionGroup('contents').orderBy('createdAt', 'desc').limit(1000);
        if (cursor) q = q.startAfter(cursor);
        const snap = await q.get();
        const rows = snap.docs.map((d) => {
          const segs = d.ref.path.split('/');
          const extra = {};
          const i = segs.indexOf('contents');
          if (i >= 1) extra.folderId = segs[i - 1];
          return buildRow('contents', d.id, d.data(), extra);
        });
        if (rows.length > 0) await upsertRows('contents', rows, key);
        const last = snap.docs.length > 0 ? snap.docs[snap.docs.length - 1] : null;
        const lastTs = last ? last.get('createdAt') : null;
        if (rows.length >= 1000 && lastTs) {
          // More chunks remain.
          state.contentsCursor = lastTs instanceof admin.firestore.Timestamp ? lastTs.toDate() : lastTs;
        } else {
          state.tableIndex = idx + 1;
          state.contentsCursor = null;
        }
        processed.push(`${table}:${rows.length}`);
      } else {
        const snap = await db.collection(table).limit(100000).get();
        const rows = snap.docs.map((d) => buildRow(table, d.id, d.data()));
        if (rows.length > 0) await upsertRows(table, rows, key);
        state.tableIndex = idx + 1;
        processed.push(`${table}:${rows.length}`);
      }

      await setState(key, state);
    }

    return res.status(200).json({ ok: true, processed, tableIndex: state.tableIndex || 0, final: !!(state.lastCompletedAt) });
  } catch (err) {
    // Likely RESOURCE_EXHAUSTED while the quota is blocked; leave state as-is.
    console.error('[backfill] Error:', err.code || '', err.message.slice(0, 200));
    return res.status(200).json({ ok: false, error: String(err.code || err.message).slice(0, 120) });
  }
};