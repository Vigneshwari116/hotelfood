import 'package:flutter/material.dart';
import 'package:foodstock/services/trial_license.dart';

/// Non-intrusive banner shown after login when the trial is ending soon.
class TrialBanner extends StatelessWidget {
  final Widget child;

  const TrialBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: TrialLicense.instance,
      builder: (context, _) {
        final license = TrialLicense.instance;
        if (!license.showWarning) {
          return child;
        }

        return Column(
          children: [
            Material(
              color: Colors.amber.shade50,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 12),
                        child: Icon(
                          Icons.schedule_outlined,
                          color: Colors.amber.shade900,
                          size: 20,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          license.warningMessage,
                          style: TextStyle(
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}
