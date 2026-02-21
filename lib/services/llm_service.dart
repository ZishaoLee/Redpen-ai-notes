import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'settings_service.dart';
import '../models/ai_config.dart';

/// LLM 调用结果封装 (Legacy support, though we prefer streams now)
class LlmResult {
  final bool success;
  final String content;
  const LlmResult({required this.success, required this.content});
}

class LlmService {
  // Use a persistent client to support Keep-Alive and connection pooling
  static final http.Client _client = http.Client();

  // ── URL Helpers ───────────────────────────────────────

  List<String> _buildUrls(AIConfig config) {
    List<String> urls = [];

    // Helper to format a single base URL
    String format(String base) {
      if (base.isEmpty) {
        return config.provider == 'gemini'
            ? 'https://generativelanguage.googleapis.com'
            : 'https://api.openai.com/v1';
      }
      if (base.endsWith('/')) return base.substring(0, base.length - 1);
      return base;
    }

    // Add Primary
    urls.add(format(config.baseUrl));

    // Add Backups
    for (var url in config.backupBaseUrls) {
      if (url.isNotEmpty) urls.add(format(url));
    }

    // Append endpoint path
    return urls.map((base) {
      if (config.provider == 'gemini') {
        return '$base/v1beta/models/${config.modelName}:streamGenerateContent?alt=sse&key=${config.apiKey}';
      } else {
        return '$base/chat/completions';
      }
    }).toList();
  }

  // ── Connection Testing ───────────────────────────────

