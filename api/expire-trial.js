/**
 * PrePora — Expire Free Trial (serverless, free-tier alternative to Cloud Functions)
 * Verifies the caller's Firebase ID token, then if their free trial has expired,
 * flips the global settings/general.paidAccess ON and clears their trial flag.
 */
const admin = require('firebase-admin');
const serviceAccount = JSON.parse(Buffer.from(process.env.FIREBASE_SA_BASE64, 'base64').toString('utf8'));

if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}

const db = admin.firestore();

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

    const userRef = db.collection('users').doc(uid);
    const userDoc = await userRef.get();
    if (!userDoc.exists) return res.status(404).json({ error: 'User not found' });

    const data = userDoc.data() || {};
    const endsAt = data.freeTrialEndsAt;
    const endMs = endsAt && endsAt.toMillis ? endsAt.toMillis() : null;

    if (data.freeTrialActive === true && endMs !== null && endMs <= now) {
      await db.collection('settings').doc('general').set({ paidAccess: true }, { merge: true });
      await userRef.update({ freeTrialActive: false });
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