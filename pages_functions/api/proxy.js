const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

export async function onRequest(context) {
  const { request } = context;

  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  if (request.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const auth = request.headers.get('Authorization') || '';
  const apiKey = auth.replace('Bearer ', '');
  if (!apiKey) {
    return new Response(JSON.stringify({ error: 'Missing Authorization header' }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  let body;
  try {
    body = await request.json();
  } catch (_) {
    return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const { model, messages, max_tokens, temperature, stream, baseUrl } = body;
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
        let errBody = '';
        try { errBody = await apiRes.text(); } catch (_) {}
        return new Response(
          `data: ${JSON.stringify({ error: true, status: apiRes.status, details: errBody })}\n\n`,
          {
            status: 200,
            headers: {
              ...corsHeaders,
              'Content-Type': 'text/event-stream',
              'Cache-Control': 'no-cache',
              'Connection': 'keep-alive',
            },
          },
        );
      }
      return new Response(apiRes.body, {
        status: 200,
        headers: {
          ...corsHeaders,
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive',
        },
      });
    }

    const data = await apiRes.json();
    return new Response(JSON.stringify(data), {
      status: apiRes.status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: 'Proxy error', details: err.message }), {
      status: 502,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}