  Future<int> testConnection(AIConfig config) async {
    final stopwatch = Stopwatch()..start();
    final urls = _buildUrls(config);

    if (config.apiKey.isEmpty) throw Exception('API Key is empty');

    for (var url in urls) {
      try {
        http.Request request;
        if (config.provider == 'gemini') {
          // For Gemini, we can use a simple generateContent with "Hi"
          // Note: The URL in _buildUrls is for streaming. We need non-streaming for simple test?
          // Or just use streaming and check first chunk.
          // Let's modify the URL for non-streaming if possible, or just use the stream endpoint.
          // Actually _buildUrls returns the streaming endpoint.
          request = http.Request('POST', Uri.parse(url));
          request.headers['Content-Type'] = 'application/json';
          request.body = jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': 'Hi'}
                ]
              }
            ],
            'generationConfig': {'maxOutputTokens': 10},
          });
        } else {
          request = http.Request('POST', Uri.parse(url));
          request.headers['Content-Type'] = 'application/json';
          request.headers['Authorization'] = 'Bearer ${config.apiKey}';
          request.body = jsonEncode({
            'model': config.modelName.isEmpty ? 'gpt-4o' : config.modelName,
            'messages': [
              {'role': 'user', 'content': 'Hi'}
            ],
            'max_tokens': 5,
            'stream': false, // Use non-stream for test
          });
        }

        final response =
            await _client.send(request).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          stopwatch.stop();
          return stopwatch.elapsedMilliseconds;
        } else {
          // Try next URL
          continue;
        }
      } catch (e) {
        continue;
      }
    }
    throw Exception('All endpoints failed');
  }

  // ── Image Compression ─────────────────────────────────

  Future<Uint8List> _compressImage(XFile file) async {
    // Optimization: Use compressWithFile to avoid loading full image into memory first
    // This reduces memory spikes and can be faster on native platforms.
    try {
      final result = await FlutterImageCompress.compressWithFile(
        file.path,
        minHeight: 1920, // Increased from 1024 to 1920 for better OCR accuracy
        minWidth: 1920, // Increased from 1024 to 1920 for better OCR accuracy
        quality: 85, // Increased from 70 to 85 to reduce artifacts
        rotate: 0, // Keep original rotation or auto
      );

      if (result != null) return result;

      // Fallback if compressWithFile returns null (e.g. not supported format)
      debugPrint('CompressWithFile returned null, falling back to bytes');
      return await file.readAsBytes();
    } catch (e) {
      debugPrint('Compression failed: $e');
      return await file.readAsBytes(); // Fallback to original
    }
  }

  // ── Streaming API: Vision Analysis ────────────────────

  Stream<String> analyzeImagesStream({
    required List<XFile> images,
    required SettingsService settings,
    required String promptContent,
    String? supplementaryPrompt,
  }) async* {
    if (images.isEmpty) {
      yield 'Error: No images selected.';
      return;
    }

    final config = settings.visionConfig;
    if (config.apiKey.isEmpty) {
      yield 'Error: API Key not configured for ${config.provider}.';
      return;
    }

    // Parallel Compression
    // Optimization: Run compression in parallel futures
    final futureBytes = images.map((img) => _compressImage(img));
    final List<Uint8List> imageBytesList = await Future.wait(futureBytes);

    final List<String> base64Images =
        imageBytesList.map((b) => base64Encode(b)).toList();

    // Construct User Message
    String userMessage = '请根据 System Prompt 的要求，对上传的图片内容进行分析处理。';
    if (supplementaryPrompt != null && supplementaryPrompt.isNotEmpty) {
      userMessage += '\n\n额外补充要求: $supplementaryPrompt';
    }

    final urls = _buildUrls(config);
    bool success = false;

    for (int i = 0; i < urls.length; i++) {
      final url = Uri.parse(urls[i]);
      debugPrint('Attempting Vision Request to ($i/${urls.length}): $url');

      try {
        http.Request request;

        if (config.provider == 'gemini') {
          request = http.Request('POST', url);
          request.headers['Content-Type'] = 'application/json';

          final List<Map<String, dynamic>> parts = [
            {'text': userMessage},
          ];
          for (final b64 in base64Images) {
            parts.add({
              'inline_data': {'mime_type': 'image/jpeg', 'data': b64},
            });
          }

          request.body = jsonEncode({
            'system_instruction': {
              'parts': [
                {'text': promptContent}
              ],
            },
            'contents': [
              {'parts': parts}
            ],
            'generationConfig': {'maxOutputTokens': 8192},
          });
        } else {
          // OpenAI
          request = http.Request('POST', url);
          request.headers['Content-Type'] = 'application/json';
          request.headers['Authorization'] = 'Bearer ${config.apiKey}';

          final List<Map<String, dynamic>> contentParts = [
            {'type': 'text', 'text': userMessage},
          ];
          for (final b64 in base64Images) {
            contentParts.add({
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,$b64'},
            });
          }

          request.body = jsonEncode({
            'model': config.modelName.isEmpty ? 'gpt-4o' : config.modelName,
            'messages': [
              {'role': 'system', 'content': promptContent},
              {'role': 'user', 'content': contentParts},
            ],
            'stream': true,
            'max_tokens': 4096,
          });
        }

        final response =
            await _client.send(request).timeout(const Duration(seconds: 30));

        if (response.statusCode != 200) {
          final body = await response.stream.bytesToString();
          debugPrint('Error from ${urls[i]}: $body');
          // If it's a server error or rate limit, try next
          if (response.statusCode >= 500 || response.statusCode == 429) {
            if (i == urls.length - 1)
              yield 'Error (${response.statusCode}): $body';
            continue;
          }
          yield 'Error (${response.statusCode}): $body';
          return; // Client error, don't retry
        }

        // Parse Stream
        final stream = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());

        await for (final line in stream) {
          if (line.trim().isEmpty) continue;

          if (config.provider == 'gemini') {
            if (line.startsWith('data: ')) {
              final jsonStr = line.substring(6);
              try {
                final json = jsonDecode(jsonStr);
                final candidates = json['candidates'] as List?;
                if (candidates != null && candidates.isNotEmpty) {
                  final content = candidates[0]['content'];
                  if (content != null && content['parts'] != null) {
                    final parts = content['parts'] as List;
                    if (parts.isNotEmpty) {
                      final text = parts[0]['text'] as String?;
                      if (text != null) yield text;
                    }
                  }
                }
              } catch (_) {}
            }
          } else {
            if (line.startsWith('data: ')) {
              final jsonStr = line.substring(6);
              if (jsonStr == '[DONE]') break;
              try {
                final json = jsonDecode(jsonStr);
                final choices = json['choices'] as List?;
                if (choices != null && choices.isNotEmpty) {
                  final delta = choices[0]['delta'];
                  if (delta != null && delta.containsKey('content')) {
                    final content = delta['content'] as String?;
                    if (content != null) yield content;
                  }
                }
              } catch (_) {}
            }
          }
        }

        success = true;
        break; // Success, exit loop
      } catch (e) {
        debugPrint('Exception connecting to ${urls[i]}: $e');
        if (i == urls.length - 1) {
          yield 'Error: All endpoints failed. Last error: $e';
        }
      }
    }
  }

  // ── Streaming API: Chat Fix ──────────────────────────

  Stream<String> chatFixTextStream({
    required String originalText,
    required List<Map<String, String>> history,
    required String newInstruction,
    required String promptContent,
    required SettingsService settings,
  }) async* {
    final config = settings.editConfig;

    if (config.apiKey.isEmpty) {
      yield 'Error: API Key not configured for ${config.provider}.';
      return;
    }

    final urls = _buildUrls(config);

    // ── Prompt Construction ──
    final String systemMessage = """
【最高优先级：全局排版与数学公式规范】
$promptContent
（注意：你在下方的所有修改，必须绝对服从上述规范！严禁破坏原有的 LaTeX 语法体系！）

【输出要求】:
你必须且只能输出修改后的纯文本代码。严禁输出任何解释！严禁使用 Markdown 代码块的反引号（```）包裹结果！
""";
    final String contextMessage = """
【原始文本片段】:
$originalText
""";
    final String userInstruction = """
【修改要求】:
$newInstruction
""";

    for (int i = 0; i < urls.length; i++) {
      final url = Uri.parse(urls[i]);
      debugPrint('Attempting Edit Request to ($i/${urls.length}): $url');

      try {
        http.Request request;

        if (config.provider == 'gemini') {
          request = http.Request('POST', url);
          request.headers['Content-Type'] = 'application/json';

          final List<Map<String, dynamic>> contents = [];

          // Turn 0: Context
          contents.add({
            'role': 'user',
            'parts': [
              {'text': contextMessage}
            ]
          });
          contents.add({
            'role': 'model',
            'parts': [
              {'text': '收到，请提供修改指令。'}
            ]
          });

          // Turn 1..N: History
          for (final msg in history) {
            contents.add({
              'role': msg['role'] == 'user' ? 'user' : 'model',
              'parts': [
                {'text': msg['content']}
              ]
            });
          }

          // Turn N+1: Current Instruction
          contents.add({
            'role': 'user',
            'parts': [
              {'text': userInstruction}
            ]
          });

          request.body = jsonEncode({
            'system_instruction': {
              'parts': [
                {'text': systemMessage}
              ],
            },
            'contents': contents,
            'generationConfig': {'maxOutputTokens': 8192},
          });
        } else {
          request = http.Request('POST', url);
          request.headers['Content-Type'] = 'application/json';
          request.headers['Authorization'] = 'Bearer ${config.apiKey}';

          final List<Map<String, dynamic>> messages = [
            {'role': 'system', 'content': systemMessage},
          ];

          messages.add({'role': 'user', 'content': contextMessage});
          messages.add({'role': 'assistant', 'content': '收到，请提供修改指令。'});

          for (final msg in history) {
            messages.add({'role': msg['role']!, 'content': msg['content']!});
          }

          messages.add({'role': 'user', 'content': userInstruction});

          request.body = jsonEncode({
            'model': config.modelName.isEmpty ? 'gpt-4o' : config.modelName,
            'messages': messages,
            'stream': true,
            'max_tokens': 4096,
          });
        }

        final response =
            await _client.send(request).timeout(const Duration(seconds: 30));

        if (response.statusCode != 200) {
          final body = await response.stream.bytesToString();
          if (response.statusCode >= 500 || response.statusCode == 429) {
            if (i == urls.length - 1)
              yield 'Error (${response.statusCode}): $body';
            continue;
          }
          yield 'Error (${response.statusCode}): $body';
          return;
        }

        final stream = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());

        await for (final line in stream) {
          if (line.trim().isEmpty) continue;
          if (config.provider == 'gemini') {
            if (line.startsWith('data: ')) {
              try {
                final json = jsonDecode(line.substring(6));
                final candidates = json['candidates'] as List?;
                if (candidates != null && candidates.isNotEmpty) {
                  final parts = candidates[0]['content']['parts'] as List?;
                  if (parts != null && parts.isNotEmpty) {
                    final text = parts[0]['text'] as String?;
                    if (text != null) yield text;
                  }
                }
              } catch (_) {}
            }
          } else {
            if (line.startsWith('data: ')) {
              final jsonStr = line.substring(6);
              if (jsonStr == '[DONE]') break;
              try {
                final json = jsonDecode(jsonStr);
                final choices = json['choices'] as List?;
                if (choices != null && choices.isNotEmpty) {
                  final delta = choices[0]['delta'];
                  if (delta != null && delta.containsKey('content')) {
                    final content = delta['content'] as String?;
                    if (content != null) yield content;
                  }
                }
              } catch (_) {}
            }
          }
        }

        break; // Success
      } catch (e) {
        debugPrint('Exception connecting to ${urls[i]}: $e');
        if (i == urls.length - 1) {
          yield 'Error: All endpoints failed. Last error: $e';
        }
      }
    }
  }
}
