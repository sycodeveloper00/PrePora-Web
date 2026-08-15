module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { supabaseUrl, bucket, path, fileBase64, filename, auth } = req.body;

  if (!supabaseUrl || !bucket || !path || !fileBase64 || !auth) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  try {
    const fileBuffer = Buffer.from(fileBase64, 'base64');
    const boundary = '----FormBoundary' + Math.random().toString(36).slice(2);

    let body = '';
    body += `--${boundary}\r\n`;
    body += `Content-Disposition: form-data; name="file"; filename="${filename || path.split('/').pop()}"\r\n`;
    body += `Content-Type: application/octet-stream\r\n\r\n`;

    const bodyEnd = `\r\n--${boundary}--\r\n`;

    const bodyStart = Buffer.from(body, 'utf-8');
    const bodyEndBuf = Buffer.from(bodyEnd, 'utf-8');
    const fullBody = Buffer.concat([bodyStart, fileBuffer, bodyEndBuf]);

    const uploadUrl = `${supabaseUrl}/storage/v1/object/${bucket}/${path}`;

    const response = await fetch(uploadUrl, {
      method: 'POST',
      headers: {
        'Authorization': auth,
        'Content-Type': `multipart/form-data; boundary=${boundary}`,
      },
      body: fullBody,
    });

    const result = await response.text();

    if (!response.ok) {
      return res.status(response.status).json({ error: result });
    }

    return res.status(200).json(JSON.parse(result));
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
};
