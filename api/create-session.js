/**
 * PrePora — Create Web Session
 * Creates a new web session record for QR code linking in BOTH
 * Firestore (so Android can find it instantly) AND Supabase mirror.
 */
const crypto = require('crypto');
const admin = require('firebase-admin');
const { createClient } = require('@supabase/supabase-js');
const supabase = createClient(
  process.env.SUPABASE_URL || 'https://brqdxhqrsfxlvwgstuto.supabase.co',
  process.env.SUPABASE_SERVICE_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJycWR4aHFyc2Z4bHZ3Z3N0dXRvIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NzE1NjgzMywiZXhwIjoyMTAyNzMyODMzfQ.gPkiuNGYAP_pJR1uSbAQWc25SyhmpwwgspJeFInXgWE'
);

if (!admin.apps.length) {
  const sa = JSON.parse(Buffer.from(process.env.FIREBASE_SA_BASE64, 'base64').toString('utf8'));
  admin.initializeApp({ credential: admin.credential.cert(sa) });
}
const db = admin.firestore();

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  try {
    const sessionId = 'web-' + crypto.randomBytes(32).toString('hex');
    const now = new Date().toISOString();
    const ts = admin.firestore.FieldValue.serverTimestamp();

    // Write to BOTH Firestore AND Supabase so Android can find it in either
    const firestorePromise = db.collection('web_sessions').doc(sessionId).set({
      status: 'waiting',
      createdAt: ts,
      connectedAt: ts,
      lastActive: ts,
    });

    const supabasePromise = supabase
      .from('web_sessions')
      .upsert({
        id: sessionId,
        status: 'waiting',
        created_at: now,
        connected_at: now,
        last_active: now,
        data: { status: 'waiting', createdAt: now },
      }, { onConflict: 'id' });

    const [fsResult, sbResult] = await Promise.allSettled([firestorePromise, supabasePromise]);

    if (fsResult.status === 'rejected') {
      console.error('[create-session] Firestore write failed:', fsResult.reason?.message || fsResult.reason);
    }
    if (sbResult.status === 'rejected') {
      console.error('[create-session] Supabase write failed:', sbResult.reason?.message || sbResult.reason);
    } else if (sbResult.value?.error) {
      console.error('[create-session] Supabase error:', sbResult.value.error.message);
    }

    return res.status(200).json({ sessionId });
  } catch (err) {
    console.error('[create-session] Error:', err);
    return res.status(500).json({ error: 'Failed to create session', detail: err.message });
  }
};

