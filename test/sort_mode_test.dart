import 'package:flutter_test/flutter_test.dart';
import 'package:jingerpicmanager/data/settings_store.dart';

void main() {
  group('SortMode SQL mapping', () {
    test('every sort mode yields a valid ORDER BY expression', () {
      // These strings are fed verbatim into `ORDER BY <sql>` in database.dart.
      // A semantic key (e.g. "date_desc") would raise "no such column" and
      // lock the library on the loading spinner. They must be real SQL.
      for (final mode in SortMode.values) {
        expect(mode.sql, isNotEmpty);
        expect(mode.sql.toLowerCase().contains(' desc') ||
                mode.sql.toLowerCase().contains(' asc'),
            isTrue,
            reason: '${mode.name} -> "${mode.sql}" is not a valid ORDER BY');
      }
    });

    test('ordering modes map to date expressions', () {
      expect(SortMode.dateNewest.sql,
          contains('COALESCE(date_taken, date_modified)'));
      expect(SortMode.dateNewest.sql.toLowerCase(), endsWith('desc'));
      expect(SortMode.dateOldest.sql.toLowerCase(), endsWith('asc'));
    });

    test('fromKey falls back to dateNewest for unknown keys', () {
      expect(SortMode.fromKey(null), SortMode.dateNewest);
      expect(SortMode.fromKey('bogus'), SortMode.dateNewest);
      expect(SortMode.fromKey('name_asc'), SortMode.nameAsc);
    });

    test('key round-trips through fromKey', () {
      for (final mode in SortMode.values) {
        expect(SortMode.fromKey(mode.key), mode);
      }
    });
  });
}
