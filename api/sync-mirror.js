// /api/sync-mirror.js
// Mirrors a single Firestore document into the READ-MIRROR Supabase.
// The service-role key is read from the mirror's own `settings/read_mirror`
// row (no new Vercel env vars needed). Writes to Firestore remain the source
// of truth; this keeps the mirror fresh for quota-free reads.
//
// POST body: { table, id, data, isActive, delete }
//   table   - mirror table name (ai_api_keys, settings, web_sessions, users, ...)
//   id      - document id
//   data    - full document map
//   isActive- (optional) if set and false, deactivates the row instead.
//   delete  - (optional) if true, removes the row from the mirror entirely.

const MIRROR_URL = 'https://qluwnxsmnxvvqoiejtbr.supabase.co';
const MIRROR_ANON =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFsdXdueHNtbnh2dnFvaWVqdGJyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcwMDAzNTEsImV4cCI6MjEwMjU3NjM1MX0.lYGxH02Kb0qS2Lm46Mc5lQoOyd7VR1-6WWSBA2TXfr8';

const SAFE_TABLES = new Set([
  'users', 'folders', 'contents', 'web_sessions', 'login_attempts',
  'notifications', 'admin_notifications', 'notices', 'feedbacks', 'settings',
  'app_updates', 'student_activities', 'assistant_access',
  'content_assistant_access', 'assistant_logins', 'login_history',
  'ai_api_keys', 'notes', 'conversations', 'messages',
]);

async function getServiceRoleKey() {
  const res = await fetch(`${MIRROR_URL}/rest/v1/settings?id=eq.read_mirror&limit=1`, {
    headers: {
      apikey: MIRROR_ANON,
      Authorization: `Bearer ${MIRROR_ANON}`,
    },
  });
  if (!res.ok) throw new Error(`read_mirror fetch ${res.status}`);
  const rows = await res.json();
  const data = rows?.[0]?.data || {};
  return data.serviceRoleKey || null;
}

