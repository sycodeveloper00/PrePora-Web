import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

class FileReaderService {
  static const int _maxOcrChars = 50000;
  static const int _maxDocChars = 50000;
  static const int _maxImageDimension = 2048;

  static const _textExtensions = {
    'txt', 'csv', 'json', 'xml', 'html', 'md',
    'py', 'js', 'dart', 'java', 'cpp', 'c', 'h', 'cs',
    'css', 'scss', 'less', 'yaml', 'yml', 'toml', 'ini', 'cfg',
    'sh', 'bat', 'ps1', 'rb', 'php', 'go', 'rs', 'swift', 'kt',
    'ts', 'jsx', 'tsx', 'vue', 'svelte',
  };

  static const _imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'};
  static const _videoExtensions = {'mp4', 'avi', 'mov', 'mkv'};
  static const _audioExtensions = {'mp3', 'wav'};
  static const _docExtensions = {'pdf', 'doc', 'docx'};

  static Future<FilePickResult?> pickAndReadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: [
          ..._textExtensions,
          ..._imageExtensions,
          ..._videoExtensions,
          ..._audioExtensions,
          ..._docExtensions,
          'ppt', 'pptx', 'xls', 'xlsx',
          'zip', 'rar', '7z',
        ],
      );

      if (result == null || result.files.isEmpty) return null;

      final file = result.files.first;
      final fileName = file.name;
      final ext = fileName.split('.').last.toLowerCase();

      if (_imageExtensions.contains(ext)) {
        return _readImage(file);
      }

      if (_videoExtensions.contains(ext) || _audioExtensions.contains(ext)) {
        return FilePickResult(
          fileName: fileName,
          content: '[Media file: $fileName] - This is a media file.',
        );
      }

      if (ext == 'pdf') {
        return _readPdf(file, fileName);
      }

      if (ext == 'docx') {
        return _readDocx(file, fileName);
      }

      if (ext == 'doc') {
        return FilePickResult(
          fileName: fileName,
          content: '[File: $fileName] - Legacy .doc format detected. Please convert to .docx or PDF for better reading.',
        );
      }

      final binaryExtensions = {'ppt', 'pptx', 'xls', 'xlsx', 'zip', 'rar', '7z'};
      if (binaryExtensions.contains(ext)) {
        return FilePickResult(
          fileName: fileName,
          content: '[File: $fileName] - This file type may need a compatible viewer.',
        );
      }

      return _readTextFile(file, fileName);
    } catch (e) {
      return null;
    }
  }

  static Future<FilePickResult> _readImage(PlatformFile file) async {
    try {
      final bytes = file.bytes ?? (!kIsWeb && file.path != null ? File(file.path!).readAsBytesSync() : null);
      if (bytes == null) {
        return FilePickResult(
          fileName: file.name,
          content: '[Image: ${file.name}] - Unable to read image data.',
        );
      }

      Uint8List processedBytes = bytes;
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        final frameInfo = await codec.getNextFrame();
        final w = frameInfo.image.width;
        final h = frameInfo.image.height;
        if (w > _maxImageDimension || h > _maxImageDimension) {
          final ratio = w / h;
          int tw, th;
          if (w > h) {
            tw = _maxImageDimension;
            th = (_maxImageDimension / ratio).round();
          } else {
            th = _maxImageDimension;
            tw = (_maxImageDimension * ratio).round();
          }
          final resizedCodec = await ui.instantiateImageCodec(bytes,
              targetWidth: tw, targetHeight: th);
          final resizedFrame = await resizedCodec.getNextFrame();
          final byteData = await resizedFrame.image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) processedBytes = byteData.buffer.asUint8List();
        }
      } catch (_) {}

      String? extracted;
      if (!kIsWeb) {
        try {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_${file.name}');
          await tempFile.writeAsBytes(processedBytes);
          final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
          try {
            final inputImage = InputImage.fromFilePath(tempFile.path);
            final recognizedText = await textRecognizer.processImage(inputImage);
            extracted = recognizedText.text.trim();
          } finally {
            await textRecognizer.close();
            if (await tempFile.exists()) await tempFile.delete();
          }
        } catch (_) {}
      }

      if (extracted != null && extracted.isNotEmpty) {
        final charCount = extracted.length;
        final preview = charCount > _maxOcrChars
            ? '${extracted.substring(0, _maxOcrChars)}\n\n[... text truncated to $charCount characters ...]'
            : extracted;
        return FilePickResult(
          fileName: file.name,
          content: 'The user shared an image: "${file.name}"\n\n'
              'Text extracted from image via OCR ($charCount chars):\n$preview',
        );
      }

      return FilePickResult(
        fileName: file.name,
        content: kIsWeb
            ? '[Image: ${file.name}] - OCR not available on web.'
            : '[Image: ${file.name}] - No readable text found in this image.',
      );
    } catch (e) {
      return FilePickResult(
        fileName: file.name,
        content: '[Image: ${file.name}] - OCR failed: $e',
      );
    }
  }

  static Future<FilePickResult> _readPdf(PlatformFile file, String fileName) async {
    try {
      final bytes = file.bytes ?? (!kIsWeb && file.path != null ? File(file.path!).readAsBytesSync() : null);
      if (bytes == null) {
        return FilePickResult(fileName: fileName, content: '[PDF: $fileName] - Unable to read file.');
      }
      final doc = PdfDocument(inputBytes: bytes);
      final text = PdfTextExtractor(doc).extractText();
      doc.dispose();
      if (text.trim().isEmpty) {
        return FilePickResult(
          fileName: fileName,
          content: '[PDF: $fileName] - No text could be extracted (scanned document).',
        );
      }
      final charCount = text.length;
      final preview = charCount > _maxDocChars
          ? '${text.substring(0, _maxDocChars)}\n\n[... PDF text truncated to $charCount characters ...]'
          : text;
      return FilePickResult(
        fileName: fileName,
        content: 'The user shared a PDF: "$fileName"\n\nPDF contents ($charCount chars):\n$preview',
      );
    } catch (e) {
      return FilePickResult(
        fileName: fileName,
        content: '[PDF: $fileName] - Could not read PDF: $e',
      );
    }
  }

  static Future<FilePickResult> _readDocx(PlatformFile file, String fileName) async {
    try {
      final bytes = file.bytes ?? (!kIsWeb && file.path != null ? File(file.path!).readAsBytesSync() : null);
      if (bytes == null) {
        return FilePickResult(fileName: fileName, content: '[DOCX: $fileName] - Unable to read file.');
      }
      final archive = ZipDecoder().decodeBytes(bytes);
      final docFile = archive.files.firstWhere(
        (f) => f.name == 'word/document.xml',
        orElse: () => throw Exception('Invalid DOCX format'),
      );
      final xmlContent = utf8.decode(docFile.content);
      final text = _stripXmlTags(xmlContent);
      if (text.trim().isEmpty) {
        return FilePickResult(
          fileName: fileName,
          content: '[DOCX: $fileName] - No text could be extracted.',
        );
      }
      final charCount = text.length;
      final preview = charCount > _maxDocChars
          ? '${text.substring(0, _maxDocChars)}\n\n[... DOCX text truncated to $charCount characters ...]'
          : text;
      return FilePickResult(
        fileName: fileName,
        content: 'The user shared a document: "$fileName"\n\nDocument contents ($charCount chars):\n$preview',
      );
    } catch (e) {
      return FilePickResult(
        fileName: fileName,
        content: '[DOCX: $fileName] - Could not read document: $e',
      );
    }
  }

  static String _stripXmlTags(String xml) {
    return xml
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static Future<FilePickResult> _readTextFile(PlatformFile file, String fileName) async {
    String? content;
    if (file.bytes != null) {
      content = utf8.decode(file.bytes!);
    } else if (!kIsWeb && file.path != null) {
      final bytes = File(file.path!).readAsBytesSync();
      content = utf8.decode(bytes);
    }
    if (content == null || content.trim().isEmpty) {
      return FilePickResult(
        fileName: fileName,
        content: '[Empty file or unable to read content]',
      );
    }
    final charCount = content.length;
    if (charCount > _maxDocChars) {
      content = '${content.substring(0, _maxDocChars)}\n\n[... file truncated to $charCount characters ...]';
    }
    return FilePickResult(fileName: fileName, content: content);
  }
}

class FilePickResult {
  final String fileName;
  final String content;
  FilePickResult({required this.fileName, required this.content});
}
