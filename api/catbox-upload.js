const { Blob } = require('buffer');

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-Filename');

  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  try {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const fileBuffer = Buffer.concat(chunks);
    if (fileBuffer.length === 0) return res.status(400).json({ error: 'Empty request body' });

    const fileName = req.headers['x-filename'] || 'upload.dat';

    const formData = new FormData();
    formData.append('reqtype', 'fileupload');
    formData.append('userhash', '');
    formData.append('fileToUpload', new Blob([fileBuffer]), fileName);

    const response = await fetch('https://catbox.moe/user/api.php', {
      method: 'POST',
      body: formData,
      signal: AbortSignal.timeout(120000),
    });

    const text = await response.text();

    if (response.ok && text.trim().startsWith('http')) {
      return res.status(200).json({ url: text.trim() });
    }

    return res.status(500).json({ error: `Catbox ${response.status}: ${text.substring(0, 200)}` });
  } catch (err) {
    return res.status(500).json({ error: err.message || 'Upload failed' });
  }
};

module.exports.config = { maxDuration: 120 };
