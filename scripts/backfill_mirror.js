// Backfill: Firestore -> READ-MIRROR Supabase (one-time sync)
// Reads every mirrored collection from Firestore and upserts into Supabase.
// Requires reads to be unblocked (Firestore quota). Writes via service_role
// key fetched from settings/read_mirror (bypasses RLS).
//
// Usage: node backfill_mirror.js [--only ai_api_keys,settings]

const admin = require('firebase-admin');
const path = require('path');

const SA_PATH = 'E:/ddd/prepora-c2d23-firebase-adminsdk-fbsvc-abc12817e5.json';
const MIRROR_URL = 'https://qluwnxsmnxvvqoiejtbr.supabase.co';
const MIRROR_ANON =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFsdXdueHNtbnh2dnFvaWVqdGJyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcwMDAzNTEsImV4cCI6MjEwMjU3NjM1MX0.lYGxH02Kb0qS2Lm46Mc5lQoOyd7VR1-6WWSBA2TXfr8';

// Map Firestore field -> Supabase column. Data is ALSO stored whole in `data` jsonb.
const COLUMN_MAP = {
  users: ['role', 'email', 'name', 'blocked', 'verified', 'freeTrialActive'],
  folders: ['name', 'locked', 'invisible', 'updating', 'groupLink', 'inheritGroup'],
  contents: ['folderId', 'parentContentId', 'name', 'title', 'type', 'url', 'youtubeUrl', 'groupLink', 'locked', 'invisible', 'updating', 'order'],
  web_sessions: ['sessionId', 'uid', 'status', 'webBrowser', 'userEmail', 'userRole', 'androidDeviceId'],
  login_attempts: ['uid', 'deviceId', 'deviceModel', 'timestamp'],
  notifications: ['uid', 'read', 'message', 'userName', 'type'],
  admin_notifications: ['read', 'message', 'type'],
  notices: ['title', 'fileType', 'addedBy'],
  feedbacks: ['uid', 'status', 'viewed', 'message', 'reply'],
  settings: ['paidAccess', 'price'],
  app_updates: ['version', 'link'],
  student_activities: ['uid', 'startedAt'],
  assistant_access: ['uid', 'folderId'],
  content_assistant_access: ['userId', 'folderId', 'contentId'],
  assistant_logins: ['folderId', 'uid', 'name', 'timestamp'],
  login_history: ['uid', 'device', 'ip', 'timestamp'],
  ai_api_keys: ['apiKey', 'baseUrl', 'model', 'provider', 'isActive'],
  notes: ['uid', 'content', 'lectureName', 'updatedAt'],
  conversations: ['uid', 'title', 'lastMessage', 'updatedAt'],
  messages: ['conversationId', 'role', 'content', 'timestamp'],
};

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
  for (const f of COLUMN_MAP[table] || []) {
    let v = data?.[f];
    if ((v === undefined || v === null) && extra?.[f] !== undefined) v = extra[f];
    const col = CAMEL_TO_COL[f] || f;
    row[col] = (v === undefined || v === null)
      ? null
      : (v instanceof admin.firestore.Timestamp ? v.toDate().toISOString() : v);
  }
  return row;
}

let serviceRoleKey = null;
async function getServiceRoleKey() {
  if (serviceRoleKey) return serviceRoleKey;
  const res = await fetch(`${MIRROR_URL}/rest/v1/settings?id=eq.read_mirror&limit=1`, {
    headers: { apikey: MIRROR_ANON, Authorization: `Bearer ${MIRROR_ANON}` },
  });
  if (!res.ok) throw new Error(`read_mirror fetch ${res.status}`);
  const rows = await res.json();
  serviceRoleKey = rows?.[0]?.data?.serviceRoleKey;
  if (!serviceRoleKey) throw new Error('service role key not found in read_mirror');
  return serviceRoleKey;
}

async function upsertRows(table, rows) {
  const key = await getServiceRoleKey();
  const headers = {
    apikey: key,
    Authorization: `Bearer ${key}`,
    'Content-Type': 'application/json',
    Prefer: 'resolution=merge-duplicates',
  };
  // Batch upsert (max 1000 rows per request)
  for (let i = 0; i < rows.length; i += 500) {
    const chunk = rows.slice(i, i + 500);
    const res = await fetch(`${MIRROR_URL}/rest/v1/${table}?on_conflict=id`, {
      method: 'POST',
      headers,
      body: JSON.stringify(chunk),
    });
    if (!res.ok) {
      const txt = await res.text().catch(() => '');
      throw new Error(`upsert ${table} ${res.status}: ${txt.slice(0, 300)}`);
    }
    console.log(`  upserted ${table} chunk ${i + 1}-${i + chunk.length}/${rows.length}`);
  }
}

