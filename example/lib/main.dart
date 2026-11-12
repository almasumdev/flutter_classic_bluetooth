// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'controller.dart';
import 'pages/capabilities_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/discover_page.dart';
import 'pages/paired_page.dart';
import 'pages/server_page.dart';
import 'widgets.dart';

void main() => runApp(const BluetoothExampleApp());

class BluetoothExampleApp extends StatelessWidget {
  const BluetoothExampleApp({super.key});

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2962FF),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      cardColor: scheme.surfaceContainerLow,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        scrolledUnderElevation: 2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluetooth Classic',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const HomeShell(),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  final _controller = BluetoothController();
  int _index = 0;

  static const _destinations = [
    _Destination('Dashboard', Icons.dashboard_outlined, Icons.dashboard),
    _Destination('Discover', Icons.radar_outlined, Icons.radar),
    _Destination('Paired', Icons.devices_outlined, Icons.devices),
    _Destination('Server', Icons.dns_outlined, Icons.dns),
    _Destination('About', Icons.fact_check_outlined, Icons.fact_check),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onControllerChanged);
    _controller.init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-sync the adapter state when returning to the app, in case the user
    // toggled Bluetooth from the system while we were backgrounded.
    if (state == AppLifecycleState.resumed) {
      _controller.refreshAdapterState();
    }
  }

  void _onControllerChanged() {
    final error = _controller.lastError;
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
      );
      _controller.clearError();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  Widget _page(int i) {
    switch (i) {
      case 0:
        return DashboardPage(
          controller: _controller,
          onNavigate: (i) => setState(() => _index = i),
        );
      case 1:
        return DiscoverPage(controller: _controller);
      case 2:
        return PairedPage(controller: _controller);
      case 3:
        return ServerPage(controller: _controller);
      default:
        return CapabilitiesPage(controller: _controller);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Bluetooth Classic'),
            actions: [
              ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  final v = adapterVisual(
                    _controller.adapterState,
                    Theme.of(context).colorScheme,
                  );
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Center(
                      child: StatusPill(
                        label: v.label,
                        color: v.color,
                        icon: v.icon,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          body: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              if (!_controller.ready) {
                return const Center(child: CircularProgressIndicator());
              }
              final content = _page(_index);
              if (!wide) return content;
              return Row(
                children: [
                  NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: (i) => setState(() => _index = i),
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (final d in _destinations)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              );
            },
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  destinations: [
                    for (final d in _destinations)
                      NavigationDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: d.label,
                      ),
                  ],
                ),
        );
      },
    );
  }
}
