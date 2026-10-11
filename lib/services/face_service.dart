import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class RawFace {
  RawFace({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.score,
    required this.embedding,
  });

  final double x;
  final double y;
  final double w;
  final double h;
  final double score;
  final List<double> embedding;
}

/// Talks to the native (Windows) ONNX Runtime face engine over a method
/// channel. All computation happens locally; nothing leaves the machine.
class FaceService {
  FaceService._();

  static final FaceService instance = FaceService._();
  static const MethodChannel _channel = MethodChannel('jingerpic/face');

  /// Whether the native face engine is reachable (Windows build with models).
  Future<bool> isSupported() async {
    try {
      await _channel
          .invokeMethod<dynamic>('detect', {
            'rgb': Uint8List.fromList([0, 0, 0]),
            'w': 1,
            'h': 1,
          })
          .timeout(const Duration(seconds: 3));
      return true;
    } on PlatformException catch (e) {
      if (e.code == 'not_implemented') return false;
      return true;
    } on TimeoutException {
      // Native side did not reply in time; treat the engine as unavailable
      // rather than blocking the library load.
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Returns the faces detected in an image file (empty list if none / error).
  Future<List<RawFace>> detect(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return [];

      img.Image src = decoded;
      final maxSide = src.width > src.height ? src.width : src.height;
      if (maxSide > 640) {
        final scale = 640 / maxSide;
        src = img.copyResize(
          decoded,
          width: (src.width * scale).round(),
          height: (src.height * scale).round(),
        );
      }

      final rgb = src.getBytes(order: img.ChannelOrder.rgb);
      final result = await _channel.invokeMethod<dynamic>('detect', {
        'rgb': rgb,
        'w': src.width,
        'h': src.height,
      });
      if (result == null) return [];
      final list = result as List<dynamic>;
      return list.map((e) {
        final m = e as Map<dynamic, dynamic>;
        final emb = (m['embedding'] as List<dynamic>)
            .map((v) => (v as num).toDouble())
            .toList();
        return RawFace(
          x: (m['x'] as num).toDouble(),
          y: (m['y'] as num).toDouble(),
          w: (m['w'] as num).toDouble(),
          h: (m['h'] as num).toDouble(),
          score: (m['score'] as num).toDouble(),
          embedding: emb,
        );
      }).toList();
    } on PlatformException {
      // Engine not available (e.g. on non-Windows or model missing).
      return [];
    } catch (_) {
      return [];
    }
  }
}

/// Clustering of L2-normalized embeddings by cosine similarity.
///
/// Uses a connected-components (union-find) approach over the pairwise
/// similarity graph: two faces belong to the same person when their cosine
/// similarity exceeds [threshold]. This is symmetric and order-independent,
/// so it avoids the drift/greedy artifacts of a single-pass representative
/// scheme (which tends to either over-merge or over-split).
///
/// Returns a cluster label (0-based) per input embedding.
List<int> clusterFaces(List<List<double>> embeddings, {double threshold = 0.4}) {
  final n = embeddings.length;
  if (n == 0) return const [];

  // Union-find.
  final parent = List<int>.generate(n, (i) => i);
  int find(int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  }

  void union(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra != rb) parent[ra] = rb;
  }

  for (int i = 0; i < n; i++) {
    final ei = embeddings[i];
    for (int j = i + 1; j < n; j++) {
      final ej = embeddings[j];
      final len = ei.length < ej.length ? ei.length : ej.length;
      double sim = 0.0;
      for (int k = 0; k < len; k++) {
        sim += ei[k] * ej[k];
      }
      if (sim > threshold) union(i, j);
    }
  }

  // Compress and renumber roots into compact 0-based labels.
  final rootToLabel = <int, int>{};
  final labels = List<int>.filled(n, 0);
  for (int i = 0; i < n; i++) {
    final r = find(i);
    final label = rootToLabel.putIfAbsent(r, () => rootToLabel.length);
    labels[i] = label;
  }
  return labels;
}
