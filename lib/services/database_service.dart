import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/task.dart';
import '../models/chat_record.dart';

class DatabaseService {
  static Isar? _instance;

  static Future<Isar> getInstance() async {
    if (_instance != null) {
      try {
        await _instance!.tasks.where().count();
        return _instance!;
      } catch (_) {
        // Instance is closed or invalid, recreate it
        _instance = null;
      }
    }

    final dir = await getApplicationDocumentsDirectory();

    // 添加超时保护，防止 Isar.open() 在 Android 16 等新平台上挂起
    try {
      _instance =
          await Isar.open(
            [TaskSchema, ChatRecordSchema],
            directory: dir.path,
            inspector: kDebugMode,
          ).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('数据库初始化超时，请检查存储权限');
            },
          );
    } catch (e) {
      debugPrint('DatabaseService: Isar.open() failed: $e');
      rethrow;
    }

    return _instance!;
  }

  static Future<void> close() async {
    if (_instance != null) {
      await _instance!.close();
      _instance = null;
    }
  }
}
