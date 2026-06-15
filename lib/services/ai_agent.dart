import 'package:flutter/foundation.dart';
import '../models/task.dart';
import '../data/task_dao.dart';
import 'ai_service.dart';

// ==================== Action 定义 ====================

/// Agent 操作类型
enum AgentActionType {
  createTask('create_task'),
  updateTask('update_task'),
  completeTask('complete_task'),
  deleteTask('delete_task'),
  decomposeTask('decompose_task'),
  addTag('add_tag'),
  removeTag('remove_tag'),
  setGroup('set_group'),
  setPriority('set_priority');

  final String value;
  const AgentActionType(this.value);

  static AgentActionType fromString(String value) {
    return AgentActionType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => AgentActionType.createTask,
    );
  }
}

/// 单个 Agent 操作
class AgentAction {
  final AgentActionType type;
  final Map<String, dynamic> params;

  const AgentAction({required this.type, required this.params});

  factory AgentAction.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? '';
    final params = json['params'] as Map<String, dynamic>? ?? {};
    return AgentAction(
      type: AgentActionType.fromString(typeStr),
      params: Map<String, dynamic>.from(params),
    );
  }

  /// 是否需要用户确认后才执行
  bool get needsConfirmation {
    switch (type) {
      case AgentActionType.deleteTask:
      case AgentActionType.completeTask:
      case AgentActionType.updateTask:
        return true;
      default:
        return false;
    }
  }

  /// 操作的简短描述（用于确认 UI）
  String get description {
    switch (type) {
      case AgentActionType.createTask:
        return '创建任务「${params['title'] ?? ''}」';
      case AgentActionType.updateTask:
        return '更新任务 [${params['taskId']}]';
      case AgentActionType.completeTask:
        return '完成任务 [${params['taskId']}]';
      case AgentActionType.deleteTask:
        return '删除任务 [${params['taskId']}]';
      case AgentActionType.decomposeTask:
        return '分解任务 [${params['taskId']}]';
      case AgentActionType.addTag:
        return '给任务 [${params['taskId']}] 添加标签「${params['tag']}」';
      case AgentActionType.removeTag:
        return '移除任务 [${params['taskId']}] 的标签「${params['tag']}」';
      case AgentActionType.setGroup:
        return '设置任务 [${params['taskId']}] 的分组为「${params['groupName']}」';
      case AgentActionType.setPriority:
        final p = params['priority'];
        final label = p == 3
            ? '高'
            : p == 2
            ? '中'
            : '低';
        return '设置任务 [${params['taskId']}] 优先级为$label';
    }
  }
}

/// Agent 响应
class AgentResponse {
  final String reply;
  final List<AgentAction> actions;

  const AgentResponse({required this.reply, this.actions = const []});

  factory AgentResponse.fromJson(Map<String, dynamic> json) {
    final reply = json['reply']?.toString() ?? '';
    final actionsList = json['actions'] as List<dynamic>? ?? [];
    final actions = actionsList
        .whereType<Map<String, dynamic>>()
        .map((a) => AgentAction.fromJson(a))
        .toList();
    return AgentResponse(reply: reply, actions: actions);
  }
}

/// Action 执行结果
class ActionResult {
  final bool success;
  final String message;
  final dynamic data;

  const ActionResult({required this.success, required this.message, this.data});
}

// ==================== 上下文构建器 ====================

