import 'dart:io';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;

enum QualityStatus {
  excellent,
  good,
  poor,
  rejected,
}

class QualityIssue {
  final String title;
  final String message;
  final bool isCritical;

  QualityIssue({
    required this.title,
    required this.message,
    this.isCritical = false,
  });
}

class ImageQualityResult {
  final QualityStatus status;
  final double score; // 0-100
  final List<QualityIssue> issues;
  final Map<String, dynamic> metrics;

  ImageQualityResult({
    required this.status,
    required this.score,
    required this.issues,
    required this.metrics,
  });
}

class ImageQualityChecker {
  // Minimum acceptable brightness (0-255)
  static const double _minBrightness = 50;
  static const double _maxBrightness = 220;
  
  // Minimum blur score (higher = sharper)
  static const double _minBlurScore = 100;
  
  // Minimum resolution
  static const int _minWidth = 500;
  static const int _minHeight = 500;

  static Future<ImageQualityResult> checkQuality(File imageFile) async {
    final issues = <QualityIssue>[];
    final metrics = <String, dynamic>{};
    double score = 100;

    // Load image
    final imageBytes = await imageFile.readAsBytes();
    final image = img.decodeImage(imageBytes);
    
    if (image == null) {
      return ImageQualityResult(
        status: QualityStatus.rejected,
        score: 0,
        issues: [QualityIssue(
          title: 'Invalid Image',
          message: 'Could not process the image file',
          isCritical: true,
        )],
        metrics: {},
      );
    }

    // 1. Check Resolution
    final resolutionScore = _checkResolution(image, issues);
    metrics['resolution'] = '${image.width}x${image.height}';
    score -= (100 - resolutionScore) * 0.2;

    // 2. Check Brightness
    final brightnessScore = _checkBrightness(image, issues);
    metrics['brightness'] = brightnessScore.toStringAsFixed(1);
    score -= (100 - brightnessScore) * 0.3;

    // 3. Check Blur/Sharpness
    final blurScore = _checkBlur(image, issues);
    metrics['sharpness'] = blurScore.toStringAsFixed(1);
    score -= (100 - blurScore) * 0.5;

    // Ensure score is between 0-100
    score = score.clamp(0, 100);

    // Determine status
    QualityStatus status;
    if (issues.any((i) => i.isCritical)) {
      status = QualityStatus.rejected;
    } else if (score >= 80) {
      status = QualityStatus.excellent;
    } else if (score >= 60) {
      status = QualityStatus.good;
    } else {
      status = QualityStatus.poor;
    }

    return ImageQualityResult(
      status: status,
      score: score,
      issues: issues,
      metrics: metrics,
    );
  }

  static double _checkResolution(img.Image image, List<QualityIssue> issues) {
    if (image.width < _minWidth || image.height < _minHeight) {
      issues.add(QualityIssue(
        title: 'Low Resolution',
        message: 'Image is too small. Please use a higher resolution photo (min ${_minWidth}x${_minHeight})',
        isCritical: true,
      ));
      return 0;
    }
    return 100;
  }

  static double _checkBrightness(img.Image image, List<QualityIssue> issues) {
    // Calculate average brightness
    int totalBrightness = 0;
    int pixelCount = 0;

    for (var y = 0; y < image.height; y += 10) {
      for (var x = 0; x < image.width; x += 10) {
        final pixel = image.getPixel(x, y);
        if (pixel != null) {
          final r = img.getRed(pixel);
          final g = img.getGreen(pixel);
          final b = img.getBlue(pixel);
          // Luminance formula
          final brightness = 0.299 * r + 0.587 * g + 0.114 * b;
          totalBrightness += brightness.toInt();
          pixelCount++;
        }
      }
    }

    final avgBrightness = pixelCount > 0 ? totalBrightness / pixelCount : 0;

    if (avgBrightness < _minBrightness) {
      issues.add(QualityIssue(
        title: 'Too Dark',
        message: 'Image is too dark. Please use better lighting or move to a brighter area',
        isCritical: true,
      ));
      return (avgBrightness / _minBrightness) * 50;
    }

    if (avgBrightness > _maxBrightness) {
      issues.add(QualityIssue(
        title: 'Too Bright',
        message: 'Image is overexposed. Please reduce lighting or avoid direct flash',
        isCritical: false,
      ));
      return 100 - ((avgBrightness - _maxBrightness) / 35 * 50);
    }

    return 100;
  }

  static double _checkBlur(img.Image image, List<QualityIssue> issues) {
    // Convert to grayscale for edge detection
    final grayscale = img.grayscale(image);
    
    // Simple Laplacian variance for blur detection
    double variance = 0;
    double mean = 0;
    final List<double> gradients = [];

    for (var y = 1; y < grayscale.height - 1; y += 4) {
      for (var x = 1; x < grayscale.width - 1; x += 4) {
        final center = img.getPixel(grayscale, x, y) ?? 0;
        final left = img.getPixel(grayscale, x - 1, y) ?? 0;
        final right = img.getPixel(grayscale, x + 1, y) ?? 0;
        final top = img.getPixel(grayscale, x, y - 1) ?? 0;
        final bottom = img.getPixel(grayscale, x, y + 1) ?? 0;

        final centerGray = img.getRed(center);
        final leftGray = img.getRed(left);
        final rightGray = img.getRed(right);
        final topGray = img.getRed(top);
        final bottomGray = img.getRed(bottom);

        // Laplacian approximation
        final gradient = (4 * centerGray - leftGray - rightGray - topGray - bottomGray).abs();
        gradients.add(gradient.toDouble());
        mean += gradient;
      }
    }

    if (gradients.isEmpty) {
      issues.add(QualityIssue(
        title: 'Processing Error',
        message: 'Could not analyze image sharpness',
        isCritical: true,
      ));
      return 0;
    }

    mean /= gradients.length;

    // Calculate variance
    for (final g in gradients) {
      variance += (g - mean) * (g - mean);
    }
    variance /= gradients.length;

    final blurScore = variance;

    if (blurScore < _minBlurScore) {
      issues.add(QualityIssue(
        title: 'Blurry Image',
        message: 'Image is out of focus. Please hold the camera steady and tap to focus',
        isCritical: true,
      ));
      return (blurScore / _minBlurScore) * 50;
    }

    return 100;
  }
}
