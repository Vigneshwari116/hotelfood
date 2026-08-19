import 'dart:io';

import 'package:flutter/material.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/repository.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final Repository _repo = Repository.instance;

  final TextEditingController _searchController =
  TextEditingController();

  final TextEditingController _taxController =
  TextEditingController(text: '0');

  final TextEditingController _discountController =
  TextEditingController(text: '0');

  final TextEditingController _barcodeController =
  TextEditingController();

  final ScrollController _cartScrollController =
  ScrollController();

  List<RawMaterial> _materials = [];
  List<Combo> _combos = [];
  List<Customer> _customers = [];

  Map<int, double> _rawStock = {};
  Map<int, double> _comboStock = {};

  bool _showingCombos = false;

  final List<CartLine> _cart = [];

  Customer? _selectedCustomer;

  String _paymentType = 'Cash';

  bool _loading = true;
  bool _saving = false;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    _loadData();

    _searchController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _searchController.dispose();
    _taxController.dispose();
    _discountController.dispose();
    _barcodeController.dispose();
    _cartScrollController.dispose();

    super.dispose();
  }

  // ============================================================
  // LOAD DATA
  // ============================================================

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final materials = await _repo.rawMaterials();
      final combos = await _repo.combosWithItems();
      final customers = await _repo.customers();
      final stock =
      await _repo.maxQuantitiesForRawMaterials();
      final comboStock =
      await _repo.maxQuantitiesForCombos();

      if (!mounted) return;

      setState(() {
        _materials = materials;
        _combos = combos;
        _customers = customers;
        _rawStock = stock;
        _comboStock = comboStock;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      _showError(
        'Failed to load POS data: $e',
      );
    }
  }

  Future<void> _refreshStock() async {
    try {
      final stock =
      await _repo.maxQuantitiesForRawMaterials();
      final comboStock =
      await _repo.maxQuantitiesForCombos();

      if (!mounted) return;

      setState(() {
        _rawStock = stock;
        _comboStock = comboStock;
      });
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Failed to refresh stock: $e',
      );
    }
  }

  // ============================================================
  // SEARCH
  // ============================================================

  String get _search =>
      _searchController.text.trim().toLowerCase();

  List<Combo> get _filteredCombos {
    if (_search.isEmpty) {
      return _combos;
    }

    return _combos.where((combo) {
      final name = combo.name.toLowerCase();
      final barcode = combo.barcode?.toLowerCase() ?? '';

      return name.contains(_search) || barcode.contains(_search);
    }).toList();
  }

  List<RawMaterial> get _filteredMaterials {
    if (_search.isEmpty) {
      return _materials;
    }

    return _materials.where((material) {
      final name =
      material.name.toLowerCase();

      final barcode =
          material.barcode?.toLowerCase() ?? '';

      return name.contains(_search) ||
          barcode.contains(_search);
    }).toList();
  }

  // ============================================================
  // BARCODE
  // ============================================================

  Future<void> _handleBarcode(
      String value,
      ) async {
    final barcode = value.trim();

    if (barcode.isEmpty) {
      return;
    }

    _barcodeController.clear();

    try {
      final material =
      await _repo.rawMaterialByBarcode(
        barcode,
      );

      if (material != null) {
        _addRawMaterial(material);
        return;
      }

      final combo = await _repo.comboByBarcode(barcode);

      if (combo == null) {
        _showError(
          'No item found for barcode "$barcode".',
        );
        return;
      }

      _addCombo(combo);
    } catch (e) {
      _showError(
        'Barcode lookup failed: $e',
      );
    }
  }

  // ============================================================
  // STOCK
  // ============================================================

  double _stockForMaterial(
      RawMaterial material,
      ) {
    if (material.id == null) {
      return material.currentStock;
    }

    return _rawStock[material.id!] ??
        material.currentStock;
  }

  // ============================================================
  // CART HELPERS
  // ============================================================

  int _cartIndexForRaw(
      int id,
      ) {
    return _cart.indexWhere(
          (line) => line.rawMaterialId == id,
    );
  }

  double _cartQtyForRaw(
      int id,
      ) {
    final index =
    _cartIndexForRaw(id);

    if (index == -1) {
      return 0;
    }

    return _cart[index].qty;
  }

  int _cartIndexForCombo(int id) {
    return _cart.indexWhere(
      (line) => line.comboId == id,
    );
  }

  double _cartQtyForCombo(int id) {
    final index = _cartIndexForCombo(id);

    if (index == -1) {
      return 0;
    }

    return _cart[index].qty;
  }

  double _stockForCombo(Combo combo) {
    if (combo.id == null) {
      return 0;
    }

    return _comboStock[combo.id!] ?? 0;
  }

  double _maxQtyForLine(CartLine line) {
    if (line.comboId != null) {
      return _comboStock[line.comboId!] ?? 0;
    }

    if (line.rawMaterialId == null) {
      return 0;
    }

    final materialIndex = _materials.indexWhere(
      (material) => material.id == line.rawMaterialId,
    );

    if (materialIndex == -1) {
      return 0;
    }

    return _stockForMaterial(_materials[materialIndex]);
  }

  // ============================================================
  // ADD COMBO
  // ============================================================

  void _addCombo(Combo combo) {
    if (combo.id == null) {
      return;
    }

    if (!combo.isActive) {
      _showError('${combo.name} is inactive.');
      return;
    }

    final available = _stockForCombo(combo);

    if (available <= 0) {
      _showError('${combo.name} is out of stock.');
      return;
    }

    final index = _cartIndexForCombo(combo.id!);

    if (index == -1) {
      setState(() {
        _cart.add(
          CartLine(
            comboId: combo.id,
            name: combo.name,
            qty: 1,
            price: combo.price,
          ),
        );
      });

      return;
    }

    final currentQty = _cart[index].qty;

    if (currentQty + 1 > available + 0.000001) {
      _showError(
        'Only ${_formatQty(available)} of ${combo.name} is available.',
      );
      return;
    }

    setState(() {
      final old = _cart[index];

      _cart[index] = CartLine(
        comboId: old.comboId,
        name: old.name,
        qty: old.qty + 1,
        price: old.price,
      );
    });
  }

  // ============================================================
  // ADD RAW MATERIAL
  // ============================================================

  void _addRawMaterial(
      RawMaterial material,
      ) {
    if (material.id == null) {
      return;
    }

    final available =
    _stockForMaterial(material);

    if (available <= 0) {
      _showError(
        '${material.name} is out of stock.',
      );
      return;
    }

    final index =
    _cartIndexForRaw(material.id!);

    // ----------------------------------------------------------
    // NEW CART LINE
    // ----------------------------------------------------------

    if (index == -1) {
      setState(() {
        _cart.add(
          CartLine(
            rawMaterialId:
            material.id,
            name: material.name,
            qty: 1,
            price:
            material.sellingPrice ?? 0,
          ),
        );
      });

      return;
    }

    // ----------------------------------------------------------
    // EXISTING CART LINE
    // ----------------------------------------------------------

    final currentQty =
        _cart[index].qty;

    if (currentQty + 1 >
        available + 0.000001) {
      _showError(
        'Only ${_formatQty(available)} '
            '${_unitForMaterial(material)} '
            'of ${material.name} is available.',
      );

      return;
    }

    setState(() {
      final old =
      _cart[index];

      _cart[index] = CartLine(
        rawMaterialId:
        old.rawMaterialId,
        name: old.name,
        qty: old.qty + 1,
        price: old.price,
      );
    });
  }

  // ============================================================
  // CHANGE QUANTITY
  // ============================================================

  void _changeQuantity(
      int index,
      double newQty,
      ) {
    if (index < 0 ||
        index >= _cart.length) {
      return;
    }

    // Remove line.
    if (newQty <= 0) {
      setState(() {
        _cart.removeAt(index);
      });

      return;
    }

    final line =
    _cart[index];

    final maxQty = _maxQtyForLine(line);

    if (newQty >
        maxQty + 0.000001) {
      _showError(
        'Maximum available quantity is '
            '${_formatQty(maxQty)}.',
      );

      return;
    }

    setState(() {
      _cart[index] =
          CartLine(
            rawMaterialId:
            line.rawMaterialId,
            comboId: line.comboId,
            name: line.name,
            qty: newQty,
            price: line.price,
          );
    });
  }

  // ============================================================
  // REMOVE CART LINE
  // ============================================================

  void _removeLine(
      int index,
      ) {
    if (index < 0 ||
        index >= _cart.length) {
      return;
    }

    setState(() {
      _cart.removeAt(index);
    });
  }

  // ============================================================
  // CLEAR CART
  // ============================================================

  void _clearCart() {
    if (_cart.isEmpty) {
      return;
    }

    setState(() {
      _cart.clear();
    });
  }

  // ============================================================
  // TOTALS
  // ============================================================

  double get _subtotal {
    return _cart.fold<double>(
      0,
          (sum, line) =>
      sum + line.amount,
    );
  }

  double get _tax {
    return double.tryParse(
      _taxController.text.trim(),
    ) ??
        0;
  }

  double get _discount {
    return double.tryParse(
      _discountController.text.trim(),
    ) ??
        0;
  }

  double get _total {
    final value =
        _subtotal +
            _tax -
            _discount;

    return value < 0
        ? 0
        : value;
  }

  // ============================================================
  // CHECKOUT
  // ============================================================

  Future<void> _checkout() async {
    if (_cart.isEmpty) {
      _showError(
        'Cart is empty.',
      );
      return;
    }

    final tax = _tax;
    final discount =
        _discount;

    if (tax < 0) {
      _showError(
        'Tax cannot be negative.',
      );
      return;
    }

    if (discount < 0) {
      _showError(
        'Discount cannot be negative.',
      );
      return;
    }

    if (_subtotal +
        tax -
        discount <
        0) {
      _showError(
        'Discount cannot be greater than subtotal plus tax.',
      );
      return;
    }

    if (_paymentType ==
        'Credit' &&
        _selectedCustomer ==
            null) {
      _showError(
        'Select a customer for credit sales.',
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final saleId =
      await _repo.recordSale(
        customerId:
        _selectedCustomer?.id,
        lines:
        List<CartLine>.from(
          _cart,
        ),
        tax: tax,
        discount: discount,
        paymentType:
        _paymentType,
      );

      if (!mounted) return;

      setState(() {
        _cart.clear();
        _saving = false;
      });

      _taxController.text =
      '0';

      _discountController.text =
      '0';

      await _refreshStock();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            'Sale #$saleId completed successfully.',
          ),
          behavior:
          SnackBarBehavior
              .floating,
        ),
      );
    } on InsufficientStockException catch (
    e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      _showError(
        e.toString(),
      );

      await _refreshStock();
    } on InvalidInventoryException catch (
    e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      _showError(
        e.toString(),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      _showError(
        'Unable to complete sale: $e',
      );
    }
  }

  // ============================================================
  // CUSTOMER
  // ============================================================

  Future<void> _selectCustomer() async {
    if (_customers.isEmpty) {
      _showError(
        'No customers found. Add a customer first.',
      );
      return;
    }

    final selected =
    await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled:
      true,
      builder:
          (sheetContext) {
        String query = '';

        return StatefulBuilder(
          builder: (
              context,
              setSheetState,
              ) {
            final filtered =
            _customers.where(
                  (customer) {
                if (query
                    .trim()
                    .isEmpty) {
                  return true;
                }

                final q =
                query
                    .trim()
                    .toLowerCase();

                return customer.name
                    .toLowerCase()
                    .contains(q) ||
                    (customer.phone ??
                        '')
                        .toLowerCase()
                        .contains(q);
              },
            ).toList();

            return SafeArea(
              child: SizedBox(
                height:
                MediaQuery.of(
                  context,
                )
                    .size
                    .height *
                    0.75,
                child: Column(
                  children: [
                    Padding(
                      padding:
                      const EdgeInsets.all(
                        16,
                      ),
                      child:
                      TextField(
                        autofocus:
                        true,
                        decoration:
                        const InputDecoration(
                          labelText:
                          'Search customer',
                          prefixIcon:
                          Icon(
                            Icons
                                .search,
                          ),
                          border:
                          OutlineInputBorder(),
                        ),
                        onChanged:
                            (value) {
                          setSheetState(
                                () {
                              query =
                                  value;
                            },
                          );
                        },
                      ),
                    ),

                    Expanded(
                      child:
                      filtered.isEmpty
                          ? const Center(
                        child:
                        Text(
                          'No customers found',
                        ),
                      )
                          : ListView
                          .builder(
                        itemCount:
                        filtered.length,
                        itemBuilder:
                            (
                            _,
                            index,
                            ) {
                          final customer =
                          filtered[
                          index];

                          return ListTile(
                            leading:
                            const CircleAvatar(
                              child:
                              Icon(
                                Icons
                                    .person,
                              ),
                            ),
                            title:
                            Text(
                              customer
                                  .name,
                            ),
                            subtitle:
                            customer.phone ==
                                null ||
                                customer
                                    .phone!
                                    .isEmpty
                                ? null
                                : Text(
                              customer
                                  .phone!,
                            ),
                            trailing:
                            Text(
                              '₹${customer.openingBalance.toStringAsFixed(2)}',
                            ),
                            onTap:
                                () {
                              Navigator
                                  .pop(
                                context,
                                customer,
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted) return;

    if (selected != null) {
      setState(() {
        _selectedCustomer =
            selected;
      });
    }
  }

  // ============================================================
  // IMAGE
  // ============================================================

  Widget _image(
      String? path, {
        double height = 100,
      }) {
    if (path == null ||
        path.trim().isEmpty) {
      return Container(
        height: height,
        width:
        double.infinity,
        color: Theme.of(
          context,
        )
            .colorScheme
            .surfaceContainerHighest,
        child:
        const Icon(
          Icons
              .image_not_supported_outlined,
          size: 38,
        ),
      );
    }

    final file =
    File(path);

    if (!file.existsSync()) {
      return Container(
        height: height,
        width:
        double.infinity,
        color: Theme.of(
          context,
        )
            .colorScheme
            .surfaceContainerHighest,
        child:
        const Icon(
          Icons
              .broken_image_outlined,
          size: 38,
        ),
      );
    }

    return Image.file(
      file,
      height: height,
      width:
      double.infinity,
      fit: BoxFit.cover,
      errorBuilder:
          (
          _,
          __,
          ___,
          ) {
        return Container(
          height: height,
          width:
          double.infinity,
          color: Theme.of(
            context,
          )
              .colorScheme
              .surfaceContainerHighest,
          child:
          const Icon(
            Icons
                .broken_image_outlined,
            size: 38,
          ),
        );
      },
    );
  }

  // ============================================================
  // MATERIAL CARD
  // ============================================================

  Widget _materialCard(
      RawMaterial material,
      ) {
    final stock =
    _stockForMaterial(
      material,
    );

    final cartQty =
    material.id == null
        ? 0.0
        : _cartQtyForRaw(
      material.id!,
    );

    final availableToAdd =
        stock - cartQty;

    final canAdd =
        availableToAdd >
            0.000001;

    final unit =
    _unitForMaterial(
      material,
    );

    return Card(
      clipBehavior:
      Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: canAdd
            ? () =>
            _addRawMaterial(
              material,
            )
            : null,
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment
              .start,
          children: [
            _image(
              material.imagePath,
              height: 100,
            ),

            Expanded(
              child: Padding(
                padding:
                const EdgeInsets.all(
                  10,
                ),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    Text(
                      material.name,
                      maxLines: 2,
                      overflow:
                      TextOverflow
                          .ellipsis,
                      style:
                      const TextStyle(
                        fontWeight:
                        FontWeight
                            .bold,
                        fontSize: 14,
                      ),
                    ),

                    const SizedBox(
                      height: 5,
                    ),

                    Text(
                      '₹${(material.sellingPrice ?? 0).toStringAsFixed(2)}',
                      style:
                      const TextStyle(
                        fontWeight:
                        FontWeight
                            .w600,
                        fontSize: 14,
                      ),
                    ),

                    const Spacer(),

                    Row(
                      children: [
                        Expanded(
                          child:
                          Text(
                            'Stock: '
                                '${_formatQty(stock)} '
                                '$unit',
                            maxLines:
                            1,
                            overflow:
                            TextOverflow
                                .ellipsis,
                            style:
                            TextStyle(
                              fontSize:
                              12,
                              color: stock <=
                                  material
                                      .reorderLevel
                                  ? Colors
                                  .orange
                                  .shade800
                                  : null,
                            ),
                          ),
                        ),

                        if (cartQty >
                            0)
                          CircleAvatar(
                            radius:
                            11,
                            child:
                            Text(
                              _formatQty(
                                cartQty,
                              ),
                              style:
                              const TextStyle(
                                fontSize:
                                10,
                              ),
                            ),
                          ),
                      ],
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

  // ============================================================
  // CART VIEW
  // ============================================================

  Widget _cartView() {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior:
      Clip.antiAlias,
      child: Column(
        children: [
          // ------------------------------------------------------
          // CART HEADER
          // ------------------------------------------------------

          Padding(
            padding:
            const EdgeInsets.fromLTRB(
              12,
              8,
              8,
              6,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons
                      .shopping_cart_outlined,
                  size: 21,
                ),

                const SizedBox(
                  width: 8,
                ),

                Expanded(
                  child: Text(
                    'Current Sale',
                    style: Theme.of(
                      context,
                    )
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                      fontWeight:
                      FontWeight
                          .bold,
                    ),
                  ),
                ),

                if (_cart
                    .isNotEmpty)
                  TextButton(
                    onPressed:
                    _clearCart,
                    child:
                    const Text(
                      'Clear',
                    ),
                  ),
              ],
            ),
          ),

          const Divider(
            height: 1,
          ),

          // ------------------------------------------------------
          // CART ITEMS
          // ------------------------------------------------------

          Expanded(
            child: _cart.isEmpty
                ? const Center(
              child: Column(
                mainAxisSize:
                MainAxisSize
                    .min,
                children: [
                  Icon(
                    Icons
                        .remove_shopping_cart_outlined,
                    size: 42,
                  ),
                  SizedBox(
                    height: 8,
                  ),
                  Text(
                    'Cart is empty',
                    style:
                    TextStyle(
                      fontWeight:
                      FontWeight
                          .w600,
                    ),
                  ),
                  SizedBox(
                    height: 3,
                  ),
                  Text(
                    'Tap an item to add it',
                  ),
                ],
              ),
            )
                : ListView
                .builder(
              controller:
              _cartScrollController,
              padding:
              const EdgeInsets
                  .symmetric(
                vertical: 4,
              ),
              itemCount:
              _cart.length,
              itemBuilder:
                  (
                  context,
                  index,
                  ) {
                return _cartLine(
                  index,
                  _cart[index],
                );
              },
            ),
          ),

          const Divider(
            height: 1,
          ),

          // ------------------------------------------------------
          // CHECKOUT
          //
          // Constrained instead of fixed height.
          // This prevents the 1px overflow seen in the screenshot.
          // ------------------------------------------------------

          Flexible(
            flex: 0,
            child:
            ConstrainedBox(
              constraints:
              const BoxConstraints(
                maxHeight: 360,
              ),
              child:
              _checkoutPanel(),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CART LINE
  // ============================================================

  Widget _cartLine(
      int index,
      CartLine line,
      ) {
    final maxQty = _maxQtyForLine(line);

    return Padding(
      padding:
      const EdgeInsets
          .symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            child:
            Icon(
              line.comboId != null
                  ? Icons.fastfood_outlined
                  : Icons.inventory_2_outlined,
              size: 17,
            ),
          ),

          const SizedBox(
            width: 8,
          ),

          Expanded(
            child: Column(
              mainAxisSize:
              MainAxisSize
                  .min,
              crossAxisAlignment:
              CrossAxisAlignment
                  .start,
              children: [
                Text(
                  line.name,
                  maxLines: 1,
                  overflow:
                  TextOverflow
                      .ellipsis,
                  style:
                  const TextStyle(
                    fontWeight:
                    FontWeight
                        .w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '₹${line.price.toStringAsFixed(2)} × '
                      '${_formatQty(line.qty)}',
                  style:
                  const TextStyle(
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          IconButton(
            visualDensity:
            VisualDensity
                .compact,
            tooltip:
            'Decrease',
            icon:
            const Icon(
              Icons
                  .remove_circle_outline,
              size: 20,
            ),
            onPressed:
                () {
              _changeQuantity(
                index,
                line.qty - 1,
              );
            },
          ),

          SizedBox(
            width: 30,
            child:
            Text(
              _formatQty(
                line.qty,
              ),
              textAlign:
              TextAlign
                  .center,
              style:
              const TextStyle(
                fontWeight:
                FontWeight
                    .bold,
                fontSize: 13,
              ),
            ),
          ),

          IconButton(
            visualDensity:
            VisualDensity
                .compact,
            tooltip:
            'Increase',
            icon:
            const Icon(
              Icons
                  .add_circle_outline,
              size: 20,
            ),
            onPressed:
            line.qty + 1 <=
                maxQty +
                    0.000001
                ? () {
              _changeQuantity(
                index,
                line.qty +
                    1,
              );
            }
                : null,
          ),

          SizedBox(
            width: 70,
            child:
            Text(
              '₹${line.amount.toStringAsFixed(2)}',
              textAlign:
              TextAlign
                  .right,
              style:
              const TextStyle(
                fontWeight:
                FontWeight
                    .bold,
                fontSize: 13,
              ),
            ),
          ),

          IconButton(
            visualDensity:
            VisualDensity
                .compact,
            tooltip:
            'Remove',
            icon:
            const Icon(
              Icons
                  .delete_outline,
              color:
              Colors.red,
              size: 20,
            ),
            onPressed:
                () =>
                _removeLine(
                  index,
                ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CHECKOUT PANEL
  // ============================================================

  Widget _checkoutPanel() {
    return SingleChildScrollView(
      padding:
      const EdgeInsets.fromLTRB(
        10,
        8,
        10,
        8,
      ),
      child: Column(
        mainAxisSize:
        MainAxisSize.min,
        crossAxisAlignment:
        CrossAxisAlignment
            .stretch,
        children: [
          // ------------------------------------------------------
          // CUSTOMER
          // ------------------------------------------------------

          InkWell(
            onTap:
            _selectCustomer,
            borderRadius:
            BorderRadius
                .circular(
              8,
            ),
            child:
            Container(
              padding:
              const EdgeInsets
                  .all(
                9,
              ),
              decoration:
              BoxDecoration(
                border:
                Border.all(
                  color: Theme.of(
                    context,
                  ).dividerColor,
                ),
                borderRadius:
                BorderRadius
                    .circular(
                  8,
                ),
              ),
              child:
              Row(
                children: [
                  const Icon(
                    Icons
                        .person_outline,
                    size: 20,
                  ),

                  const SizedBox(
                    width: 8,
                  ),

                  Expanded(
                    child:
                    Column(
                      mainAxisSize:
                      MainAxisSize
                          .min,
                      crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                      children: [
                        const Text(
                          'Customer',
                          style:
                          TextStyle(
                            fontSize:
                            11,
                          ),
                        ),
                        Text(
                          _selectedCustomer
                              ?.name ??
                              'Walk-in Customer',
                          maxLines:
                          1,
                          overflow:
                          TextOverflow
                              .ellipsis,
                          style:
                          const TextStyle(
                            fontWeight:
                            FontWeight
                                .w600,
                            fontSize:
                            13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Icon(
                    Icons
                        .chevron_right,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          // ------------------------------------------------------
          // PAYMENT
          // ------------------------------------------------------

          DropdownButtonFormField<
              String>(
            value:
            _paymentType,
            isDense:
            true,
            decoration:
            const InputDecoration(
              labelText:
              'Payment Type',
              border:
              OutlineInputBorder(),
              prefixIcon:
              Icon(
                Icons
                    .payments_outlined,
              ),
            ),
            items: const [
              DropdownMenuItem(
                value:
                'Cash',
                child:
                Text(
                  'Cash',
                ),
              ),
              DropdownMenuItem(
                value:
                'UPI',
                child:
                Text(
                  'UPI',
                ),
              ),
              DropdownMenuItem(
                value:
                'Card',
                child:
                Text(
                  'Card',
                ),
              ),
              DropdownMenuItem(
                value:
                'Credit',
                child:
                Text(
                  'Credit',
                ),
              ),
            ],
            onChanged:
                (value) {
              if (value ==
                  null) {
                return;
              }

              setState(() {
                _paymentType =
                    value;
              });
            },
          ),

          const SizedBox(
            height: 8,
          ),

          // ------------------------------------------------------
          // TAX / DISCOUNT
          // ------------------------------------------------------

          Row(
            children: [
              Expanded(
                child:
                TextField(
                  controller:
                  _taxController,
                  keyboardType:
                  const TextInputType
                      .numberWithOptions(
                    decimal:
                    true,
                  ),
                  decoration:
                  const InputDecoration(
                    labelText:
                    'Tax',
                    prefixText:
                    '₹ ',
                    border:
                    OutlineInputBorder(),
                    isDense:
                    true,
                  ),
                  onChanged:
                      (_) {
                    setState(
                          () {},
                    );
                  },
                ),
              ),

              const SizedBox(
                width: 8,
              ),

              Expanded(
                child:
                TextField(
                  controller:
                  _discountController,
                  keyboardType:
                  const TextInputType
                      .numberWithOptions(
                    decimal:
                    true,
                  ),
                  decoration:
                  const InputDecoration(
                    labelText:
                    'Discount',
                    prefixText:
                    '₹ ',
                    border:
                    OutlineInputBorder(),
                    isDense:
                    true,
                  ),
                  onChanged:
                      (_) {
                    setState(
                          () {},
                    );
                  },
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 8,
          ),

          // ------------------------------------------------------
          // TOTALS
          // ------------------------------------------------------

          _summaryRow(
            'Subtotal',
            _subtotal,
          ),

          const SizedBox(
            height: 2,
          ),

          _summaryRow(
            'Tax',
            _tax,
          ),

          const SizedBox(
            height: 2,
          ),

          _summaryRow(
            'Discount',
            -_discount,
          ),

          const Divider(
            height: 14,
          ),

          _summaryRow(
            'TOTAL',
            _total,
            large:
            true,
          ),

          const SizedBox(
            height: 6,
          ),

          // ------------------------------------------------------
          // COMPLETE SALE
          // ------------------------------------------------------

          SizedBox(
            height: 46,
            child:
            FilledButton
                .icon(
              onPressed:
              _saving ||
                  _cart
                      .isEmpty
                  ? null
                  : _checkout,
              icon: _saving
                  ? const SizedBox(
                height:
                18,
                width:
                18,
                child:
                CircularProgressIndicator(
                  strokeWidth:
                  2,
                ),
              )
                  : const Icon(
                Icons
                    .check_circle_outline,
              ),
              label:
              Text(
                _saving
                    ? 'Processing...'
                    : 'Complete Sale',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SUMMARY ROW
  // ============================================================

  Widget _summaryRow(
      String label,
      double value, {
        bool large =
        false,
      }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style:
            TextStyle(
              fontSize:
              large
                  ? 17
                  : 13,
              fontWeight:
              large
                  ? FontWeight
                  .bold
                  : FontWeight
                  .normal,
            ),
          ),
        ),
        Text(
          '${value < 0 ? '-' : ''}'
              '₹${value.abs().toStringAsFixed(2)}',
          style:
          TextStyle(
            fontSize:
            large
                ? 19
                : 13,
            fontWeight:
            large
                ? FontWeight
                .bold
                : FontWeight
                .w600,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // MAIN BUILD
  // ============================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    return Scaffold(
      appBar:
      AppBar(
        title:
        const Text(
          'POS',
        ),
        actions: [
          IconButton(
            tooltip:
            'Refresh',
            onPressed:
            _loading
                ? null
                : _loadData,
            icon:
            const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
        child:
        CircularProgressIndicator(),
      )
          : Column(
        children: [
          _topBar(),

          Expanded(
            child:
            _buildResponsiveBody(),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TOP BAR
  // ============================================================

  Widget _topBar() {
    return Padding(
      padding:
      const EdgeInsets.fromLTRB(
        10,
        8,
        10,
        8,
      ),
      child:
      Row(
        children: [
          Expanded(
            child:
            TextField(
              controller:
              _searchController,
              decoration:
              InputDecoration(
                hintText:
                'Search items or combos...',
                prefixIcon:
                const Icon(
                  Icons.search,
                ),
                suffixIcon:
                _search.isEmpty
                    ? null
                    : IconButton(
                  onPressed:
                      () {
                    _searchController
                        .clear();
                  },
                  icon:
                  const Icon(
                    Icons.clear,
                  ),
                ),
                border:
                const OutlineInputBorder(),
                isDense:
                true,
              ),
            ),
          ),

          const SizedBox(
            width: 8,
          ),

          SizedBox(
            width: 210,
            child:
            TextField(
              controller:
              _barcodeController,
              onSubmitted:
              _handleBarcode,
              decoration:
              const InputDecoration(
                hintText:
                'Scan barcode',
                prefixIcon:
                Icon(
                  Icons
                      .qr_code_scanner,
                ),
                border:
                OutlineInputBorder(),
                isDense:
                true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // RESPONSIVE BODY
  // ============================================================

  Widget _buildResponsiveBody() {
    final width =
        MediaQuery.of(
          context,
        ).size.width;

    if (width < 900) {
      return _mobileBody();
    }

    return Row(
      children: [
        Expanded(
          child:
          _productArea(),
        ),

        const SizedBox(
          width: 8,
        ),

        SizedBox(
          width:
          width < 1200
              ? 390
              : 440,
          child:
          Padding(
            padding:
            const EdgeInsets
                .only(
              right: 8,
              bottom: 8,
            ),
            child:
            _cartView(),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // MOBILE BODY
  // ============================================================

  Widget _mobileBody() {
    return Column(
      children: [
        Expanded(
          child:
          _productArea(),
        ),

        const SizedBox(
          height: 6,
        ),

        SizedBox(
          height: 420,
          child:
          Padding(
            padding:
            const EdgeInsets
                .fromLTRB(
              8,
              0,
              8,
              8,
            ),
            child:
            _cartView(),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // PRODUCT AREA
  // ============================================================

  Widget _productArea() {
    return Column(
      children: [
        // --------------------------------------------------------
        // ITEMS HEADER
        //
        // No TabBar here because there is currently only one tab.
        // This completely removes the TabController error.
        // --------------------------------------------------------

        Container(
          height: 48,
          margin:
          const EdgeInsets
              .symmetric(
            horizontal: 8,
          ),
          padding:
          const EdgeInsets
              .symmetric(
            horizontal: 8,
          ),
          decoration:
          BoxDecoration(
            border:
            Border(
              bottom:
              BorderSide(
                color: Theme.of(
                  context,
                ).dividerColor,
              ),
            ),
          ),
          child:
          Row(
            children: [
              ChoiceChip(
                label: const Text('Items'),
                selected: !_showingCombos,
                onSelected: (_) {
                  setState(() {
                    _showingCombos = false;
                  });
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Combos'),
                selected: _showingCombos,
                onSelected: (_) {
                  setState(() {
                    _showingCombos = true;
                  });
                },
              ),
            ],
          ),
        ),

        Expanded(
          child: _showingCombos
              ? _combosGrid()
              : _materialsGrid(),
        ),
      ],
    );
  }

  // ============================================================
  // MATERIAL GRID
  // ============================================================

  Widget _materialsGrid() {
    final materials =
        _filteredMaterials;

    if (materials.isEmpty) {
      return _emptyProducts(
        icon:
        Icons
            .inventory_2_outlined,
        title:
        'No raw materials found',
      );
    }

    return GridView.builder(
      padding:
      const EdgeInsets.all(
        10,
      ),
      gridDelegate:
      const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent:
        230,

        // Reduced from 220 to 205.
        // This gives more vertical room
        // in the POS window.
        mainAxisExtent:
        205,

        crossAxisSpacing:
        10,
        mainAxisSpacing:
        10,
      ),
      itemCount:
      materials.length,
      itemBuilder:
          (
          _,
          index,
          ) {
        return _materialCard(
          materials[index],
        );
      },
    );
  }

  Widget _combosGrid() {
    final combos = _filteredCombos;

    if (combos.isEmpty) {
      return _emptyProducts(
        icon: Icons.fastfood_outlined,
        title: 'No combos found',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate:
      const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 230,
        mainAxisExtent: 205,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: combos.length,
      itemBuilder: (_, index) {
        return _comboCard(combos[index]);
      },
    );
  }

  Widget _comboCard(Combo combo) {
    final stock = _stockForCombo(combo);
    final cartQty =
        combo.id == null ? 0.0 : _cartQtyForCombo(combo.id!);
    final canAdd = stock - cartQty > 0.000001;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: canAdd ? () => _addCombo(combo) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _image(combo.imagePath, height: 100),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      combo.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '₹${combo.price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Stock: ${_formatQty(stock)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (cartQty > 0)
                          CircleAvatar(
                            radius: 11,
                            child: Text(
                              _formatQty(cartQty),
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                      ],
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

  // ============================================================
  // EMPTY PRODUCTS
  // ============================================================

  Widget _emptyProducts({
    required IconData icon,
    required String title,
  }) {
    return Center(
      child:
      Column(
        mainAxisSize:
        MainAxisSize
            .min,
        children: [
          Icon(
            icon,
            size: 55,
            color:
            Colors.grey,
          ),

          const SizedBox(
            height: 10,
          ),

          Text(
            title,
            style:
            const TextStyle(
              fontSize: 17,
              fontWeight:
              FontWeight
                  .bold,
            ),
          ),

          if (_search
              .isNotEmpty) ...[
            const SizedBox(
              height: 5,
            ),
            const Text(
              'Try another search.',
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // UNIT
  // ============================================================

  String _unitForMaterial(
      RawMaterial material,
      ) {
    // Your current RawMaterial model contains unitId,
    // but POS does not currently have the Unit short code.
    //
    // Therefore the UI displays "units" for now.

    return 'units';
  }

  // ============================================================
  // FORMAT QUANTITY
  // ============================================================

  String _formatQty(
      double value,
      ) {
    if ((value -
        value.roundToDouble())
        .abs() <
        0.000001) {
      return value
          .round()
          .toString();
    }

    return value
        .toStringAsFixed(2)
        .replaceFirst(
      RegExp(
        r'\.?0+$',
      ),
      '',
    );
  }

  // ============================================================
  // ERROR
  // ============================================================

  void _showError(
      String message,
      ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content:
        Text(message),
        backgroundColor:
        Theme.of(
          context,
        )
            .colorScheme
            .error,
        behavior:
        SnackBarBehavior
            .floating,
      ),
    );
  }
}