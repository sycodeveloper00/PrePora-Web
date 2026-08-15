export async function onRequest(context) {
  const { request } = context;

  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  };

  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (request.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }

  try {
    const body = await request.json();
    const { supabaseUrl, bucket, path, fileBase64, filename, auth, _method } = body;

    if (!supabaseUrl || !bucket || !path || !auth) {
      return new Response(JSON.stringify({ error: 'Missing required fields' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    if (_method === 'DELETE') {
      const deleteUrl = `${supabaseUrl}/storage/v1/object/${bucket}/${path}`;
      const response = await fetch(deleteUrl, {
        method: 'DELETE',
        headers: { 'Authorization': auth },
      });
      const result = await response.text();
      if (!response.ok) {
        return new Response(JSON.stringify({ error: result }), { status: response.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }
      return new Response(result, { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    if (!fileBase64) {
      return new Response(JSON.stringify({ error: 'Missing fileBase64' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const fileBuffer = Uint8Array.from(atob(fileBase64), c => c.charCodeAt(0));
    const boundary = '----FormBoundary' + Math.random().toString(36).slice(2);
    const fname = filename || path.split('/').pop();

    const part1 = new TextEncoder().encode(
      `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${fname}"\r\nContent-Type: application/octet-stream\r\n\r\n`
    );
    const part2 = new TextEncoder().encode(`\r\n--${boundary}--\r\n`);

    const fullBody = new Uint8Array(part1.length + fileBuffer.length + part2.length);
    fullBody.set(part1, 0);
    fullBody.set(fileBuffer, part1.length);
    fullBody.set(part2, part1.length + fileBuffer.length);

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
      return new Response(JSON.stringify({ error: result }), { status: response.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    return new Response(result, { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
}
