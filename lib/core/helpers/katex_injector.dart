class KaTeXInjector {
  static const _cdnBase = 'https://cdn.jsdelivr.net/npm/katex@0.16.11/dist';

  static const _cdnCss = '$_cdnBase/katex.min.css';
  static const _cdnJs = '$_cdnBase/katex.min.js';
  static const _cdnAutoRender = '$_cdnBase/contrib/auto-render.min.js';

  static String inject(String html) {
    var result = html;

    // Replace any depth of relative path to KaTeX files
    // Matches: katex/katex.min.css, ../katex/..., ../../katex/..., ../../../../katex/...
    final cssPattern = RegExp(r'(?:\.\./)*katex/katex\.min\.css');
    final jsPattern = RegExp(r'(?:\.\./)*katex/katex\.min\.js');
    final arPattern = RegExp(r'(?:\.\./)*katex/auto-render\.min\.js');

    result = result.replaceAll(cssPattern, _cdnCss);
    result = result.replaceAll(jsPattern, _cdnJs);
    result = result.replaceAll(arPattern, _cdnAutoRender);

    // Ensure KaTeX is injected even if HTML has NO katex references at all
    final hasKatexCss = result.contains('katex.min.css');
    final hasKatexJs = result.contains('katex.min.js');

    final buffer = StringBuffer();
    if (!hasKatexCss) {
      buffer.writeln('<link rel="stylesheet" href="$_cdnCss">');
    }
    if (!hasKatexJs) {
      buffer.writeln('<script src="$_cdnJs"></script>');
      buffer.writeln('<script src="$_cdnAutoRender"></script>');
    }

    final injection = buffer.toString();
    if (injection.isNotEmpty) {
      if (result.contains('</head>')) {
        result = result.replaceFirst('</head>', '$injection</head>');
      } else if (result.contains('<body')) {
        result = result.replaceFirst(RegExp(r'<body[^>]*>'), '$injection\$0');
      } else {
        result = '$injection$result';
      }
    }

    return result;
  }
}
