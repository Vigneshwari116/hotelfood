import 'package:flutter/material.dart';
import '../services/repository.dart';
import '../widgets/responsive_shell.dart';

class DashboardScreen extends StatefulWidget {
  final bool isAdmin;

  const DashboardScreen({
    super.key,
    required this.isAdmin,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _materials = 0;
  int _lowStock = 0;
  int _negativeStock = 0;

  double _todaySales = 0;
  List<Map<String, dynamic>> _locationSales = [];

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
      final stock = await repo.currentStockReport();
      final today = DateTime.now();

      double todayTotal = 0;
      List<Map<String, dynamic>> locationSales = [];

      if (widget.isAdmin) {
        locationSales = await repo.dailySalesByLocation(today);
        todayTotal = locationSales.fold<double>(
          0,
          (sum, row) => sum + ((row['total'] as num?)?.toDouble() ?? 0),
        );
      } else {
        final sales = await repo.salesReport(includeVoided: false);
        todayTotal = sales.where((s) {
          final saleDate = DateTime.parse(s['sale_date'].toString());
          return saleDate.year == today.year &&
              saleDate.month == today.month &&
              saleDate.day == today.day;
        }).fold<double>(
          0,
          (sum, s) => sum + (s['total'] as num).toDouble(),
        );
      }

      final lowStock = stock.where((r) {
        final current = (r['current_stock'] as num).toDouble();
        final reorder = (r['reorder_level'] as num).toDouble();

        return current >= 0 && current <= reorder;
      }).length;

      final negativeStock = stock.where((r) {
        final current = (r['current_stock'] as num).toDouble();
        return current < -0.000001;
      }).length;

      if (!mounted) return;

      setState(() {
        _materials = materials.length;
        _lowStock = lowStock;
        _negativeStock = negativeStock;
        _todaySales = todayTotal;
        _locationSales = locationSales;
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

  String _shortLocationName(String name) {
    final trimmed = name.trim();
    if (trimmed.length <= 16) return trimmed;
    return '${trimmed.substring(0, 14)}…';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ResponsivePage(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else ...[
                      if (widget.isAdmin && _locationSales.isNotEmpty) ...[
                        Text(
                          'Today\'s Sales by Location',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 10),
                        ResponsiveGrid(
                          tileWidth: 170,
                          children: [
                            ..._locationSales.map((row) {
                              final total =
                                  (row['total'] as num?)?.toDouble() ?? 0;
                              final count =
                                  (row['sale_count'] as num?)?.toInt() ?? 0;
                              final name =
                                  row['location_name']?.toString() ?? 'Location';
                              return _compactLocationCard(
                                _shortLocationName(name),
                                '₹${total.toStringAsFixed(0)}',
                                '$count bills',
                                Icons.storefront_outlined,
                              );
                            }),
                            _compactLocationCard(
                              'Total',
                              '₹${_todaySales.toStringAsFixed(0)}',
                              '${_locationSales.fold<int>(0, (sum, row) => sum + ((row['sale_count'] as num?)?.toInt() ?? 0))} bills',
                              Icons.summarize_outlined,
                              highlighted: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],
                      ResponsiveGrid(
                        tileWidth: 220,
                        children: [
                          _statCard(
                            'Today\'s Sales',
                            '₹${_todaySales.toStringAsFixed(2)}',
                            Icons.point_of_sale,
                          ),
                          _statCard(
                            'Menu Items',
                            '$_materials',
                            Icons.inventory_2,
                          ),
                          _statCard(
                            'Low Stock Alerts',
                            _negativeStock > 0
                                ? '$_lowStock low, $_negativeStock negative'
                                : '$_lowStock',
                            Icons.warning_amber,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _compactLocationCard(
    String label,
    String value,
    String subtitle,
    IconData icon, {
    bool highlighted = false,
  }) {
    final color = highlighted
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.secondary;
    return Card(
      elevation: highlighted ? 3 : 1,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: highlighted ? color : null,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(
    String label,
    String value,
    IconData icon,
  ) {
    final color = Theme.of(context).colorScheme.primary;
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
