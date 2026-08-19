import 'package:flutter/material.dart';
import 'package:foodstock/model/models.dart';
import '../services/repository.dart';
import '../widgets/responsive_shell.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  List<Customer> _customers = [];
  Customer? _selected;
  List<Map<String, dynamic>> _ledger = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await Repository.instance.customers();
    setState(() {
      _customers = c;
      _selected ??= c.isNotEmpty ? c.first : null;
    });
    if (_selected != null) _loadLedger();
  }

  Future<void> _loadLedger() async {
    final l = await Repository.instance.customerLedger(_selected!.id!);
    setState(() => _ledger = l);
  }

  double get _balance => _ledger.isEmpty ? 0 : (_ledger.first['balance_after'] as num).toDouble();

  Future<void> _addCustomer() async {
    final saved = await showDialog<bool>(context: context, builder: (_) => const _CustomerDialog());
    if (saved == true) _load();
  }

  Future<void> _recordPayment() async {
    if (_selected == null) return;
    final ctrl = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Record Payment'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Amount received'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, double.tryParse(ctrl.text) ?? 0),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (amount != null && amount > 0) {
      await Repository.instance.recordCustomerPayment(_selected!.id!, amount);
      _loadLedger();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < Breakpoints.mobile;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCustomer,
        icon: const Icon(Icons.person_add),
        label: const Text('Customer'),
      ),
      body: ResponsivePage(
        child: Flex(
          direction: isMobile ? Axis.vertical : Axis.horizontal,
          children: [
            SizedBox(
              width: isMobile ? double.infinity : 280,
              height: isMobile ? 220 : null,
              child: ListView.builder(
                itemCount: _customers.length,
                itemBuilder: (context, i) {
                  final c = _customers[i];
                  return ListTile(
                    selected: c.id == _selected?.id,
                    title: Text(c.name),
                    subtitle: Text(c.phone ?? '—'),
                    onTap: () {
                      setState(() => _selected = c);
                      _loadLedger();
                    },
                  );
                },
              ),
            ),
            if (!isMobile) const VerticalDivider(width: 1),
            Expanded(
              child: _selected == null
                  ? const Center(child: Text('No customers yet'))
                  : Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(_selected!.name,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                        Text('Balance: ₹${_balance.toStringAsFixed(2)}',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _balance > 0 ? Colors.red : Colors.green)),
                        const SizedBox(width: 12),
                        OutlinedButton(onPressed: _recordPayment, child: const Text('Record Payment')),
                      ],
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _ledger.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final e = _ledger[i];
                          final amt = (e['amount'] as num).toDouble();
                          return ListTile(
                            dense: true,
                            leading: Icon(amt >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                                color: amt >= 0 ? Colors.red : Colors.green),
                            title: Text(e['type']),
                            subtitle: Text(e['entry_date']),
                            trailing: Text('₹${amt.toStringAsFixed(2)}  (Bal ₹${e['balance_after']})'),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerDialog extends StatefulWidget {
  const _CustomerDialog();
  @override
  State<_CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<_CustomerDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _creditLimit = TextEditingController(text: '0');
  final _opening = TextEditingController(text: '0');

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    await Repository.instance.addCustomer(Customer(
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      creditLimit: double.tryParse(_creditLimit.text) ?? 0,
      openingBalance: double.tryParse(_opening.text) ?? 0,
    ));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Add Customer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
              controller: _creditLimit,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Credit Limit', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _opening,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Opening Balance', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ]),
          ]),
        ),
      ),
    );
  }
}
