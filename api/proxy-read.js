const { createClient } = require('@supabase/supabase-js');

// Proxy auth secret — stored as Vercel env var, NOT in APK
const PROXY_SECRET = process.env.PROXY_SECRET || '';

// Master Supabase — conversations, messages, settings, AI keys (service key NEVER in APK)
const MASTER = {
  name: 'Master',
  url: 'https://ybiviymuxubvloqjngfu.supabase.co',
  serviceKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InliaXZpeW11eHVidmxvcWpuZ2Z1Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4OTM3MjQzOSwiZXhwIjoyMTA0OTQ4NDM5fQ.kIoWInC-ZDNsPx6xpCACO0ee2Kfer7jMBRCtAQv_8gQ',
};

// In-memory response cache — persists across requests within same Vercel function instance
const CACHE = new Map();
const CACHE_TTL = 15000; // 15 seconds
function getCached(key) {
  const entry = CACHE.get(key);
  if (!entry) return null;
  if (Date.now() > entry.exp) { CACHE.delete(key); return null; }
  return entry.data;
}
function setCache(key, data) {
  if (CACHE.size > 500) CACHE.clear(); // prevent memory leak
  CACHE.set(key, { data, exp: Date.now() + CACHE_TTL });
}

// Storage projects — folders, contents, share_links (keys NEVER exposed to client)
const PROJECTS = [
  { name: 'Primary 2',  role: 'primary',  url: 'https://brqdxhqrsfxlvwgstuto.supabase.co', serviceKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJycWR4aHFyc2Z4bHZ3Z3N0dXRvIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NzE1NjgzMywiZXhwIjoyMTAyNzMyODMzfQ.gPkiuNGYAP_pJR1uSbAQWc25SyhmpwwgspJeFInXgWE' },
  { name: 'Primary 3',  role: 'primary',  url: 'https://avzdjlwswulewgbciwyj.supabase.co', serviceKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF2emRqbHdzd3VsZXdnYmNpd3lqIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NzIxMDczMSwiZXhwIjoyMTAyNzg2NzMxfQ.xlnVp4yWL9Ptv0Y54aeXvFYN1MwTN5rI22Dy_0G7X-M' },
  { name: 'Primary 4',  role: 'primary',  url: 'https://dneeqtkyyovsrbefbeyg.supabase.co', serviceKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRuZWVxdGt5eW92c3JiZWZiZXlnIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NzMzMTEzNCwiZXhwIjoyMTAyOTA3MTM0fQ.W9WJiBkwamdYlM124dUR8FwttYb503opPs4WaB2c2Ug' },
  { name: 'Backup 1',   role: 'backup',   url: 'https://efxftqrdnlzqzyofcbxh.supabase.co', serviceKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVmeGZ0cXJkbmx6cXp5b2ZjYnhoIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NzE1ODAyMCwiZXhwIjoyMTAyNzM0MDIwfQ._jFEeHO31gkVxnJQ3u-WCCFwSzkSttTYAVNQsnM857A' },
  { name: 'Backup 3',   role: 'backup',   url: 'https://vllcbapmyldujxmqlrlu.supabase.co', serviceKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZsbGNiYXBteWxkdWp4bXFscmx1Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NzMzMTE2NSwiZXhwIjoyMTAyOTA3MTY1fQ.yS6m34LpmhqKRTtw_Pew0y5SUHqoDD-6eZRrDNZdimc' },
  { name: 'Backup 4',   role: 'backup',   url: 'https://ilbchsmxhtqeeqbljoyq.supabase.co', serviceKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlsYmNoc214aHRxZWVxYmxqb3lxIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NzMzNzgyNiwiZXhwIjoyMTAyOTEzODI2fQ.aJ0Bcaw9MMbd8M1voaZjbKumlL2RjHHFcg_MbG5YHXk' },
  { name: 'Primary 1',  role: 'primary',  url: 'https://rqedljcelpbkocsdbbyu.supabase.co', serviceKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJxZWRsamNlbHBia29jc2RiYnl1Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NzU1OTc5MywiZXhwIjoyMTAzMTM1NzkzfQ.b-yNIn1MJhzUYxTP_m94_AqpmAAUJXO63AMrSnBS54E' },
  { name: 'Backup 2',   role: 'backup',   url: 'https://jlltinlyrcycofibztmk.supabase.co', serviceKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpsbHRpbmx5cmN5Y29maWJ6dG1rIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NzU1OTMwOCwiZXhwIjoyMTAzMTM1MzA4fQ.LK7X3bADuHS65_7rp1PY3YVq0RKmfnPu2ROEqqLlNfo' },
];

module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  if (PROXY_SECRET) {
    const provided = req.headers['x-proxy-secret'];
    if (!provided || provided !== PROXY_SECRET) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
  }

  try {
    let parsed = req.body;
    if (!parsed || typeof parsed !== 'object') {
      const chunks = [];
      for await (const chunk of req) chunks.push(chunk);
      const raw = Buffer.concat(chunks).toString();
      parsed = raw ? JSON.parse(raw) : {};
    }

    const { table, query, startIndex, target } = parsed;
    if (!table) return res.status(400).json({ error: 'Missing table' });

    // Route to Master Supabase
    if (target === 'master') {
      const cacheKey = `master:${table}:${query || ''}`;
      const cached = getCached(cacheKey);
      if (cached) return res.status(200).json(cached);

      let q = query || '';
      if (!q.includes('limit=')) q += q ? '&limit=5000' : 'limit=5000';
      const url = `${MASTER.url}/rest/v1/${table}?${q}`;
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 8000);
      try {
        const r = await fetch(url, {
          method: 'GET',
          headers: { 'apikey': MASTER.serviceKey, 'Authorization': `Bearer ${MASTER.serviceKey}`, 'Content-Type': 'application/json' },
          signal: controller.signal,
        });
        clearTimeout(timer);
        if (r.status === 200 || r.status === 206) {
          const rows = await r.json();
          const resp = { data: rows, project: MASTER.name, index: 0 };
          setCache(cacheKey, resp);
          return res.status(200).json(resp);
        }
        return res.status(200).json({ data: [], project: MASTER.name, index: 0 });
      } catch (e) {
        clearTimeout(timer);
        return res.status(200).json({ data: [], project: MASTER.name, index: 0 });
      }
    }

    // Storage projects — failover chain
    const startIdx = typeof startIndex === 'number' ? startIndex : 0;
    const timeout = 3000; // reduced from 5s to 3s

    for (let attempt = 0; attempt < PROJECTS.length; attempt++) {
      const idx = (startIdx + attempt) % PROJECTS.length;
      const p = PROJECTS[idx];

      const cacheKey = `${idx}:${table}:${query || ''}`;
      const cached = getCached(cacheKey);
      if (cached) return res.status(200).json({ ...cached, project: p.name, index: idx });

      try {
        let q = query || '';
        if (!q.includes('limit=')) {
          q += q ? '&limit=5000' : 'limit=5000';
        }

        const url = `${p.url}/rest/v1/${table}?${q}`;
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), timeout);

        const r = await fetch(url, {
          method: 'GET',
          headers: {
            'apikey': p.serviceKey,
            'Authorization': `Bearer ${p.serviceKey}`,
            'Content-Type': 'application/json',
          },
          signal: controller.signal,
        });
        clearTimeout(timer);

        if (r.status === 200 || r.status === 206) {
          const rows = await r.json();
          const resp = { data: rows, project: p.name, index: idx };
          setCache(cacheKey, resp);
          return res.status(200).json(resp);
        }
      } catch (_) {
        continue;
      }
    }

    return res.status(200).json({ data: [], project: null, index: startIdx });
  } catch (err) {
    return res.status(500).json({ error: 'Proxy read error', details: err.message });
  }
};

module.exports.config = { maxDuration: 10 };
