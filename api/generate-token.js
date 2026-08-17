const admin = require('firebase-admin');
const serviceAccount = JSON.parse(Buffer.from(process.env.FIREBASE_SA_BASE64, 'base64').toString('utf8'));

if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}

const db = admin.firestore();

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  try {
    const { sessionId } = req.body;
    if (!sessionId) return res.status(400).json({ error: 'sessionId required' });

    const sessionDoc = await db.collection('web_sessions').doc(sessionId).get();
    if (!sessionDoc.exists) return res.status(404).json({ error: 'Session not found' });

    const data = sessionDoc.data();
    if (data.status !== 'connected') return res.status(400).json({ error: 'Session not connected' });

    const uid = data.uid;
    if (!uid) return res.status(400).json({ error: 'No uid in session' });

    const customToken = await admin.auth().createCustomToken(uid);

    return res.status(200).json({ customToken, uid });
  } catch (err) {
    console.error('[generate-token] Error:', err);
    return res.status(500).json({ error: 'Internal error', detail: err.message });
  }
};
