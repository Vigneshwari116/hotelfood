import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:foodstock/database/database_helper.dart';
import 'package:foodstock/database/api_config.dart';
import 'package:foodstock/services/auth_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/item_import_service.dart';
import 'services/repository.dart';

import 'widgets/brand_logo.dart';
import 'widgets/responsive_shell.dart';
import 'theme/brand_theme.dart';

import 'screens/dashboard_screen.dart';
import 'screens/simple_masters_screen.dart';
import 'screens/raw_material_master_screen.dart';
import 'screens/purchase_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/pos_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/printer_settings_screen.dart';
import 'screens/backup_screen.dart';
import 'screens/reset_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite / desktop database support.
  DBHelper.init();

  runApp(const RestoPosApp());
}

// ============================================================
// APP
// ============================================================

class RestoPosApp extends StatelessWidget {
  const RestoPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shilpa Enterprise',
      debugShowCheckedModeBanner: false,

      theme: buildBrandTheme(),

      home: const _StartupGate(),
    );
  }
}

// ============================================================
// STARTUP GATE
// ============================================================

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  late Future<void> _ready;
  AuthSession? _session;

  @override
  void initState() {
    super.initState();

    _ready = _initializeApp();
  }

  Future<void> _initializeApp() async {
    await DBHelper.instance.appDb;
    await Repository.instance.ensureDefaultUsers();
    await Repository.instance.ensureStandardUnits();
    await Repository.instance.ensureDefaultCategories();
    try {
      const seedKey = 'menu_csv_seed';
      const seedVersion = 8;
      final remote = ApiConfig.enabled;
      int seeded;
      if (remote) {
        final db = await DBHelper.instance.appDb;
        final rows = await db.query(
          'app_meta',
          where: 'key = ?',
          whereArgs: [seedKey],
        );
        seeded = rows.isEmpty
            ? 0
            : int.tryParse(rows.first['value']?.toString() ?? '') ?? 0;
      } else {
        final prefs = await SharedPreferences.getInstance();
        seeded = prefs.getInt(seedKey) ?? 0;
      }
      await ItemImportService().importCsvText(
        await rootBundle.loadString(
          'assets/templates/menu_items_import.csv',
        ),
        updateExisting: seeded < seedVersion,
        replaceCatalog: seeded < seedVersion,
      );
      if (seeded < seedVersion) {
        if (remote) {
          final db = await DBHelper.instance.appDb;
          await db.delete('app_meta', where: 'key = ?', whereArgs: [seedKey]);
          await db.insert('app_meta', {
            'key': seedKey,
            'value': '$seedVersion',
          });
        } else {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(seedKey, seedVersion);
        }
      }
    } catch (_) {}
    await Repository.instance.writeOffExpiredStock();
    _session = await AuthSession.load();
    if (_session != null) {
      Repository.instance.bindSession(
        role: _session!.role,
        locationId: _session!.locationId,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 60,
                      color: Colors.red,
                    ),

                    const SizedBox(height: 16),

                    const Text(
                      'Unable to initialize application',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 20),

                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _ready = _initializeApp();
                        });
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final session = _session;
        if (session != null) {
          return MainShell(
            username: session.username,
            role: session.role,
            locationName: session.locationName,
          );
        }

        return const LoginScreen();
      },
    );
  }
}

// ============================================================
// LOGIN SCREEN
// ============================================================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();

  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();

    super.dispose();
  }

  Future<void> _login() async {
    final username = _user.text.trim();
    final password = _pass.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _error = 'Please enter username and password';
      });

      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = await DBHelper.instance.appDb;

      final rows = await db.query(
        'users',
        where: 'username = ?',
        whereArgs: [username],
      );

      if (rows.isEmpty ||
          rows.first['password_hash'] != hashPin(password)) {
        setState(() {
          _loading = false;
          _error = 'Invalid username or password';
        });

        return;
      }

      final role = (rows.first['role'] ?? 'staff').toString();
      final locationId = rows.first['location_id'] as int?;
      String? locationName;

      if (locationId != null) {
        final locationRows = await db.query(
          'locations',
          where: 'id = ?',
          whereArgs: [locationId],
          limit: 1,
        );
        if (locationRows.isNotEmpty) {
          locationName = locationRows.first['name']?.toString();
        }
      }

      await AuthSession.save(
        username: username,
        role: role,
        locationId: locationId,
        locationName: locationName,
      );

      Repository.instance.bindSession(
        role: role,
        locationId: locationId,
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainShell(
            username: username,
            role: role,
            locationName: locationName,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Login failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 380,
            ),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandLogo(height: 168),

                    const SizedBox(height: 28),

                    // USERNAME
                    TextField(
                      controller: _user,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // PASSWORD
                    TextField(
                      controller: _pass,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _login(),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 10),

                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.red,
                        ),
                      ),
                    ],

                    const SizedBox(height: 22),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: _loading ? null : _login,
                        child: _loading
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                            : const Text(
                          'Login',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// MAIN SHELL
// ============================================================

class MainShell extends StatefulWidget {
  final String username;
  final String role;
  final String? locationName;

  const MainShell({
    super.key,
    required this.username,
    required this.role,
    this.locationName,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _shellGeneration = 0;

  bool get _isAdmin => widget.role.toLowerCase() == 'admin';

  void _handleSessionReset() {
    setState(() {
      _shellGeneration++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final salesItem = NavItem(
      icon: Icons.point_of_sale,
      label: 'Sales / POS',
      page: const PosScreen(),
    );

    final items = _isAdmin
        ? <NavEntry>[
            NavItem(
              icon: Icons.dashboard_outlined,
              label: 'Dashboard',
              page: DashboardScreen(isAdmin: _isAdmin),
            ),
            salesItem,
            NavItem(
              icon: Icons.inventory_2_outlined,
              label: 'Inventory',
              page: const InventoryScreen(),
            ),
            NavItem(
              icon: Icons.shopping_cart_outlined,
              label: 'Purchase',
              page: const PurchaseScreen(),
            ),
            NavItem(
              icon: Icons.warehouse_outlined,
              label: 'Menu Items',
              page: const RawMaterialMasterScreen(),
            ),
            NavItem(
              icon: Icons.category_outlined,
              label: 'Masters',
              page: const SimpleMastersScreen(),
            ),
            NavItem(
              icon: Icons.bar_chart_outlined,
              label: 'Reports',
              page: const ReportsScreen(),
            ),
            NavItem(
              icon: Icons.print_outlined,
              label: 'Printers',
              page: const PrinterSettingsScreen(),
            ),
            NavGroup(
              icon: Icons.settings_outlined,
              label: 'Settings',
              children: [
                NavItem(
                  icon: Icons.backup_outlined,
                  label: 'Backup',
                  page: const BackupScreen(),
                ),
                NavItem(
                  icon: Icons.restart_alt,
                  label: 'Reset',
                  page: ResetScreen(
                    onSessionReset: _handleSessionReset,
                  ),
                ),
              ],
            ),
          ]
        : <NavEntry>[salesItem];

    return ResponsiveShell(
      key: ValueKey(_shellGeneration),
      title: 'Shilpa Enterprise',
      userLabel: widget.locationName ?? widget.username,
      items: items,
      onLogout: () async {
        await AuthSession.clear();
        Repository.instance.clearSession();
        if (Platform.isAndroid || Platform.isIOS) {
          await SystemNavigator.pop();
          return;
        }
        if (!context.mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const LoginScreen(),
          ),
        );
      },
    );
  }
}
