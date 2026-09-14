const { createClient } = require('@supabase/supabase-js');

const PROXY_SECRET = process.env.PROXY_SECRET || '';

// Master Supabase — conversations, messages, settings, AI keys
const MASTER = {
  name: 'Master',
  url: 'https://ybiviymuxubvloqjngfu.supabase.co',
  serviceKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InliaXZpeW11eHVidmxvcWpuZ2Z1Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4OTM3MjQzOSwiZXhwIjoyMTA0OTQ4NDM5fQ.kIoWInC-ZDNsPx6xpCACO0ee2Kfer7jMBRCtAQv_8gQ',
};

// Storage projects
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

    const { table, id, data, delete: isDelete, writeAll, target, query } = parsed;
    if (!table) return res.status(400).json({ error: 'Missing table' });

    const timeout = 10000;

    // ─── Master Supabase writes ───
    if (target === 'master') {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeout);
      try {
        if (isDelete && id) {
          const encodedId = encodeURIComponent(id);
          const r = await fetch(`${MASTER.url}/rest/v1/${table}?id=eq.${encodedId}`, {
            method: 'DELETE',
            headers: { 'apikey': MASTER.serviceKey, 'Authorization': `Bearer ${MASTER.serviceKey}`, 'Prefer': 'return=minimal' },
            signal: controller.signal,
          });
          clearTimeout(timer);
          return res.status(r.status).json({ success: r.status < 300 });
        } else if (data) {
          // Use query param for upsert support (no body id needed)
          let endpoint = `${MASTER.url}/rest/v1/${table}`;
          const headers = {
            'apikey': MASTER.serviceKey,
            'Authorization': `Bearer ${MASTER.serviceKey}`,
            'Content-Type': 'application/json',
            'Prefer': 'resolution=merge-duplicates,return=representation',
          };
          const body = id ? { id, ...data } : data;
          const r = await fetch(endpoint, {
            method: 'POST',
            headers,
            body: JSON.stringify(body),
            signal: controller.signal,
          });
          clearTimeout(timer);
          const result = r.status < 300 ? await r.json().catch(() => null) : null;
          return res.status(r.status).json({ success: r.status < 300, data: result });
        }
        clearTimeout(timer);
        return res.status(400).json({ error: 'Missing data' });
      } catch (e) {
        clearTimeout(timer);
        return res.status(502).json({ success: false, error: e.message });
      }
    }

    // ─── Storage projects ───
    if (!id) return res.status(400).json({ error: 'Missing id' });

    if (writeAll) {
      const results = await Promise.allSettled(PROJECTS.map(async (p) => {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), timeout);
        try {
          const encodedId = encodeURIComponent(id);
          if (isDelete) {
            const r = await fetch(`${p.url}/rest/v1/${table}?id=eq.${encodedId}`, {
              method: 'DELETE',
              headers: { 'apikey': p.serviceKey, 'Authorization': `Bearer ${p.serviceKey}`, 'Prefer': 'return=minimal' },
              signal: controller.signal,
            });
            clearTimeout(timer);
            return { project: p.name, ok: r.status < 300, status: r.status };
          } else {
            const body = { id, ...data };
            const r = await fetch(`${p.url}/rest/v1/${table}`, {
              method: 'POST',
              headers: { 'apikey': p.serviceKey, 'Authorization': `Bearer ${p.serviceKey}`, 'Content-Type': 'application/json', 'Prefer': 'resolution=merge-duplicates,return=minimal' },
              body: JSON.stringify(body),
              signal: controller.signal,
            });
            clearTimeout(timer);
            return { project: p.name, ok: r.status < 300, status: r.status };
          }
        } catch (e) {
          clearTimeout(timer);
          return { project: p.name, ok: false, error: e.message };
        }
      }));

      const anySuccess = results.some(r => r.status === 'fulfilled' && r.value?.ok);
      return res.status(anySuccess ? 200 : 502).json({
        success: anySuccess,
        results: results.map(r => r.status === 'fulfilled' ? r.value : { ok: false, error: r.reason?.message }),
      });
    } else {
      const p = PROJECTS[0];
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeout);
      try {
        const encodedId = encodeURIComponent(id);
        if (isDelete) {
          const r = await fetch(`${p.url}/rest/v1/${table}?id=eq.${encodedId}`, {
            method: 'DELETE',
            headers: { 'apikey': p.serviceKey, 'Authorization': `Bearer ${p.serviceKey}`, 'Prefer': 'return=minimal' },
            signal: controller.signal,
          });
          clearTimeout(timer);
          return res.status(r.status).json({ success: r.status < 300 });
        } else {
          const body = { id, ...data };
          const r = await fetch(`${p.url}/rest/v1/${table}`, {
            method: 'POST',
            headers: { 'apikey': p.serviceKey, 'Authorization': `Bearer ${p.serviceKey}`, 'Content-Type': 'application/json', 'Prefer': 'resolution=merge-duplicates,return=minimal' },
            body: JSON.stringify(body),
            signal: controller.signal,
          });
          clearTimeout(timer);
          return res.status(r.status).json({ success: r.status < 300 });
        }
      } catch (e) {
        clearTimeout(timer);
        return res.status(502).json({ success: false, error: e.message });
      }
    }
  } catch (err) {
    return res.status(500).json({ error: 'Proxy write error', details: err.message });
  }
};

module.exports.config = { maxDuration: 30 };
