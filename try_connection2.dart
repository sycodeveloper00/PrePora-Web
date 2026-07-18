import 'dart:io';

void main() async {
  // Try actual HttpClient with connectionFactory
  try {
    var client = HttpClient();
    client.connectionFactory = (Uri url, String? host, int port) async {
      print('ConnectionFactory called: host=$host, port=$port');
      // Try connecting to Cloudflare IP directly
      var socket = await Socket.connect('104.21.27.200', port,
          timeout: Duration(seconds: 5));
      print('Connected to 104.21.27.200:$port');
      // Return a ConnectionTask - might not work
      return ConnectionTask<Socket>(socket, () => socket.destroy());
    };

    var req = await client.getUrl(Uri.parse('https://bazaarlink.ai/'));
    req.headers.set('Host', 'bazaarlink.ai');
    var resp = await req.close();
    var body = await resp.transform(utf8.decoder).join();
    print('Status: ${resp.statusCode}');
    print('Body: ${body.substring(0, 100)}');
    client.close();
  } catch (e) {
    print('Error: $e');
    print('Type: ${e.runtimeType}');
  }
}
