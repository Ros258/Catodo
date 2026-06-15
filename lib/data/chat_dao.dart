import 'package:isar/isar.dart';
import '../models/chat_record.dart';

/// 对话记录数据访问对象
///
/// 提供对话历史的 CRUD 操作。
/// 默认最多保留 200 条消息，超出后自动清理最早的消息。
class ChatDao {
  final Isar isar;
  static const int _maxRecords = 200;

  ChatDao(this.isar);

  /// 保存一条对话记录
  Future<ChatRecord> insert(ChatRecord record) async {
    await isar.writeTxn(() async {
      await isar.chatRecords.put(record);
    });

    // 自动清理超出上限的旧消息
    await _trimIfNeeded();

    return record;
  }

  /// 批量保存对话记录（用于初始化时恢复历史）
  Future<void> insertAll(List<ChatRecord> records) async {
    await isar.writeTxn(() async {
      await isar.chatRecords.putAll(records);
    });
  }

  /// 按时间正序获取最近的对话记录
  ///
  /// [limit] 最大返回条数，默认 100
  Future<List<ChatRecord>> getRecent({int limit = 100}) async {
    return await isar.chatRecords.where()
      .sortByCreatedAt()
      .findAll();
  }

  /// 获取所有对话记录（按时间正序）
  Future<List<ChatRecord>> getAll() async {
    return await isar.chatRecords.where()
      .sortByCreatedAt()
      .findAll();
  }

  /// 清空所有对话记录
  Future<void> clearAll() async {
    await isar.writeTxn(() async {
      await isar.chatRecords.clear();
    });
  }

  /// 获取总消息条数
  Future<int> get count async {
    return await isar.chatRecords.count();
  }

  /// 删除超过上限的旧消息，保留最近 [_maxRecords] 条
  Future<void> _trimIfNeeded() async {
    final total = await count;
    if (total <= _maxRecords) return;

    final toDelete = total - _maxRecords;
    final oldest = await isar.chatRecords.where()
      .sortByCreatedAt()
      .limit(toDelete)
      .findAll();

    if (oldest.isNotEmpty) {
      final ids = oldest.map((r) => r.id).toList();
      await isar.writeTxn(() async {
        await isar.chatRecords.deleteAll(ids);
      });
    }
  }
}
