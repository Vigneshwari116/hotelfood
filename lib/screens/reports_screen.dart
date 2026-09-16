import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:foodstock/model/models.dart';
import '../services/item_import_service.dart';
import '../services/report_pdf.dart';
import '../services/repository.dart';
import '../widgets/responsive_shell.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TabBar(
            controller: _tab,
            isScrollable: true,
            tabs: const [
              Tab(text: 'Stock Summary'),
              Tab(text: 'Bill-wise Sales'),
              Tab(text: 'Bill-wise Purchase'),
              Tab(text: 'Day End'),
              Tab(text: 'Top Selling'),
            ],
          ),
          Expanded(
            child: TabBarView(controller: _tab, children: const [
              _StockSummaryTab(),
              _BillWiseSalesTab(),
              _PurchaseBillsTab(),
              _DayEndTab(),
              _TopSellingTab(),
            ]),
          ),
        ],
      ),
    );
  }
}

class _StockReportTab extends StatefulWidget {
  const _StockReportTab();
  @override
  State<_StockReportTab> createState() => _StockReportTabState();
}

class _StockReportTabState extends State<_StockReportTab> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Repository.instance.currentStockReport();
      if (!mounted) return;
      setState(() {
        _rows = r;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rows = [];
        _loading = false;
      });
    }
  }

  double _rowValue(Map<String, dynamic> r) {
    final qty = (r['current_stock'] as num?)?.toDouble() ?? 0;
    final cp = (r['cost_price'] as num?)?.toDouble() ?? 0;
    return qty * cp;
  }

  static String _formatNumber(double value) {
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final totalValue = _rows.fold<double>(0, (sum, r) => sum + _rowValue(r));

    final lowStockCount = _rows.where((r) {
      final stock = (r['current_stock'] as num?)?.toDouble() ?? 0;
      final reorder = (r['reorder_level'] as num?)?.toDouble() ?? 0;
      return stock >= 0 && stock <= reorder;
    }).length;

    final negativeStockCount = _rows.where((r) {
      final stock = (r['current_stock'] as num?)?.toDouble() ?? 0;
      return stock < -0.000001;
    }).length;

    // Items with no Cost Price set — their value can't be counted,
    // so flag it rather than silently treating them as ₹0.
    final missingPriceCount = _rows.where((r) => r['cost_price'] == null).length;

    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _rows.isEmpty
                ? const Center(child: Text('No menu items yet'))
                : SingleChildScrollView(
              child: DataTable(columns: const [
                DataColumn(label: Text('Item')),
                DataColumn(label: Text('Category')),
                DataColumn(label: Text('Stock')),
                DataColumn(label: Text('Unit')),
                DataColumn(label: Text('Value (₹)'), numeric: true),
              ], rows: _rows.map((r) {
                final stock = (r['current_stock'] as num?)?.toDouble() ?? 0;
                final reorder = (r['reorder_level'] as num?)?.toDouble() ?? 0;
                final negative = stock < -0.000001;
                final low = !negative && stock <= reorder;
                final value = _rowValue(r);
                final hasPrice = r['cost_price'] != null;
                final stockStyle = negative
                    ? const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      )
                    : low
                        ? const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          )
                        : null;

                return DataRow(cells: [
                  DataCell(Text(
                    RawMaterial.staffLabelFor(
                      r['name']?.toString() ?? '',
                      r['sub_item']?.toString(),
                    ),
                    style: stockStyle,
                  )),
                  DataCell(Text(r['category'] ?? '-')),
                  DataCell(Text(
                    _formatNumber(stock),
                    style: stockStyle,
                  )),
                  DataCell(Text(r['unit'] ?? '-')),
                  DataCell(Text(
                    hasPrice ? _formatNumber(value) : '—',
                    style: TextStyle(color: hasPrice ? null : Colors.grey.shade400),
                  )),
                ]);
              }).toList()),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Stock Value',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(
                        '₹ ${totalValue.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_rows.length} items in stock',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                      ),
                      if (lowStockCount > 0)
                        Text(
                          '$lowStockCount low stock',
                          style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      if (negativeStockCount > 0)
                        Text(
                          '$negativeStockCount negative stock',
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  if (missingPriceCount > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '$missingPriceCount item(s) have no Cost Price set — excluded from total value',
                      style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StockSummaryTab extends StatefulWidget {
  const _StockSummaryTab();
  @override
  State<_StockSummaryTab> createState() => _StockSummaryTabState();
}

class _StockSummaryTabState extends State<_StockSummaryTab> {
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await Repository.instance.stockMovementReport(
        from: _from,
        to: _to,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = [];
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _setRange(DateTime from, DateTime to) {
    setState(() {
      _from = from;
      _to = to;
    });
    _load();
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatQty(num? value) {
    final number = value?.toDouble() ?? 0;
    if ((number - number.roundToDouble()).abs() < 0.000001) {
      return number.round().toString();
    }
    return number.toStringAsFixed(2);
  }

  String _formatMoney(num? value) {
    if (value == null) return '—';
    return '₹${value.toDouble().toStringAsFixed(2)}';
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: _to,
    );
    if (picked != null) {
      _setRange(picked, _to.isBefore(picked) ? picked : _to);
    }
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: _from,
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      _setRange(_from.isAfter(picked) ? picked : _from, picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final openingQty = _rows.fold<double>(
      0,
      (sum, row) => sum + ((row['opening_qty'] as num?)?.toDouble() ?? 0),
    );
    final purchaseQty = _rows.fold<double>(
      0,
      (sum, row) => sum + ((row['purchase_qty'] as num?)?.toDouble() ?? 0),
    );
    final salesQty = _rows.fold<double>(
      0,
      (sum, row) => sum + ((row['sales_qty'] as num?)?.toDouble() ?? 0),
    );
    final closingQty = _rows.fold<double>(
      0,
      (sum, row) => sum + ((row['closing_qty'] as num?)?.toDouble() ?? 0),
    );

    return ResponsivePage(
      maxWidth: 1400,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'All menu items are always listed. Pick dates to see opening, purchases, sales, and closing for that period only.',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Period: ${_formatDate(_from)}'
            '${_from.year == _to.year && _from.month == _to.month && _from.day == _to.day ? '' : ' → ${_formatDate(_to)}'}'
            '  •  Opening + Purchases − Sales = Closing',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text('From ${_formatDate(_from)}'),
                onPressed: _pickFromDate,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text('To ${_formatDate(_to)}'),
                onPressed: _pickToDate,
              ),
              TextButton(
                onPressed: () {
                  final today = DateTime.now();
                  _setRange(today, today);
                },
                child: const Text('Today'),
              ),
              TextButton(
                onPressed: () {
                  final today = DateTime.now();
                  final start = today.subtract(Duration(days: today.weekday - 1));
                  _setRange(start, today);
                },
                child: const Text('This week'),
              ),
              TextButton(
                onPressed: () {
                  final today = DateTime.now();
                  _setRange(DateTime(today.year, today.month, 1), today);
                },
                child: const Text('This month'),
              ),
              FilledButton.icon(
                onPressed: _rows.isEmpty
                    ? null
                    : () async {
                        await ReportPdf.shareTable(
                          title: 'Stock Summary',
                          headers: const [
                            'Item',
                            'Unit',
                            'Opening',
                            'Purchase',
                            'Sales',
                            'Closing',
                          ],
                          rows: _rows
                              .map(
                                (row) => [
                                  RawMaterial.staffLabelFor(
                                    row['item_name']?.toString() ?? '',
                                    row['sub_item']?.toString(),
                                  ),
                                  row['unit']?.toString() ?? '-',
                                  _formatQty(row['opening_qty']),
                                  _formatQty(row['purchase_qty']),
                                  _formatQty(row['sales_qty']),
                                  _formatQty(row['closing_qty']),
                                ],
                              )
                              .toList(),
                          totalLine:
                              'Opening ${_formatQty(openingQty)}  •  Purchase ${_formatQty(purchaseQty)}  •  Sales ${_formatQty(salesQty)}  •  Closing ${_formatQty(closingQty)}',
                        );
                      },
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('Share PDF'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _rows.isEmpty
                ? const Center(
                    child: Text(
                      'No menu items found for this location.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                        border: TableBorder.all(
                          color: Colors.grey.shade400,
                          width: 1,
                        ),
                        headingRowColor: WidgetStateProperty.all(
                          Colors.grey.shade100,
                        ),
                        columns: const [
                          DataColumn(label: Text('Item')),
                          DataColumn(label: Text('Unit')),
                          DataColumn(label: Text('Opening'), numeric: true),
                          DataColumn(label: Text('Purchase'), numeric: true),
                          DataColumn(label: Text('Sales'), numeric: true),
                          DataColumn(label: Text('Closing'), numeric: true),
                        ],
                        rows: _rows.map((row) {
                          return DataRow(
                            cells: [
                              DataCell(Text(
                                RawMaterial.staffLabelFor(
                                  row['item_name']?.toString() ?? '',
                                  row['sub_item']?.toString(),
                                ),
                              )),
                              DataCell(Text(row['unit']?.toString() ?? '-')),
                              DataCell(Text(_formatQty(row['opening_qty']))),
                              DataCell(Text(_formatQty(row['purchase_qty']))),
                              DataCell(Text(_formatQty(row['sales_qty']))),
                              DataCell(Text(
                                _formatQty(row['closing_qty']),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              )),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 18,
                runSpacing: 8,
                children: [
                  Text(
                    'Opening: ${_formatQty(openingQty)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Purchase: ${_formatQty(purchaseQty)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Sales: ${_formatQty(salesQty)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Closing: ${_formatQty(closingQty)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemSalesTab extends StatefulWidget {
  const _ItemSalesTab();
  @override
  State<_ItemSalesTab> createState() => _ItemSalesTabState();
}

class _ItemSalesTabState extends State<_ItemSalesTab> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? _error;

  Future<void> _load() async {
    try {
      final r = await Repository.instance
          .itemSalesReport()
          .timeout(const Duration(seconds: 25));
      if (!mounted) return;
      setState(() {
        _rows = r;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = [];
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Loading item sales…'),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _load();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No sales yet.\nComplete a bill in Sales / POS, then open this tab again.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final totalQty = _rows.fold<double>(
      0,
      (sum, r) => sum + ((r['sold_qty'] as num?)?.toDouble() ?? 0),
    );
    final totalAmt = _rows.fold<double>(
      0,
      (sum, r) => sum + ((r['total_amount'] as num?)?.toDouble() ?? 0),
    );

    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total sold: ${_formatNumber(totalQty)}  •  ₹${totalAmt.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await ReportPdf.shareTable(
                    title: 'Item Sales',
                    headers: const ['Item', 'Sold qty', 'Amount'],
                    rows: _rows
                        .map(
                          (r) => [
                            RawMaterial.staffLabelFor(
                              r['item_name']?.toString() ?? '',
                              r['sub_item']?.toString(),
                            ),
                            r['sold_qty']?.toString() ?? '',
                            '₹${r['total_amount']}',
                          ],
                        )
                        .toList(),
                    totalLine:
                        'Total sold ${_formatNumber(totalQty)}  •  Amount ₹${totalAmt.toStringAsFixed(2)}',
                  );
                },
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('Share PDF'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: _rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final r = _rows[i];
                final stock = (r['current_stock'] as num?)?.toDouble();
                final kind = r['sale_kind']?.toString() ?? 'item';
                final kindLabel = kind == 'combo'
                    ? 'Combo bundle'
                    : kind == 'component'
                        ? 'Used in combos'
                        : null;
                final negativeStock =
                    stock != null && stock < -0.000001;
                return ListTile(
                  title: Text(
                    RawMaterial.staffLabelFor(
                      r['item_name']?.toString() ?? '',
                      r['sub_item']?.toString(),
                    ),
                  ),
                  subtitle: Text(
                    [
                      if (kindLabel != null) kindLabel,
                      'Sold ${r['sold_qty']}',
                      if (stock != null)
                        negativeStock
                            ? 'Stock ${_formatNumber(stock)} (negative)'
                            : 'Stock left ${_formatNumber(stock)}',
                    ].join('  •  '),
                    style: negativeStock
                        ? TextStyle(
                            color: Colors.red.shade800,
                            fontWeight: FontWeight.w600,
                          )
                        : null,
                  ),
                  trailing: Text('₹${r['total_amount']}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(double value) {
    if ((value - value.roundToDouble()).abs() < 0.000001) {
      return value.round().toString();
    }
    return value.toStringAsFixed(2);
  }
}

class _SalesReportTab extends StatefulWidget {
  const _SalesReportTab();
  @override
  State<_SalesReportTab> createState() => _SalesReportTabState();
}

class _SalesReportTabState extends State<_SalesReportTab> {
  List<Map<String, dynamic>> _rows = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Repository.instance.salesReport();
    setState(() => _rows = r);
  }

  Future<void> _confirmVoid(Map<String, dynamic> sale) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Void sale #${sale['id']}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This puts the raw materials it used back into stock and marks the sale voided. This cannot be undone.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Reason (optional)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Void Sale'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await Repository.instance.voidSale(
          sale['id'] as int, reasonCtrl.text.trim().isEmpty ? 'Voided by staff' : reasonCtrl.text.trim());
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sale voided — stock restored')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTotal = _rows
        .where((r) => (r['is_voided'] as int? ?? 0) == 0)
        .fold<double>(0, (s, r) => s + (r['total'] as num));
    return ResponsivePage(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Total Sales: ₹${activeTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: _rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = _rows[i];
              final voided = (r['is_voided'] as int? ?? 0) == 1;
              return ListTile(
                title: Text('₹${r['total']}  •  ${r['payment_type']}',
                    style: voided
                        ? const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey)
                        : null),
                subtitle: Text(voided
                    ? 'VOIDED — ${r['voided_reason'] ?? ''}'
                    : (r['sale_date'] as String)),
                trailing: voided
                    ? const Icon(Icons.block, color: Colors.grey)
                    : TextButton(
                  onPressed: () => _confirmVoid(r),
                  child: const Text('Void'),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _ReportDateRangeBar extends StatelessWidget {
  const _ReportDateRangeBar({
    required this.from,
    required this.to,
    required this.onFromChanged,
    required this.onToChanged,
    required this.onToday,
    required this.onThisWeek,
    required this.onThisMonth,
  });

  final DateTime from;
  final DateTime to;
  final VoidCallback onFromChanged;
  final VoidCallback onToChanged;
  final VoidCallback onToday;
  final VoidCallback onThisWeek;
  final VoidCallback onThisMonth;

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today, size: 16),
          label: Text('From ${_formatDate(from)}'),
          onPressed: onFromChanged,
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today, size: 16),
          label: Text('To ${_formatDate(to)}'),
          onPressed: onToChanged,
        ),
        TextButton(onPressed: onToday, child: const Text('Today')),
        TextButton(onPressed: onThisWeek, child: const Text('This week')),
        TextButton(onPressed: onThisMonth, child: const Text('This month')),
      ],
    );
  }
}

class _BillSummaryRow extends StatelessWidget {
  const _BillSummaryRow({
    required this.billLabel,
    required this.dateLabel,
    required this.amountLabel,
    required this.selected,
    required this.onTap,
  });

  final String billLabel;
  final String dateLabel;
  final String amountLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colorScheme.primaryContainer.withValues(alpha: 0.35) : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Text(
                billLabel,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  dateLabel,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
              Text(
                amountLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BillLineRow extends StatelessWidget {
  const _BillLineRow({
    required this.title,
    required this.detail,
  });

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            detail,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _BillWiseSalesTab extends StatefulWidget {
  const _BillWiseSalesTab();
  @override
  State<_BillWiseSalesTab> createState() => _BillWiseSalesTabState();
}

class _BillWiseSalesTabState extends State<_BillWiseSalesTab> {
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  List<Map<String, dynamic>> _bills = [];
  Map<String, dynamic>? _selected;
  List<Map<String, dynamic>> _lines = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  Future<void> _loadBills() async {
    setState(() => _loading = true);
    final bills = await Repository.instance.salesReport(
      from: _from,
      to: _to,
      includeVoided: false,
    );
    if (!mounted) return;
    setState(() {
      _bills = bills;
      _loading = false;
      if (_selected != null) {
        final id = _selected!['id'];
        _selected = bills.cast<Map<String, dynamic>?>().firstWhere(
              (bill) => bill?['id'] == id,
              orElse: () => null,
            );
      }
      if (_selected != null) {
        _loadLines(_selected!['id'] as int);
      } else {
        _lines = [];
      }
    });
  }

  Future<void> _loadLines(int saleId) async {
    final lines = await Repository.instance.saleItems(saleId);
    if (!mounted) return;
    setState(() => _lines = lines);
  }

  void _selectBill(Map<String, dynamic> bill) {
    setState(() => _selected = bill);
    _loadLines(bill['id'] as int);
  }

  String _formatBillDate(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.length >= 10) return text.substring(0, 10);
    return text;
  }

  String _formatQty(num? value) {
    final number = value?.toDouble() ?? 0;
    if ((number - number.roundToDouble()).abs() < 0.000001) {
      return number.round().toString();
    }
    return number.toStringAsFixed(2);
  }

  double get _rangeTotal {
    return _bills.fold<double>(
      0,
      (sum, bill) => sum + ((bill['total'] as num?)?.toDouble() ?? 0),
    );
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: _to,
    );
    if (picked == null) return;
    setState(() {
      _from = picked;
      if (_to.isBefore(_from)) _to = _from;
      _selected = null;
      _lines = [];
    });
    await _loadBills();
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: _from,
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _to = picked;
      if (_from.isAfter(_to)) _from = _to;
      _selected = null;
      _lines = [];
    });
    await _loadBills();
  }

  void _setToday() {
    final today = DateTime.now();
    setState(() {
      _from = today;
      _to = today;
      _selected = null;
      _lines = [];
    });
    _loadBills();
  }

  void _setThisWeek() {
    final today = DateTime.now();
    final start = today.subtract(Duration(days: today.weekday - 1));
    setState(() {
      _from = start;
      _to = today;
      _selected = null;
      _lines = [];
    });
    _loadBills();
  }

  void _setThisMonth() {
    final today = DateTime.now();
    setState(() {
      _from = DateTime(today.year, today.month, 1);
      _to = today;
      _selected = null;
      _lines = [];
    });
    _loadBills();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ResponsivePage(
      maxWidth: 1200,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'BILL-WISE REPORT',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                _ReportDateRangeBar(
                  from: _from,
                  to: _to,
                  onFromChanged: _pickFromDate,
                  onToChanged: _pickToDate,
                  onToday: _setToday,
                  onThisWeek: _setThisWeek,
                  onThisMonth: _setThisMonth,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _bills.isEmpty
                      ? const Center(child: Text('No sales in this date range'))
                      : ListView.separated(
                          itemCount: _bills.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final bill = _bills[index];
                            final selected =
                                _selected?['id'] == bill['id'];
                            return _BillSummaryRow(
                              billLabel: 'Bill #${bill['id']}',
                              dateLabel: _formatBillDate(bill['sale_date']),
                              amountLabel:
                                  '₹${(bill['total'] as num).toStringAsFixed(2)}',
                              selected: selected,
                              onTap: () => _selectBill(bill),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_bills.length} bill(s) in range',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        Text(
                          'Total ₹${_rangeTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            flex: 6,
            child: _selected == null
                ? const Center(
                    child: Text('Select a bill to see line items'),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Bill #${_selected!['id']} — ${_formatBillDate(_selected!['sale_date'])}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Total ₹${(_selected!['total'] as num).toStringAsFixed(2)}',
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _lines.isEmpty
                            ? const Center(child: Text('No line items'))
                            : ListView.separated(
                                itemCount: _lines.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final line = _lines[index];
                                  final qty = (line['qty'] as num?)?.toDouble() ?? 0;
                                  final amount =
                                      (line['amount'] as num?)?.toDouble() ?? 0;
                                  return _BillLineRow(
                                    title: RawMaterial.staffLabelFor(
                                      line['item_name']?.toString() ?? '',
                                      line['sub_item']?.toString(),
                                    ),
                                    detail:
                                        'Qty ${_formatQty(qty)}  •  ₹${amount.toStringAsFixed(2)}',
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _DayEndTab extends StatefulWidget {
  const _DayEndTab();
  @override
  State<_DayEndTab> createState() => _DayEndTabState();
}

class _DayEndTabState extends State<_DayEndTab> {
  DateTime _date = DateTime.now();
  Map<String, dynamic>? _report;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Repository.instance.dayEndReport(_date);
    setState(() => _report = r);
  }

  @override
  Widget build(BuildContext context) {
    final byPayment = (_report?['by_payment'] as List<Map<String, dynamic>>?) ?? [];
    final grandTotal = (_report?['grand_total'] as num?)?.toDouble() ?? 0;
    final voidedCount = (_report?['voided_count'] as int?) ?? 0;
    final voidedTotal = (_report?['voided_total'] as num?)?.toDouble() ?? 0;
    return ResponsivePage(
      maxWidth: 500,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Cash-up / shift close for a single day. Match the Cash row against what\'s actually in the drawer.',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text('${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
                onPressed: () async {
                  final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime.now().subtract(const Duration(days: 730)),
                      lastDate: DateTime.now());
                  if (picked != null) {
                    setState(() => _date = picked);
                    _load();
                  }
                },
              ),
            ),
          ]),
          const SizedBox(height: 16),
          if (_report == null)
            const Center(child: CircularProgressIndicator())
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...byPayment.map((p) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${(p['payment_type'] as String).toUpperCase()}  (${p['cnt']} sales)'),
                          Text('₹${(p['total'] as num).toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    )),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Grand Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('₹${grandTotal.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    if (voidedCount > 0) ...[
                      const SizedBox(height: 8),
                      Text('$voidedCount voided sale(s) worth ₹${voidedTotal.toStringAsFixed(2)} excluded above',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PurchaseBillsTab extends StatefulWidget {
  const _PurchaseBillsTab();
  @override
  State<_PurchaseBillsTab> createState() => _PurchaseBillsTabState();
}

class _PurchaseBillsTabState extends State<_PurchaseBillsTab> {
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  List<Map<String, dynamic>> _bills = [];
  Map<String, dynamic>? _selected;
  List<Map<String, dynamic>> _lines = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  Future<void> _loadBills() async {
    setState(() => _loading = true);
    final bills = await Repository.instance.purchases(
      from: _from,
      to: _to,
    );
    if (!mounted) return;
    setState(() {
      _bills = bills;
      _loading = false;
      if (_selected != null) {
        final id = _selected!['id'];
        _selected = bills.cast<Map<String, dynamic>?>().firstWhere(
              (bill) => bill?['id'] == id,
              orElse: () => null,
            );
      }
      if (_selected != null) {
        _loadLines(_selected!['id'] as int);
      } else {
        _lines = [];
      }
    });
  }

  Future<void> _loadLines(int purchaseId) async {
    final lines = await Repository.instance.purchaseItems(purchaseId);
    if (!mounted) return;
    setState(() => _lines = lines);
  }

  void _selectBill(Map<String, dynamic> bill) {
    setState(() => _selected = bill);
    _loadLines(bill['id'] as int);
  }

  String _formatBillDate(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.length >= 10) return text.substring(0, 10);
    return text;
  }

  String _formatQty(num? value) {
    final number = value?.toDouble() ?? 0;
    if ((number - number.roundToDouble()).abs() < 0.000001) {
      return number.round().toString();
    }
    return number.toStringAsFixed(2);
  }

  double get _rangeTotal {
    return _bills.fold<double>(
      0,
      (sum, bill) => sum + ((bill['total_amount'] as num?)?.toDouble() ?? 0),
    );
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: _to,
    );
    if (picked == null) return;
    setState(() {
      _from = picked;
      if (_to.isBefore(_from)) _to = _from;
      _selected = null;
      _lines = [];
    });
    await _loadBills();
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: _from,
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _to = picked;
      if (_from.isAfter(_to)) _from = _to;
      _selected = null;
      _lines = [];
    });
    await _loadBills();
  }

  void _setToday() {
    final today = DateTime.now();
    setState(() {
      _from = today;
      _to = today;
      _selected = null;
      _lines = [];
    });
    _loadBills();
  }

  void _setThisWeek() {
    final today = DateTime.now();
    final start = today.subtract(Duration(days: today.weekday - 1));
    setState(() {
      _from = start;
      _to = today;
      _selected = null;
      _lines = [];
    });
    _loadBills();
  }

  void _setThisMonth() {
    final today = DateTime.now();
    setState(() {
      _from = DateTime(today.year, today.month, 1);
      _to = today;
      _selected = null;
      _lines = [];
    });
    _loadBills();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ResponsivePage(
      maxWidth: 1200,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'BILL-WISE PURCHASE REPORT',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                _ReportDateRangeBar(
                  from: _from,
                  to: _to,
                  onFromChanged: _pickFromDate,
                  onToChanged: _pickToDate,
                  onToday: _setToday,
                  onThisWeek: _setThisWeek,
                  onThisMonth: _setThisMonth,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _bills.isEmpty
                      ? const Center(
                          child: Text('No purchases in this date range'),
                        )
                      : ListView.separated(
                          itemCount: _bills.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final bill = _bills[index];
                            final selected = _selected?['id'] == bill['id'];
                            return _BillSummaryRow(
                              billLabel: 'Bill #${bill['id']}',
                              dateLabel: _formatBillDate(bill['purchase_date']),
                              amountLabel:
                                  '₹${(bill['total_amount'] as num).toStringAsFixed(2)}',
                              selected: selected,
                              onTap: () => _selectBill(bill),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_bills.length} bill(s) in range',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        Text(
                          'Total ₹${_rangeTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            flex: 6,
            child: _selected == null
                ? const Center(
                    child: Text('Select a bill to see purchased items'),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Bill #${_selected!['id']} — ${_formatBillDate(_selected!['purchase_date'])}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Total ₹${(_selected!['total_amount'] as num).toStringAsFixed(2)}',
                      ),
                      if (_selected!['supplier_name'] != null)
                        Text(
                          'Supplier: ${_selected!['supplier_name']}',
                        ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _lines.isEmpty
                            ? const Center(child: Text('No line items'))
                            : ListView.separated(
                                itemCount: _lines.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final line = _lines[index];
                                  final qty =
                                      (line['qty'] as num?)?.toDouble() ?? 0;
                                  final rate =
                                      (line['rate'] as num?)?.toDouble() ?? 0;
                                  final amount =
                                      (line['amount'] as num?)?.toDouble() ??
                                          qty * rate;
                                  return _BillLineRow(
                                    title: RawMaterial.staffLabelFor(
                                      line['material_name']?.toString() ??
                                          '',
                                      line['material_sub_item']?.toString(),
                                    ),
                                    detail:
                                        'Qty ${_formatQty(qty)} ${line['unit'] ?? ''}  •  ₹${amount.toStringAsFixed(2)}',
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _TopSellingTab extends StatefulWidget {
  const _TopSellingTab();
  @override
  State<_TopSellingTab> createState() => _TopSellingTabState();
}

class _TopSellingTabState extends State<_TopSellingTab> {
  List<Map<String, dynamic>> _rows = [];
  @override
  void initState() {
    super.initState();
    Repository.instance.topSellingItems().then((r) => setState(() => _rows = r));
  }

  @override
  Widget build(BuildContext context) {
    if (_rows.isEmpty) return const Center(child: Text('No sales yet'));
    return ResponsivePage(
      child: SizedBox(
        height: 320,
        child: BarChart(
          BarChartData(
            barGroups: [
              for (int i = 0; i < _rows.length; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(toY: (_rows[i]['total_qty'] as num).toDouble(), width: 18)
                ]),
            ],
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, meta) {
                    final idx = v.toInt();
                    if (idx < 0 || idx >= _rows.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        RawMaterial.staffLabelFor(
                          _rows[idx]['item_name']?.toString() ?? '',
                          _rows[idx]['sub_item']?.toString(),
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 9),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}