/// 构建任务上下文，注入到 LLM 请求中
@visibleForTesting
String buildTaskContext(List<Task> tasks) {
  if (tasks.isEmpty) {
    return '【当前任务上下文】\n当前没有活跃任务。';
  }

  final buffer = StringBuffer('【当前任务上下文】\n活跃任务共 ${tasks.length} 个：\n');

  // 最多注入 50 个任务
  final limitedTasks = tasks.take(50);

  for (final task in limitedTasks) {
    final priorityLabel = task.priority == 3
        ? '高'
        : task.priority == 2
        ? '中'
        : task.priority == 1
        ? '低'
        : '无';
    final tagsStr = task.tags.isNotEmpty
        ? ' | 标签:${task.tags.map((t) => '「$t」').join(',')}'
        : '';
    final groupStr = task.groupName != null ? ' | 分组:${task.groupName}' : '';
    final dueStr = task.dueDate != null
        ? ' | 截止:${task.dueDate!.toIso8601String().split('T')[0]}'
        : '';

    buffer.writeln(
      '- [id:${task.id}] ${task.title} | 优先级:$priorityLabel$groupStr$tagsStr$dueStr',
    );
  }

  // 收集所有分组和标签
  final groups = <String>{};
  final tags = <String>{};
  for (final task in tasks) {
    if (task.groupName != null) groups.add(task.groupName!);
    for (final tag in task.tags) {
      if (tag.isNotEmpty) tags.add(tag);
    }
  }

  if (groups.isNotEmpty) {
    final sortedGroups = groups.toList()..sort();
    buffer.writeln('可用分组: [${sortedGroups.join(', ')}]');
  }
  if (tags.isNotEmpty) {
    final sortedTags = tags.toList()..sort();
    buffer.writeln('可用标签: [${sortedTags.join(', ')}]');
  }

  return buffer.toString();
}

// ==================== Action 执行器 ====================

/// 执行单个 Agent Action
Future<ActionResult> executeAction(AgentAction action, TaskDao dao) async {
  try {
    switch (action.type) {
      case AgentActionType.createTask:
        return await _executeCreateTask(action, dao);

      case AgentActionType.updateTask:
        return await _executeUpdateTask(action, dao);

      case AgentActionType.completeTask:
        return await _executeCompleteTask(action, dao);

      case AgentActionType.deleteTask:
        return await _executeDeleteTask(action, dao);

      case AgentActionType.decomposeTask:
        return await _executeDecomposeTask(action, dao);

      case AgentActionType.addTag:
        return await _executeAddTag(action, dao);

      case AgentActionType.removeTag:
        return await _executeRemoveTag(action, dao);

      case AgentActionType.setGroup:
        return await _executeSetGroup(action, dao);

      case AgentActionType.setPriority:
        return await _executeSetPriority(action, dao);
    }
  } catch (e) {
    return ActionResult(success: false, message: '执行失败: $e');
  }
}

Future<ActionResult> _executeCreateTask(AgentAction action, TaskDao dao) async {
  final title = action.params['title'] as String? ?? '';
  if (title.isEmpty) {
    return const ActionResult(success: false, message: '任务标题不能为空');
  }

  final task = Task(
    title: title,
    description: action.params['description'] as String?,
    priority: _parsePriority(action.params['priority']),
    dueDate: _parseDate(action.params['dueDate']),
    tags: _parseStringList(action.params['tags']),
    groupName: action.params['groupName'] as String?,
  );

  final created = await dao.insertTask(task);
  return ActionResult(
    success: true,
    message: '已创建任务「${created.title}」',
    data: created,
  );
}

Future<ActionResult> _executeUpdateTask(AgentAction action, TaskDao dao) async {
  final taskId = _parseTaskId(action.params['taskId']);
  if (taskId == null) {
    return const ActionResult(success: false, message: '无效的任务 ID');
  }

  final existing = await dao.getTaskById(taskId);
  if (existing == null) {
    return ActionResult(success: false, message: '任务 $taskId 不存在');
  }

  var updated = existing;
  if (action.params.containsKey('title')) {
    updated = updated.copyWith(title: action.params['title'] as String);
  }
  if (action.params.containsKey('description')) {
    updated = updated.copyWith(
      description: action.params['description'] as String?,
    );
  }
  if (action.params.containsKey('priority')) {
    updated = updated.copyWith(
      priority: _parsePriority(action.params['priority']),
    );
  }
  if (action.params.containsKey('dueDate')) {
    updated = updated.copyWith(dueDate: _parseDate(action.params['dueDate']));
  }
  if (action.params.containsKey('tags')) {
    updated = updated.copyWith(tags: _parseStringList(action.params['tags']));
  }
  if (action.params.containsKey('groupName')) {
    updated = updated.copyWith(
      groupName: action.params['groupName'] as String?,
    );
  }

  await dao.updateTask(updated);
  return ActionResult(
    success: true,
    message: '已更新任务「${updated.title}」',
    data: updated,
  );
}

