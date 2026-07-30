# PrePora — OTP Password Reset with Brevo (Complete Guide)

## Overview
Build an OTP-based password reset system using:
- **Firebase Authentication** (existing accounts — no changes)
- **Brevo** (free email service — send OTP emails)
- **Cloud Functions** (generate OTP, send email, verify OTP, reset password)
- **Flutter app** (OTP input screen)

## Flow
```
1. User taps "Forgot Password"
2. User enters email → App calls Cloud Function: "sendOtp"
3. Cloud Function:
   a. Verify email exists in Firebase Auth
   b. Generate 6-digit OTP
   c. Save OTP to Firestore (with 10-min expiry)
   d. Send OTP via Brevo email (custom HTML template)
   e. Return success
4. User receives email with 6-digit OTP
5. User enters OTP in app → App calls Cloud Function: "verifyOtpAndReset"
6. Cloud Function:
   a. Check OTP matches Firestore record
   b. Check OTP not expired
   c. Reset password in Firebase Auth
   d. Delete OTP from Firestore
   e. Return success
7. User sees "Password Reset Successfully" → redirected to login
```

---

## Brevo Setup (ALREADY DONE by user)

| Item | Value |
|------|-------|
| Sender Name | PrePora |
| Sender Email | mental6600+0000@outlook.com |
| Sender Status | **Verified** |
| API Key | User needs to generate from Brevo → Settings → SMTP & API → API Keys |

---

## Files to Create/Modify

### 1. NEW: `functions/package.json`
```json
{
  "name": "prepora-functions",
  "scripts": {
    "build": "tsc",
    "serve": "npm run build && firebase emulators:start --only functions",
    "deploy": "firebase deploy --only functions"
  },
  "engines": {
    "node": "18"
  },
  "main": "lib/index.js",
  "dependencies": {
    "firebase-admin": "^12.0.0",
    "firebase-functions": "^5.0.0",
    "sib-api-v3-sdk": "^8.5.0"
  },
  "devDependencies": {
    "typescript": "^5.4.0"
  }
}
```

### 2. NEW: `functions/tsconfig.json`
```json
{
  "compilerOptions": {
    "module": "commonjs",
    "noImplicitReturns": true,
    "noUnusedLocals": true,
    "outDir": "lib",
    "sourceMap": true,
    "strict": true,
    "target": "es2017",
    "skipLibCheck": true
  },
  "compileOnSave": true,
  "include": ["src"]
}
```

### 3. NEW: `functions/src/index.ts`

Two Cloud Functions:

#### `sendOtp` — Generates OTP + sends email via Brevo
```
Input: { email: string }
Logic:
  1. Verify user exists in Firebase Auth (getUserByEmail)
  2. Generate 6-digit random OTP
  3. Save to Firestore collection "password_resets":
     {
       email: string,
       otp: string (hashed with SHA-256),
       createdAt: timestamp,
       expiresAt: timestamp (now + 10 minutes),
       used: false
     }
  4. Send email via Brevo API:
     - From: PrePora <mental6600+0000@outlook.com>
     - To: user's email
     - Subject: "Your PrePora Password Reset Code"
     - HTML: Custom OTP email template (see below)
  5. Return { success: true }
Error cases:
  - Email not found → return error
  - Brevo API fails → return error
```

#### `verifyOtpAndReset` — Verifies OTP + resets password
```
Input: { email: string, otp: string, newPassword: string }
Logic:
  1. Find OTP record in Firestore "password_resets":
     - email matches
     - used == false
     - expiresAt > now
  2. Compare OTP (hash input, compare with stored hash)
  3. If match:
     a. Update password in Firebase Auth (admin.auth().updateUser)
     b. Mark OTP as used (or delete record)
     c. Return { success: true }
  4. If no match or expired → return error
```

### 4. Brevo API Integration (in Cloud Function)
```typescript
const SibApiV3Sdk = require('sib-api-v3-sdk');

// Initialize Brevo
const defaultClient = SibApiV3Sdk.ApiClient.instance;
const apiKey = defaultClient.authentications['api-key'];
apiKey.apiKey = process.env.BREVO_API_KEY; // Set via Firebase config

// Send email function
async function sendOtpEmail(toEmail: string, otpCode: string) {
  const apiInstance = new SibApiV3Sdk.TransactionalEmailsApi();
  
  const sendSmtpEmail = new SibApiV3Sdk.SendSmtpEmail();
  sendSmtpEmail.sender = { name: "PrePora", email: "mental6600+0000@outlook.com" };
  sendSmtpEmail.to = [{ email: toEmail }];
  sendSmtpEmail.subject = "Your PrePora Password Reset Code";
  sendSmtpEmail.htmlContent = `<!DOCTYPE html>
