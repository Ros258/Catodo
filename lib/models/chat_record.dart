import 'package:isar/isar.dart';

part 'chat_record.g.dart';

/// 持久化的对话记录，与 UI 层 ChatMessage 对应
///
/// pendingActions（确认卡片）属于瞬时状态，不持久化。
/// 每次进入聊天页面自动恢复最近 100 条消息。
@collection
class ChatRecord {
  Id id = Isar.autoIncrement;

  @Index()
  late DateTime createdAt;

  /// 消息发送方：true = 用户，false = AI 助手
  @Index()
  late bool isUser;

  /// 消息文本内容
  late String text;

  ChatRecord({
    required this.isUser,
    required this.text,
  }) {
    createdAt = DateTime.now();
  }
}
