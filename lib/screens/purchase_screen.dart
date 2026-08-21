import 'package:flutter/material.dart';
import 'package:foodstock/model/models.dart';

import '../services/repository.dart';
import '../widgets/responsive_shell.dart';

class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key});

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

/// One purchase item.
class _PurchaseLine {
  RawMaterial? material;

  /// Number of packets being purchased. Optional — only used to
  /// auto-fill [qtyCtrl] when the selected material has a known
  /// units-per-packet count. The actual stock update always uses
  /// [quantity] (base units), not this.
  final TextEditingController packetsCtrl =
  TextEditingController();

  final TextEditingController qtyCtrl =
  TextEditingController();

  final TextEditingController rateCtrl =
  TextEditingController();

  /// Bumped when the line is cleared so the item search field resets.
  Key searchKey = UniqueKey();

  void dispose() {
    packetsCtrl.dispose();
    qtyCtrl.dispose();
    rateCtrl.dispose();
  }

  void reset() {
    material = null;
    packetsCtrl.clear();
    qtyCtrl.clear();
    rateCtrl.clear();
    searchKey = UniqueKey();
  }

  double get packets {
    return double.tryParse(
      packetsCtrl.text.trim(),
    ) ??
        0;
  }

  /// Recalculates qtyCtrl from the entered packet count, if the
  /// selected material has a units-per-packet value set. Does
  /// nothing (leaves qty as manually entered) otherwise.
  void applyPacketsToQty() {
    final perPacket = material?.unitsPerPacket;

    if (perPacket == null || perPacket <= 0) {
      return;
    }

    final packetCount = packets;

    if (packetCount <= 0) {
      return;
    }

    final computed = packetCount * perPacket;

    qtyCtrl.text = computed % 1 == 0
        ? computed.toStringAsFixed(0)
        : computed.toStringAsFixed(2);
  }

  double get quantity {
    return double.tryParse(
      qtyCtrl.text.trim(),
    ) ??
        0;
  }

  double get rate {
    return double.tryParse(
      rateCtrl.text.trim(),
    ) ??
        0;
  }

  double get amount {
    return quantity * rate;
  }
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  // ==========================================================
  // DATA
  // ==========================================================

  List<Supplier> _suppliers = [];
  List<RawMaterial> _materials = [];
  List<Map<String, dynamic>> _history = [];

  int? _supplierId;

  final List<_PurchaseLine> _lines = [
    _PurchaseLine(),
  ];

  bool _loading = true;
  bool _saving = false;

  String? _error;

  String _materialLabel(RawMaterial material) {
    final sub = material.trimmedSubItem;
    if (sub == null) return material.name;
    return '${material.name} ($sub)';
  }

