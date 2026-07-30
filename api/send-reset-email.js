const https = require('https');
const crypto = require('crypto');
const admin = require('firebase-admin');
const serviceAccount = JSON.parse(Buffer.from(process.env.FIREBASE_SA_BASE64, 'base64').toString('utf8'));

if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}

const db = admin.firestore();

const BREVO_API_KEY = process.env.BREVO_API_KEY;
const BREVO_API_URL = 'https://api.brevo.com/v3/smtp/email';
const APP_URL = 'https://prepora-passwordreset-bg9dwg9sz-sycodeveloper00.vercel.app';

const EMAIL_HTML = `
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"></head>
<body style="margin:0;padding:0;background-color:#0D0221;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background-color:#0D0221;padding:40px 20px;">
<tr><td align="center">
<table width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;">
<tr><td align="center" style="padding:30px 0 10px 0;">
<table cellpadding="0" cellspacing="0"><tr>
<td style="background:linear-gradient(135deg,#7B2FF7,#C084FC);border-radius:16px;padding:14px 24px;">
<span style="font-size:28px;font-weight:800;color:#FFFFFF;letter-spacing:2px;">PrePora</span>
</td></tr></table>
</td></tr>
<tr><td align="center" style="padding:10px 40px 30px 40px;">
<table width="100%"><tr><td style="border-top:1px solid rgba(123,47,247,0.3);"></td></tr></table>
</td></tr>
<tr><td style="padding:0 20px;">
<table width="100%" style="background:linear-gradient(145deg,rgba(123,47,247,0.15),rgba(30,10,60,0.9));border:1px solid rgba(123,47,247,0.25);border-radius:20px;overflow:hidden;">
<tr><td style="background:linear-gradient(90deg,#7B2FF7,#C084FC);height:4px;"></td></tr>
<tr><td style="padding:45px 40px 20px 40px;">
<table width="100%">
<tr><td align="center" style="padding-bottom:25px;">
<table cellpadding="0" cellspacing="0"><tr>
<td style="background:rgba(123,47,247,0.2);border-radius:50%;width:70px;height:70px;text-align:center;vertical-align:middle;">
<span style="font-size:32px;line-height:70px;">&#128274;</span>
</td></tr></table>
</td></tr>
<tr><td align="center" style="padding-bottom:15px;">
<span style="font-size:26px;font-weight:700;color:#FFFFFF;">Reset Your Password</span>
</td></tr>
<tr><td align="center" style="padding-bottom:30px;">
<span style="font-size:15px;color:#B8A9D4;line-height:1.7;">
Hi <strong style="color:#C084FC;">{{user_name}}</strong>,<br><br>
We received a request to reset the password for your PrePora account.<br>
Click the button below to create a new password.
</span>
</td></tr>
<tr><td align="center" style="padding-bottom:35px;">
<table cellpadding="0" cellspacing="0" style="margin:0 auto;"><tr>
<td align="center" style="background:linear-gradient(135deg,#00C853,#00E676);border-radius:14px;box-shadow:0 4px 20px rgba(0,200,83,0.4);">
<a href="{{reset_link}}" target="_blank" style="display:inline-block;padding:22px 80px;font-size:20px;font-weight:800;color:#FFFFFF;text-decoration:none;letter-spacing:1px;font-family:'Segoe UI',Roboto,sans-serif;">
&#128274; Reset My Password
</a>
</td></tr></table>
</td></tr>
<tr><td align="center" style="padding-bottom:20px;">
<table style="background:rgba(255,193,7,0.1);border:1px solid rgba(255,193,7,0.25);border-radius:10px;">
<tr><td style="padding:12px 20px;">
<span style="font-size:13px;color:#FFC107;">
&#9200; This link expires in <strong>15 minutes</strong>. If you didn't request this, ignore this email.
</span>
</td></tr></table>
</td></tr>
</table>
</td></tr></table>
</td></tr>
<tr><td style="padding:25px 40px;">
<table width="100%" style="background:rgba(123,47,247,0.08);border:1px solid rgba(123,47,247,0.15);border-radius:12px;">
<tr><td style="padding:18px 22px;">
<span style="font-size:13px;color:#9B8ABF;line-height:1.6;">
&#128737; <strong style="color:#C084FC;">Security Tip:</strong> Never share your password with anyone. PrePora will never ask for your password via email.
</span>
</td></tr></table>
</td></tr>
<tr><td style="padding:0 40px 15px 40px;">
<table width="100%" style="background:rgba(0,184,212,0.08);border:1px solid rgba(0,184,212,0.2);border-radius:12px;">
<tr><td style="padding:14px 20px;">
<span style="font-size:13px;color:#00B8D4;line-height:1.6;">
&#128712; <strong>Check your Spam/Junk folder</strong> if you don't see this email in your inbox. Mark it as "Not Spam" to receive future emails in your inbox.
</span>
</td></tr></table>
</td></tr>
<tr><td align="center" style="padding:20px 30px 10px 30px;">
<span style="font-size:12px;color:#5A4A7A;">This email was sent to <strong style="color:#8B7AB8;">{{user_email}}</strong></span>
</td></tr>
<tr><td align="center" style="padding:5px 30px 15px 30px;">
<span style="font-size:11px;color:#3D2E5C;line-height:1.5;">PrePora &mdash; Smart Learning Platform<br>&copy; 2026 PrePora. All rights reserved.</span>
</td></tr>
<tr><td align="center" style="padding:0 30px 25px 30px;">
<span style="font-size:10px;color:#2A1E45;line-height:1.5;">This is a system generated email. Please do not reply to this email.</span>
</td></tr>
</table>
</td></tr></table>
</body></html>
`;