<html>
<body style="margin:0;padding:0;background:#0D0D1A;font-family:Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="padding:40px 20px;">
<tr><td align="center">
<table width="480" cellpadding="0" cellspacing="0" style="background:#1A0533;border-radius:20px;border:1px solid rgba(255,255,255,0.08);">
<tr><td style="padding:40px;text-align:center;">
<img src="https://zynfizrocesynbaguhtj.supabase.co/storage/v1/object/public/notices/public/email/logo.png" width="80" height="80" style="border-radius:20px;display:block;margin:0 auto 16px;" />
<h1 style="color:#fff;font-size:24px;margin:0;">PrePora</h1>
<p style="color:rgba(255,255,255,0.5);font-size:13px;margin:6px 0 0;">Your Learning Companion</p>
</td></tr>
<tr><td style="padding:0 40px;"><hr style="border:none;border-top:1px solid rgba(124,58,237,0.4);" /></td></tr>
<tr><td style="padding:32px 40px;text-align:center;">
<h2 style="color:#fff;font-size:20px;margin:0 0 12px;">Your Reset Code</h2>
<p style="color:rgba(255,255,255,0.65);font-size:14px;line-height:1.7;">
Use the following code to reset your password. This code expires in 10 minutes.
</p>
<div style="background:rgba(124,58,237,0.15);border:2px dashed #7C3AED;border-radius:12px;padding:20px;margin:24px 0;">
<span style="color:#fff;font-size:36px;font-weight:800;letter-spacing:8px;">${otpCode}</span>
</div>
<p style="color:rgba(255,255,255,0.45);font-size:12px;">
If you did not request a password reset, please ignore this email.
</p>
</td></tr>
<tr><td style="padding:0 40px;"><hr style="border:none;border-top:1px solid rgba(255,255,255,0.08);" /></td></tr>
<tr><td style="padding:24px 40px 32px;text-align:center;">
<p style="color:rgba(255,255,255,0.3);font-size:11px;margin:0;">
This email was sent by PrePora
</p>
</td></tr>
</table>
</td></tr>
</table>
</body>
</html>`;
  
  return apiInstance.sendTransacEmail(sendSmtpEmail);
}
```

### 5. Firestore Collection: `password_resets`
```
password_resets/{autoId}
  ├── email: string
  ├── otp: string (SHA-256 hashed)
  ├── createdAt: Timestamp
  ├── expiresAt: Timestamp (createdAt + 10 min)
  └── used: boolean
```

### 6. MODIFY: `lib/core/services/firebase_service.dart`

Add new methods:
```dart
// Call Cloud Function to send OTP
static Future<void> sendOtp(String email) async {
  final functions = FirebaseFunctions.instance;
  final result = await functions.httpsCallable('sendOtp').call({'email': email});
  if (result.data['success'] != true) throw Exception('Failed to send OTP');
}

// Call Cloud Function to verify OTP and reset password
static Future<void> verifyOtpAndReset(String email, String otp, String newPassword) async {
  final functions = FirebaseFunctions.instance;
  final result = await functions.httpsCallable('verifyOtpAndReset').call({
    'email': email,
    'otp': otp,
    'newPassword': newPassword,
  });
  if (result.data['success'] != true) throw Exception('Failed to reset password');
}
```

Keep old `sendPasswordReset()` method (don't delete — might be useful later).

### 7. NEW: `lib/features/auth/presentation/otp_verification_screen.dart`

New screen with:
- Display "OTP sent to your email" message
- 6-digit OTP input field (6 separate boxes or single field)
- "Verify OTP" button
- "Resend OTP" link (with 60-second cooldown)
- On success → show "New Password" form:
  - New Password field
  - Confirm Password field
  - "Reset Password" button
- On success → show success message → navigate to login

### 8. MODIFY: `lib/features/auth/presentation/forgot_password_screen.dart`

Current flow: email → sends Firebase reset link
New flow: email → calls `sendOtp` → navigates to OTP verification screen

Change `_sendReset()` method:
```dart
Future<void> _sendReset() async {
  final email = _emailCtrl.text.trim();
  // ... validation ...
  setState(() { _isLoading = true; _error = null; });
  try {
    await FirebaseService.sendOtp(email);  // Changed from sendPasswordReset
    if (mounted) {
      context.go('/auth/otp-verify', extra: email);  // Navigate to OTP screen
    }
  } on FirebaseAuthException catch (e) {
    // ... error handling ...
  }
}
```

### 9. MODIFY: `lib/core/router/app_router.dart`

Add new route:
```dart
GoRoute(
  path: '/auth/otp-verify',
  builder: (context, state) => OtpVerificationScreen(email: state.extra as String),
),
```

---

## Environment Variables (Firebase Config)

Set Brevo API key in Firebase:
```bash
firebase functions:config:set brevo.api_key="YOUR_BREVO_API_KEY_HERE"
```

Access in Cloud Function:
```typescript
const brevoApiKey = process.env.BREVO_API_KEY;
```

---

## Testing

1. Deploy Cloud Functions: `firebase deploy --only functions`
2. Test `sendOtp` function from Firebase Console → Functions → Try it
3. Check if email arrives with OTP
4. Test `verifyOtpAndReset` function
5. Test full flow in Flutter app

---

## Key Reminders

- OTP expires in 10 minutes
- OTP is stored as SHA-256 hash (never plain text)
- Brevo free plan: 300 emails/day
- Firebase Auth accounts are NOT modified until password is actually reset
- Old `sendPasswordReset()` method kept as backup
- Custom email template matches PrePora branding (dark purple theme)
