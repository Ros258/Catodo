import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/ai_service.dart';
import '../../services/ai_agent.dart';
import '../../providers/task_providers.dart';
import '../../providers/isar_provider.dart';
import '../../data/task_dao.dart';
import '../../data/chat_dao.dart';
import '../../models/task.dart';
import '../../models/chat_record.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  AIService? _aiService;

  @override
  void initState() {
    super.initState();
    _initAIService();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final isarAsync = ref.read(isarProvider);
    final isar = isarAsync.valueOrNull;
    if (isar == null) {
      // Isar 未就绪，显示欢迎消息
      _messages.add(
        ChatMessage(
          isUser: false,
          text:
              '你好！我是 AI 助手，可以直接帮你管理任务：\n'
              '1. 创建任务 - "帮我创建一个高优先级任务：完成报告"\n'
              '2. 分解任务 - "分解任务「学习 Flutter」"\n'
              '3. 调整优先级 - "把任务「买牛奶」设为低优先级"\n'
              '4. 加标签/分组 - "给任务加标签「紧急」"\n'
              '5. 完成/删除 - "完成任务「买牛奶」"\n'
              '6. 自由对话 - 直接输入你的问题',
        ),
      );
      return;
    }

    final dao = ChatDao(isar);
    final records = await dao.getRecent(limit: 100);

    if (records.isEmpty) {
      // 无历史记录，显示欢迎消息
      _messages.add(
        ChatMessage(
          isUser: false,
          text:
              '你好！我是 AI 助手，可以直接帮你管理任务：\n'
              '1. 创建任务 - "帮我创建一个高优先级任务：完成报告"\n'
              '2. 分解任务 - "分解任务「学习 Flutter」"\n'
              '3. 调整优先级 - "把任务「买牛奶」设为低优先级"\n'
              '4. 加标签/分组 - "给任务加标签「紧急」"\n'
              '5. 完成/删除 - "完成任务「买牛奶」"\n'
              '6. 自由对话 - 直接输入你的问题',
        ),
      );
    } else {
      // 恢复历史消息
      for (final record in records) {
        _messages.add(ChatMessage(isUser: record.isUser, text: record.text));
      }
    }

    setState(() {});
  }

  Future<void> _initAIService() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final apiKey = prefs.getString('ai_api_key') ?? '';
      final apiUrl = prefs.getString('ai_api_url') ?? '';
      final model = prefs.getString('ai_model') ?? '';
      final providerId = prefs.getString('ai_provider_id') ?? 'custom';

      if (apiKey.isNotEmpty && apiUrl.isNotEmpty && model.isNotEmpty) {
        _aiService = AIService(
          AIConfig(
            providerId: providerId,
            apiKey: apiKey,
            apiUrl: apiUrl,
            modelName: model,
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to initialize AI service: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 持久化一条消息到 Isar（不含确认卡片）
  Future<void> _persistMessage(ChatMessage message) async {
    if (message.pendingActions != null) return; // 确认卡片不持久化
    final isarAsync = ref.read(isarProvider);
    final isar = isarAsync.valueOrNull;
    if (isar == null) return;

    final dao = ChatDao(isar);
    await dao.insert(ChatRecord(isUser: message.isUser, text: message.text));
  }

  /// 清空当前会话的历史记录
  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空对话历史'),
        content: const Text('确定要清空所有对话记录吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final isarAsync = ref.read(isarProvider);
    final isar = isarAsync.valueOrNull;
    if (isar != null) {
      final dao = ChatDao(isar);
      await dao.clearAll();
    }

    setState(() => _messages.clear());
    _scrollToBottom();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    setState(() => _messages.add(ChatMessage(isUser: true, text: text)));
    _persistMessage(ChatMessage(isUser: true, text: text));
    _scrollToBottom();

    if (_aiService == null) {
      setState(
        () => _messages.add(
          ChatMessage(isUser: false, text: '请先在设置中配置 AI 助手的 API 参数。'),
        ),
      );
      _persistMessage(ChatMessage(isUser: false, text: '请先在设置中配置 AI 助手的 API 参数。'));
      _scrollToBottom();
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 构建任务上下文
      final tasksAsync = ref.read(activeTasksProvider);
      final tasks = tasksAsync.valueOrNull ?? [];
      final context = buildTaskContext(tasks);

      // 调用 Agent
      final response = await _aiService!.requestAgentAction(
        userMessage: text,
        context: context,
      );

      // 分离需要确认和自动执行的 actions
      final autoActions = <AgentAction>[];
      final confirmActions = <AgentAction>[];

      for (final action in response.actions) {
        if (action.needsConfirmation) {
          confirmActions.add(action);
        } else {
          autoActions.add(action);
        }
      }

      // 自动执行低风险操作
      final autoResults = <ActionResult>[];
      if (autoActions.isNotEmpty) {
        final isarAsync = ref.read(isarProvider);
        final isar = isarAsync.valueOrNull;
        if (isar != null) {
          final dao = TaskDao(isar);
          for (final action in autoActions) {
            final result = await executeAction(action, dao);
            autoResults.add(result);
          }
        }
      }

      // 构建回复消息
      final replyBuffer = StringBuffer(response.reply);

      // 附加自动执行结果
      for (final result in autoResults) {
        if (result.success) {
          replyBuffer.write('\n\n✓ ${result.message}');
        } else {
          replyBuffer.write('\n\n✗ ${result.message}');
        }
      }

      setState(() {
        _messages.add(ChatMessage(isUser: false, text: replyBuffer.toString()));
      });

      _persistMessage(ChatMessage(isUser: false, text: replyBuffer.toString()));

      // 需要确认的操作显示确认卡片
      if (confirmActions.isNotEmpty) {
        setState(() {
          _messages.add(
            ChatMessage(
              isUser: false,
              text: '',
              pendingActions: confirmActions,
            ),
          );
        });
      }

      _scrollToBottom();
    } catch (e) {
      setState(
        () => _messages.add(ChatMessage(isUser: false, text: '抱歉，发生错误：$e')),
      );
      _persistMessage(ChatMessage(isUser: false, text: '抱歉，发生错误：$e'));
      _scrollToBottom();
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  Future<void> _confirmActions(List<AgentAction> actions) async {
    final isarAsync = ref.read(isarProvider);
    final isar = isarAsync.valueOrNull;
    if (isar == null) {
      setState(
        () => _messages.add(ChatMessage(isUser: false, text: '数据库未就绪，请稍后再试。')),
      );
      _persistMessage(ChatMessage(isUser: false, text: '数据库未就绪，请稍后再试。'));
      _scrollToBottom();
      return;
    }

    final dao = TaskDao(isar);
    final results = <ActionResult>[];

    for (final action in actions) {
      final result = await executeAction(action, dao);
      results.add(result);
    }

    final buffer = StringBuffer('已执行操作：\n');
    for (final result in results) {
      buffer.writeln(
        result.success ? '✓ ${result.message}' : '✗ ${result.message}',
      );
    }

    setState(() {
      _messages.add(ChatMessage(isUser: false, text: buffer.toString()));
    });
    _persistMessage(ChatMessage(isUser: false, text: buffer.toString()));
    _scrollToBottom();
  }

  void _cancelActions() {
    setState(() {
      _messages.add(ChatMessage(isUser: false, text: '已取消操作。'));
    });
    _persistMessage(ChatMessage(isUser: false, text: '已取消操作。'));
    _scrollToBottom();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 头部
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'AI 助手',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: _clearHistory,
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('清空'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _showQuickActions,
                            icon: const Icon(Icons.auto_awesome, size: 18),
                            label: const Text('快捷操作'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Text(
                    '智能任务管理 Agent',
                    style: TextStyle(fontSize: 12, color: Color(0xFF757575)),
                  ),
                ],
              ),
            ),

            // 聊天区域
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _messages.length + (_isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length && _isLoading) {
                    return _buildLoadingBubble();
                  }
                  return _buildMessageBubble(_messages[index]);
                },
              ),
            ),

            // 输入区域
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _messageController,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: const InputDecoration(
                          hintText: '输入消息...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _isLoading ? null : _sendMessage,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _isLoading ? Colors.grey : Colors.black,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(24),
                        ),
                      ),
                      child: _isLoading
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingBubble() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Card(
          color: Color(0xFFF5F5F5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 80,
              height: 20,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 8,
                    height: 8,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  SizedBox(width: 8),
                  Text(
                    '思考中...',
                    style: TextStyle(fontSize: 12, color: Color(0xFF757575)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    // 确认卡片
    if (message.pendingActions != null && message.pendingActions!.isNotEmpty) {
      return _buildConfirmationCard(message.pendingActions!);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: message.isUser
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          decoration: BoxDecoration(
            color: message.isUser ? Colors.black : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(message.isUser ? 16 : 0),
              bottomRight: Radius.circular(message.isUser ? 0 : 16),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              message.text,
              style: TextStyle(
                color: message.isUser ? Colors.white : Colors.black87,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmationCard(List<AgentAction> actions) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Card(
        color: const Color(0xFFFFF8E1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFFFD54F)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber,
                    color: Colors.orange.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '需要确认',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...actions.map(
                (action) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.arrow_right,
                        size: 16,
                        color: Colors.black54,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          action.description,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _cancelActions,
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _confirmActions(actions),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('确认执行'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQuickActions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '快捷操作',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.add_task, color: Colors.green),
              title: const Text('创建任务'),
              subtitle: const Text('让 AI 帮你创建新任务'),
              onTap: () {
                Navigator.pop(context);
                _messageController.text = '帮我创建一个任务：';
                _sendMessage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.call_split, color: Colors.purple),
              title: const Text('分解任务'),
              subtitle: const Text('选择一个任务，让 AI 拆解为子任务'),
              onTap: () {
                Navigator.pop(context);
                _showTaskPicker('分解');
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag, color: Colors.red),
              title: const Text('调整优先级'),
              subtitle: const Text('选择任务并设置优先级'),
              onTap: () {
                Navigator.pop(context);
                _showTaskPicker('调整优先级');
              },
            ),
            ListTile(
              leading: const Icon(Icons.label, color: Colors.blue),
              title: const Text('加标签/分组'),
              subtitle: const Text('给任务添加标签或设置分组'),
              onTap: () {
                Navigator.pop(context);
                _showTaskPicker('加标签');
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.teal),
              title: const Text('完成任务'),
              subtitle: const Text('选择要完成的任务'),
              onTap: () {
                Navigator.pop(context);
                _showTaskPicker('完成');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showTaskPicker(String actionType) {
    final tasksAsync = ref.read(activeTasksProvider);
    final tasks = tasksAsync.valueOrNull ?? [];

    if (tasks.isEmpty) {
      setState(
        () =>
            _messages.add(ChatMessage(isUser: false, text: '当前没有可用任务，请先创建任务。')),
      );
      _persistMessage(ChatMessage(isUser: false, text: '当前没有可用任务，请先创建任务。'));
      _scrollToBottom();
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          height: constraints.maxHeight * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '选择要$actionType的任务',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: tasks.length,
                  itemBuilder: (_, i) => ListTile(
                    title: Text(tasks[i].title),
                    subtitle: Text(
                      tasks[i].dueDate != null
                          ? '截止: ${tasks[i].dueDate!.toLocal().toString().split('.')[0]}'
                          : '无截止日期',
                    ),
                    leading: Icon(
                      tasks[i].priority >= 2 ? Icons.flag : Icons.outlined_flag,
                      color: tasks[i].priority >= 2 ? Colors.red : Colors.grey,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      String message;
                      switch (actionType) {
                        case '分解':
                          message = '分解任务「${tasks[i].title}」';
                          break;
                        case '调整优先级':
                          message = '调整任务「${tasks[i].title}」的优先级';
                          break;
                        case '加标签':
                          message = '给任务「${tasks[i].title}」加标签和分组';
                          break;
                        case '完成':
                          message = '完成任务「${tasks[i].title}」';
                          break;
                        default:
                          message = '帮我管理任务「${tasks[i].title}」';
                      }
                      _messageController.text = message;
                      _sendMessage();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatMessage {
  final bool isUser;
  final String text;
  final List<AgentAction>? pendingActions;

  ChatMessage({required this.isUser, required this.text, this.pendingActions});
}
