import 'package:shared_preferences/shared_preferences.dart';

class LogbookStorage {
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString('logbook.v1');
  Future<void> write(String value) async {
    if (!await (await SharedPreferences.getInstance()).setString(
      'logbook.v1',
      value,
    )) {
      throw StateError('Could not save Logbook');
    }
  }
}
