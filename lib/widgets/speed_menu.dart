// lib/widgets/speed_menu.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SpeedMenu extends StatelessWidget {
  final double currentSpeed;
  final ValueChanged<double> onSpeedSelected;

  static const List<double> supportedSpeeds = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
  ];

  const SpeedMenu({
    super.key,
    required this.currentSpeed,
    required this.onSpeedSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required double current,
    required ValueChanged<double> onSelected,
  }) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14141B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SpeedMenu(
        currentSpeed: current,
        onSpeedSelected: (s) {
          Navigator.of(context).pop();
          onSelected(s);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12, left: 4),
              child: Text(
                'Playback Speed',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: supportedSpeeds.map((s) {
                final isSelected = (s - currentSpeed).abs() < 0.05;
                final label = s == 1.0 ? '1×' : '$s×';
                return GestureDetector(
                  onTap: () => onSpeedSelected(s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    width: 76,
                    height: 42,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.08),
                        width: 0.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      style: GoogleFonts.inter(
                        color: isSelected ? Colors.black : Colors.white,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13.5,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
