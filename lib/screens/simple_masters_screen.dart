import 'package:flutter/material.dart';
import 'package:foodstock/model/models.dart';
import '../services/repository.dart';

class SimpleMastersScreen extends StatefulWidget {
  const SimpleMastersScreen({super.key});

  @override
  State<SimpleMastersScreen> createState() => _SimpleMastersScreenState();
}

class _SimpleMastersScreenState extends State<SimpleMastersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();

    _tab = TabController(
      length: 2,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // IMPORTANT:
    // No Scaffold/AppBar here. ResponsiveShell already provides
    // the outer Scaffold, AppBar (with the "Masters" title and
    // the drawer/menu button), so wrapping this page in its own
    // Scaffold+AppBar would stack a second title bar on top of
    // the shell's, which is what was causing the doubled
    // "Masters" heading and the overlapping tab labels.
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.primary,
          child: TabBar(
            controller: _tab,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: const [
              Tab(
                icon: Icon(Icons.category_outlined),
                text: 'Categories',
              ),
              Tab(
                icon: Icon(Icons.local_shipping_outlined),
                text: 'Suppliers',
              ),
            ],
          ),
        ),

        Expanded(
          child: TabBarView(
            controller: _tab,
            children: const [
              _CategoryTab(),
              _SupplierTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// CATEGORY TAB
// (Raw Material categories only — Menu Item categories are
// managed separately and are intentionally not offered here.)
// ============================================================

class _CategoryTab extends StatefulWidget {
  const _CategoryTab();

  @override
  State<_CategoryTab> createState() => _CategoryTabState();
}

class _CategoryTabState extends State<_CategoryTab> {
  List<Category> _categories = [];

  final TextEditingController _nameCtrl =
  TextEditingController();

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result =
      await Repository.instance.categories(type: 'raw_material');

      if (!mounted) return;

      setState(() {
        _categories = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to load categories: $e',
          ),
        ),
      );
    }
  }

  Future<void> _addCategory() async {
    final name = _nameCtrl.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter category name'),
        ),
      );
      return;
    }

    if (_saving) return;

    setState(() {
      _saving = true;
    });

    try {
      await Repository.instance.addCategory(
        Category(
          name: name,
          type: 'raw_material',
        ),
      );

      _nameCtrl.clear();

      await _load();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Category added successfully'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to add category: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  // ============================================================
  // DELETE CATEGORY
  // ============================================================

  Future<void> _deleteCategory(Category category) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text(
          'Delete "${category.name}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await Repository.instance.deleteCategory(category.id!);
      await _load();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Category deleted')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            const Text(
              'Category Master',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 16),

            LayoutBuilder(
              builder: (context, constraints) {
                final mobile =
                    constraints.maxWidth < 600;

                if (mobile) {
                  return Column(
                    children: [
                      TextField(
                        controller: _nameCtrl,
                        decoration:
                        const InputDecoration(
                          labelText: 'Category Name',
                          border:
                          OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 12),

                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed:
                          _saving
                              ? null
                              : _addCategory,
                          icon: const Icon(
                            Icons.add,
                          ),
                          label: Text(
                            _saving
                                ? 'Adding...'
                                : 'Add Category',
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameCtrl,
                        decoration:
                        const InputDecoration(
                          labelText: 'Category Name',
                          border:
                          OutlineInputBorder(),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    FilledButton.icon(
                      onPressed:
                      _saving
                          ? null
                          : _addCategory,
                      icon: const Icon(
                        Icons.add,
                      ),
                      label: Text(
                        _saving
                            ? 'Adding...'
                            : 'Add',
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 20),

            const Divider(),

            const SizedBox(height: 10),

            const Text(
              'Categories',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Expanded(
              child: _loading
                  ? const Center(
                child:
                CircularProgressIndicator(),
              )
                  : _categories.isEmpty
                  ? const Center(
                child: Text(
                  'No categories found',
                ),
              )
                  : ListView.separated(
                itemCount:
                _categories.length,
                separatorBuilder:
                    (_, __) =>
                const Divider(
                  height: 1,
                ),
                itemBuilder:
                    (context, index) {
                  final category =
                  _categories[index];

                  return ListTile(
                    leading:
                    const CircleAvatar(
                      child: Icon(
                        Icons.category,
                      ),
                    ),
                    title: Text(
                      category.name,
                      style:
                      const TextStyle(
                        fontWeight:
                        FontWeight.w600,
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Delete category',
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                      ),
                      onPressed: () =>
                          _deleteCategory(category),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SUPPLIER TAB
// ============================================================

class _SupplierTab extends StatefulWidget {
  const _SupplierTab();

  @override
  State<_SupplierTab> createState() =>
      _SupplierTabState();
}

class _SupplierTabState
    extends State<_SupplierTab> {
  List<Supplier> _suppliers = [];

  final TextEditingController _nameCtrl =
  TextEditingController();

  final TextEditingController _mobileCtrl =
  TextEditingController();

  final TextEditingController _cityCtrl =
  TextEditingController();

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result =
      await Repository.instance.suppliers();

      if (!mounted) return;

      setState(() {
        _suppliers = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to load suppliers: $e',
          ),
        ),
      );
    }
  }

  Future<void> _addSupplier() async {
    final name = _nameCtrl.text.trim();
    final mobile = _mobileCtrl.text.trim();
    final city = _cityCtrl.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter supplier name',
          ),
        ),
      );
      return;
    }

    if (mobile.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter mobile number',
          ),
        ),
      );
      return;
    }

    if (city.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter city',
          ),
        ),
      );
      return;
    }

    if (_saving) return;

    setState(() {
      _saving = true;
    });

    try {
      await Repository.instance.addSupplier(
        Supplier(
          name: name,
          mobile: mobile,
          city: city,
        ),
      );

      _nameCtrl.clear();
      _mobileCtrl.clear();
      _cityCtrl.clear();

      await _load();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Supplier added successfully',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to add supplier: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            const Text(
              'Supplier Master',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 16),

            LayoutBuilder(
              builder: (context, constraints) {
                final mobile =
                    constraints.maxWidth < 600;

                if (mobile) {
                  return Column(
                    children: [
                      TextField(
                        controller: _nameCtrl,
                        textCapitalization:
                        TextCapitalization.words,
                        decoration:
                        const InputDecoration(
                          labelText:
                          'Supplier Name',
                          hintText:
                          'Enter supplier name',
                          border:
                          OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 12),

                      TextField(
                        controller: _mobileCtrl,
                        keyboardType:
                        TextInputType.phone,
                        decoration:
                        const InputDecoration(
                          labelText: 'Mobile',
                          hintText:
                          'Enter mobile number',
                          border:
                          OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 12),

                      TextField(
                        controller: _cityCtrl,
                        textCapitalization:
                        TextCapitalization.words,
                        decoration:
                        const InputDecoration(
                          labelText: 'City',
                          hintText:
                          'Enter city',
                          border:
                          OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 12),

                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed:
                          _saving
                              ? null
                              : _addSupplier,
                          icon: const Icon(
                            Icons.add,
                          ),
                          label: Text(
                            _saving
                                ? 'Saving...'
                                : 'Add Supplier',
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _nameCtrl,
                        decoration:
                        const InputDecoration(
                          labelText:
                          'Supplier Name',
                          border:
                          OutlineInputBorder(),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: TextField(
                        controller: _mobileCtrl,
                        keyboardType:
                        TextInputType.phone,
                        decoration:
                        const InputDecoration(
                          labelText: 'Mobile',
                          border:
                          OutlineInputBorder(),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: TextField(
                        controller: _cityCtrl,
                        decoration:
                        const InputDecoration(
                          labelText: 'City',
                          border:
                          OutlineInputBorder(),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    FilledButton.icon(
                      onPressed:
                      _saving
                          ? null
                          : _addSupplier,
                      icon: const Icon(
                        Icons.add,
                      ),
                      label: Text(
                        _saving
                            ? 'Saving...'
                            : 'Add',
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 20),

            const Divider(),

            const SizedBox(height: 10),

            Row(
              children: [
                const Text(
                  'Suppliers',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(
                    '${_suppliers.length}',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Expanded(
              child: _loading
                  ? const Center(
                child:
                CircularProgressIndicator(),
              )
                  : _suppliers.isEmpty
                  ? const Center(
                child: Column(
                  mainAxisSize:
                  MainAxisSize.min,
                  children: [
                    Icon(
                      Icons
                          .local_shipping_outlined,
                      size: 55,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No suppliers found',
                      style: TextStyle(
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              )
                  : ListView.separated(
                itemCount:
                _suppliers.length,
                separatorBuilder:
                    (_, __) =>
                const Divider(
                  height: 1,
                ),
                itemBuilder:
                    (context, index) {
                  final supplier =
                  _suppliers[index];

                  return ListTile(
                    leading:
                    const CircleAvatar(
                      child: Icon(
                        Icons
                            .local_shipping,
                      ),
                    ),
                    title: Text(
                      supplier.name,
                      style:
                      const TextStyle(
                        fontWeight:
                        FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${supplier.mobile ?? ''}'
                          '  •  '
                          '${supplier.city ?? ''}',
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
