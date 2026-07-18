import 'dart:js' as js;

void callRenderPdf(String blobUrl, String containerId) {
  js.context.callMethod('renderPdfToCanvas', [blobUrl, containerId, js.context['innerWidth']]);
}
