import 'package:flutter/material.dart';

import 'brand_logo.dart';

/// ============================================================
/// BREAKPOINTS
/// ============================================================

class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 1000;
}

/// ============================================================
/// NAV ITEM / GROUP
/// ============================================================

abstract class NavEntry {}

class NavItem extends NavEntry {
  final IconData icon;
  final String label;
  final Widget page;

  NavItem({
    required this.icon,
    required this.label,
    required this.page,
  });
}

class NavGroup extends NavEntry {
  final IconData icon;
  final String label;
  final List<NavItem> children;

  NavGroup({
    required this.icon,
    required this.label,
    required this.children,
  });
}

List<NavItem> flattenNavEntries(List<NavEntry> entries) {
  final flat = <NavItem>[];
  for (final entry in entries) {
    if (entry is NavItem) {
      flat.add(entry);
    } else if (entry is NavGroup) {
      flat.addAll(entry.children);
    }
  }
  return flat;
}

int? groupIndexContainingFlat(
  List<NavEntry> entries,
  int flatIndex,
) {
  var index = 0;
  for (var groupIndex = 0; groupIndex < entries.length; groupIndex++) {
    final entry = entries[groupIndex];
    if (entry is NavItem) {
      if (index == flatIndex) return null;
      index++;
    } else if (entry is NavGroup group) {
      for (final _ in group.children) {
        if (index == flatIndex) return groupIndex;
        index++;
      }
    }
  }
  return null;
}

/// ============================================================
/// RESPONSIVE SHELL
///
/// Desktop >= 1000
///     -> Permanent left sidebar
///
/// Tablet 600 - 999
///     -> Drawer + normal content
///
/// Mobile < 600
///     -> Drawer + normal content
///
/// NO BOTTOM NAVIGATION BAR
/// ============================================================

class ResponsiveShell extends StatefulWidget {
  final String title;
  final String? userLabel;
  final List<NavEntry> items;
  final VoidCallback? onLogout;

  const ResponsiveShell({
    super.key,
    required this.title,
    required this.items,
    this.userLabel,
    this.onLogout,
  });

  @override
  State<ResponsiveShell> createState() => _ResponsiveShellState();
}

class _ResponsiveShellState extends State<ResponsiveShell> {
  int _index = 0;
  Set<int> _expandedGroupIndices = {};

  List<NavItem> get _flatItems => flattenNavEntries(widget.items);

  @override
  void initState() {
    super.initState();
    _syncExpandedGroups();
  }

