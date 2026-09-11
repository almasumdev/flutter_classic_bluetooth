import 'dart:math' as math;

/// Controls how a [BtcReconnectingConnection] retries after the link drops.
///
/// Reconnect delays grow exponentially (`initialBackoff`,
/// `initialBackoff * backoffMultiplier`, ...), capped at [maxBackoff].
///
/// {@category Models}
class BtcReconnectPolicy {
  /// Creates a reconnect policy. The defaults retry forever with 1s → 30s
  /// exponential backoff and a 15s per-attempt connect timeout.
  const BtcReconnectPolicy({
    this.maxAttempts,
    this.initialBackoff = const Duration(seconds: 1),
    this.maxBackoff = const Duration(seconds: 30),
    this.backoffMultiplier = 2.0,
    this.connectTimeout = const Duration(seconds: 15),
  });

  /// Maximum consecutive reconnect attempts (retries) before giving up.
  ///
  /// `null` (the default) retries indefinitely. The first connect is not a
  /// retry, so `maxAttempts: 3` means one initial attempt plus three retries.
  final int? maxAttempts;

  /// Delay before the first retry.
  final Duration initialBackoff;

  /// Upper bound on the backoff delay.
  final Duration maxBackoff;

  /// Factor the backoff grows by after each failed retry.
  final double backoffMultiplier;

  /// Per-attempt connect timeout, or `null` to wait indefinitely.
  final Duration? connectTimeout;

  /// The exponential, capped backoff before reconnect [attempt] (1-based).
  Duration backoffForAttempt(int attempt) {
    final n = attempt < 1 ? 1 : attempt;
    final ms =
        initialBackoff.inMilliseconds *
        math.pow(backoffMultiplier, n - 1).toDouble();
    final capped = math.min(ms, maxBackoff.inMilliseconds.toDouble());
    return Duration(milliseconds: capped.round());
  }
}