function httpsReq(method, fullUrl, headers = {}, body = null) {
  return new Promise((resolve, reject) => {
    const u = new URL(fullUrl);
    const opts = { hostname: u.hostname, port: u.port || 443, path: u.pathname + u.search, method, headers };
    if (body) opts.headers['Content-Type'] = 'application/json';
    const req = https.request(opts, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function findUserByEmail(email) {
  try {
    const userRecord = await admin.auth().getUserByEmail(email);
    return { uid: userRecord.uid, name: userRecord.displayName || email.split('@')[0] };
  } catch (e) {
    return null;
  }
}

async function storeResetToken(uid, token) {
  const expiry = Date.now() + 15 * 60 * 1000;
  await db.collection('password_resets').add({
    uid,
    token,
    expiry,
    used: false,
    createdAt: Date.now()
  });
}

async function sendBrevoEmail(toEmail, userName, resetLink) {
  const htmlContent = EMAIL_HTML
    .replace(/\{\{user_name\}\}/g, userName)
    .replace(/\{\{user_email\}\}/g, toEmail)
    .replace(/\{\{reset_link\}\}/g, resetLink);

  const payload = JSON.stringify({
    sender: { name: 'PrePora', email: 'prepora@hotmail.com' },
    to: [{ email: toEmail }],
    subject: 'Reset Your PrePora Password',
    htmlContent,
  });

  return httpsReq('POST', BREVO_API_URL, {
    'Content-Type': 'application/json',
    'api-key': BREVO_API_KEY,
  }, JSON.parse(payload));
}

module.exports = async function handler(req, res) {
  console.log('[send-reset-email] Request:', req.method);
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  try {
    const { email } = req.body;
    if (!email) return res.status(400).json({ error: 'Email required' });

    const user = await findUserByEmail(email);
    console.log('[send-reset-email] user:', JSON.stringify(user));

    if (!user) {
      return res.status(200).json({ success: true, message: 'If an account exists, a reset email has been sent.' });
    }

    const token = crypto.randomBytes(32).toString('hex');
    console.log('[send-reset-email] Storing token for uid:', user.uid);
    await storeResetToken(user.uid, token);

    const resetLink = `${APP_URL}/auth/reset-password?token=${token}`;
    const brevoResult = await sendBrevoEmail(email, user.name, resetLink);

    if (brevoResult.status >= 200 && brevoResult.status < 300) {
      return res.status(200).json({ success: true, message: 'If an account exists, a reset email has been sent.' });
    } else {
      return res.status(200).json({ success: false, message: 'Failed to send email' });
    }
  } catch (err) {
    console.error('[send-reset-email] ERROR:', err.message);
    return res.status(500).json({ error: err.message });
  }
};
