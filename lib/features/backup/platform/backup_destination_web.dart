import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

@JS('ripotBackup')
external _BackupBridge? get _bridge;

extension type _BackupBridge(JSObject _) implements JSObject {
  external bool get supported;
  external JSPromise<JSString?> location();
  external JSPromise<JSString?> choose();
  external JSPromise<JSBoolean> acquire();
  external JSPromise<JSAny?> release();
  external JSPromise<JSString> write(
    JSUint8Array bytes,
    JSString scope,
    JSNumber keep,
    JSString name,
  );
}

class BackupDestination {
  _BackupBridge get _activeBridge =>
      _bridge ?? (throw StateError('Reload Ripot to enable backup tools.'));
  bool get supported => _bridge?.supported ?? false;
  bool get needsDownloadConfirmation => !supported;
  Future<String?> location() async =>
      supported ? (await _activeBridge.location().toDart)?.toDart : null;
  Future<String?> choose() async =>
      supported ? (await _activeBridge.choose().toDart)?.toDart : null;
  Future<bool> acquire() async => (await _activeBridge.acquire().toDart).toDart;
  Future<void> release() async {
    await _activeBridge.release().toDart;
  }

  Future<String> write(Uint8List bytes, String scope, int keep) async {
    final name =
        'Ripot-$scope-${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.ripotbackup';
    if (supported) {
      return (await _activeBridge
              .write(bytes.toJS, scope.toJS, keep.toJS, name.toJS)
              .toDart)
          .toDart;
    }
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/octet-stream'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = name;
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    Future.delayed(
      const Duration(minutes: 1),
      () => web.URL.revokeObjectURL(url),
    );
    return name;
  }
}