// ---- Read budget tracking (Firestore read quota) ----
let totalReads = 0;
let READ_BUDGET = 9000; // default = 18% of 50k daily reads
const budgetArg = process.argv.find((a) => a.startsWith('--budget='));
if (budgetArg) READ_BUDGET = parseInt(budgetArg.split('=')[1], 10) || READ_BUDGET;

function markReads(n) {
  totalReads += n;
  console.log(`  [reads so far: ${totalReads}/${READ_BUDGET}]`);
  return totalReads >= READ_BUDGET;
}

async function readAndMirror(collection, table, maxDocs = 100000) {
  console.log(`\n[${table}] reading ${collection}...`);
  const snap = await admin.firestore().collection(collection).limit(maxDocs).get();
  const rows = snap.docs.map((d) => buildRow(table, d.id, d.data()));
  const budgetHit = markReads(rows.length);
  if (rows.length === 0) { console.log(`  empty`); return false; }
  await upsertRows(table, rows);
  console.log(`  done: ${rows.length}`);
  return budgetHit;
}

async function readAndMirrorSub(collection, table) {
  console.log(`\n[${table}] reading collectionGroup ${collection}...`);
  const snap = await admin.firestore().collectionGroup(collection).limit(100000).get();
  const rows = snap.docs.map((d) => {
    const segs = d.ref.path.split('/');
    const extra = {};
    if (table === 'conversations' || table === 'notes') {
      const i = segs.indexOf(table === 'conversations' ? 'conversations' : 'notes');
      if (i >= 1) extra.uid = segs[i - 1];
    } else if (table === 'messages') {
      const i = segs.indexOf('messages');
      if (i >= 1) extra.conversationId = segs[i - 1];
    } else if (table === 'contents') {
      const i = segs.indexOf('contents');
      if (i >= 1) extra.folderId = segs[i - 1];
    }
    return buildRow(table, d.id, d.data(), extra);
  });
  const budgetHit = markReads(rows.length);
  if (rows.length === 0) { console.log(`  empty`); return false; }
  await upsertRows(table, rows);
  console.log(`  done: ${rows.length}`);
  return budgetHit;
}

const TOP_LEVEL = [
  ['users', 'users'],
  ['folders', 'folders'],
  ['web_sessions', 'web_sessions'],
  ['login_attempts', 'login_attempts'],
  ['notifications', 'notifications'],
  ['admin_notifications', 'admin_notifications'],
  ['notices', 'notices'],
  ['feedbacks', 'feedbacks'],
  ['settings', 'settings'],
  ['app_updates', 'app_updates'],
  ['student_activities', 'student_activities'],
  ['Assistant_access', 'assistant_access'],
  ['content_Assistant_access', 'content_assistant_access'],
  ['Assistant_logins', 'assistant_logins'],
  ['login_history', 'login_history'],
  ['ai_api_keys', 'ai_api_keys'],
];

const SUB_COLLECTIONS = [
  ['notes', 'notes'],
  ['conversations', 'conversations'],
  ['messages', 'messages'],
  ['logins', 'login_history'],
  ['contents', 'contents'],
];

async function main() {
  admin.initializeApp({ credential: admin.credential.cert(SA_PATH) });

  const onlyArg = process.argv.find((a) => a.startsWith('--only='));
  const only = onlyArg ? onlyArg.split('=')[1].split(',').map((s) => s.trim()).filter(Boolean) : null;

  for (const [collection, table] of TOP_LEVEL) {
    if (only && !only.includes(table)) continue;
    if (totalReads >= READ_BUDGET) { console.log(`\nREAD BUDGET REACHED (${totalReads}/${READ_BUDGET}) - stopping`); break; }
    try { const hit = await readAndMirror(collection, table); if (hit) break; } catch (e) { console.error(`FAILED ${table}:`, e.message); }
  }

  for (const [collection, table] of SUB_COLLECTIONS) {
    if (only && !only.includes(table)) continue;
    if (totalReads >= READ_BUDGET) { console.log(`\nREAD BUDGET REACHED (${totalReads}/${READ_BUDGET}) - stopping`); break; }
    try { const hit = await readAndMirrorSub(collection, table); if (hit) break; } catch (e) { console.error(`FAILED ${table}:`, e.message); }
  }

  console.log(`\nDone. Total Firestore reads used: ${totalReads}/${READ_BUDGET}`);
  process.exit(0);
}

main().catch((e) => { console.error('Fatal:', e); process.exit(1); });