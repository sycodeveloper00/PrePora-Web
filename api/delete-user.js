/**
 * PrePora — Delete User (serverless, free-tier alternative to Cloud Functions)
 * Verifies caller is an ADMIN via Firebase ID token + users/{uid}.role, then
 * permanently deletes the target user from Firebase Auth.
 */
const admin = require('firebase-admin');
const serviceAccount = JSON.parse(Buffer.from(process.env.FIREBASE_SA_BASE64, 'base64').toString('utf8'));

if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}

const db = admin.firestore();

module.exports = async function handler(req, res) {
  console.log('[delete-user] Request received:', req.method);
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  try {
    const { idToken, uid } = req.body;
    if (!idToken) return res.status(400).json({ error: 'idToken required' });
    if (!uid || typeof uid !== 'string') return res.status(400).json({ error: 'uid required' });

    const decoded = await admin.auth().verifyIdToken(idToken);
    const callerUid = decoded.uid;

    const callerDoc = await db.collection('users').doc(callerUid).get();
    const callerRole = (callerDoc.data() && callerDoc.data().role) || '';
    if (callerRole !== 'admin') {
      return res.status(403).json({ error: 'Only admins can delete users' });
    }

    await admin.auth().deleteUser(uid);
    console.log('[delete-user] Deleted user:', uid);
    return res.status(200).json({ success: true });
  } catch (err) {
    console.error('[delete-user] ERROR:', err.message);
    if (err.code === 'auth/id-token-expired' || err.code === 'auth/argument-error') {
      return res.status(401).json({ error: 'Invalid or expired session token' });
    }
    if (err.code === 'auth/user-not-found') {
      return res.status(404).json({ error: 'User account not found' });
    }
    return res.status(500).json({ error: err.message });
  }
};