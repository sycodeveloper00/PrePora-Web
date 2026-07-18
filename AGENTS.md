# MEPCO OCR + .DAT Matching Tool — Project Context

## Project Goal
Build a tool (Flutter app) that:
1. Reads `.DAT` files (MEPCO electricity billing CSV format)
2. Lets user upload photos from gallery
3. Uses **on-device OCR (Google ML Kit)** to find Sr.No from photos
4. Matches Sr.No with `Ref_No` column in .DAT file
5. Attaches photo to correct record
6. User reviews → Export updated `.DAT` file

## APK Analysis — `MMR (GEN)_MobileApp_V87.9_09042026 For MEPCO Only.apk`
- **Package:** `com.project.dreams.general`
- **Developer:** Dreams
- **Type:** Native Android (Java) — Meter Reading for MEPCO
- **Version:** 87.9
- **Uses:** Camera, Barcode (ZXing), GPS, .DAT import/export
- **Sample .DAT from APK:** `users.DAT` = `UserID,UserName,UserPassword,UserGroupID` (CSV)
- **Consumer .DAT format:** CSV with header: `Billing_Month,Ref_No,Sanction_Load,Name,...`
- **Ref_No:** 14-digit number starting with `5680` — this is the Sr.No to match

## Tech Stack Decision
| Component | Choice | Reason |
|-----------|--------|--------|
| OCR Engine | **Google ML Kit Text Recognition** | Free, offline, unlimited, no API key needed |
| Framework | **Flutter** | Cross-platform, already have Flutter setup |
| .DAT Parsing | **CSV parsing** (Dart `csv` package) | .DAT files are CSV format |
| Photo Picker | `image_picker` package | Built-in gallery access |
| Budget | **$0** | Everything runs on-device, no server/API costs |

## Alternative OCR Options Tested (for reference)
- **Tesseract OCR** — Free, but needs separate install on Windows. pip packages installed: `pytesseract`, `Pillow`, `openpyxl`
- **EasyOCR** — Fallback option, pure Python, no separate install
- **Google ML Kit** — Best for mobile (Flutter) — selected for final solution

## BazaarLink API (from Prepora work)
- **API Key:** `sk-bl-foHbeBqqZJM8O6gYEmmouGtftnSBdpPNqvy_aRc-BTEW7Qfr`
- **Status:** Integrated in Prepora's `ai_service.dart` — TEMPORARY changes
- **Warning:** Key may expire. User should sign up for own key at BazaarLink
- **Other free APIs tried:** FreeTheAi, ZeroLimitAI (no credit card needed)

## Prepora App Changes (temporary)
- `pubspec.yaml`: Added `http` package, removed `google_generative_ai`
- `lib/core/services/ai_service.dart`: Rewritten with BazaarLink API + Firestore content context
- These changes are temporary — user may revert after testing

## Sample .DAT File
- **Path:** `C:\Users\Muhammad Tanzeel\AppData\Local\Temp\06-08-15265-07.DAT`
- **Columns:** Billing_Month, Ref_No, Sanction_Load, Name, Meter_Number_1..4, CNIC, Unique_ID, KWH readings, etc. (~80 columns)
- **Format:** CSV with header row, comma-separated, no quotes

## Connected Devices
- **Phone:** Samsung SM-A065F (Galaxy A06) — connected via ADB
- **ADB available** on this PC
- Phone's WhatsApp internal storage accessible at:
  `/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Documents/`

## Next Steps (Pending User Input)
1. Confirm whether to build Flutter app (new project) or Python PC script
2. Share sample photo(s) showing Sr.No location for OCR testing
3. Define exact workflow: batch upload vs single, review UI design
4. Build MVP: .DAT reader → OCR engine → matching logic → export

## Important Notes
- Photos contain many numbers — OCR needs to identify which number is the Sr.No
- Sr.No printed in laser/dot matrix style (not handwritten)
- Final export should produce .DAT file that MMR app can consume
- Results should be exportable back to .DAT format (same CSV structure)
