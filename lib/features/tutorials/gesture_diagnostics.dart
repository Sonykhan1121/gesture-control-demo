/// One reading from the actual tutorial acceptance checks. A null result means
/// the check could not run yet, never a successful or failed measurement.
class GestureCheck {
  const GestureCheck(this.id, this.label, this.detail, this.passed);

  final String id;
  final String label;
  final String detail;
  final bool? passed;
}

String gesturePercent(double value) =>
    value.isFinite ? '${(value * 100).toStringAsFixed(1)}%' : 'invalid';