Future<ActionResult> _executeCompleteTask(
  AgentAction action,
  TaskDao dao,
) async {
  final taskId = _parseTaskId(action.params['taskId']);
  if (taskId == null) {
    return const ActionResult(success: false, message: '无效的任务 ID');
  }

  final existing = await dao.getTaskById(taskId);
  if (existing == null) {
    return ActionResult(success: false, message: '任务 $taskId 不存在');
  }

  final updated = existing.copyWith(isCompleted: true);
  await dao.updateTask(updated);
  return ActionResult(success: true, message: '已完成任务「${existing.title}」');
}

Future<ActionResult> _executeDeleteTask(AgentAction action, TaskDao dao) async {
  final taskId = _parseTaskId(action.params['taskId']);
  if (taskId == null) {
    return const ActionResult(success: false, message: '无效的任务 ID');
  }

  final existing = await dao.getTaskById(taskId);
  if (existing == null) {
    return ActionResult(success: false, message: '任务 $taskId 不存在');
  }

  await dao.softDeleteTask(taskId);
  return ActionResult(success: true, message: '已删除任务「${existing.title}」');
}

Future<ActionResult> _executeDecomposeTask(
  AgentAction action,
  TaskDao dao,
) async {
  final taskId = _parseTaskId(action.params['taskId']);
  if (taskId == null) {
    return const ActionResult(success: false, message: '无效的任务 ID');
  }

  final existing = await dao.getTaskById(taskId);
  if (existing == null) {
    return ActionResult(success: false, message: '任务 $taskId 不存在');
  }

  final subtasksRaw = action.params['subtasks'] as List<dynamic>? ?? [];
  if (subtasksRaw.isEmpty) {
    return const ActionResult(success: false, message: '子任务列表不能为空');
  }

  final createdTitles = <String>[];
  for (final st in subtasksRaw) {
    if (st is! Map<String, dynamic>) continue;
    final title = st['title'] as String? ?? '';
    if (title.isEmpty) continue;

    final task = Task(
      title: title,
      priority: _parsePriority(st['priority']),
      groupName: existing.groupName,
      tags: List<String>.from(existing.tags),
    );
    await dao.insertTask(task);
    createdTitles.add(title);
  }

  return ActionResult(
    success: true,
    message: '已将「${existing.title}」分解为 ${createdTitles.length} 个子任务',
    data: createdTitles,
  );
}

Future<ActionResult> _executeAddTag(AgentAction action, TaskDao dao) async {
  final taskId = _parseTaskId(action.params['taskId']);
  final tag = action.params['tag'] as String? ?? '';
  if (taskId == null) {
    return const ActionResult(success: false, message: '无效的任务 ID');
  }
  if (tag.isEmpty) {
    return const ActionResult(success: false, message: '标签不能为空');
  }

  final existing = await dao.getTaskById(taskId);
  if (existing == null) {
    return ActionResult(success: false, message: '任务 $taskId 不存在');
  }

  if (existing.tags.contains(tag)) {
    return ActionResult(
      success: true,
      message: '任务「${existing.title}」已有标签「$tag」',
    );
  }

  final updated = existing.copyWith(tags: [...existing.tags, tag]);
  await dao.updateTask(updated);
  return ActionResult(
    success: true,
    message: '已给任务「${existing.title}」添加标签「$tag」',
  );
}

Future<ActionResult> _executeRemoveTag(AgentAction action, TaskDao dao) async {
  final taskId = _parseTaskId(action.params['taskId']);
  final tag = action.params['tag'] as String? ?? '';
  if (taskId == null) {
    return const ActionResult(success: false, message: '无效的任务 ID');
  }
  if (tag.isEmpty) {
    return const ActionResult(success: false, message: '标签不能为空');
  }

  final existing = await dao.getTaskById(taskId);
  if (existing == null) {
    return ActionResult(success: false, message: '任务 $taskId 不存在');
  }

  final updated = existing.copyWith(
    tags: existing.tags.where((t) => t != tag).toList(),
  );
  await dao.updateTask(updated);
  return ActionResult(
    success: true,
    message: '已移除任务「${existing.title}」的标签「$tag」',
  );
}

