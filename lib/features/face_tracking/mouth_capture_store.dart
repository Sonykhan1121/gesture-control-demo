import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Durable numeric captures, separate from profile/account preferences.
/// Writes are serialized and replaced atomically; no camera frames are saved.
class MouthCaptureStore {
  MouthCaptureStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _directory;
  Future<void> _pending = Future<void>.value();

  Future<Map<String, dynamic>?> load() async {
    await _pending;
    try {
      final folder = await _directory();
      final decoded = jsonDecode(
        await File('${folder.path}/mouth-debug-captures.json').readAsString(),
      );
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
        return null;
      }
      return decoded;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<void> save(Map<String, Object?> snapshot) {
    final encoded = jsonEncode(snapshot);
    final operation = _pending.then((_) async {
      final folder = await _directory();
      await folder.create(recursive: true);
      final file = File('${folder.path}/mouth-debug-captures.json');
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(encoded, flush: true);
      await temp.rename(file.path);
    });
    _pending = operation.catchError((Object error) {});
    return operation;
  }
}
