import 'package:flutter/material.dart';

import 'package:foodstock/services/session_reset_service.dart';
import 'package:foodstock/widgets/responsive_shell.dart';

class ResetScreen extends StatefulWidget {
  final VoidCallback? onSessionReset;

  const ResetScreen({
    super.key,
    this.onSessionReset,
  });

  @override
  State<ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends State<ResetScreen> {
  static const _unlockCode = 'ramsai';

  final TextEditingController _codeController = TextEditingController();
  bool _resetting = false;

  bool get _codeMatches => _codeController.text == _unlockCode;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _performReset() async {
    if (!_codeMatches || _resetting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset all shop data?'),
        content: const Text(
          'This permanently deletes every sale, purchase, stock record, '
          'customer, menu item, and combo from the shop database '
          '(including data on the VPS server). '
          'Default menu items will be restored from the built-in list. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _resetting = true);

    try {
      await SessionResetService.clearAllShopData();
      _codeController.clear();
      widget.onSessionReset?.call();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'All sales and records deleted. Shop data has been reset.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reset failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _resetting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ResponsivePage(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.restart_alt,
                      size: 48,
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Reset shop data',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Deletes all sales, purchases, stock history, customers, '
                      'and menu items from the database. Also clears printer '
                      'and receipt screen preferences. Default menu is restored.',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        height: 1.35,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _codeController,
                      decoration: const InputDecoration(
                        labelText: 'Enter code to enable reset',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_codeMatches) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _resetting ? null : _performReset,
                        icon: _resetting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.restart_alt),
                        label: Text(
                          _resetting ? 'Resetting...' : 'Reset',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
