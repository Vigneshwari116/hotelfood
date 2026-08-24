import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
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
    _tab = TabController(length: 6, vsync: this);
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
              Tab(text: 'Stock Report'),
              Tab(text: 'Item Sales'),
              Tab(text: 'Sales Report'),
              Tab(text: 'Day End'),
              Tab(text: 'Purchase Report'),
              Tab(text: 'Top Selling'),
            ],
          ),
          Expanded(
            child: TabBarView(controller: _tab, children: const [
              _StockReportTab(),
              _ItemSalesTab(),
              _SalesReportTab(),
              _DayEndTab(),
              _PurchaseReportTab(),
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
    final r = await Repository.instance.currentStockReport();
    setState(() {
      _rows = r;
      _loading = false;
    });
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
      return stock <= reorder;
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
                DataColumn(label: Text('Sub Item')),
                DataColumn(label: Text('Category')),
                DataColumn(label: Text('Stock')),
                DataColumn(label: Text('Unit')),
                DataColumn(label: Text('Value (₹)'), numeric: true),
              ], rows: _rows.map((r) {
                final stock = (r['current_stock'] as num?)?.toDouble() ?? 0;
                final reorder = (r['reorder_level'] as num?)?.toDouble() ?? 0;
                final low = stock <= reorder;
                final value = _rowValue(r);
                final hasPrice = r['cost_price'] != null;

                return DataRow(cells: [
                  DataCell(Text(
                    r['name'] ?? '',
                    style: low ? const TextStyle(color: Colors.red, fontWeight: FontWeight.bold) : null,
                  )),
                  DataCell(Text(r['sub_item']?.toString() ?? '-')),
                  DataCell(Text(r['category'] ?? '-')),
                  DataCell(Text(_formatNumber(stock))),
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

  Future<void> _load() async {
    try {
      final r = await Repository.instance.itemSalesReport();
      if (!mounted) return;
      setState(() {
        _rows = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_rows.isEmpty) {
      return const Center(child: Text('No item sales yet'));
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
                    headers: const ['Item', 'Sub item', 'Sold qty', 'Amount'],
                    rows: _rows
                        .map(
                          (r) => [
                            r['item_name']?.toString() ?? '',
                            (r['sub_item'] as String?)?.trim() ?? '',
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
                final sub = (r['sub_item'] as String?)?.trim();
                final stock = (r['current_stock'] as num?)?.toDouble();
                return ListTile(
                  title: Text(r['item_name']?.toString() ?? ''),
                  subtitle: Text(
                    [
                      if (sub != null && sub.isNotEmpty) sub,
                      'Sold ${r['sold_qty']}',
                      if (stock != null) 'Stock left ${_formatNumber(stock)}',
                    ].join('  •  '),
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

class _PurchaseReportTab extends StatefulWidget {
  const _PurchaseReportTab();
  @override
  State<_PurchaseReportTab> createState() => _PurchaseReportTabState();
}

class _PurchaseReportTabState extends State<_PurchaseReportTab> {
  List<Map<String, dynamic>> _rows = [];
  @override
  void initState() {
    super.initState();
    Repository.instance.purchaseReport().then((r) => setState(() => _rows = r));
  }

  @override
  Widget build(BuildContext context) {
    final totalAmt = _rows.fold<double>(
      0,
      (sum, r) => sum + ((r['amount'] as num?)?.toDouble() ?? 0),
    );

    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total purchase: ₹${totalAmt.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              FilledButton.icon(
                onPressed: _rows.isEmpty
                    ? null
                    : () async {
                        await ReportPdf.shareTable(
                          title: 'Purchase Report',
                          headers: const [
                            'Date',
                            'Supplier',
                            'Item',
                            'Qty',
                            'Rate',
                            'Amount',
                          ],
                          rows: _rows
                              .map(
                                (r) => [
                                  r['purchase_date']?.toString() ?? '',
                                  r['supplier_name']?.toString() ?? '-',
                                  r['material_name']?.toString() ?? '',
                                  r['qty']?.toString() ?? '',
                                  '₹${r['rate']}',
                                  '₹${r['amount']}',
                                ],
                              )
                              .toList(),
                          totalLine:
                              'Total purchase ₹${totalAmt.toStringAsFixed(2)}',
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
                ? const Center(child: Text('No purchases yet'))
                : ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = _rows[i];
                      return ListTile(
                        title: Text(
                          '${r['material_name']}  •  qty ${r['qty']} @ ₹${r['rate']}',
                        ),
                        subtitle: Text(
                          '${r['supplier_name'] ?? '-'}  •  ${r['purchase_date']}',
                        ),
                        trailing: Text('₹${r['amount']}'),
                      );
                    },
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
                        [
                          _rows[idx]['item_name'],
                          if ((_rows[idx]['sub_item'] as String?)
                                  ?.trim()
                                  .isNotEmpty ==
                              true)
                            _rows[idx]['sub_item'],
                        ].join('\n'),
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