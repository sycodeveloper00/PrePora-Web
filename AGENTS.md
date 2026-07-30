# PrePora Web + Android — Project Context

## Project Overview
PrePora is a study platform with AI tutoring, note management, PDF viewing, and student progress tracking. Two codebases:
- **Web:** `E:\E_Drive_Projects\PrePora Web` (Flutter web, deployed to Vercel + Cloudflare)
- **Android:** `E:\E_Drive_Projects\Prepora` (Flutter Android, deployed via APK)
- **Both share the same Firestore database**

## Deployment
- **Web:** Vercel `prepora-web.vercel.app` (Flutter build + `/api` serverless functions)
- **Admin:** Cloudflare Pages `admin-prepora.pages.dev`
- **Password Reset:** Vercel `prepora-passwordreset` (standalone HTML)
- Deploy: `flutter build web` → `cd build/web` → `Copy-Item -Path api -Destination build\web\api -Recurse -Force` → `vercel --prod --yes`
- `.vercel/project.json` must be copied to `build\web\.vercel\` after `flutter clean`

## Domain-Based Routing (Web)
- `prepora-web.vercel.app` → always redirects to `/link-web` (QR only, no login)
- `admin-prepora.pages.dev` → redirects unauthenticated to `/auth/login`, blocks non-admin roles

## Key Features
- AI Chat (BazaarLink API via Vercel proxy, word-by-word typing animation)
- PDF.js inline viewer with annotation (draw, highlight, eraser)
- Noto Nastaliq Urdu font for Urdu text rendering
- LaTeX/math fraction rendering (fixLatex in ai_service.dart)
- Student progress tracking, daily streak notifications
- Brevo-based forgot password (email flow + standalone reset page)
- Google Drive / OneDrive / Dropbox in-app browser with sign-in support
- Link with Web Version (QR scan from Android → Firebase Auth custom token on web)
- Admin panel: student activity, device history, cascade delete

## Session Management
- **Web:** 12-min inactivity timeout for admin/assistant only (SessionManager); pauses on background
- **Students:** No timeout on any platform
- **Android:** No SessionManager — Firebase Auth persists by default

## Admin Panel Student Activity (Latest)
- Full screen sheet (not bottom sheet)
- Green dot on active device (within 5 min of last login)
- Per-device web link history (queries `web_sessions` + `login_attempts`)
- Device click → read-only `_AdminLinkHistoryScreen` (NO QR/camera — student privacy)
- `Icons.qr_code_scanner_rounded` used everywhere (replaced `link_rounded`)

## Admin Panel Security
- `link_rounded` icon replaced with `qr_code_scanner_rounded` on all panels
- Admin device click shows read-only history only — no QR scanner/camera options
- Student privacy: admin cannot see QR codes or link devices

## Firebase Auth Persistence
- Android: persists by default (survives app updates)
- Uninstall: data wiped by OS (unavoidable)
- Web: custom token via `/api/generate-token` endpoint

## Service Account
- Path: `E:\ddd\prepora-c2d23-firebase-adminsdk-fbsvc-abc12817e597a7acb56f9fe44dbedc6344004992.json`
- Stored as Vercel env var `FIREBASE_SA_BASE64` (base64-encoded)
- Used by `send-reset-email.js` and `reset-password.js`

## Brevo Email
- API key in env var, sender: `prepora@hotmail.com`
- Free plan: 300 emails/day
- Password reset email with green gradient button, professional template

## AI Configuration
- BazaarLink API via Vercel serverless proxy (`api/proxy.js`)
- `enable_thinking: false`, `max_tokens: 4096`
- Language matching: English→English, Roman Urdu→Roman Urdu, Urdu→Urdu
- Step-by-step math solutions required
- Identity protection: never reveal API provider/model names

## Important Notes
- `flutter analyze` shows warnings/info but no errors
- `api/` directory not included in `flutter build web` — must copy manually
- `workmanager` package removed from Android (incompatible with Flutter/Kotlin setup)
- `SessionManager` auto-logout is web-only, admin/assistant-only
