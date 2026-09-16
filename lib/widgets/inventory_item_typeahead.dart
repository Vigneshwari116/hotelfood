import 'package:flutter/material.dart';
import 'package:foodstock/services/inventory_search.dart';
import 'package:foodstock/theme/brand_theme.dart';

class InventoryItemTypeahead extends StatefulWidget {
  const InventoryItemTypeahead({
    super.key,
    required this.entries,
    required this.onSelected,
    this.controller,
    this.selectedPrimaryLabel,
    this.enabled = true,
    this.hintText = 'Type name, sub item or barcode',
    this.labelText,
    this.onQueryChanged,
  });

  final List<InventorySearchEntry> entries;
  final ValueChanged<InventorySearchEntry> onSelected;
  final TextEditingController? controller;
  final String? selectedPrimaryLabel;
  final bool enabled;
  final String hintText;
  final String? labelText;
  final ValueChanged<String>? onQueryChanged;

  @override
  State<InventoryItemTypeahead> createState() => _InventoryItemTypeaheadState();
}

class _InventoryItemTypeaheadState extends State<InventoryItemTypeahead> {
  static const _tapGroup = 'inventory-item-search';

  late final TextEditingController _controller;
  late final bool _ownsController;
  final _focus = FocusNode();
  final _fieldKey = GlobalKey();
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  double _fieldWidth = 0;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TextEditingController();
    _syncTextFromSelection();
    _controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant InventoryItemTypeahead oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedPrimaryLabel != oldWidget.selectedPrimaryLabel &&
        !_focus.hasFocus) {
      _syncTextFromSelection();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    _focus.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    widget.onQueryChanged?.call(_controller.text);
    if (mounted) {
      setState(() {});
    }
  }

  void _syncTextFromSelection() {
    final next = widget.selectedPrimaryLabel ?? '';
    if (_controller.text != next) {
      _controller.text = next;
    }
  }

  List<InventorySearchEntry> get _matches =>
      filterInventorySearchEntries(widget.entries, _controller.text);

  void _openList() {
    if (!widget.enabled) return;
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    setState(() {
      _fieldWidth = box?.size.width ?? MediaQuery.sizeOf(context).width;
    });
    if (!_portal.isShowing) {
      _portal.show();
    } else {
      setState(() {});
    }
  }

  void _closeList() {
    if (_portal.isShowing) {
      _portal.hide();
    }
  }

  void _pick(InventorySearchEntry entry) {
    _controller.text = entry.primaryLabel;
    _closeList();
    _focus.unfocus();
    widget.onSelected(entry);
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    final selectedLabel = widget.selectedPrimaryLabel;

    return TapRegion(
      groupId: _tapGroup,
      onTapOutside: (_) {
        _closeList();
        _focus.unfocus();
      },
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) {
          return CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 4),
            child: Align(
              alignment: Alignment.topLeft,
              widthFactor: 1,
              heightFactor: 1,
              child: TapRegion(
                groupId: _tapGroup,
                child: Material(
                  color: Colors.white,
                  elevation: 6,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: _fieldWidth,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFD5DDDB)),
                        ),
                        child: matches.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                child: Text(
                                  'No matching items',
                                  style: TextStyle(
                                    color: Colors.black54,
                                    fontSize: 13,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: matches.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, i) {
                                  final entry = matches[i];
                                  final selected = selectedLabel != null &&
                                      entry.primaryLabel == selectedLabel;
                                  return InkWell(
                                    onTapDown: (_) => _pick(entry),
                                    child: ColoredBox(
                                      color: selected
                                          ? BrandColors.teal.withOpacity(0.08)
                                          : Colors.white,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              entry.primaryLabel,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: selected
                                                    ? FontWeight.w600
                                                    : FontWeight.w500,
                                                color: selected
                                                    ? BrandColors.teal
                                                    : Colors.black87,
                                              ),
                                            ),
                                            if (entry.secondaryLabel != null)
                                              Text(
                                                entry.secondaryLabel!,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        child: CompositedTransformTarget(
          link: _link,
          child: TextField(
            key: _fieldKey,
            controller: _controller,
            focusNode: _focus,
            enabled: widget.enabled,
            textInputAction: TextInputAction.search,
            onTap: _openList,
            onChanged: (_) => _openList(),
            onSubmitted: (value) {
              final submittedMatches =
                  filterInventorySearchEntries(widget.entries, value);
              if (submittedMatches.isNotEmpty) {
                _pick(submittedMatches.first);
              }
            },
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              labelText: widget.labelText,
              hintText: widget.hintText,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _controller.text.isEmpty
                  ? const Icon(Icons.arrow_drop_down)
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _controller.clear();
                        _focus.requestFocus();
                        _openList();
                      },
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ),
    );
  }
}
