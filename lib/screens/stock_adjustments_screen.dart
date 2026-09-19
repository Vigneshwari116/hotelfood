import 'package:flutter/material.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/repository.dart';
import 'package:foodstock/services/sub_item_stock.dart';
import 'package:foodstock/widgets/responsive_shell.dart';

class StockAdjustmentsScreen extends StatefulWidget {
  const StockAdjustmentsScreen({super.key});

  @override
  State<StockAdjustmentsScreen> createState() => _StockAdjustmentsScreenState();
}

class _StockAdjustmentsScreenState extends State<StockAdjustmentsScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();

  List<Map<String, dynamic>> _rows = [];
  List<RawMaterial> _materials = [];

  RawMaterial? _selectedMaterial;
  final TextEditingController _qtyController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final materials = await Repository.instance.rawMaterialsForDisplay(
        includeHidden: true,
      );
      final holders = SubItemStock.deduplicateToCanonicalStockHolders(materials);
      final rows = await Repository.instance.stockAdjustments(
        from: _from,
        to: _to,
      );

      if (!mounted) return;
      setState(() {
        _materials = holders;
        _rows = rows;
        _loading = false;
        if (_selectedMaterial != null &&
            !holders.any((item) => item.id == _selectedMaterial!.id)) {
          _selectedMaterial = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = [];
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2020),
      lastDate: _to,
    );
    if (picked == null) return;
    setState(() => _from = picked);
    await _load();
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: _from,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _to = picked);
    await _load();
  }

  Future<void> _saveAdjustment() async {
    final material = _selectedMaterial;
    if (material?.id == null) {
      _showMessage('Select an item to adjust.', isError: true);
      return;
    }

    final qty = double.tryParse(_qtyController.text.trim());
    if (qty == null || qty == 0) {
      _showMessage('Enter a non-zero adjustment quantity.', isError: true);
      return;
    }

    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      _showMessage('Reason is required.', isError: true);
      return;
    }

    setState(() => _saving = true);

    try {
      await Repository.instance.adjustStock(material!.id!, qty, reason);
      _qtyController.clear();
      _reasonController.clear();
      setState(() => _selectedMaterial = null);
      await _load();
      if (!mounted) return;
      _showMessage('Stock adjustment saved.');
    } on InsufficientStockException catch (e) {
      _showMessage(e.toString(), isError: true);
    } on InvalidInventoryException catch (e) {
      _showMessage(e.toString(), isError: true);
    } catch (e) {
      _showMessage('Failed to save adjustment: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showMessage(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.red.shade700 : null,
      ),
    );
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

  String _formatSignedQty(num? value) {
    final number = value?.toDouble() ?? 0;
    final text = _formatQty(number.abs());
    if (number > 0) return '+$text';
    if (number < 0) return '-$text';
    return text;
  }

  String _itemLabel(Map<String, dynamic> row) {
    return RawMaterial.staffLabelFor(
      row['item_name']?.toString() ?? '',
      row['sub_item']?.toString(),
    );
  }

  String _formatAdjustDate(String? value) {
    if (value == null || value.isEmpty) return '—';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return '${parsed.day.toString().padLeft(2, '0')}/'
        '${parsed.month.toString().padLeft(2, '0')}/'
        '${parsed.year} '
        '${parsed.hour.toString().padLeft(2, '0')}:'
        '${parsed.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < Breakpoints.mobile;

    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Record manual stock corrections. Adjustments update live stock, '
            'Stock Summary closing totals, and appear in this list.',
            style: TextStyle(color: Colors.grey.shade700, height: 1.35),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'New adjustment',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<RawMaterial>(
                    value: _selectedMaterial,
                    decoration: const InputDecoration(
                      labelText: 'Item',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _materials
                        .map(
                          (material) => DropdownMenuItem(
                            value: material,
                            child: Text(material.staffLabel),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _selectedMaterial = value),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _qtyController,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Adjustment qty',
                            hintText: 'Use + to add, − to reduce',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _reasonController,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: 'Reason',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _saveAdjustment,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving...' : 'Save adjustment'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _loading ? null : _pickFromDate,
                icon: const Icon(Icons.date_range_outlined, size: 18),
                label: Text('From ${_formatDate(_from)}'),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : _pickToDate,
                icon: const Icon(Icons.date_range_outlined, size: 18),
                label: Text('To ${_formatDate(_to)}'),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _rows.isEmpty
                        ? const Center(child: Text('No adjustments in this period'))
                        : isMobile
                            ? ListView.separated(
                                itemCount: _rows.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final row = _rows[index];
                                  return Card(
                                    child: ListTile(
                                      title: Text(_itemLabel(row)),
                                      subtitle: Text(
                                        '${_formatAdjustDate(row['adjust_date']?.toString())}\n'
                                        '${row['reason']?.toString().trim().isEmpty ?? true ? '—' : row['reason']}',
                                      ),
                                      trailing: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            _formatSignedQty(row['qty']),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            'Closing ${_formatQty(row['closing_stock'])}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              )
                            : SingleChildScrollView(
                                scrollDirection: Axis.vertical,
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    columns: const [
                                      DataColumn(label: Text('Date')),
                                      DataColumn(label: Text('Item')),
                                      DataColumn(label: Text('Adjustment')),
                                      DataColumn(label: Text('Reason')),
                                      DataColumn(label: Text('Closing stock')),
                                    ],
                                    rows: _rows.map((row) {
                                      final reason =
                                          row['reason']?.toString().trim();
                                      return DataRow(
                                        cells: [
                                          DataCell(Text(
                                            _formatAdjustDate(
                                              row['adjust_date']?.toString(),
                                            ),
                                          )),
                                          DataCell(Text(_itemLabel(row))),
                                          DataCell(Text(
                                            _formatSignedQty(row['qty']),
                                          )),
                                          DataCell(Text(
                                            reason == null || reason.isEmpty
                                                ? '—'
                                                : reason,
                                          )),
                                          DataCell(Text(
                                            _formatQty(row['closing_stock']),
                                          )),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
          ),
        ],
      ),
    );
  }
}
