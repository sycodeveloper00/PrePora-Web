/**
 * PrePora — Expire Free Trial (Supabase version)
 * Verifies the caller's Firebase ID token, then if their free trial has expired,
 * flips the global settings/general.paidAccess ON and clears their trial flag.
 * No Firestore dependency — uses Supabase for all data operations.
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
  console.log('[expire-trial] Request received:', req.method);
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  try {
    const { idToken } = req.body;
    if (!idToken) return res.status(400).json({ error: 'idToken required' });

    const decoded = await admin.auth().verifyIdToken(idToken);
    const uid = decoded.uid;
    const now = Date.now();

    // Read user from Supabase
    const { data: user, error: userError } = await supabase
      .from('users')
      .select('id, free_trial_active, free_trial_ends_at, data')
      .eq('id', uid)
      .single();

    if (userError || !user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Check free trial status
    const trialActive = user.free_trial_active === true;
    const endsAt = user.free_trial_ends_at;
    const endMs = endsAt ? new Date(endsAt).getTime() : null;

    if (trialActive && endMs !== null && endMs <= now) {
      // Trial has expired — flip paidAccess ON and clear trial flag

      // Update settings: paidAccess = true
      const { data: settings } = await supabase
        .from('settings')
        .select('data')
        .eq('id', 'general')
        .single();

      const settingsData = settings?.data || {};
      settingsData.paidAccess = true;

      await supabase
        .from('settings')
        .upsert({
          id: 'general',
          data: settingsData,
        }, { onConflict: 'id' });

      // Update user: clear trial flag
      const userData = user.data || {};
      userData.freeTrialActive = false;

      await supabase
        .from('users')
        .update({
          free_trial_active: false,
          data: userData,
        })
        .eq('id', uid);

      console.log('[expire-trial] Trial expired for uid:', uid, '- paidAccess ON');
      return res.status(200).json({ flipped: true });
    }

    return res.status(200).json({ flipped: false });
  } catch (err) {
    console.error('[expire-trial] ERROR:', err.message);
    if (err.code === 'auth/id-token-expired' || err.code === 'auth/argument-error') {
      return res.status(401).json({ error: 'Invalid or expired session token' });
    }
    return res.status(500).json({ error: err.message });
  }
};