Future<ActionResult> _executeSetGroup(AgentAction action, TaskDao dao) async {
  final taskId = _parseTaskId(action.params['taskId']);
  final groupName = action.params['groupName'] as String?;
  if (taskId == null) {
    return const ActionResult(success: false, message: '无效的任务 ID');
  }

  final existing = await dao.getTaskById(taskId);
  if (existing == null) {
    return ActionResult(success: false, message: '任务 $taskId 不存在');
  }

  final updated = existing.copyWith(groupName: groupName);
  await dao.updateTask(updated);
  return ActionResult(
    success: true,
    message: '已设置任务「${existing.title}」的分组为「${groupName ?? '无'}」',
  );
}

Future<ActionResult> _executeSetPriority(
  AgentAction action,
  TaskDao dao,
) async {
  final taskId = _parseTaskId(action.params['taskId']);
  if (taskId == null) {
    return const ActionResult(success: false, message: '无效的任务 ID');
  }

  final existing = await dao.getTaskById(taskId);
  if (existing == null) {
    return ActionResult(success: false, message: '任务 $taskId 不存在');
  }

  final priority = _parsePriority(action.params['priority']);
  final updated = existing.copyWith(priority: priority);
  await dao.updateTask(updated);

  final label = priority == 3
      ? '高'
      : priority == 2
      ? '中'
      : priority == 1
      ? '低'
      : '无';
  return ActionResult(
    success: true,
    message: '已设置任务「${existing.title}」优先级为$label',
  );
}

// ==================== 辅助方法 ====================

int _parsePriority(dynamic value) {
  if (value is int) return value.clamp(0, 3);
  if (value is String) return int.tryParse(value)?.clamp(0, 3) ?? 0;
  return 0;
}

int? _parseTaskId(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

List<String> _parseStringList(dynamic value) {
  if (value is List) {
    return value.whereType<String>().toList();
  }
  return [];
}

// ==================== Agent System Prompt ====================

const String kAgentSystemPrompt = '''
你是一个智能任务管理助手，可以直接操作用户的任务列表。

## 你的能力
你可以执行以下操作来帮助用户管理任务：

| 操作 | 说明 | 必填参数 | 可选参数 |
|------|------|---------|---------|
| create_task | 创建新任务 | title | priority(1-3), description, tags[], groupName, dueDate(YYYY-MM-DD) |
| update_task | 更新已有任务 | taskId | title, description, priority, dueDate, tags, groupName |
| complete_task | 标记任务完成 | taskId | — |
| delete_task | 删除任务 | taskId | — |
| decompose_task | 拆解任务为子任务 | taskId, subtasks[{title,priority?}] | — |
| add_tag | 添加标签 | taskId, tag | — |
| remove_tag | 移除标签 | taskId, tag | — |
| set_group | 设置分组 | taskId, groupName | — |
| set_priority | 调整优先级 | taskId, priority | — |

## 核心规则
1. **复用优先**：优先使用上下文中已有的分组和标签名，不要随意创建新的分类体系，除非用户明确要求
2. **优先级定义**：1 = 低（可延后），2 = 中（重要但不紧急），3 = 高（必须优先处理）
3. **必须用 taskId**：对已有任务执行更新、完成、删除、分解等操作时，必须使用上下文中的任务 id
4. **不确定时先问**：当用户意图模糊、任务指代不明、或操作可能产生不可逆后果，务必只回复提问，不执行任何 action
5. **拆解原则**：子任务数量 2-5 个，每个子任务必须是具体可执行的行动，而非抽象方向
6. **简洁有温度**：回复控制在 2-3 个短句内，语气友好但专业，避免说教和套话
7. **代词消解**：当用户使用"它""这个""那个"等代词时，请结合上下文推断具体指向的任务

## 输出格式（严格遵守）
你必须只返回以下 JSON 结构，不要添加任何额外文本或 markdown 标记：
{"reply": "你的自然语言回复", "actions": [{"type": "操作类型", "params": {具体参数}}]}

如果本次对话不需要执行任何操作，actions 设为空数组 []。
''';
