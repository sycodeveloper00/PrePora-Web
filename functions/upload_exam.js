/**
 * PrePora Upload Tool
 * 
 * Usage:
 *   node upload_exam.js --list
 *   node upload_exam.js --check "C:\path\to\file.html"
 *   node upload_exam.js "C:\path\to\file.html" "NAT-ICS"
 * 
 * Requires: FIREBASE_SA env var (base64 service account)
 */

const admin = require('firebase-admin');
const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');

// Firebase Admin init
const saBase64 = process.env.FIREBASE_SA_BASE64 || 'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5bmZpenJvY2VzeW5iYWd1aHRqIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MzY3MjkzOSwiZXhwIjoyMDk5MjQ4OTM5fQ.CdfQUkM_-O9lYZ8MIcJh8H1n_-SHIWUuwI8DE5HGdZU';

const SUPABASE_URL = 'https://zynfizrocesynbaguhtj.supabase.co';
const SERVICE_KEY = saBase64;
const BUCKET = 'folder_files';

function httpPut(url, headers, data) {
    return new Promise((resolve, reject) => {
        const u = new URL(url);
        const options = { hostname: u.hostname, port: u.port || 443, path: u.pathname + u.search, method: 'PUT', headers };
        const req = https.request(options, (res) => {
            let body = '';
            res.on('data', d => body += d);
            res.on('end', () => resolve({ status: res.statusCode, body }));
        });
        req.on('error', reject);
        req.write(data);
        req.end();
    });
}

function preCheck(filepath) {
    const content = fs.readFileSync(filepath, 'utf-8');
    const issues = [];
    if (content.includes('\u00c2')) issues.push('A-char (encoding)');
    if (content.includes('factorsto')) issues.push('factorsto (missing space)');
    if (content.includes('perquery')) issues.push('perquery (missing space)');
    if (content.includes('Sumof')) issues.push('Sumof (missing space)');
    if (content.match(/find\d/)) issues.push('find6 (missing space)');
    if (content.includes('color:#f0f6fc')) issues.push('dark timer');
    return issues;
}

async function listFolders() {
    const db = admin.firestore();
    const snapshot = await db.collection('folders').get();
    console.log('\n=== Available Folders ===\n');
    snapshot.forEach(doc => {
        const data = doc.data();
        console.log(`  ${data.title || 'Untitled'} -> ${doc.id}`);
    });
}

async function findFolderId(name) {
    const db = admin.firestore();
    const snapshot = await db.collection('folders').get();
    for (const doc of snapshot.docs) {
        const data = doc.data();
        if ((data.title || '').toLowerCase() === name.toLowerCase()) {
            return doc.id;
        }
    }
    // Partial match
    for (const doc of snapshot.docs) {
        const data = doc.data();
        if ((data.title || '').toLowerCase().includes(name.toLowerCase())) {
            return doc.id;
        }
    }
    return null;
}

async function uploadFile(filepath, folderName) {
    const filename = path.basename(filepath);
    const content = fs.readFileSync(filepath);

    // 1. Upload to Supabase
    const timestamp = Date.now();
    const storageName = `${timestamp}_${filename}`;
    const storagePath = `${BUCKET}/${storageName}`;
    const uploadUrl = `${SUPABASE_URL}/storage/v1/object/${storagePath}`;

    console.log(`\n1. Uploading to Supabase: ${storageName}...`);
    const resp = await httpPut(uploadUrl, {
        'Authorization': `Bearer ${SERVICE_KEY}`,
        'Content-Type': 'text/html; charset=utf-8',
        'x-upsert': 'true'
    }, content);

    if (resp.status !== 200 && resp.status !== 201) {
        console.log(`ERROR: Supabase upload failed: ${resp.status} ${resp.body.substring(0, 300)}`);
        return false;
    }
    console.log(`   OK (${content.length} bytes)`);

    const downloadUrl = `${SUPABASE_URL}/storage/v1/object/public/${storagePath}`;

    // 2. Find folder
    console.log(`2. Finding folder: ${folderName}...`);
    const folderId = await findFolderId(folderName);
    if (!folderId) {
        console.log(`ERROR: Folder "${folderName}" not found`);
        return false;
    }
    console.log(`   Found: ${folderId}`);

    // 3. Create Firestore entry
    console.log(`3. Creating Firestore entry...`);
    const db = admin.firestore();
    const contentsRef = db.collection('folders').doc(folderId).collection('contents');
    const docRef = await contentsRef.add({
        type: 'file',
        name: filename,
        url: downloadUrl,
        source: 'supabase_storage',
        createdAt: admin.firestore.FieldValue.serverTimestamp()
    });
    console.log(`   Entry created: ${docRef.id}`);

    // 4. Increment item_count
    const folderRef = db.collection('folders').doc(folderId);
    const folderDoc = await folderRef.get();
    const currentCount = folderDoc.data()?.item_count || 0;
    await folderRef.update({ item_count: currentCount + 1 });
    console.log(`   item_count updated: ${currentCount} -> ${currentCount + 1}`);

    console.log(`\nDONE! "${filename}" uploaded successfully.`);
    console.log(`URL: ${downloadUrl}`);
    return true;
}

async function main() {
    const args = process.argv.slice(2);

    if (args.length === 0) {
        console.log('\n=== PrePora Upload Tool ===\n');
        console.log('Usage:');
        console.log('  node upload_exam.js --list');
        console.log('  node upload_exam.js --check "file.html"');
        console.log('  node upload_exam.js "file.html" "folder-name"');
        console.log('\nExamples:');
        console.log('  node upload_exam.js --list');
        console.log('  node upload_exam.js --check "C:\\path\\file.html"');
        console.log('  node upload_exam.js "C:\\path\\file.html" "NAT-ICS"');
        return;
    }

    // Init Firebase Admin with application default credentials or skip
    try {
        if (!admin.apps.length) {
            admin.initializeApp({
                credential: admin.credential.applicationDefault(),
            });
        }
    } catch (e) {
        // If ADC not available, try without
        try {
            if (!admin.apps.length) {
                admin.initializeApp({});
            }
        } catch (e2) {
            console.log('WARNING: Firebase Admin init without credentials. Firestore operations may fail.');
        }
    }

    if (args[0] === '--list') {
        await listFolders();
    } else if (args[0] === '--check') {
        const filepath = args[1];
        if (!filepath || !fs.existsSync(filepath)) {
            console.log('ERROR: File not found');
            return;
        }
        console.log(`\nChecking: ${filepath}`);
        const issues = preCheck(filepath);
        if (issues.length > 0) {
            console.log(`ISSUES FOUND: ${issues.join(', ')}`);
        } else {
            console.log('FILE IS CLEAN - ready to upload!');
        }
    } else {
        const filepath = args[0];
        const folderName = args[1];

        if (!fs.existsSync(filepath)) {
            console.log(`ERROR: File not found: ${filepath}`);
            return;
        }

        // Pre-check
        console.log('\nChecking file...');
        const issues = preCheck(filepath);
        if (issues.length > 0) {
            console.log(`ISSUES FOUND: ${issues.join(', ')}`);
            console.log('Fix these before uploading!');
            return;
        }
        console.log('File is clean.');

        const name = folderName || 'NAT-ICS';
        await uploadFile(filepath, name);
    }
}

main().catch(console.error);
