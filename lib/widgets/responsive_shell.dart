import 'package:flutter/material.dart';
import 'package:foodstock/branding/app_brand.dart';
import 'package:foodstock/widgets/brand_logo.dart';

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
  final List<NavItem> items;

  const ResponsiveShell({
    super.key,
    required this.title,
    required this.items,
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
                  title: widget.title,
                  pageTitle: currentItem.label,
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

  const _DesktopSidebar({
    required this.title,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
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
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            color: Colors.white,
            child: Semantics(
              label: title,
              child: const BrandLogo(height: 72),
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

          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              AppBrand.name,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
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

  const _AppDrawer({
    required this.title,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
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
              40,
              20,
              16,
            ),
            color: Colors.white,
            child: Column(
              children: [
                Semantics(
                  label: title,
                  child: const BrandLogo(height: 88),
                ),
                const SizedBox(height: 8),
                const Text(
                  AppBrand.tagline,
                  style: TextStyle(
                    color: AppBrand.teal,
                    fontSize: 12,
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

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const BrandLogo(height: 22),

                  const SizedBox(width: 8),

                  Text(
                    AppBrand.name,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
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
  final String title;
  final String pageTitle;

  const _TopBar({
    required this.title,
    required this.pageTitle,
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

          const BrandLogo(height: 22),

          const SizedBox(width: 8),

          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
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