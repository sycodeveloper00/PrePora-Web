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

  const apiKey = req.headers.authorization?.replace('Bearer ', '');
  if (!apiKey) {
    return res.status(401).json({ error: 'Missing Authorization header' });
  }

  const { model, messages, max_tokens, temperature, stream, baseUrl } = req.body;
  const targetBase = baseUrl || 'https://bazaarlink.ai/api/v1';

  try {
    const apiRes = await fetch(`${targetBase}/chat/completions`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: model || 'openrouter/free',
        messages,
        max_tokens: max_tokens || 4096,
        temperature: temperature ?? 0.3,
        stream: stream || false,
      }),
    });

    if (stream) {
      if (!apiRes.ok) {
        res.setHeader('Content-Type', 'text/event-stream');
        res.setHeader('Cache-Control', 'no-cache');
        res.setHeader('Connection', 'keep-alive');
        let errBody = '';
        try { errBody = await apiRes.text(); } catch (_) {}
        res.write(`data: ${JSON.stringify({ error: true, status: apiRes.status, details: errBody })}\n\n`);
        return res.end();
      }
      res.setHeader('Content-Type', 'text/event-stream');
      res.setHeader('Cache-Control', 'no-cache');
      res.setHeader('Connection', 'keep-alive');

      const reader = apiRes.body.getReader();
      const decoder = new TextDecoder();

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        res.write(decoder.decode(value, { stream: true }));
      }
      return res.end();
    }

    const data = await apiRes.json();
    return res.status(apiRes.status).json(data);
  } catch (err) {
    return res.status(502).json({ error: 'Proxy error', details: err.message });
  }
};
