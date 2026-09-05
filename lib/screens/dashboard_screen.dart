import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/repository.dart';
import '../services/sales_export_service.dart';
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
  List<Map<String, dynamic>> _locations = [];

  DateTime _exportFrom = DateTime.now();
  DateTime _exportTo = DateTime.now();
  int? _exportLocationId;
  bool _exporting = false;

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
      List<Map<String, dynamic>> locations = [];

      if (widget.isAdmin) {
        locationSales = await repo.dailySalesByLocation(today);
        locations = await repo.locations();
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
        _locations = locations;
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

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickExportDate({
    required bool isFrom,
  }) async {
    final initial = isFrom ? _exportFrom : _exportTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;

    setState(() {
      if (isFrom) {
        _exportFrom = picked;
        if (_exportTo.isBefore(_exportFrom)) {
          _exportTo = _exportFrom;
        }
      } else {
        _exportTo = picked;
        if (_exportFrom.isAfter(_exportTo)) {
          _exportFrom = _exportTo;
        }
      }
    });
  }

  Future<void> _exportSales() async {
    if (_exporting) return;

    setState(() {
      _exporting = true;
    });

    try {
      final rows = await Repository.instance.salesExportReport(
        from: _exportFrom,
        to: _exportTo,
        locationId: _exportLocationId,
      );

      final locationLabel = _exportLocationId == null
          ? 'all_locations'
          : _locations
              .firstWhere(
                (row) => row['id'] == _exportLocationId,
                orElse: () => {'name': 'location'},
              )['name']
              .toString()
              .replaceAll(' ', '_');
      final fileName =
          'sales_${_formatDate(_exportFrom)}_to_${_formatDate(_exportTo)}_$locationLabel.xlsx';

      final isDesktop = !kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

      String path;
      if (isDesktop) {
        final picked = await FilePicker.platform.saveFile(
          dialogTitle: 'Save sales export',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: const ['xlsx'],
        );
        path = picked ??
            p.join(
              (await getApplicationDocumentsDirectory()).path,
              fileName,
            );
      } else {
        path = p.join(
          (await getApplicationDocumentsDirectory()).path,
          fileName,
        );
      }

      final bytes = SalesExportService.buildXlsx(rows);
      await File(path).writeAsBytes(bytes);

      if (!mounted) return;

      if (!isDesktop) {
        await Share.shareXFiles(
          [XFile(path)],
          subject: 'Sales export',
          text: 'Sales export for ${_formatDate(_exportFrom)} to ${_formatDate(_exportTo)}',
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            rows.isEmpty
                ? 'No sales found for the selected filters. Empty Excel file saved.'
                : isDesktop
                    ? 'Exported ${rows.length} sale(s) to $path'
                    : 'Exported ${rows.length} sale(s). Share sheet opened.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
        });
      }
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
                        const SizedBox(height: 24),
                        _adminExportSection(context),
                      ],
                      if (!widget.isAdmin)
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

  Widget _adminExportSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Export Sales',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text('From ${_formatDate(_exportFrom)}'),
                  onPressed: () => _pickExportDate(isFrom: true),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text('To ${_formatDate(_exportTo)}'),
                  onPressed: () => _pickExportDate(isFrom: false),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<int?>(
                    value: _exportLocationId,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('All locations'),
                      ),
                      ..._locations.map((location) {
                        return DropdownMenuItem<int?>(
                          value: location['id'] as int,
                          child: Text(location['name']?.toString() ?? 'Location'),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _exportLocationId = value;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _exporting ? null : _exportSales,
                  icon: _exporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                  label: const Text('Export Excel'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Includes full customer name and mobile for every sale in the selected range.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
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