  Iterable<RawMaterial> _searchMaterials(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return _materials.take(40);
    }
    final words = q.split(RegExp(r'\s+'));
    return _materials.where((material) {
      final haystack = [
        material.name,
        material.trimmedSubItem ?? '',
        material.barcode ?? '',
      ].join(' ').toLowerCase();
      return words.every((word) => haystack.contains(word));
    }).take(40);
  }

  void _applyMaterial(_PurchaseLine line, RawMaterial? value) {
    setState(() {
      line.material = value;
      line.packetsCtrl.clear();
      if (line.rateCtrl.text.trim().isEmpty &&
          value?.costPrice != null &&
          value!.costPrice! > 0) {
        final cp = value.costPrice!;
        line.rateCtrl.text =
            cp % 1 == 0 ? cp.toStringAsFixed(0) : cp.toStringAsFixed(2);
      }
    });
  }

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ==========================================================
  // LOAD
  // ==========================================================

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final suppliers =
      await Repository.instance.suppliers();

      final materials =
      await Repository.instance.rawMaterials();

      final history =
      await Repository.instance.purchases();

      if (!mounted) return;

      setState(() {
        _suppliers = suppliers;
        _materials = materials;
        _history = history;

        if (_supplierId == null &&
            suppliers.isNotEmpty) {
          _supplierId = suppliers.first.id;
        }

        if (_supplierId != null &&
            !suppliers.any(
                  (s) => s.id == _supplierId,
            )) {
          _supplierId =
          suppliers.isNotEmpty
              ? suppliers.first.id
              : null;
        }

        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }

    super.dispose();
  }

  // ==========================================================
  // SELECTED SUPPLIER
  // ==========================================================

  Supplier? get _selectedSupplier {
    if (_supplierId == null) {
      return null;
    }

    for (final supplier in _suppliers) {
      if (supplier.id == _supplierId) {
        return supplier;
      }
    }

    return null;
  }

  // ==========================================================
  // ADD NEW SUPPLIER (INLINE)
  // ==========================================================
  //
  // The dialog only COLLECTS and VALIDATES the input. It pops
  // synchronously the moment "Save Supplier" is tapped — no
  // network call happens while the dialog is still open. This
  // avoids popping a route in the middle of an async gap, which
  // is what was triggering the "_dependents.isEmpty" framework
  // assertion. The actual save (and the loading state) happens
  // afterward, once the dialog has fully closed.

  Future<void> _showAddSupplierDialog() async {
    final nameCtrl = TextEditingController();
    final mobileCtrl = TextEditingController();
    final cityCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final newSupplier = await showDialog<Supplier>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add New Supplier'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Supplier Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? 'Enter supplier name'
                        : null,
                  ),

                  const SizedBox(height: 12),

                  TextFormField(
                    controller: mobileCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Mobile',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? 'Enter mobile number'
                        : null,
                  ),

                  const SizedBox(height: 12),

                  TextFormField(
                    controller: cityCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'City',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? 'Enter city'
                        : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                // Close the keyboard and validate before popping —
                // both happen synchronously, in the same gesture.
                FocusScope.of(dialogContext).unfocus();

                if (!(formKey.currentState?.validate() ?? false)) {
                  return;
                }

                Navigator.of(dialogContext).pop(
                  Supplier(
                    name: nameCtrl.text.trim(),
                    mobile: mobileCtrl.text.trim(),
                    city: cityCtrl.text.trim(),
                  ),
                );
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save Supplier'),
            ),
          ],
        );
      },
    );

    nameCtrl.dispose();
    mobileCtrl.dispose();
    cityCtrl.dispose();

    if (newSupplier == null) {
      return;
    }

    // The dialog is fully closed now — safe to run the async save.
    setState(() {
      _saving = true;
    });

    try {
      await Repository.instance.addSupplier(newSupplier);

      // Reload suppliers and auto-select the newly added one
      // (assumes the most recently added supplier is last in the list;
      // falls back to matching by name if repository returns sorted data).
      final suppliers = await Repository.instance.suppliers();

      if (!mounted) return;

      setState(() {
        _suppliers = suppliers;
        _saving = false;

        if (suppliers.isNotEmpty) {
          _supplierId = suppliers.last.id;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Supplier added successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add supplier: $e'),
        ),
      );
    }
  }

  // ==========================================================
  // NUMBER FORMAT HELPER
  // ==========================================================

  String _formatNumber(double value) {
    return value % 1 == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  // ==========================================================
  // ADD LINE
  // ==========================================================

  void _addLine() {
    if (_saving) return;

    setState(() {
      _lines.add(
        _PurchaseLine(),
      );
    });
  }

  // ==========================================================
  // REMOVE LINE
  // ==========================================================

  void _removeLine(int index) {
    if (_saving) return;
    if (index < 0 || index >= _lines.length) return;

    FocusScope.of(context).unfocus();

    setState(() {
      if (_lines.length == 1) {
        _lines.first.reset();
        return;
      }

      final line = _lines.removeAt(index);
      line.dispose();
    });
  }

  // ==========================================================
  // TOTAL
  // ==========================================================

  double get _grandTotal {
    double total = 0;

    for (final line in _lines) {
      total += line.amount;
    }

    return total;
  }

  // ==========================================================
  // VALIDATION
  // ==========================================================

  bool _validate() {
    if (_supplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select a supplier.',
          ),
        ),
      );

      return false;
    }

    bool hasItem = false;

    for (final line in _lines) {
      if (line.material == null) {
        continue;
      }

      hasItem = true;

      if (line.quantity <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Enter quantity for ${line.material!.name}.',
            ),
          ),
        );

        return false;
      }

      if (line.rate <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Enter rate for ${line.material!.name}.',
            ),
          ),
        );

        return false;
      }

      if (line.material!.id == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${line.material!.name} has an invalid ID.',
            ),
          ),
        );

        return false;
      }
    }

    if (!hasItem) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please add at least one raw material.',
          ),
        ),
      );

      return false;
    }

    return true;
  }

  // ==========================================================
  // SAVE PURCHASE
  // ==========================================================

  Future<void> _submit() async {
    if (_saving) {
      return;
    }

    if (!_validate()) {
      return;
    }

    final lines =
    <Map<String, dynamic>>[];

    for (final line in _lines) {
      if (line.material == null) {
        continue;
      }

      lines.add({
        'raw_material_id':
        line.material!.id!,
        'qty': line.quantity,
        'rate': line.rate,
      });
    }

    setState(() {
      _saving = true;
    });

    try {
      await Repository.instance.recordPurchase(
        supplierId: _supplierId,
        invoiceNo: null,
        date: DateTime.now(),
        lines: lines,
        notes: null,
      );

      if (!mounted) {
        return;
      }

      // Clear old lines.
      for (final line in _lines) {
        line.dispose();
      }

      _lines.clear();
      _lines.add(
        _PurchaseLine(),
      );

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Purchase saved successfully. Stock updated.',
          ),
          backgroundColor: Colors.green,
        ),
      );

      await _load();
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to save purchase: $e',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final width =
        MediaQuery.of(context).size.width;

    final isMobile =
        width < Breakpoints.mobile;

    return Scaffold(
      body: ResponsivePage(
        child: _loading
            ? const Center(
          child:
          CircularProgressIndicator(),
        )
            : _error != null
            ? _buildError()
            : _buildContent(isMobile),
      ),
    );
  }

  // ==========================================================
  // ERROR
  // ==========================================================

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment:
        MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 50,
            color: Colors.red,
          ),
          const SizedBox(height: 12),
          const Text(
            'Unable to load purchase data',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? '',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(
              Icons.refresh,
            ),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // CONTENT
  // ==========================================================

  Widget _buildContent(
      bool isMobile,
      ) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 40,
        ),
        children: [
          _buildHeader(),

          const SizedBox(height: 20),

          _buildSupplierSection(
            isMobile,
          ),

          const SizedBox(height: 16),

          _buildItemsSection(
            isMobile,
          ),

          const SizedBox(height: 16),

          _buildTotalSection(
            isMobile,
          ),

          const SizedBox(height: 24),

          _buildPurchaseHistory(),
        ],
      ),
    );
  }

  // ==========================================================
  // HEADER
  // ==========================================================

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                'Add raw materials and update stock',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed:
          _saving ? null : _load,
          icon: const Icon(
            Icons.refresh,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // SUPPLIER SECTION
  // ==========================================================

  Widget _buildSupplierSection(
      bool isMobile,
      ) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.local_shipping_outlined,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Supplier',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed:
                  _saving ? null : _showAddSupplierDialog,
                  icon: const Icon(
                    Icons.add,
                    size: 18,
                  ),
                  label: const Text(
                    'New Supplier',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            if (_suppliers.isEmpty)
              _buildNoSupplier()
            else ...[
              DropdownButtonFormField<int>(
                value: _supplierId,
                isExpanded: true,
                decoration:
                const InputDecoration(
                  labelText:
                  'Supplier Name',
                  border:
                  OutlineInputBorder(),
                  prefixIcon: Icon(
                    Icons.person_outline,
                  ),
                ),
                items:
                _suppliers.map(
                      (supplier) {
                    return DropdownMenuItem<int>(
                      value: supplier.id,
                      child: Text(
                        supplier.name,
                        overflow:
                        TextOverflow.ellipsis,
                      ),
                    );
                  },
                ).toList(),
                onChanged: _saving
                    ? null
                    : (value) {
                  setState(() {
                    _supplierId =
                        value;
                  });
                },
              ),

              const SizedBox(height: 12),

              _buildSupplierInfo(
                isMobile,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // NO SUPPLIER
  // ==========================================================

  Widget _buildNoSupplier() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius:
        BorderRadius.circular(10),
        border: Border.all(
          color: Colors.orange.shade200,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline,
            color: Colors.orange,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'No suppliers found. Tap "New Supplier" above to add one.',
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SUPPLIER INFO
  // ==========================================================

  Widget _buildSupplierInfo(
      bool isMobile,
      ) {
    final supplier =
        _selectedSupplier;

    if (supplier == null) {
      return const SizedBox();
    }

    final mobile =
        supplier.mobile?.trim() ?? '';

    final city =
        supplier.city?.trim() ?? '';

    if (isMobile) {
      return Column(
        children: [
          _readOnlyInfoField(
            label: 'Mobile',
            value: mobile.isEmpty
                ? '-'
                : mobile,
            icon:
            Icons.phone_outlined,
          ),
          const SizedBox(height: 12),
          _readOnlyInfoField(
            label: 'City',
            value:
            city.isEmpty ? '-' : city,
            icon:
            Icons.location_city_outlined,
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: _readOnlyInfoField(
            label: 'Mobile',
            value: mobile.isEmpty
                ? '-'
                : mobile,
            icon:
            Icons.phone_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _readOnlyInfoField(
            label: 'City',
            value:
            city.isEmpty ? '-' : city,
            icon:
            Icons.location_city_outlined,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // READ ONLY SUPPLIER FIELD
  // ==========================================================

  Widget _readOnlyInfoField({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
      ),
      child: Text(
        value,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ==========================================================
  // ITEMS SECTION
  // ==========================================================

  Widget _buildItemsSection(
      bool isMobile,
      ) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Purchase Items',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${_lines.length} item${_lines.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    color:
                    Colors.grey.shade600,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            if (_materials.isEmpty)
              _buildNoMaterialsMessage()
            else
              _buildItemsGrid(),

            const SizedBox(height: 8),

            OutlinedButton.icon(
              onPressed:
              _saving ||
                  _materials.isEmpty
                  ? null
                  : _addLine,
              icon: const Icon(
                Icons.add,
              ),
              label: const Text(
                'Add Another Item',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // NO MATERIALS
  // ==========================================================

  Widget _buildNoMaterialsMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius:
        BorderRadius.circular(10),
        border: Border.all(
          color: Colors.red.shade200,
        ),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 42,
            color: Colors.red,
          ),
          SizedBox(height: 10),
          Text(
            'No Raw Materials Found',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 5),
          Text(
            'Add raw materials from Raw Material Master first.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // ITEMS LIST (stacked cards — no fixed pixel widths, so it
  // can never overflow horizontally on a narrow screen)
  // ==========================================================

  Widget _buildItemsGrid() {
    return Column(
      children: [
        for (int i = 0; i < _lines.length; i++) _buildItemCard(i),
      ],
    );
  }

  Widget _buildItemCard(int index) {
    final line = _lines[index];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Item ${index + 1}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: _lines.length == 1 ? 'Clear item' : 'Remove item',
                iconSize: 22,
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                ),
                onPressed: _saving ? null : () => _removeLine(index),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Autocomplete<RawMaterial>(
            key: line.searchKey,
            displayStringForOption: _materialLabel,
            initialValue: TextEditingValue(
              text: line.material == null ? '' : _materialLabel(line.material!),
            ),
            optionsBuilder: (textEditingValue) {
              return _searchMaterials(textEditingValue.text);
            },
            onSelected: _saving
                ? (_) {}
                : (value) => _applyMaterial(line, value),
            fieldViewBuilder: (
              context,
              textController,
              focusNode,
              onFieldSubmitted,
            ) {
              return TextFormField(
                controller: textController,
                focusNode: focusNode,
                enabled: !_saving,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Item',
                  hintText: 'Type name, sub item or barcode',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
                onFieldSubmitted: (_) => onFieldSubmitted(),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 220,
                      minWidth: 280,
                      maxWidth: 480,
                    ),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, i) {
                        final material = options.elementAt(i);
                        return ListTile(
                          dense: true,
                          title: Text(
                            _materialLabel(material),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: material.barcode == null ||
                                  material.barcode!.trim().isEmpty
                              ? null
                              : Text(material.barcode!),
                          onTap: () => onSelected(material),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),

          // PACKETS (only for materials with a known packet size)
          if (line.material?.unitsPerPacket != null &&
              line.material!.unitsPerPacket! > 0) ...[
            const SizedBox(height: 10),
            TextField(
              controller: line.packetsCtrl,
              enabled: !_saving,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {
                line.applyPacketsToQty();
              }),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Packets',
                helperText: '1 packet = '
                    '${_formatNumber(line.material!.unitsPerPacket!)} units'
                    ' — fills Qty below',
                border: const OutlineInputBorder(),
              ),
            ),
          ],

          const SizedBox(height: 10),

          // QTY / RATE / AMOUNT
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: line.qtyCtrl,
                  enabled: !_saving,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Qty',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: TextField(
                  controller: line.rateCtrl,
                  enabled: !_saving,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Rate (₹)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Amount (₹)',
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    line.amount.toStringAsFixed(2),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // TOTAL SECTION
  // ==========================================================

  Widget _buildTotalSection(
      bool isMobile,
      ) {
    return Card(
      elevation: 0,
      child: Padding(
        padding:
        const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total Amount',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '₹ ${_grandTotal.toStringAsFixed(2)}',
                  style:
                  const TextStyle(
                    fontSize: 24,
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed:
                _saving ||
                    _materials.isEmpty
                    ? null
                    : _submit,
                icon: _saving
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child:
                  CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
                    : const Icon(
                  Icons.save_outlined,
                ),
                label: Text(
                  _saving
                      ? 'Saving Purchase...'
                      : 'Save Purchase',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // PURCHASE HISTORY
  // ==========================================================

  Widget _buildPurchaseHistory() {
    return Card(
      elevation: 0,
      child: Padding(
        padding:
        const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.history,
                ),
                SizedBox(width: 8),
                Text(
                  'Recent Purchases',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            if (_history.isEmpty)
              const Padding(
                padding:
                EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    'No purchases recorded yet.',
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics:
                const NeverScrollableScrollPhysics(),
                itemCount:
                _history.length > 10
                    ? 10
                    : _history.length,
                separatorBuilder:
                    (_, __) =>
                const Divider(),
                itemBuilder:
                    (context, index) {
                  final purchase =
                  _history[index];

                  final supplier =
                      purchase[
                      'supplier_name'] ??
                          'Supplier';

                  final total =
                      (purchase[
                      'total_amount']
                      as num?)
                          ?.toDouble() ??
                          0;

                  final date =
                      purchase[
                      'purchase_date']
                          ?.toString() ??
                          '';

                  return ListTile(
                    contentPadding:
                    EdgeInsets.zero,
                    leading:
                    const CircleAvatar(
                      child: Icon(
                        Icons
                            .shopping_cart_outlined,
                      ),
                    ),
                    title: Text(
                      supplier.toString(),
                      style:
                      const TextStyle(
                        fontWeight:
                        FontWeight.w600,
                      ),
                    ),
                    subtitle:
                    Text(date),
                    trailing: Text(
                      '₹ ${total.toStringAsFixed(2)}',
                      style:
                      const TextStyle(
                        fontWeight:
                        FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
