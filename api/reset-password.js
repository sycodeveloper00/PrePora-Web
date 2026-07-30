const admin = require('firebase-admin');
const serviceAccount = JSON.parse(Buffer.from(process.env.FIREBASE_SA_BASE64, 'base64').toString('utf8'));

if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}

const db = admin.firestore();

async function findTokenDoc(token) {
  const snap = await db.collection('password_resets')
    .where('token', '==', token).limit(1).get();
  if (snap.empty) return null;
  const doc = snap.docs[0];
  return { docId: doc.id, ...doc.data() };
}

async function markTokenUsed(docId) {
  await db.collection('password_resets').doc(docId).update({ used: true });
}

async function deleteResetTokens(uid) {
  const snap = await db.collection('password_resets').where('uid', '==', uid).get();
  for (const doc of snap.docs) {
    await doc.ref.delete();
  }
}

module.exports = async function handler(req, res) {
  console.log('[reset-password] Request received:', req.method);
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  try {
    const { token, newPassword, email } = req.body;
    console.log('[reset-password] Body:', { token: token?.substring(0, 10) + '...', email, pwLength: newPassword?.length });
    if (!token || !newPassword || !email) {
      return res.status(400).json({ error: 'Token, email, and newPassword required' });
    }
    if (newPassword.length < 6) {
      return res.status(400).json({ error: 'Password must be at least 6 characters' });
    }

    const tokenDoc = await findTokenDoc(token);
    if (!tokenDoc) {
      console.log('[reset-password] Token NOT found');
      return res.status(400).json({ error: 'Invalid reset token' });
    }
    if (tokenDoc.used) {
      console.log('[reset-password] Token already used');
      return res.status(400).json({ error: 'This reset link has already been used' });
    }
    if (Date.now() > (tokenDoc.expiry || 0)) {
      console.log('[reset-password] Token expired');
      return res.status(400).json({ error: 'This reset link has expired' });
    }

    const uid = tokenDoc.uid;
    console.log('[reset-password] Updating password for uid:', uid);
    await admin.auth().updateUser(uid, { password: newPassword });
    await markTokenUsed(tokenDoc.docId);
    await deleteResetTokens(uid);
    console.log('[reset-password] Password reset SUCCESS');

    return res.status(200).json({ success: true, message: 'Password reset successfully' });
  } catch (err) {
    console.error('[reset-password] ERROR:', err.message);
    if (err.code === 'auth/user-not-found') {
      return res.status(400).json({ error: 'User account not found' });
    }
    return res.status(500).json({ error: err.message });
  }
};