  @override
  void didUpdateWidget(ResponsiveShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _index = 0;
      _syncExpandedGroups();
    }
  }

  void _syncExpandedGroups() {
    final groupIndex = groupIndexContainingFlat(widget.items, _index);
    if (groupIndex != null) {
      _expandedGroupIndices = {groupIndex};
    }
  }

  void _selectPage(int index) {
    if (index < 0 || index >= _flatItems.length) return;

    setState(() {
      _index = index;
      _syncExpandedGroups();
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    final isDesktop = width >= Breakpoints.tablet;

    final currentItem = _flatItems[_index];

    if (isDesktop) {
      return _buildDesktop(
        context,
        currentItem,
      );
    }

    return _buildMobileTablet(
      context,
      currentItem,
    );
  }

  // ==========================================================
  // DESKTOP
  // ==========================================================

  Widget _buildDesktop(
      BuildContext context,
      NavItem currentItem,
      ) {
    return Scaffold(
      body: Row(
        children: [
          // --------------------------------------------------
          // LEFT SIDEBAR
          // --------------------------------------------------

          SizedBox(
            width: 250,
            child: _DesktopSidebar(
              title: widget.title,
              entries: widget.items,
              flatItems: _flatItems,
              selectedIndex: _index,
              expandedGroupIndices: _expandedGroupIndices,
              onGroupExpansionChanged: (groupIndex, expanded) {
                setState(() {
                  if (expanded) {
                    _expandedGroupIndices.add(groupIndex);
                  } else {
                    _expandedGroupIndices.remove(groupIndex);
                  }
                });
              },
              onSelected: _selectPage,
              userLabel: widget.userLabel,
              onLogout: widget.onLogout,
            ),
          ),

          const VerticalDivider(
            width: 1,
            thickness: 1,
          ),

          // --------------------------------------------------
          // CONTENT
          // --------------------------------------------------

          Expanded(
            child: Column(
              children: [
                _TopBar(
                  pageTitle: currentItem.label,
                  userLabel: widget.userLabel,
                  onLogout: widget.onLogout,
                ),

                Expanded(
                  child: currentItem.page,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // MOBILE + TABLET
  // ==========================================================

  Widget _buildMobileTablet(
      BuildContext context,
      NavItem currentItem,
      ) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          currentItem.label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (widget.onLogout != null)
            IconButton(
              tooltip: 'Logout',
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),

      // ------------------------------------------------------
      // DRAWER
      // ------------------------------------------------------
      //
      // Scaffold automatically shows a hamburger icon in the
      // AppBar's leading slot whenever `drawer` is set and no
      // custom `leading` is provided, so we don't add a second,
      // manual menu button here.

      drawer: _AppDrawer(
        title: widget.title,
        entries: widget.items,
        flatItems: _flatItems,
        selectedIndex: _index,
        expandedGroupIndices: _expandedGroupIndices,
        onGroupExpansionChanged: (groupIndex, expanded) {
          setState(() {
            if (expanded) {
              _expandedGroupIndices.add(groupIndex);
            } else {
              _expandedGroupIndices.remove(groupIndex);
            }
          });
        },
        onSelected: (index) {
          _selectPage(index);

          Navigator.of(context).pop();
        },
        userLabel: widget.userLabel,
        onLogout: widget.onLogout,
      ),

      // ------------------------------------------------------
      // PAGE
      // ------------------------------------------------------

      body: currentItem.page,
    );
  }
}

/// ============================================================
/// DESKTOP SIDEBAR
/// ============================================================

class _DesktopSidebar extends StatelessWidget {
  final String title;
  final List<NavEntry> entries;
  final List<NavItem> flatItems;
  final int selectedIndex;
  final Set<int> expandedGroupIndices;
  final void Function(int groupIndex, bool expanded) onGroupExpansionChanged;
  final ValueChanged<int> onSelected;
  final String? userLabel;
  final VoidCallback? onLogout;

  const _DesktopSidebar({
    required this.title,
    required this.entries,
    required this.flatItems,
    required this.selectedIndex,
    required this.expandedGroupIndices,
    required this.onGroupExpansionChanged,
    required this.onSelected,
    this.userLabel,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          Container(
            height: 108,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            color: Colors.white,
            child: Semantics(
              label: title,
              child: const BrandLogo(height: 88),
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: _buildNavChildren(context),
            ),
          ),

          if (onLogout != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: ListTile(
                leading: Icon(
                  Icons.logout,
                  color: Colors.grey.shade700,
                ),
                title: const Text('Logout'),
                subtitle: userLabel == null
                    ? null
                    : Text(userLabel!),
                onTap: onLogout,
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildNavChildren(BuildContext context) {
    final children = <Widget>[];
    var flatIndex = 0;

    for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
      final entry = entries[entryIndex];
      if (entry is NavItem) {
        children.add(
          _SidebarItem(
            item: entry,
            selected: selectedIndex == flatIndex,
            onTap: () => onSelected(flatIndex),
          ),
        );
        flatIndex++;
      } else if (entry is NavGroup group) {
        final expanded = expandedGroupIndices.contains(entryIndex);
        children.add(
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
            ),
            child: ExpansionTile(
              key: ValueKey('nav_group_${entryIndex}_$expanded'),
              initiallyExpanded: expanded,
              onExpansionChanged: (value) =>
                  onGroupExpansionChanged(entryIndex, value),
              leading: Icon(
                group.icon,
                color: Colors.grey.shade700,
              ),
              title: Text(
                group.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: [
                for (final child in group.children)
                  Builder(
                    builder: (context) {
                      final currentFlat = flatIndex;
                      flatIndex++;
                      return _SidebarSubItem(
                        item: child,
                        selected: selectedIndex == currentFlat,
                        onTap: () => onSelected(currentFlat),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      }
    }

    return children;
  }
}

class _SidebarSubItem extends StatelessWidget {
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarSubItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 10, bottom: 2),
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 20,
                  color: selected
                      ? theme.colorScheme.primary
                      : Colors.grey.shade600,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.w500,
                      color: selected
                          ? theme.colorScheme.primary
                          : Colors.grey.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ============================================================
/// SIDEBAR ITEM
/// ============================================================

class _SidebarItem extends StatelessWidget {
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 3,
      ),
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 22,
                  color: selected
                      ? theme.colorScheme.primary
                      : Colors.grey.shade700,
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: selected
                          ? theme.colorScheme.primary
                          : Colors.grey.shade800,
                    ),
                  ),
                ),

                if (selected)
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ============================================================
/// MOBILE / TABLET DRAWER
/// ============================================================

class _AppDrawer extends StatelessWidget {
  final String title;
  final List<NavEntry> entries;
  final List<NavItem> flatItems;
  final int selectedIndex;
  final Set<int> expandedGroupIndices;
  final void Function(int groupIndex, bool expanded) onGroupExpansionChanged;
  final ValueChanged<int> onSelected;
  final String? userLabel;
  final VoidCallback? onLogout;

  const _AppDrawer({
    required this.title,
    required this.entries,
    required this.flatItems,
    required this.selectedIndex,
    required this.expandedGroupIndices,
    required this.onGroupExpansionChanged,
    required this.onSelected,
    this.userLabel,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Drawer(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
            child: Semantics(
              label: title,
              child: const BrandLogo(height: 110),
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10),
              children: _buildNavChildren(context, theme),
            ),
          ),

          if (onLogout != null)
            SafeArea(
              child: ListTile(
                leading: Icon(
                  Icons.logout,
                  color: Colors.grey.shade700,
                ),
                title: const Text('Logout'),
                subtitle: userLabel == null ? null : Text(userLabel!),
                onTap: () {
                  Navigator.of(context).pop();
                  onLogout!();
                },
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildNavChildren(BuildContext context, ThemeData theme) {
    final children = <Widget>[];
    var flatIndex = 0;

    for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
      final entry = entries[entryIndex];
      if (entry is NavItem item) {
        final selected = selectedIndex == flatIndex;
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: ListTile(
              leading: Icon(
                item.icon,
                color: selected
                    ? theme.colorScheme.primary
                    : Colors.grey.shade700,
              ),
              title: Text(
                item.label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: selected
                      ? theme.colorScheme.primary
                      : Colors.grey.shade800,
                ),
              ),
              selected: selected,
              selectedTileColor: theme.colorScheme.primaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              trailing: selected
                  ? Icon(Icons.chevron_right, color: theme.colorScheme.primary)
                  : null,
              onTap: () => onSelected(flatIndex),
            ),
          ),
        );
        flatIndex++;
      } else if (entry is NavGroup group) {
        final expanded = expandedGroupIndices.contains(entryIndex);
        children.add(
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: PageStorageKey('drawer_nav_group_$entryIndex'),
              initiallyExpanded: expanded,
              onExpansionChanged: (value) =>
                  onGroupExpansionChanged(entryIndex, value),
              leading: Icon(group.icon, color: Colors.grey.shade700),
              title: Text(
                group.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              children: [
                for (final child in group.children)
                  Builder(
                    builder: (context) {
                      final currentFlat = flatIndex;
                      final selected = selectedIndex == currentFlat;
                      flatIndex++;
                      return ListTile(
                        leading: Icon(
                          child.icon,
                          size: 20,
                          color: selected
                              ? theme.colorScheme.primary
                              : Colors.grey.shade600,
                        ),
                        title: Text(
                          child.label,
                          style: TextStyle(
                            fontWeight:
                                selected ? FontWeight.bold : FontWeight.w500,
                            color: selected
                                ? theme.colorScheme.primary
                                : Colors.grey.shade800,
                          ),
                        ),
                        selected: selected,
                        onTap: () => onSelected(currentFlat),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      }
    }

    return children;
  }
}

/// ============================================================
/// TOP BAR - DESKTOP
/// ============================================================

class _TopBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String pageTitle;
  final String? userLabel;
  final VoidCallback? onLogout;

  const _TopBar({
    required this.pageTitle,
    this.userLabel,
    this.onLogout,
  });

  @override
  Size get preferredSize =>
      const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            pageTitle,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          const Spacer(),

          if (userLabel != null) ...[
            Icon(
              Icons.person_outline,
              size: 18,
              color: Colors.grey.shade600,
            ),
            const SizedBox(width: 6),
            Text(
              userLabel!,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
          ],

          if (onLogout != null)
            IconButton(
              tooltip: 'Logout',
              onPressed: onLogout,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
    );
  }
}

/// ============================================================
/// RESPONSIVE PAGE
/// ============================================================

class ResponsivePage extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsivePage({
    super.key,
    required this.child,
    this.maxWidth = 1200,
  });

  @override
  Widget build(BuildContext context) {
    final width =
        MediaQuery.of(context).size.width;

    final isMobile =
        width < Breakpoints.mobile;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
        ),
        child: Padding(
          padding: EdgeInsets.all(
            isMobile ? 12 : 24,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// ============================================================
/// RESPONSIVE GRID
/// ============================================================

class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double tileWidth;
  final double spacing;

  const ResponsiveGrid({
    super.key,
    required this.children,
    this.tileWidth = 260,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (children.isEmpty) {
          return const SizedBox.shrink();
        }

        int columns =
        (constraints.maxWidth / tileWidth)
            .floor();

        columns = columns.clamp(1, 8);

        final width =
            (constraints.maxWidth -
                spacing * (columns - 1)) /
                columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: children
              .map(
                (child) => SizedBox(
              width: width,
              child: child,
            ),
          )
              .toList(),
        );
      },
    );
  }
}