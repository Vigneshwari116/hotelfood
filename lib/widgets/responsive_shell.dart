import 'package:flutter/material.dart';

/// ============================================================
/// BREAKPOINTS
/// ============================================================

class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 1000;
}

/// ============================================================
/// NAV ITEM
/// ============================================================

class NavItem {
  final IconData icon;
  final String label;
  final Widget page;

  NavItem({
    required this.icon,
    required this.label,
    required this.page,
  });
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
  final List<NavItem> items;
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

  void _selectPage(int index) {
    if (index < 0 || index >= widget.items.length) return;

    setState(() {
      _index = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    final isDesktop = width >= Breakpoints.tablet;

    final currentItem = widget.items[_index];

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
              items: widget.items,
              selectedIndex: _index,
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
        items: widget.items,
        selectedIndex: _index,
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
  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String? userLabel;
  final VoidCallback? onLogout;

  const _DesktopSidebar({
    required this.title,
    required this.items,
    required this.selectedIndex,
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
          // --------------------------------------------------
          // LOGO / TITLE
          // --------------------------------------------------

          Container(
            height: 80,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.storefront,
                  color: Colors.white,
                  size: 30,
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // --------------------------------------------------
          // MENU
          // --------------------------------------------------

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(
                vertical: 12,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];

                final selected =
                    selectedIndex == index;

                return _SidebarItem(
                  item: item,
                  selected: selected,
                  onTap: () {
                    onSelected(index);
                  },
                );
              },
            ),
          ),

          // --------------------------------------------------
          // FOOTER
          // --------------------------------------------------

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
  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String? userLabel;
  final VoidCallback? onLogout;

  const _AppDrawer({
    required this.title,
    required this.items,
    required this.selectedIndex,
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
          // --------------------------------------------------
          // DRAWER HEADER
          // --------------------------------------------------

          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              20,
              45,
              20,
              20,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.storefront,
                    color: theme.colorScheme.primary,
                    size: 30,
                  ),
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 3),

                      const Text(
                        'Order & Stock Console',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // --------------------------------------------------
          // MENU
          // --------------------------------------------------

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(
                vertical: 10,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];

                final selected =
                    selectedIndex == index;

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
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
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: selected
                            ? theme.colorScheme.primary
                            : Colors.grey.shade800,
                      ),
                    ),

                    selected: selected,

                    selectedTileColor:
                    theme.colorScheme.primaryContainer,

                    shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(10),
                    ),

                    trailing: selected
                        ? Icon(
                      Icons.chevron_right,
                      color:
                      theme.colorScheme.primary,
                    )
                        : null,

                    onTap: () {
                      onSelected(index);
                    },
                  ),
                );
              },
            ),
          ),

          // --------------------------------------------------
          // FOOTER
          // --------------------------------------------------

          if (onLogout != null)
            SafeArea(
              child: ListTile(
                leading: Icon(
                  Icons.logout,
                  color: Colors.grey.shade700,
                ),
                title: const Text('Logout'),
                subtitle: userLabel == null
                    ? null
                    : Text(userLabel!),
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