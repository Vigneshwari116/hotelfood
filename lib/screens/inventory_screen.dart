import 'package:flutter/material.dart';
import 'package:foodstock/model/models.dart';
import '../services/repository.dart';
import '../widgets/responsive_shell.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TabBar(
            controller: _tab,
            isScrollable: MediaQuery.of(context).size.width < Breakpoints.mobile,
            tabs: const [
              Tab(text: 'Current Stock'),
              Tab(text: 'Stock Ledger'),
              Tab(text: 'Stock Adjustment'),
              Tab(text: 'Expiry / Shelf Life'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: const [
                _CurrentStockTab(),
                _StockLedgerTab(),
                _StockAdjustmentTab(),
                _ExpiryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentStockTab extends StatefulWidget {
  const _CurrentStockTab();
  @override
  State<_CurrentStockTab> createState() => _CurrentStockTabState();
}

class _CurrentStockTabState extends State<_CurrentStockTab> {
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Repository.instance.currentStockReport();
    setState(() => _rows = r);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < Breakpoints.mobile;
    return ResponsivePage(
      child: _rows.isEmpty
          ? const Center(child: Text('No stock data yet'))
          : SingleChildScrollView(
        scrollDirection: isMobile ? Axis.horizontal : Axis.vertical,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Item')),
            DataColumn(label: Text('Category')),
            DataColumn(label: Text('Unit')),
            DataColumn(label: Text('Current Stock')),
            DataColumn(label: Text('Reorder Level')),
            DataColumn(label: Text('Status')),
          ],
          rows: _rows.map((r) {
            final cur = (r['current_stock'] as num).toDouble();
            final reorder = (r['reorder_level'] as num).toDouble();
            final negative = cur < -0.000001;
            final low = !negative && cur <= reorder;
            final statusLabel = negative ? 'Negative' : low ? 'Low' : 'OK';
            final statusColor = negative
                ? Colors.red.shade200
                : low
                    ? Colors.red.shade100
                    : Colors.green.shade100;
            return DataRow(cells: [
              DataCell(Text(r['name'])),
              DataCell(Text(r['category'] ?? '-')),
              DataCell(Text(r['unit'] ?? '-')),
              DataCell(Text(
                cur.toStringAsFixed(2),
                style: negative
                    ? const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      )
                    : null,
              )),
              DataCell(Text(reorder.toStringAsFixed(2))),
              DataCell(Chip(
                label: Text(statusLabel),
                backgroundColor: statusColor,
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

class _StockLedgerTab extends StatefulWidget {
  const _StockLedgerTab();
  @override
  State<_StockLedgerTab> createState() => _StockLedgerTabState();
}

class _StockLedgerTabState extends State<_StockLedgerTab> {
  List<RawMaterial> _materials = [];
  RawMaterial? _selected;
  List<Map<String, dynamic>> _ledger = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await Repository.instance.rawMaterials();
    setState(() {
      _materials = m;
      _selected ??= m.isNotEmpty ? m.first : null;
    });
    if (_selected != null) _loadLedger();
  }

  Future<void> _loadLedger() async {
    final l = await Repository.instance.stockLedger(_selected!.id!);
    setState(() => _ledger = l);
  }

  @override
  Widget build(BuildContext context) {
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<RawMaterial>(
            value: _selected,
            decoration: const InputDecoration(labelText: 'Select item', border: OutlineInputBorder()),
            items: _materials.map((m) => DropdownMenuItem(value: m, child: Text(m.name))).toList(),
            onChanged: (v) {
              setState(() => _selected = v);
              _loadLedger();
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _ledger.isEmpty
                ? const Center(child: Text('No movement recorded'))
                : ListView.separated(
              itemCount: _ledger.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final e = _ledger[i];
                final isIn = (e['qty_in'] as num) > 0;
                return ListTile(
                  leading: Icon(isIn ? Icons.arrow_downward : Icons.arrow_upward,
                      color: isIn ? Colors.green : Colors.red),
                  title: Text('${e['ref_type']}  •  ${isIn ? '+${e['qty_in']}' : '-${e['qty_out']}'}'),
                  subtitle: Text(e['entry_date']),
                  trailing: Text('Bal: ${e['balance_after']}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StockAdjustmentTab extends StatefulWidget {
  const _StockAdjustmentTab();
  @override
  State<_StockAdjustmentTab> createState() => _StockAdjustmentTabState();
}

class _StockAdjustmentTabState extends State<_StockAdjustmentTab> {
  List<RawMaterial> _materials = [];
  RawMaterial? _selected;
  final _qtyCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  String _direction = 'reduce'; // add | reduce (damage/loss/correction)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await Repository.instance.rawMaterials();
    setState(() {
      _materials = m;
      _selected ??= m.isNotEmpty ? m.first : null;
    });
  }

  Future<void> _submit() async {
    if (_selected == null) return;
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    if (qty <= 0) return;
    final delta = _direction == 'add' ? qty : -qty;
    await Repository.instance.adjustStock(_selected!.id!, delta,
        _reasonCtrl.text.trim().isEmpty ? _direction : _reasonCtrl.text.trim());
    _qtyCtrl.clear();
    _reasonCtrl.clear();
    _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stock adjusted')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < Breakpoints.mobile;
    return ResponsivePage(
      maxWidth: 600,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Adjust for damage, loss, wastage, or manual correction.',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          DropdownButtonFormField<RawMaterial>(
            value: _selected,
            decoration: const InputDecoration(labelText: 'Item', border: OutlineInputBorder()),
            items: _materials.map((m) => DropdownMenuItem(value: m, child: Text(m.name))).toList(),
            onChanged: (v) => setState(() => _selected = v),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'add', label: Text('Add'), icon: Icon(Icons.add)),
              ButtonSegment(value: 'reduce', label: Text('Reduce'), icon: Icon(Icons.remove)),
            ],
            selected: {_direction},
            onSelectionChanged: (s) => setState(() => _direction = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _qtyCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonCtrl,
            decoration: const InputDecoration(
                labelText: 'Reason (damage / loss / correction)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _submit, child: const Text('Apply Adjustment')),
        ],
      ),
    );
  }
}

class _ExpiryTab extends StatefulWidget {
  const _ExpiryTab();
  @override
  State<_ExpiryTab> createState() => _ExpiryTabState();
}

class _ExpiryTabState extends State<_ExpiryTab> {
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Repository.instance.expiringBatches(withinDays: 14);
    setState(() => _rows = r);
  }

  bool _isPast(String isoDate) =>
      DateTime.parse(isoDate).isBefore(DateTime.now());

  Future<void> _writeOffExpired() async {
    final writtenOff = await Repository.instance.writeOffExpiredStock();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(writtenOff.isEmpty
            ? 'Nothing already expired — nothing to write off'
            : 'Wrote off ${writtenOff.length} expired batch(es) as wastage')));
  }

  @override
  Widget build(BuildContext context) {
    final anyExpired = _rows.any((r) => _isPast(r['expiry_date']));
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (anyExpired)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                onPressed: _writeOffExpired,
                icon: const Icon(Icons.delete_sweep, color: Colors.red),
                label: const Text('Write off already-expired stock as wastage'),
              ),
            ),
          Expanded(
            child: _rows.isEmpty
                ? const Center(child: Text('Nothing expiring in the next 14 days'))
                : ListView.separated(
              itemCount: _rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final r = _rows[i];
                final expired = _isPast(r['expiry_date']);
                final rate = r['rate'] as num?;
                return ListTile(
                  leading: Icon(
                      expired ? Icons.error : Icons.warning_amber,
                      color: expired ? Colors.red : Colors.orange),
                  title: Text(r['material_name']),
                  subtitle: Text('Batch #${r['id']} · Qty remaining: ${r['qty_remaining']}'
                      '${rate != null ? ' · Cost/unit: ${rate.toStringAsFixed(2)}' : ''}'),
                  trailing: Text(
                    expired ? 'Expired ${r['expiry_date']}' : r['expiry_date'],
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: expired ? Colors.red : null),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
