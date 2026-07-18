import 'dart:convert';
import 'package:http/http.dart' as http;

class WebScraperService {
  static Future<String?> fetchUrlContent(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      });
      if (response.statusCode == 200) {
        final body = response.body;
        final cleaned = _stripHtml(body);
        return cleaned.length > 8000 ? '${cleaned.substring(0, 8000)}...' : cleaned;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> fetchYouTubeTranscript(String videoId) async {
    try {
      final response = await http.get(
        Uri.parse('https://youtubetranscript.com/?v=$videoId'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          final text = data.map((e) => e['text']).join(' ');
          return text.length > 8000 ? '${text.substring(0, 8000)}...' : text;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> searchYouTube(String query) async {
    try {
      final response = await http.get(
        Uri.parse('https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      );
      if (response.statusCode == 200) {
        final body = response.body;
        final videoIds = RegExp(r'\/watch\?v=([a-zA-Z0-9_-]{11})').allMatches(body).toList();
        if (videoIds.length > 3) videoIds.length = 3;

        final results = <String>[];
        for (final match in videoIds) {
          final vid = match.group(1)!;
          final titleMatch = RegExp('$vid.*?title="(.*?)"').firstMatch(body);
          final title = titleMatch?.group(1) ?? 'Untitled';
          results.add('$title (https://youtube.com/watch?v=$vid)');
        }

        if (results.isEmpty) return null;

        final list = results.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n');
        return 'YouTube search results for "$query":\n\n$list\n\n'
            'To get the transcript of any of these videos, share its link.';
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static String _stripHtml(String html) {
    final withoutTags = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
    final decoded = withoutTags
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'&[a-zA-Z]+;'), ' ');
    return decoded.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String? extractVideoId(String url) {
    final patterns = [
      RegExp(r'(?:youtube\.com/watch\?v=|youtu\.be/|youtube\.com/embed/)([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/shorts/([a-zA-Z0-9_-]{11})'),
    ];
    for (final p in patterns) {
      final match = p.firstMatch(url);
      if (match != null) return match.group(1);
    }
    return null;
  }

  static bool isUrl(String text) {
    return text.contains(RegExp(r'https?://[^\s]+'));
  }

  static bool isYouTubeSearchQuery(String text) {
    final lower = text.toLowerCase();
    return lower.startsWith('search youtube') ||
        lower.startsWith('find youtube') ||
        lower.startsWith('youtube search') ||
        lower.contains('find a video on') ||
        lower.contains('search for') && lower.contains('youtube');
  }

  static String _extractSearchQuery(String text) {
    final lower = text.toLowerCase();
    final patterns = [
      RegExp(r'(?:search youtube|find youtube|youtube search)\s+(?:for\s+)?(.+)', caseSensitive: false),
      RegExp(r'find\s+a\s+video\s+on\s+(.+)', caseSensitive: false),
      RegExp(r'search\s+for\s+(.+?)\s+on\s+youtube', caseSensitive: false),
    ];
    for (final p in patterns) {
      final match = p.firstMatch(text);
      if (match != null) return match.group(1)!.trim();
    }
    return text;
  }

  static Future<String?> processMessage(String text) async {
    final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(text);
    if (urlMatch == null) {
      if (isYouTubeSearchQuery(text)) {
        final query = _extractSearchQuery(text);
        return await searchYouTube(query);
      }
      return null;
    }

    final url = urlMatch.group(0)!;
    final videoId = extractVideoId(url);

    if (videoId != null) {
      final transcript = await fetchYouTubeTranscript(videoId);
      if (transcript != null) {
        return 'The user shared a YouTube video (https://youtube.com/watch?v=$videoId). '
            'Here is its transcript:\n\n$transcript\n\n'
            'Use this transcript to answer the user\'s questions about the video. '
            'If the transcript is empty or irrelevant, just acknowledge the video topic.';
      }
      return 'The user shared a YouTube video link ($url). '
          'Acknowledge it and offer help based on the topic. You have permission to access YouTube content.';
    }

    final content = await fetchUrlContent(url);
    if (content != null) {
      return 'The user shared this link: $url\n\n'
          'Here is the content from that page:\n\n$content\n\n'
          'Use this content to answer the user\'s questions.';
    }
    return null;
  }
}
