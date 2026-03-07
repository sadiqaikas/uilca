import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'biosphere_flow.dart';

class BiosphereRepository {
  BiosphereRepository._();
  static final BiosphereRepository instance = BiosphereRepository._();

  List<BiosphereFlow>? _cache;
  Future<List<BiosphereFlow>>? _future;

  Future<List<BiosphereFlow>> load() {
    if (_cache != null) return Future.value(_cache);
    _future ??= _loadInternal();
    return _future!;
  }

Future<List<BiosphereFlow>> _loadInternal() async {
  print('[Repo] _loadInternal(): start');
  final jsonStr = await rootBundle.loadString('assets/biosphere3_flows.json');
  print('[Repo] loaded asset, length=${jsonStr.length}');
  final data = json.decode(jsonStr) as List<dynamic>;

  final List<BiosphereFlow> list = [];
  for (var item in data) {
    if (item is! Map<String, dynamic>) continue;
    try {
      // take 'code' as the UUID, if missing fall back to 'id'
      final idRaw   = item['code']   as String? ?? item['id']   as String? ?? '';
      final nameRaw = item['name']   as String?                ?? '';
      final unitRaw = item['unit']   as String?                ?? '';
      final catsRaw = item['categories'];
      final catsList = catsRaw is List
          ? catsRaw.map((e) => e?.toString().trim() ?? '').toList()
          : <String>[];

      final id   = idRaw.trim();
      final name = nameRaw.trim();
      if (id.isEmpty || name.isEmpty) {
        print('[Repo] skipping flow with empty id/name: code="$idRaw" name="$nameRaw"');
        continue;
      }

      list.add(BiosphereFlow(
        id:         id,
        name:       name,
        unit:       unitRaw.trim(),
        categories: catsList.where((c) => c.isNotEmpty).toList(),
      ));
    } catch (e) {
      print('[Repo] error parsing flow, skipping: $e');
    }
  }

  print('[Repo] parsed ${list.length} valid flows (out of ${data.length})');
  _cache = list;
  return list;
}





  Future<List<BiosphereFlow>> _parseAsync(String jsonStr) {
    if (kIsWeb) {
            print('[Repo Debug] parsing on web event-loop');

      // No real isolates on web; parse on a later event-loop tick.
      return Future<List<BiosphereFlow>>(() {
        final data = json.decode(jsonStr) as List<dynamic>;
        return data
            .map((e) => BiosphereFlow.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } else {
            print('[Repo Debug] parsing on isolate');
print('[Repo Debug] parsing JSON synchronously');
final data = json.decode(jsonStr) as List<dynamic>;
final list = data.map((e) => BiosphereFlow.fromJson(e)).toList();
print('[Repo Debug] parsed ${list.length} flows');
_cache = list;
return Future.value(list);

    }
  }
}

List<BiosphereFlow> _parseOnIsolate(String jsonStr) {
  final data = json.decode(jsonStr) as List<dynamic>;
  return data
      .map((e) => BiosphereFlow.fromJson(e as Map<String, dynamic>))
      .toList();
}
