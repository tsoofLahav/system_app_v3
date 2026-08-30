/// Rank Connect info / Add connection rows without AI.
///
/// Empty search: names similar to the marked text, then the same topic, then
/// the rest. A typed search drops the similar-text bucket and lists the topic
/// first, then everywhere else.
library;

const double similarNameThreshold = 0.45;

String normalizeComparable(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// Dice on character bigrams, with exact / contains boosts.
double textSimilarity(String a, String b) {
  final left = normalizeComparable(a);
  final right = normalizeComparable(b);
  if (left.isEmpty || right.isEmpty) return 0;
  if (left == right) return 1;
  if (left.contains(right) || right.contains(left)) {
    final shorter = left.length < right.length ? left.length : right.length;
    final longer = left.length < right.length ? right.length : left.length;
    return 0.72 + 0.27 * (shorter / longer);
  }
  return _diceBigrams(left, right);
}

bool isSimilarName(String probe, String title) {
  return textSimilarity(probe, title) >= similarNameThreshold;
}

int infoPickBucket({
  required String title,
  required int? itemTopicId,
  required String query,
  required String similarTo,
  required int? topicId,
}) {
  final searching = query.trim().isNotEmpty;
  if (!searching &&
      similarTo.trim().isNotEmpty &&
      isSimilarName(similarTo, title)) {
    return 0;
  }
  if (topicId != null && itemTopicId == topicId) return 1;
  return 2;
}

int compareInfoPicks({
  required String titleA,
  required String titleB,
  required int? topicA,
  required int? topicB,
  required String query,
  required String similarTo,
  required int? topicId,
}) {
  final bucketA = infoPickBucket(
    title: titleA,
    itemTopicId: topicA,
    query: query,
    similarTo: similarTo,
    topicId: topicId,
  );
  final bucketB = infoPickBucket(
    title: titleB,
    itemTopicId: topicB,
    query: query,
    similarTo: similarTo,
    topicId: topicId,
  );
  if (bucketA != bucketB) return bucketA.compareTo(bucketB);
  if (bucketA == 0 && query.trim().isEmpty) {
    return textSimilarity(
      similarTo,
      titleB,
    ).compareTo(textSimilarity(similarTo, titleA));
  }
  return titleA.toLowerCase().compareTo(titleB.toLowerCase());
}

List<T> rankInfoPicks<T>({
  required List<T> items,
  required String Function(T item) titleOf,
  required int? Function(T item) topicOf,
  String query = '',
  String similarTo = '',
  int? topicId,
}) {
  final filtered = [
    for (final item in items)
      if (query.trim().isEmpty ||
          titleOf(item).toLowerCase().contains(query.trim().toLowerCase()))
        item,
  ];
  filtered.sort(
    (a, b) => compareInfoPicks(
      titleA: titleOf(a),
      titleB: titleOf(b),
      topicA: topicOf(a),
      topicB: topicOf(b),
      query: query,
      similarTo: similarTo,
      topicId: topicId,
    ),
  );
  return filtered;
}

double _diceBigrams(String a, String b) {
  if (a.length < 2 || b.length < 2) return a == b ? 1.0 : 0.0;
  final left = _bigrams(a);
  final right = _bigrams(b);
  if (left.isEmpty || right.isEmpty) return 0;
  var overlap = 0;
  final used = List<bool>.filled(right.length, false);
  for (final gram in left) {
    for (var i = 0; i < right.length; i++) {
      if (used[i] || right[i] != gram) continue;
      used[i] = true;
      overlap++;
      break;
    }
  }
  return (2 * overlap) / (left.length + right.length);
}

List<String> _bigrams(String value) {
  if (value.length < 2) return const [];
  return [for (var i = 0; i < value.length - 1; i++) value.substring(i, i + 2)];
}
