// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

/// Reusable UI atoms + small formatting helpers shared across the pages.

// ── Formatting helpers ───────────────────────────────────────────────────────

({String label, Color color, IconData icon}) adapterVisual(
  BtcAdapterState state,
  ColorScheme cs,
) {
  switch (state) {
    case BtcAdapterState.on:
      return (label: 'On', color: cs.primary, icon: Icons.bluetooth);
    case BtcAdapterState.turningOn:
      return (
        label: 'Turning on...',
        color: cs.tertiary,
        icon: Icons.bluetooth_searching,
      );
    case BtcAdapterState.turningOff:
      return (
        label: 'Turning off...',
        color: cs.tertiary,
        icon: Icons.bluetooth_disabled,
      );
    case BtcAdapterState.off:
      return (label: 'Off', color: cs.error, icon: Icons.bluetooth_disabled);
    case BtcAdapterState.unauthorized:
      return (label: 'No permission', color: cs.error, icon: Icons.block);
    case BtcAdapterState.unsupported:
      return (
        label: 'Unsupported',
        color: cs.outline,
        icon: Icons.do_not_disturb,
      );
    case BtcAdapterState.unknown:
      return (label: 'Unknown', color: cs.outline, icon: Icons.help_outline);
  }
}

({String label, Color color}) bondVisual(BtcBondState state, ColorScheme cs) {
  switch (state) {
    case BtcBondState.bonded:
      return (label: 'Paired', color: cs.primary);
    case BtcBondState.bonding:
      return (label: 'Pairing...', color: cs.tertiary);
    case BtcBondState.none:
      return (label: 'Not paired', color: cs.outline);
  }
}

({String label, Color color, IconData icon}) connectionVisual(
  BtcConnectionState state,
  ColorScheme cs,
) {
  switch (state) {
    case BtcConnectionState.connected:
      return (label: 'Connected', color: cs.primary, icon: Icons.link);
    case BtcConnectionState.connecting:
      return (label: 'Connecting...', color: cs.tertiary, icon: Icons.sync);
    case BtcConnectionState.disconnecting:
      return (
        label: 'Disconnecting...',
        color: cs.tertiary,
        icon: Icons.link_off,
      );
    case BtcConnectionState.disconnected:
      return (label: 'Disconnected', color: cs.error, icon: Icons.link_off);
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────────

/// A pill-shaped status chip with a leading icon.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Five-bar RSSI signal strength indicator. Null RSSI renders as muted bars.
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.rssi, this.size = 18});

  final int? rssi;
  final double size;

  int get _level {
    final v = rssi;
    if (v == null) return 0;
    if (v >= -55) return 4;
    if (v >= -67) return 3;
    if (v >= -78) return 2;
    if (v >= -90) return 1;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = _level == 0
        ? cs.outlineVariant
        : (_level >= 3 ? cs.primary : (_level == 2 ? cs.tertiary : cs.error));
    return SizedBox(
      width: size,
      height: size,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(4, (i) {
          final on = i < _level;
          return Container(
            width: size * 0.18,
            height: size * (0.4 + i * 0.2),
            decoration: BoxDecoration(
              color: on ? active : cs.outlineVariant.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}

/// Round device avatar coloured by bond state.
class DeviceAvatar extends StatelessWidget {
  const DeviceAvatar({super.key, required this.device});

  final BtcDevice device;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bonded = device.bondState == BtcBondState.bonded;
    return CircleAvatar(
      radius: 22,
      backgroundColor: bonded
          ? cs.primaryContainer
          : cs.surfaceContainerHighest,
      child: Icon(
        bonded ? Icons.bluetooth_connected : Icons.bluetooth,
        color: bonded ? cs.onPrimaryContainer : cs.onSurfaceVariant,
      ),
    );
  }
}

/// A titled card section with optional trailing action.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 16),
  });

  final String title;
  final IconData? icon;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// A simple label → value row.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: mono
                    ? const [FontFeature.tabularFigures()]
                    : null,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Centered empty / placeholder state.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
