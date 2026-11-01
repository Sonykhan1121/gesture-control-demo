import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Eye diagnostics have their own app-private file; mouth tuning is untouched.
class EyeCaptureStore {
  EyeCaptureStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _directory;
  Future<void> _pending = Future<void>.value();
  Future<void> save(Map<String, Object?> snapshot) {
    final encoded = jsonEncode(snapshot);
    final task = _pending.then((_) async {
      final directory = await _directory();
      await directory.create(recursive: true);
      final file = File('${directory.path}/eye-debug-captures.json');
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(encoded, flush: true);
      await temp.rename(file.path);
    });
    _pending = task.catchError((Object error) {});
    return task;
  }
}
