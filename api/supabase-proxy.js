module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  try {
    let parsed = req.body;
    if (!parsed || typeof parsed !== 'object') {
      const chunks = [];
      for await (const chunk of req) chunks.push(chunk);
      const raw = Buffer.concat(chunks).toString();
      parsed = raw ? JSON.parse(raw) : {};
    }
    const { action, projectUrl, serviceKey, bucketName, table, method, query, headers: customHeaders, body: reqBody } = parsed;

    // GitHub proxy action (for Clorabase) — doesn't need projectUrl/serviceKey
    if (action === 'github_proxy') {
      const { ghMethod, ghUrl, ghToken, ghBody } = parsed;
      if (!ghUrl || !ghToken) {
        return res.status(400).json({ error: 'Missing ghUrl or ghToken' });
      }
      const ghHeaders = {
        'Authorization': `token ${ghToken}`,
        'Accept': 'application/vnd.github.v3+json',
      };
      if (ghBody && (ghMethod === 'PUT' || ghMethod === 'POST' || ghMethod === 'PATCH')) {
        ghHeaders['Content-Type'] = 'application/json';
      }
      const ghRes = await fetch(ghUrl, {
        method: ghMethod || 'GET',
        headers: ghHeaders,
        body: ghBody ? (typeof ghBody === 'string' ? ghBody : JSON.stringify(ghBody)) : undefined,
      });
      const ghText = await ghRes.text();
      let ghJson;
      try { ghJson = JSON.parse(ghText); } catch (_) { ghJson = ghText; }
      return res.status(ghRes.status).json(ghJson);
    }

    if (!projectUrl || !serviceKey) {
      return res.status(400).json({ error: 'Missing projectUrl or serviceKey' });
    }

    const base = projectUrl.replace(/\/$/, '');

    if (action === 'verify') {
      const r = await fetch(`${base}/storage/v1/bucket`, {
        method: 'GET',
        headers: { 'Authorization': `Bearer ${serviceKey}` },
      });
      if (r.status === 200) return res.json({ valid: true });
      if (r.status === 401 || r.status === 403) return res.json({ valid: false, error: 'Invalid credentials' });
      if (r.status === 530) return res.json({ valid: false, error: 'Project is paused or unreachable (HTTP 530).' });
      return res.json({ valid: false, error: `Server error: ${r.status}` });
    }

    if (action === 'check_bucket') {
      const r = await fetch(`${base}/storage/v1/bucket/${bucketName}`, {
        method: 'GET',
        headers: { 'Authorization': `Bearer ${serviceKey}` },
      });
      return res.json({ exists: r.status === 200 });
    }

    if (action === 'create_bucket') {
      const r = await fetch(`${base}/storage/v1/bucket`, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${serviceKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: bucketName, public: true }),
      });
      return res.json({ ok: r.status === 200 || r.status === 201 || r.status === 409 });
    }

    if (action === 'storage_usage') {
      let totalBytes = 0, fileCount = 0;
      for (const bucket of ['folder_files', 'notices']) {
        try {
          let offset = 0;
          const limit = 1000;
          while (true) {
            const r = await fetch(`${base}/storage/v1/object/list/${bucket}`, {
              method: 'POST',
              headers: { 'Authorization': `Bearer ${serviceKey}`, 'Content-Type': 'application/json' },
              body: JSON.stringify({ prefix: '', limit, offset, sortBy: { column: 'created_at', order: 'desc' } }),
            });
            if (r.status !== 200) break;
            const items = await r.json();
            if (!items || items.length === 0) break;
            for (const item of items) {
              totalBytes += item.metadata?.size ?? 0;
              fileCount++;
            }
            if (items.length < limit) break;
            offset += limit;
          }
        } catch (_) {}
      }
      return res.json({ totalBytes, fileCount });
    }

    if (action === 'supabase_write') {
      if (!table || !method) {
        return res.status(400).json({ error: 'Missing table or method' });
      }
      const writeUrl = `${base}/rest/v1/${table}${query || ''}`;
      const fwdHeaders = {
        'Authorization': `Bearer ${serviceKey}`,
        'apikey': serviceKey,
        ...customHeaders,
      };
      const r = await fetch(writeUrl, {
        method,
        headers: fwdHeaders,
        body: reqBody ? JSON.stringify(reqBody) : undefined,
      });
      const text = await r.text();
      let jsonBody;
      try { jsonBody = JSON.parse(text); } catch (_) { jsonBody = text; }
      return res.status(r.status).json(jsonBody);
    }

    return res.status(400).json({ error: 'Unknown action' });
  } catch (err) {
    return res.status(502).json({ error: 'Proxy error', details: err.message });
  }
};

module.exports.config = {
  api: {
    bodyParser: {
      sizeLimit: '50mb',
    },
  },
  maxDuration: 60,
};
