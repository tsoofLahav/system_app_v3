import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/models/details_block_summary.dart';

void main() {
  test('DetailsBlockSummary.fromJson parses API payload', () {
    final item = DetailsBlockSummary.fromJson({
      'block_id': 42,
      'file_id': 7,
      'file_name': 'Recipes',
      'title': 'Chicken soup',
      'text_preview': 'Ingredients…',
      'text': 'Full body',
    });

    expect(item.blockId, 42);
    expect(item.fileId, 7);
    expect(item.fileName, 'Recipes');
    expect(item.title, 'Chicken soup');
    expect(item.textPreview, 'Ingredients…');
    expect(item.text, 'Full body');
  });

  test('DetailsBlockSummary.fromJson defaults optional strings', () {
    final item = DetailsBlockSummary.fromJson({
      'block_id': 1,
      'file_id': 2,
    });

    expect(item.fileName, '');
    expect(item.title, '');
    expect(item.textPreview, '');
    expect(item.text, '');
  });
}
