import 'package:flutter/material.dart';
import '../services/repository.dart';
import '../widgets/responsive_shell.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _materials = 0;
  int _menuItems = 0;
  int _customers = 0;
  int _lowStock = 0;

  double _todaySales = 0;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = Repository.instance;

      final materials = await repo.rawMaterials();
      final customers = await repo.customers();
      final stock = await repo.currentStockReport();
      final sales = await repo.salesReport();

      final today = DateTime.now();

      final todayTotal = sales.where((s) {
        final saleDate = DateTime.parse(s['sale_date'].toString());

        return saleDate.year == today.year &&
            saleDate.month == today.month &&
            saleDate.day == today.day;
      }).fold<double>(
        0,
            (sum, s) => sum + (s['total'] as num).toDouble(),
      );

      final lowStock = stock.where((r) {
        final current = (r['current_stock'] as num).toDouble();
        final reorder = (r['reorder_level'] as num).toDouble();

        return current <= reorder;
      }).length;

      if (!mounted) return;

      setState(() {
        _materials = materials.length;
        _customers = customers.length;
        _lowStock = lowStock;
        _todaySales = todayTotal;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load dashboard: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ResponsivePage(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),

                  // Dashboard heading only
                  const Text(
                    'Dashboard',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 20),

                  if (_loading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else
                    ResponsiveGrid(
                      tileWidth: 220,
                      children: [
                        _statCard(
                          'Today\'s Sales',
                          '₹${_todaySales.toStringAsFixed(2)}',
                          Icons.point_of_sale,
                          Colors.green,
                        ),

                        _statCard(
                          'Raw Materials',
                          '$_materials',
                          Icons.inventory_2,
                          Colors.blue,
                        ),

                        _statCard(
                          'Menu Items',
                          '$_menuItems',
                          Icons.restaurant_menu,
                          Colors.orange,
                        ),

                        _statCard(
                          'Customers',
                          '$_customers',
                          Icons.people,
                          Colors.purple,
                        ),

                        _statCard(
                          'Low Stock Alerts',
                          '$_lowStock',
                          Icons.warning_amber,
                          Colors.red,
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _statCard(
      String label,
      String value,
      IconData icon,
      Color color,
      ) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: color,
                size: 28,
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}