import 'package:flutter/material.dart';
import 'package:foodstock/services/sub_item_stock.dart';

/// Dropdown for picking an existing stock group or entering a new one.
class SubItemGroupField extends StatefulWidget {
  const SubItemGroupField({
    super.key,
    required this.existingGroups,
    required this.initialValue,
    required this.onChanged,
    this.decoration,
    this.isDense = true,
  });

  final List<String> existingGroups;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final InputDecoration? decoration;
  final bool isDense;

  static const String addNewSentinel = '__add_new_group__';

  @override
  State<SubItemGroupField> createState() => _SubItemGroupFieldState();
}

class _SubItemGroupFieldState extends State<SubItemGroupField> {
  static const String _addNewSentinel = SubItemGroupField.addNewSentinel;

  late final TextEditingController _newGroupController;
  bool _addingNew = false;
  String? _selectedGroup;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue.trim();
    _newGroupController = TextEditingController(text: initial);
    _selectedGroup = _resolveSelection(initial);
    _addingNew = _selectedGroup == _addNewSentinel;
  }

  @override
  void didUpdateWidget(SubItemGroupField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final initial = widget.initialValue.trim();
    if (initial != oldWidget.initialValue.trim()) {
      _selectedGroup = _resolveSelection(initial);
      _addingNew = _selectedGroup == _addNewSentinel;
      if (_addingNew) {
        _newGroupController.text = initial;
      }
    }
  }

  @override
  void dispose() {
    _newGroupController.dispose();
    super.dispose();
  }

  String? _resolveSelection(String value) {
    if (value.isEmpty) return null;
    final canonical = SubItemStock.resolveCanonicalLabel(
      value,
      widget.existingGroups,
    );
    if (widget.existingGroups.any(
      (group) => SubItemStock.normalizeGroupKey(group) ==
          SubItemStock.normalizeGroupKey(canonical),
    )) {
      return canonical;
    }
    return _addNewSentinel;
  }

  void _emit(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    widget.onChanged(
      SubItemStock.resolveCanonicalLabel(trimmed, widget.existingGroups),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_addingNew) {
      return TextField(
        controller: _newGroupController,
        decoration: (widget.decoration ??
                const InputDecoration(
                  labelText: 'New group',
                ))
            .copyWith(
          suffixIcon: widget.existingGroups.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Pick existing group',
                  icon: const Icon(Icons.list_alt),
                  onPressed: () {
                    setState(() {
                      _addingNew = false;
                      _selectedGroup = widget.existingGroups.isNotEmpty
                          ? widget.existingGroups.first
                          : null;
                    });
                    if (_selectedGroup != null) {
                      _emit(_selectedGroup!);
                    }
                  },
                ),
        ),
        onChanged: _emit,
      );
    }

    return DropdownButtonFormField<String>(
      value: _selectedGroup,
      isExpanded: true,
      isDense: widget.isDense,
      decoration: widget.decoration ??
          const InputDecoration(
            labelText: 'Sub Item / Group',
          ),
      items: [
        ...widget.existingGroups.map(
          (group) => DropdownMenuItem<String>(
            value: group,
            child: Text(
              group,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const DropdownMenuItem<String>(
          value: _addNewSentinel,
          child: Text('+ Add new group'),
        ),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _selectedGroup = value;
          _addingNew = value == _addNewSentinel;
          if (_addingNew) {
            _newGroupController.text = widget.initialValue.trim();
          }
        });
        if (!_addingNew) {
          _emit(value);
        } else if (_newGroupController.text.trim().isNotEmpty) {
          _emit(_newGroupController.text);
        }
      },
    );
  }
}
