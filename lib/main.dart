import 'package:flutter/material.dart';
import 'package:foodstock/database/database_helper.dart';
import 'services/repository.dart';

import 'widgets/responsive_shell.dart';

import 'screens/dashboard_screen.dart';
import 'screens/simple_masters_screen.dart';
import 'screens/raw_material_master_screen.dart';
import 'screens/purchase_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/pos_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/printer_settings_screen.dart';

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
      title: 'Five Star — Order & Stock Console',
      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        useMaterial3: true,

        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B1E1E),
          primary: const Color(0xFF8B1E1E),
          secondary: const Color(0xFFE0A526),
        ),

        scaffoldBackgroundColor: const Color(0xFFF7EFE1),

        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF8B1E1E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),

        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(),
        ),

        cardTheme: const CardThemeData(
          elevation: 1,
          margin: EdgeInsets.zero,
        ),
      ),

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

  @override
  void initState() {
    super.initState();

    _ready = _initializeApp();
  }

  Future<void> _initializeApp() async {
    await DBHelper.instance.database;
    await Repository.instance.ensureDefaultUsers();
    await Repository.instance.ensureStandardUnits();
    await Repository.instance.writeOffExpiredStock();
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
      final db = await DBHelper.instance.database;

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

      if (!mounted) return;

      final role = (rows.first['role'] ?? 'staff').toString();

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainShell(
            username: username,
            role: role,
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
                    // LOGO
                    const Icon(
                      Icons.storefront,
                      size: 60,
                      color: Color(0xFF8B1E1E),
                    ),

                    const SizedBox(height: 12),

                    const Text(
                      'FIVE STAR',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF8B1E1E),
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      'Order & Stock Console',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),

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

class MainShell extends StatelessWidget {
  final String username;
  final String role;

  const MainShell({
    super.key,
    required this.username,
    required this.role,
  });

  bool get _isAdmin => role.toLowerCase() == 'admin';

  @override
  Widget build(BuildContext context) {
    final salesItem = NavItem(
      icon: Icons.point_of_sale,
      label: 'Sales / POS',
      page: const PosScreen(),
    );

    final items = _isAdmin
        ? [
            NavItem(
              icon: Icons.dashboard_outlined,
              label: 'Dashboard',
              page: const DashboardScreen(),
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
              label: 'Raw Materials',
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
          ]
        : [salesItem];

    return ResponsiveShell(
      title: 'Five Star',
      userLabel: username,
      items: items,
      onLogout: () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const LoginScreen(),
          ),
        );
      },
    );
  }
}
