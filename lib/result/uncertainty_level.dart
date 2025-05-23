// lib/models/uncertainty_level.dart

/// Buckets for the three levels of uncertainty in your pipeline.
enum UncertaintyLevel {
  /// 0% uncertainty (user-defined)
  user,
  /// ~10% uncertainty (database lookup)
  database,
  /// ~25% uncertainty (adapted record)
  adapted,
  /// ~50% uncertainty (LLM‐inferred)
  inferred;

  /// Map a numeric fraction → bucket.
  static UncertaintyLevel fromValue(double value) {
    if (value <= 0.0) return UncertaintyLevel.user;
    if (value <= 0.1) return UncertaintyLevel.database;
    if (value <= 0.25) return UncertaintyLevel.adapted;
    return UncertaintyLevel.inferred;
  }

  /// Human-readable label.
  String get label {
    switch (this) {
      case UncertaintyLevel.user:
        return 'User';
      case UncertaintyLevel.database:
        return 'Database';
      case UncertaintyLevel.adapted:
        return 'Adapted';
      case UncertaintyLevel.inferred:
        return 'Inferred';
    }
  }
}
