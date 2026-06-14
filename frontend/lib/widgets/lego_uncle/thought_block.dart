import 'package:flutter/material.dart';

class ThoughtBlock extends StatelessWidget {
  final String text;
  final bool isVisible;

  const ThoughtBlock({
    super.key,
    required this.text,
    this.isVisible = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxWidth: 160),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey[300]!, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            offset: const Offset(4, 4),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Text(
            text,
            style: const TextStyle(
              color: Colors.black,
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          // Connector "block" to the uncle
          Positioned(
            bottom: -20,
            left: 20,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey[300]!, width: 2),
              ),
            ),
          ),
          Positioned(
            bottom: -12,
            left: 14,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey[300]!, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
