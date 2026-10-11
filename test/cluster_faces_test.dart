import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:jingerpicmanager/services/face_service.dart';

/// A tiny L2-normalized 4-d embedding helper.
List<double> emb(List<double> v) {
  double s = 0;
  for (final x in v) s += x * x;
  final n = s > 0 ? 1.0 / sqrt(s) : 1.0;
  return v.map((x) => x * n).toList();
}

void main() {
  test('identical embeddings fall into the same cluster', () {
    final e = emb([1, 2, 3, 4]);
    final labels = clusterFaces([e, e, e], threshold: 0.4);
    expect(labels.toSet().length, 1);
  });

  test('orthogonal embeddings stay separate', () {
    final a = emb([1, 0, 0, 0]);
    final b = emb([0, 1, 0, 0]);
    final labels = clusterFaces([a, b], threshold: 0.4);
    expect(labels[0], isNot(labels[1]));
  });

  test('clustering is transitive (connected components)', () {
    // a ~ b and b ~ c (both above threshold), but a and c are below it.
    // All three must merge into one cluster because the similarity graph is
    // connected (transitive closure), not split because a and c are weak.
    final a = emb([1.0, 0.0, 0.0, 0.0]);
    final b = emb([0.95, 0.3, 0.0, 0.0]); // strongly ~a
    final c = emb([0.3, 0.95, 0.0, 0.0]); // strongly ~b, weakly ~a
    final labels = clusterFaces([a, b, c], threshold: 0.4);
    expect(labels.toSet().length, 1);
  });

  test('two clearly different people are separated', () {
    final p1 = [emb([1, 0, 0, 0]), emb([0.98, 0.1, 0, 0])];
    final p2 = [emb([0, 1, 0, 0]), emb([0, 0.97, 0.1, 0])];
    final all = [...p1, ...p2];
    final labels = clusterFaces(all, threshold: 0.4);
    expect(labels[0], labels[1]); // person 1
    expect(labels[2], labels[3]); // person 2
    expect(labels[0], isNot(labels[2]));
  });

  test('empty input returns empty labels', () {
    expect(clusterFaces([]), isEmpty);
  });
}