async function buildRow(table, id, data) {
  const row = { id, data: data || {} };
  const assign = (col, field) => {
    const v = data?.[field];
    if (v !== undefined && v !== null) row[col] = v;
  };
  switch (table) {
    case 'ai_api_keys':
      assign('api_key', 'apiKey');
      assign('base_url', 'baseUrl');
      assign('model', 'model');
      assign('provider', 'provider');
      assign('is_active', 'isActive');
      break;
    case 'settings':
      assign('paid_access', 'paidAccess');
      assign('price', 'price');
      break;
    case 'users':
      assign('role', 'role');
      assign('email', 'email');
      assign('name', 'name');
      assign('blocked', 'blocked');
      assign('verified', 'verified');
      assign('free_trial_active', 'freeTrialActive');
      break;
    case 'web_sessions':
      assign('session_id', 'sessionId');
      assign('uid', 'uid');
      assign('status', 'status');
      assign('web_browser', 'webBrowser');
      assign('user_email', 'userEmail');
      assign('user_role', 'userRole');
      assign('android_device_id', 'androidDeviceId');
      break;
    case 'contents':
      assign('folder_id', 'folderId');
      assign('parent_content_id', 'parentContentId');
      assign('name', 'name');
      assign('title', 'title');
      assign('type', 'type');
      assign('url', 'url');
      assign('group_link', 'groupLink');
      break;
    case 'folders':
      assign('name', 'name');
      assign('group_link', 'groupLink');
      break;
    case 'notes':
      assign('uid', 'uid');
      assign('content', 'content');
      assign('lecture_name', 'lectureName');
      assign('updated_at', 'updatedAt');
      break;
    case 'conversations':
      assign('uid', 'uid');
      assign('title', 'title');
      assign('last_message', 'lastMessage');
      assign('updated_at', 'updatedAt');
      break;
    case 'messages':
      assign('conversation_id', 'conversationId');
      assign('role', 'role');
      assign('content', 'content');
      assign('timestamp', 'timestamp');
      break;
    case 'notifications':
      assign('uid', 'uid');
      assign('read', 'read');
      assign('message', 'message');
      assign('user_name', 'userName');
      assign('type', 'type');
      break;
    case 'feedbacks':
      assign('uid', 'uid');
      assign('status', 'status');
      assign('viewed', 'viewed');
      assign('message', 'message');
      assign('reply', 'reply');
      break;
    case 'assistant_access':
      assign('uid', 'uid');
      assign('folder_id', 'folderId');
      break;
    case 'content_assistant_access':
      assign('user_id', 'userId');
      assign('folder_id', 'folderId');
      assign('content_id', 'contentId');
      break;
    case 'assistant_logins':
      assign('folder_id', 'folderId');
      assign('uid', 'uid');
      assign('name', 'name');
      assign('timestamp', 'timestamp');
      break;
    case 'student_activities':
      assign('uid', 'uid');
      assign('started_at', 'startedAt');
      break;
    case 'login_history':
      assign('uid', 'uid');
      assign('device', 'device');
      assign('ip', 'ip');
      assign('timestamp', 'timestamp');
      break;
    case 'login_attempts':
      assign('uid', 'uid');
      assign('device_id', 'deviceId');
      assign('device_model', 'deviceModel');
      assign('timestamp', 'timestamp');
      break;
    case 'app_updates':
      assign('version', 'version');
      assign('link', 'link');
      break;
    case 'notices':
      assign('title', 'title');
      assign('file_type', 'fileType');
      assign('added_by', 'addedBy');
      break;
    case 'admin_notifications':
      assign('read', 'read');
      assign('message', 'message');
      assign('type', 'type');
      break;
    default:
      break;
  }
  return row;
}

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  try {
    const { table, id, data, isActive, delete: deleteRow } = req.body || {};
    if (!table || !id) return res.status(400).json({ error: 'table and id required' });
    if (!SAFE_TABLES.has(table)) return res.status(400).json({ error: `table ${table} not allowed` });

    const serviceRoleKey = await getServiceRoleKey();
    if (!serviceRoleKey) return res.status(500).json({ error: 'read_mirror service role key missing' });

    const headers = {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      'Content-Type': 'application/json',
      Prefer: 'resolution=merge-duplicates',
    };

    let out;
    if (deleteRow === true) {
      const r = await fetch(`${MIRROR_URL}/rest/v1/${table}?id=eq.${encodeURIComponent(id)}`, {
        method: 'DELETE',
        headers: { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}` },
      });
      if (!r.ok && r.status !== 404) return res.status(502).json({ error: `mirror delete ${r.status}` });
      out = { ok: true, action: 'delete', id };
    } else if (isActive === false) {
      const r = await fetch(`${MIRROR_URL}/rest/v1/${table}?id=eq.${encodeURIComponent(id)}`, {
        method: 'PATCH',
        headers: { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}` },
        body: JSON.stringify({ is_active: false }),
      });
      if (!r.ok) return res.status(502).json({ error: `mirror patch ${r.status}`, detail: await r.text().catch(() => '') });
      out = { ok: true, action: 'deactivate', id };
    } else {
      const row = await buildRow(table, id, data);
      if (table === 'ai_api_keys' && isActive !== undefined && isActive !== null) {
        row.is_active = isActive;
      }
      if (table === 'ai_api_keys' && row.is_active === true) {
        const r = await fetch(`${MIRROR_URL}/rest/v1/${table}?id=neq.${encodeURIComponent(id)}`, {
          method: 'PATCH',
          headers: { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}` },
          body: JSON.stringify({ is_active: false }),
        });
        if (!r.ok) return res.status(502).json({ error: `mirror deactivate-others ${r.status}` });
      }
      const r = await fetch(`${MIRROR_URL}/rest/v1/${table}?on_conflict=id`, {
        method: 'POST',
        headers,
        body: JSON.stringify(row),
      });
      if (!r.ok) return res.status(502).json({ error: `mirror upsert ${r.status}`, detail: await r.text().catch(() => '') });
      out = { ok: true, action: 'upsert', id };
    }

    return res.status(200).json(out);
  } catch (err) {
    console.error('[sync-mirror] Error:', err.message);
    return res.status(500).json({ error: 'Internal error', detail: err.message });
  }
};
