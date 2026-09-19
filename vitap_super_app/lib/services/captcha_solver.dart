import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class CaptchaSolver {
  List<List<double>>? _weights;
  List<double>? _biases;
  bool _isInitialized = false;

  static const String _letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final jsonString = await rootBundle.loadString('assets/weights.json');
      final Map<String, dynamic> data = json.decode(jsonString);

      final List<dynamic> weightsRaw = data['weights'];
      _weights = weightsRaw
          .map(
            (row) => (row as List).map((e) => (e as num).toDouble()).toList(),
          )
          .toList();

      final List<dynamic> biasesRaw = data['biases'];
      _biases = biasesRaw.map((e) => (e as num).toDouble()).toList();

      _isInitialized = true;
    } catch (e) {
      throw Exception('Failed to load captcha weights: $e');
    }
  }

  Future<String> predict(String base64Image) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (base64Image.contains(',')) {
      base64Image = base64Image.split(',')[1];
    }

    final bytes = base64Decode(base64Image);
    final image = img.decodeImage(bytes);

    if (image == null) {
      throw Exception('Failed to decode image');
    }

    // 1. Compute Saturation Map
    // Saturation = (max(R,G,B) - min(R,G,B)) * 255 / max(R,G,B)
    final width = image.width; // Should be 200
    final height = image.height; // Should be 40
    final saturate = List.generate(height, (_) => List.filled(width, 0.0));

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();

        final mx = [r, g, b].reduce(max);
        final mn = [r, g, b].reduce(min);

        if (mx > 0) {
          saturate[y][x] = ((mx - mn) * 255.0) / mx;
        }
      }
    }

    String result = '';

    // 2. Segment and Classify each of the 6 characters
    for (int i = 0; i < 6; i++) {
      final x1 = (i + 1) * 25 + 2;
      final y1 = 7 + 5 * (i % 2) + 1;
      final x2 = (i + 2) * 25 + 1;
      final y2 = 35 - 5 * ((i + 1) % 2);

      // Extract patch
      final patchHeight = y2 - y1;
      final patchWidth = x2 - x1;

      // Calculate average saturation for the patch
      double sum = 0;
      for (int py = y1; py < y2; py++) {
        for (int px = x1; px < x2; px++) {
          sum += saturate[py][px];
        }
      }
      final avg = sum / (patchHeight * patchWidth);

      // Binarize and flatten
      final dwImg = List<double>.filled(patchHeight * patchWidth, 0.0);
      int idx = 0;
      for (int py = y1; py < y2; py++) {
        for (int px = x1; px < x2; px++) {
          dwImg[idx++] = saturate[py][px] > avg ? 1.0 : 0.0;
        }
      }

      // Linear Classifier: dot product + bias
      final output = List<double>.filled(_letters.length, 0.0);
      for (int c = 0; c < _letters.length; c++) {
        double dot = 0.0;
        for (int f = 0; f < dwImg.length; f++) {
          dot += dwImg[f] * _weights![f][c];
        }
        output[c] = dot + _biases![c];
      }

      // Softmax (argmax is sufficient)
      int maxIdx = 0;
      double maxVal = output[0];
      for (int c = 1; c < output.length; c++) {
        if (output[c] > maxVal) {
          maxVal = output[c];
          maxIdx = c;
        }
      }

      result += _letters[maxIdx];
    }

    return result;
  }
}
