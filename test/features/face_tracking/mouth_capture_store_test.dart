import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/face_tracking/mouth_capture_store.dart';
import 'package:hand_gesture/features/face_tracking/mouth_diagnostics.dart';
import 'mouth_motion_test.dart' show measurement;

void main() {
  test(
    'All three numeric phases persist, sequential writes keep the latest complete snapshot',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'lazivoo-mouth-capture-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final capture = MouthDiagnosticCapture();
      final store = MouthCaptureStore(directory: () async => dir);
      final writes = <Future<void>>[];
      for (var i = 0; i < 3; i++) {
        final phase = MouthCapturePhase.values[i];
        capture.start(phase, Duration(seconds: i * 4));
        capture.add(
          measurement(gap: .02 + i * .05, smile: i == 1 ? .7 : .05),
          30,
        );
        capture.finishIfDue(Duration(seconds: i * 4 + 3));
        writes.add(
          store.save({
            'version': 1,
            'session': 123,
            'captures': Map.of(capture.history),
          }),
        );
      }
      await Future.wait(writes);
      final decoded =
          jsonDecode(
                await File(
                  '${dir.path}/mouth-debug-captures.json',
                ).readAsString(),
              )
              as Map;
      expect((await store.load())!['session'], 123);
      final captures = decoded['captures'] as Map;
      expect(captures.keys, containsAll(['normal', 'smile', 'talk']));
      expect(captures['talk']['gapMedian'], closeTo(.12, 1e-8));
      expect(captures['smile']['smileMedian'], closeTo(.7, 1e-8));
      expect(
        await File('${dir.path}/mouth-debug-captures.json.tmp').exists(),
        isFalse,
      );
    },
  );
  test(
    'A failed save is reported and cannot poison later capture writes',
    () async {
      final dir = await Directory.systemTemp.createTemp('lazivoo-mouth-retry-');
      addTearDown(() => dir.delete(recursive: true));
      var fail = true;
      final store = MouthCaptureStore(
        directory: () async {
          if (fail) throw const FileSystemException('test failure');
          return dir;
        },
      );
      await expectLater(
        store.save({'phase': 'normal'}),
        throwsA(isA<FileSystemException>()),
      );
      fail = false;
      await store.save({'phase': 'talk'});
      expect(
        jsonDecode(
          await File('${dir.path}/mouth-debug-captures.json').readAsString(),
        )['phase'],
        'talk',
      );
    },
  );
}
