import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// Clorabase Storage Service - Uses GitHub API as backend
/// Files are stored in a GitHub repository (Clorabase-projects/)
///
/// On web, all GitHub API calls are routed through a Vercel serverless proxy
/// (`/api/github-proxy`) because the browser's CORS policy blocks direct
/// requests to api.github.com.
class ClorabaseService {
  ClorabaseService._();

  static const String _proxyUrl = 'https://prepora-web.vercel.app/api/supabase-proxy';

  /// Makes a GitHub API request. On web, routes through Vercel proxy to bypass CORS.
  static Future<http.Response> _githubRequest({
    required String method,
    required String url,
    required String token,
    Map<String, dynamic>? body,
  }) async {
    if (kIsWeb) {
      return await http.post(
        Uri.parse(_proxyUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'action': 'github_proxy',
          'ghMethod': method,
          'ghUrl': url,
          'ghToken': token,
          if (body != null) 'ghBody': body,
        }),
      ).timeout(const Duration(seconds: 60));
    }
    final headers = {
      'Authorization': 'token $token',
      'Accept': 'application/vnd.github.v3+json',
    };
    if (body != null && (method == 'PUT' || method == 'POST' || method == 'PATCH')) {
      headers['Content-Type'] = 'application/json';
    }
    final uri = Uri.parse(url);
    switch (method) {
      case 'GET':
        return await http.get(uri, headers: headers);
      case 'PUT':
        return await http.put(uri, headers: headers, body: json.encode(body));
      case 'POST':
        return await http.post(uri, headers: headers, body: json.encode(body));
      case 'DELETE':
        return await http.delete(uri, headers: headers, body: body != null ? json.encode(body) : null);
      default:
        return await http.get(uri, headers: headers);
    }
  }

  /// Upload a file to Clorabase (GitHub repo)
  /// [username] - GitHub username
  /// [token] - GitHub Personal Access Token (PAT)
  /// [project] - Project name (folder in Clorabase-projects repo)
  /// [bytes] - File bytes to upload
  /// [filename] - Full path: e.g., "storage/images/photo.jpg"
  static Future<String> uploadFile({
    required String username,
    required String token,
    required String project,
    required List<int> bytes,
    required String filename,
  }) async {
    final repo = 'Clorabase-projects';
    final path = '$project/storage/$filename';
    final apiUrl = 'https://api.github.com/repos/$username/$repo/contents/$path';

    // Check if file already exists (to get SHA for update)
    String? existingSha;
    try {
      final checkResp = await _githubRequest(
        method: 'GET',
        url: apiUrl,
        token: token,
      );
      if (checkResp.statusCode == 200) {
        final data = json.decode(checkResp.body);
        existingSha = data['sha'] as String?;
      }
    } catch (_) {}

    // Encode file to base64
    final base64Content = base64Encode(bytes);

    // Create or update file (with retry up to 3 times)
    Exception? lastError;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final reqBody = <String, dynamic>{
          'message': 'Upload $filename via Clorabase',
          'content': base64Content,
        };
        if (existingSha != null) {
          reqBody['sha'] = existingSha;
        }

        final response = await _githubRequest(
          method: 'PUT',
          url: apiUrl,
          token: token,
          body: reqBody,
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          final rawUrl = 'https://raw.githubusercontent.com/$username/$repo/main/$path';
          return rawUrl;
        }

        // If 422 (already exists / SHA mismatch), re-fetch SHA and retry
        if (response.statusCode == 422 && attempt < 3) {
          try {
            final recheck = await _githubRequest(method: 'GET', url: apiUrl, token: token);
            if (recheck.statusCode == 200) {
              final data = json.decode(recheck.body);
              existingSha = data['sha'] as String?;
            }
          } catch (_) {}
          await Future.delayed(Duration(seconds: attempt * 2));
          continue;
        }

        lastError = Exception('Clorabase upload failed: ${response.statusCode} ${response.body}');
        if (attempt < 3) await Future.delayed(Duration(seconds: attempt * 2));
      } catch (e) {
        lastError = Exception('Clorabase upload attempt $attempt failed: $e');
        if (attempt < 3) await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    throw lastError ?? Exception('Clorabase upload failed after 3 attempts');
  }

  /// Delete a file from Clorabase
  static Future<void> deleteFile({
    required String username,
    required String token,
    required String project,
    required String filename,
  }) async {
    final repo = 'Clorabase-projects';
    final path = '$project/storage/$filename';
    final apiUrl = 'https://api.github.com/repos/$username/$repo/contents/$path';

    // Get SHA first
    final checkResp = await _githubRequest(
      method: 'GET',
      url: apiUrl,
      token: token,
    );

    if (checkResp.statusCode != 200) {
      throw Exception('File not found');
    }

    final data = json.decode(checkResp.body);
    final sha = data['sha'] as String;

    final response = await _githubRequest(
      method: 'DELETE',
      url: apiUrl,
      token: token,
      body: {
        'message': 'Delete $filename via Clorabase',
        'sha': sha,
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Delete failed: ${response.statusCode}');
    }
  }

  /// Verify Clorabase credentials and ensure "Clorabase-projects" repo exists
  static Future<Map<String, dynamic>> verifyCredentials({
    required String username,
    required String token,
  }) async {
    try {
      final response = await _githubRequest(
        method: 'GET',
        url: 'https://api.github.com/user',
        token: token,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final login = data['login'] as String? ?? '';
        if (login.toLowerCase() != username.toLowerCase()) {
          return {'valid': false, 'error': 'Token belongs to @$login, not @$username'};
        }

        // Check if "Clorabase-projects" repo exists, create if not
        final repoCheck = await _githubRequest(
          method: 'GET',
          url: 'https://api.github.com/repos/$username/Clorabase-projects',
          token: token,
        );

        if (repoCheck.statusCode == 404) {
          // Auto-create the repo
          final createResp = await _githubRequest(
            method: 'POST',
            url: 'https://api.github.com/user/repos',
            token: token,
            body: {
              'name': 'Clorabase-projects',
              'description': 'PrePora Clorabase storage',
              'auto_init': true,
              'private': false,
            },
          );
          if (createResp.statusCode != 201) {
            return {'valid': false, 'error': 'Failed to create repo: ${createResp.statusCode} ${createResp.body}'};
          }
        }

        return {'valid': true, 'name': data['name'] ?? login};
      }
      return {'valid': false, 'error': 'Invalid token (HTTP ${response.statusCode})'};
    } catch (e) {
      return {'valid': false, 'error': 'Connection failed: $e'};
    }
  }

  /// Get storage usage info
  static Future<Map<String, dynamic>> getStorageUsage({
    required String username,
    required String token,
    required String project,
  }) async {
    try {
      final repo = 'Clorabase-projects';
      final path = '$project/storage';
      final apiUrl = 'https://api.github.com/repos/$username/$repo/contents/$path';

      final response = await _githubRequest(
        method: 'GET',
        url: apiUrl,
        token: token,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          final fileCount = data.length;
          return {'fileCount': fileCount, 'status': 'ready'};
        }
        return {'fileCount': 0, 'status': 'empty'};
      }
      return {'fileCount': 0, 'status': 'error'};
    } catch (_) {
      return {'fileCount': 0, 'status': 'error'};
    }
  }
}
