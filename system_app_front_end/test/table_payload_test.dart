import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/objects/data/table_payload.dart';

void main() {
  group('TableObjectPayload', () {
    test('empty has one row of empty cells', () {
      final p = TableObjectPayload.empty(columns: 2);
      expect(TableObjectPayload.chartEnabled(p), isFalse);
      expect(p['rows'], hasLength(1));
      expect((p['rows'] as List).first, hasLength(2));
    });

    test('emptyChart enables chart quality', () {
      final p = TableObjectPayload.emptyChart();
      expect(TableObjectPayload.chartEnabled(p), isTrue);
      expect(TableObjectPayload.pointerObjectType(p), 'graph');
      final rows = TableObjectPayload.rowsOf(p);
      expect(rows, hasLength(2));
      expect(rows[0][0]['text'], 'A');
      expect(rows[1][1]['text'], '2');
    });

    test('normalize maps legacy labels/values', () {
      final p = TableObjectPayload.normalize({
        'labels': ['X', 'Y'],
        'values': ['3', '4'],
        'chartType': 'pie',
        'colors': ['#111111', '#222222'],
      });
      expect(p['chart']['enabled'], isTrue);
      expect(p['chart']['chartType'], 'pie');
      expect(p['rows'][0][0]['text'], 'X');
      expect(p['rows'][1][1]['text'], '4');
      expect(p['chart']['colors'], ['#111111', '#222222']);
    });

    test('plain rows keep chart off', () {
      final p = TableObjectPayload.normalize({
        'rows': [
          [
            {'text': 'H'},
          ],
        ],
      });
      expect(TableObjectPayload.chartEnabled(p), isFalse);
      expect(TableObjectPayload.pointerObjectType(p), 'table');
    });
  });
}
