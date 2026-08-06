class KaTeXInjector {
  static const _cdnBase = 'https://cdn.jsdelivr.net/npm/katex@0.16.11/dist';

  static const _cdnCss = '$_cdnBase/katex.min.css';
  static const _cdnJs = '$_cdnBase/katex.min.js';
  static const _cdnAutoRender = '$_cdnBase/contrib/auto-render.min.js';

  static String inject(String html) {
    var result = html;

    // Replace local KaTeX CSS references with CDN
    result = result.replaceAll(
      '../../../katex/katex.min.css', _cdnCss);
    result = result.replaceAll(
      '../../katex/katex.min.css', _cdnCss);
    result = result.replaceAll(
      '../katex/katex.min.css', _cdnCss);
    result = result.replaceAll(
      'katex/katex.min.css', _cdnCss);

    // Replace local KaTeX JS references with CDN
    result = result.replaceAll(
      '../../../katex/katex.min.js', _cdnJs);
    result = result.replaceAll(
      '../../katex/katex.min.js', _cdnJs);
    result = result.replaceAll(
      '../katex/katex.min.js', _cdnJs);
    result = result.replaceAll(
      'katex/katex.min.js', _cdnJs);

    // Replace local auto-render references with CDN
    result = result.replaceAll(
      '../../../katex/auto-render.min.js', _cdnAutoRender);
    result = result.replaceAll(
      '../../katex/auto-render.min.js', _cdnAutoRender);
    result = result.replaceAll(
      '../katex/auto-render.min.js', _cdnAutoRender);
    result = result.replaceAll(
      'katex/auto-render.min.js', _cdnAutoRender);

    return result;
  }
}
