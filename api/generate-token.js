/**
 * PrePora — Generate Custom Token (Supabase version)
 * Verifies the web session exists in Supabase, then creates a Firebase custom token.
 * No Firestore dependency — uses Supabase for session verification.
 */
const admin = require('firebase-admin');
const serviceAccount = JSON.parse(Buffer.from(process.env.FIREBASE_SA_BASE64, 'base64').toString('utf8'));

if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}

const { createClient } = require('@supabase/supabase-js');
const supabase = createClient(
  process.env.SUPABASE_URL || 'https://brqdxhqrsfxlvwgstuto.supabase.co',
  process.env.SUPABASE_SERVICE_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJycWR4aHFyc2Z4bHZ3Z3N0dXRvIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NzE1NjgzMywiZXhwIjoyMTAyNzMyODMzfQ.gPkiuNGYAP_pJR1uSbAQWc25SyhmpwwgspJeFInXgWE'
);

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  try {
    const { sessionId, uid: clientUid } = req.body;
    if (!sessionId) return res.status(400).json({ error: 'sessionId required' });

    let uid = clientUid;

    // If client didn't send uid, verify session from Supabase
    if (!uid) {
      try {
        const { data: session, error } = await supabase
          .from('web_sessions')
          .select('status, uid')
          .eq('id', sessionId)
          .single();

        if (error || !session) {
          return res.status(404).json({ error: 'Session not found' });
        }
        if (session.status !== 'connected') {
          return res.status(400).json({ error: 'Session not connected' });
        }
        uid = session.uid;
      } catch (sbErr) {
        console.warn('[generate-token] Supabase read failed:', sbErr.message);
        return res.status(503).json({ error: 'Service temporarily unavailable' });
      }
    }

    if (!uid) return res.status(400).json({ error: 'No uid provided or in session' });

    const customToken = await admin.auth().createCustomToken(uid);

    return res.status(200).json({ customToken, uid });
  } catch (err) {
    console.error('[generate-token] Error:', err);
    return res.status(500).json({ error: 'Internal error', detail: err.message });
  }
};

