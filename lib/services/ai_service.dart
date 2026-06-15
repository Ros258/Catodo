import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'llm_provider_registry.dart';
import 'ai_agent.dart';

class AIConfig {
  final String providerId;
  final String apiKey;
  final String apiUrl;
  final String modelName;

  AIConfig({
    this.providerId = 'custom',
    required this.apiKey,
    required this.apiUrl,
    required this.modelName,
  });

  bool get isValid =>
      apiKey.isNotEmpty && apiUrl.isNotEmpty && modelName.isNotEmpty;

  LLMProvider get provider => LLMProviderRegistry.getById(providerId);
}

/// 连接测试结果
class ConnectionTestResult {
  final bool success;
  final String message;
  final String? detail;

  ConnectionTestResult({
    required this.success,
    required this.message,
    this.detail,
  });
}

class AIService {
  final AIConfig config;
  final Dio _dio;
  final LLMProvider _provider;

  AIService(this.config)
    : _provider = config.provider,
      _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 60),
          headers: {
            'Authorization': 'Bearer ${config.apiKey}',
            'Content-Type': 'application/json',
          },
        ),
      );

  @visibleForTesting
  String get fullApiUrl => config.apiUrl;

  /// 从 apiUrl 推导出 models 端点 URL
  ///
  /// 规则：将末尾的 /chat/completions 替换为 /models
  /// 例如：https://api.openai.com/v1/chat/completions → https://api.openai.com/v1/models
  @visibleForTesting
  String get modelsEndpoint {
    final url = fullApiUrl;
    if (url.endsWith('/chat/completions')) {
      return url.replaceAll('/chat/completions', '/models');
    }
    // 如果 URL 不以 /chat/completions 结尾，尝试在最后一个 / 前插入
    final lastSlash = url.lastIndexOf('/');
    if (lastSlash > 0) {
      return '${url.substring(0, lastSlash)}/models';
    }
    return '$url/models';
  }

  /// 从厂商 API 动态获取可用模型列表
  ///
  /// 通过 GET /models 端点获取，返回模型 ID 列表。
  /// 如果请求失败，返回空列表。
  Future<List<String>> fetchModels() async {
    if (config.apiUrl.isEmpty || config.apiKey.isEmpty) {
      return [];
    }

    try {
      final response = await _dio.get(
        modelsEndpoint,
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      final data = response.data;
      if (data is! Map) return [];

      final modelList = data['data'];
      if (modelList is! List) return [];

      final models = <String>[];
      for (final item in modelList) {
        if (item is Map) {
          final id = item['id'];
          if (id is String && id.isNotEmpty) {
            models.add(id);
          }
        }
      }

      models.sort();
      return models;
    } catch (e) {
      debugPrint('获取模型列表失败: $e');
      return [];
    }
  }

  /// 请求结构化 JSON 输出
  ///
  /// 兼容策略：
  /// - 不发送 response_format（最大兼容性，所有厂商都支持）
  /// - 通过 prompt 强制要求 JSON 格式
  /// - 宽容解析响应：兼容 markdown 代码块包裹、多余空白等
  Future<Map<String, dynamic>?> requestStructuredOutput({
    required String systemPrompt,
    required String userPrompt,
  }) async {
    try {
      final data = <String, dynamic>{
        'model': config.modelName,
        'messages': [
          {
            'role': 'system',
            'content':
                '$systemPrompt\n\n【格式约束 - 最高优先级】你的整个回复必须是一个纯 JSON 对象，且只能包含 JSON 内容。禁止输出任何 markdown 标记（如 ```json）、代码块包装、解释性文字、或 JSON 之外的任何内容。',
          },
          {'role': 'user', 'content': userPrompt},
        ],
        'temperature': _provider.defaultTemperature,
      };

      final response = await _dio.post(fullApiUrl, data: data);

      final rawContent = _extractContent(response.data);
      if (rawContent == null) {
        debugPrint('AI API 响应格式无法解析: ${response.data}');
        return null;
      }

      return _parseJsonContent(rawContent);
    } on DioException catch (e) {
      final errorMsg = _parseError(e);
      debugPrint('AI API 请求失败: $errorMsg');
      debugPrint('  请求 URL: $fullApiUrl');
      return null;
    } catch (e) {
      debugPrint('AI 服务异常: $e');
      debugPrint('  请求 URL: $fullApiUrl');
      return null;
    }
  }

  /// 轻量级连接测试
  ///
  /// 发送最简单的请求验证连通性，不依赖 JSON 解析等业务逻辑。
  /// 返回详细的测试结果，便于用户排查问题。
  Future<ConnectionTestResult> testConnection() async {
    // 第一步：验证配置完整性
    if (!config.isValid) {
      return ConnectionTestResult(
        success: false,
        message: '配置不完整',
        detail: '请填写 API URL、API Key 和模型名称',
      );
    }

    // 第二步：验证 URL 格式
    final uri = Uri.tryParse(fullApiUrl);
    if (uri == null || (!uri.hasScheme || !uri.hasAuthority)) {
      return ConnectionTestResult(
        success: false,
        message: 'API URL 格式无效',
        detail:
            '当前 URL: $fullApiUrl\n应为完整地址，如 https://api.openai.com/v1/chat/completions',
      );
    }

    // 第三步：发送最简请求测试连通性
    try {
      final response = await _dio.post(
        fullApiUrl,
        data: {
          'model': config.modelName,
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
          'max_tokens': 5,
        },
      );

      // 验证响应中能提取出内容
      final content = _extractContent(response.data);
      if (content != null) {
        return ConnectionTestResult(
          success: true,
          message: '连接成功',
          detail: '模型 ${config.modelName} 响应正常',
        );
      }

      // 响应格式不标准但请求本身成功了
      return ConnectionTestResult(
        success: true,
        message: '连接成功（响应格式非标准）',
        detail: 'API 可达，但响应结构可能与预期不同。功能可能受影响。',
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final responseBody = e.response?.data;
      String detail = '';

      if (responseBody is Map) {
        // 尝试提取厂商返回的错误信息
        final errorObj = responseBody['error'];
        if (errorObj is Map) {
          detail = errorObj['message']?.toString() ?? '';
        } else if (errorObj is String) {
          detail = errorObj;
        }
        if (detail.isEmpty) {
          detail = responseBody.toString();
        }
      } else if (responseBody != null) {
        detail = responseBody.toString();
      }

      switch (statusCode) {
        case 401:
          return ConnectionTestResult(
            success: false,
            message: 'API Key 无效或已过期',
            detail: detail.isNotEmpty ? '厂商返回: $detail' : '请检查 API Key 是否正确',
          );
        case 403:
          return ConnectionTestResult(
            success: false,
            message: '访问被拒绝',
            detail: detail.isNotEmpty ? '厂商返回: $detail' : '请检查 API Key 权限',
          );
        case 404:
          return ConnectionTestResult(
            success: false,
            message: '端点未找到',
            detail:
                '请检查 API URL 是否正确\n当前 URL: $fullApiUrl\n${detail.isNotEmpty ? '厂商返回: $detail' : ''}',
          );
        case 429:
          return ConnectionTestResult(
            success: true,
            message: '连接正常（请求频率受限）',
            detail: 'API Key 有效，但当前请求频率超限，请稍后再试',
          );
        case 400:
          return ConnectionTestResult(
            success: false,
            message: '请求参数错误',
            detail:
                '可能是模型名称不正确\n当前模型: ${config.modelName}\n${detail.isNotEmpty ? '厂商返回: $detail' : ''}',
          );
        case 500:
        case 502:
        case 503:
          return ConnectionTestResult(
            success: false,
            message: '厂商服务器错误 ($statusCode)',
            detail: '这不是你的配置问题，请稍后再试',
          );
        default:
          final errType = e.type;
          if (errType == DioExceptionType.connectionTimeout ||
              errType == DioExceptionType.connectionError) {
            return ConnectionTestResult(
              success: false,
              message: '无法连接到服务器',
              detail:
                  '请检查:\n1. API URL 是否正确\n2. 网络是否正常\n3. 是否需要代理访问\n当前 URL: $fullApiUrl',
            );
          }
          return ConnectionTestResult(
            success: false,
            message: '请求失败 ($statusCode)',
            detail: detail.isNotEmpty ? '厂商返回: $detail' : e.message ?? '',
          );
      }
    } catch (e) {
      return ConnectionTestResult(
        success: false,
        message: '未知错误',
        detail: e.toString(),
      );
    }
  }

  /// 从响应中提取文本内容，兼容不同厂商的响应格式
  ///
  /// 标准格式: response.data['choices'][0]['message']['content']
  /// 兼容格式:
  /// - choices 为空数组 → 返回 null
  /// - content 为 null → 尝试 tool_calls 等字段
  /// - response.data 直接是字符串
  String? _extractContent(dynamic responseData) {
    if (responseData is! Map) return null;

    // 标准路径: choices[0].message.content
    final choices = responseData['choices'];
    if (choices is List && choices.isNotEmpty) {
      final firstChoice = choices[0];
      if (firstChoice is Map) {
        final message = firstChoice['message'];
        if (message is Map) {
          final content = message['content'];
          if (content is String && content.isNotEmpty) {
            return content;
          }
        }
      }
    }

    // 某些厂商可能用 output 字段
    final output = responseData['output'];
    if (output is Map) {
      final text = output['text'];
      if (text is String && text.isNotEmpty) return text;
      final choices2 = output['choices'];
      if (choices2 is List && choices2.isNotEmpty) {
        final first = choices2[0];
        if (first is Map) {
          final content = first['message']?['content'] ?? first['content'];
          if (content is String && content.isNotEmpty) return content;
        }
      }
    }

    // data 字段（某些代理服务）
    final dataField = responseData['data'];
    if (dataField is String && dataField.isNotEmpty) return dataField;

    return null;
  }

  /// 宽容解析 JSON 内容
  ///
  /// 兼容：
  /// - 纯 JSON 字符串
  /// - 被 ```json ... ``` 包裹的字符串
  /// - 前后有多余空白/换行的字符串
  static Map<String, dynamic>? _parseJsonContent(String raw) {
    var content = raw.trim();

    // 去除 markdown 代码块包裹
    final codeBlockRegex = RegExp(r'```(?:json)?\s*([\s\S]*?)```');
    final match = codeBlockRegex.firstMatch(content);
    if (match != null) {
      content = match.group(1)?.trim() ?? content;
    }

    try {
      final parsed = jsonDecode(content);
      if (parsed is Map<String, dynamic>) return parsed;
      return null;
    } catch (_) {
      // 尝试找到第一个 { 和最后一个 } 之间的内容
      final start = content.indexOf('{');
      final end = content.lastIndexOf('}');
      if (start >= 0 && end > start) {
        try {
          final parsed = jsonDecode(content.substring(start, end + 1));
          if (parsed is Map<String, dynamic>) return parsed;
        } catch (_) {}
      }
      return null;
    }
  }

  String _parseError(DioException e) {
    final statusCode = e.response?.statusCode;
    final responseBody = e.response?.data;
    String detail = '';
    if (responseBody is Map) {
      final errorObj = responseBody['error'];
      if (errorObj is Map) {
        detail = errorObj['message']?.toString() ?? '';
      } else if (errorObj is String) {
        detail = errorObj;
      }
    }

    switch (statusCode) {
      case 401:
        return '认证失败：API Key 无效或已过期';
      case 403:
        return '访问被拒绝：请检查 API Key 权限';
      case 404:
        return '端点未找到：请检查 API URL 和模型名称${detail.isNotEmpty ? ' ($detail)' : ''}';
      case 429:
        return '请求频率超限：请稍后再试';
      case 500:
        return '服务器内部错误：请稍后再试';
      case 503:
        return '服务暂时不可用：请稍后再试';
      default:
        return '请求失败 ($statusCode): ${e.message ?? e.type.name}';
    }
  }

  Future<List<Map<String, dynamic>>?> decomposeTask(String taskTitle) async {
    const systemPrompt = '''
你是一个严谨的个人效能与项目管理专家。你的任务是将用户输入的复杂任务拆解为 3-5 个具体可执行的子任务。

## 拆解原则
1. 每个子任务必须是一个明确的、可度量的行动，而非模糊方向
2. 子任务按逻辑先后排序，先完成依赖项，再推进主体
3. 单个子任务的预估时间不超过 120 分钟；如果原任务确实很大，拆成更多步骤
4. 优先级反映该子任务对整体目标的贡献度：
   - 1 = 可延后，不影响主线
   - 2 = 重要，推动整体进展
   - 3 = 阻塞性前置任务，必须优先完成

## 输出格式（纯 JSON，不含任何 markdown 标记）
{
  "tasks": [
    {"title": "具体可执行的子任务名称", "priority": 2, "estimatedMinutes": 30}
  ]
}
''';

    final result = await requestStructuredOutput(
      systemPrompt: systemPrompt,
      userPrompt: taskTitle,
    );

    return result?['tasks'] as List<Map<String, dynamic>>?;
  }

  Future<String?> getOverdueSupport(String taskTitle, DateTime dueDate) async {
    final systemPrompt =
        '''
你是一位温暖而专业的时间管理教练，兼具心理咨询师的共情能力。

## 背景
用户的任务「$taskTitle」原定 ${dueDate.toString()} 完成，现已超期。用户可能正在经历自责、焦虑或逃避心理。

## 回复框架（按顺序）
1.【共情】先认可用户的感受，肯定 ta 已经付出的努力。用 1-2 句话减轻心理负担，绝对不要指责或说教
2.【引导】通过一个开放式提问帮助用户自我觉察拖延原因。例如：
  - "你觉得这个任务是目标太模糊了，还是第一步不知道从哪里开始？"
  - "是不是过程中遇到了没预料到的阻碍？"
3.【行动】给出 1 条非常具体、门槛极低的"微行动"建议，让用户能立刻动手。例如：
  - "现在打开文档，只写标题就好"
  - "把任务分解纸上写出第一步就行"

## 约束
- 总回复控制在 100 字以内
- 语气温暖但不煽情，专业但不冷漠
- 避免泛泛的鸡汤和空洞的鼓励

返回 JSON：{"response": "你的回复"}
''';

    final result = await requestStructuredOutput(
      systemPrompt: systemPrompt,
      userPrompt: '我需要帮助处理这个超时任务。',
    );

    return result?['response'] as String?;
  }

  /// 请求 Agent 执行操作
  ///
  /// 使用 Agent 专用 system prompt + 任务上下文，
  /// LLM 返回包含 reply 和 actions 的 JSON。
  Future<AgentResponse> requestAgentAction({
    required String userMessage,
    required String context,
  }) async {
    final systemPrompt = '$kAgentSystemPrompt\n\n$context';

    final result = await requestStructuredOutput(
      systemPrompt: systemPrompt,
      userPrompt: userMessage,
    );

    if (result == null) {
      return const AgentResponse(reply: '抱歉，我暂时无法处理你的请求。');
    }

    return AgentResponse.fromJson(result);
  }
}
