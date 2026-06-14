import 'package:flutter/material.dart';

/// A single Lego-style block widget.
class LegoBlock extends StatelessWidget {
  final double width;
  final double height;
  final Color color;
  final bool hasStud;
  final BorderRadius? borderRadius;

  const LegoBlock({
    super.key,
    required this.width,
    required this.height,
    required this.color,
    this.hasStud = true,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasStud)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStud(),
              if (width > 40) ...[
                const SizedBox(width: 8),
                _buildStud(),
              ],
            ],
          ),
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: borderRadius ?? BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                offset: const Offset(1, 1),
                blurRadius: 1,
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.1),
                offset: const Offset(-1, -1),
                blurRadius: 1,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStud() {
    return Container(
      width: 12,
      height: 4,
      decoration: BoxDecoration(
        color: color.withOpacity(0.9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}

/// The visual representation of the Lego Uncle.
class LegoUncleBody extends StatelessWidget {
  final String mood; // 'anger', 'contentment', 'appreciation'
  final double scale;

  const LegoUncleBody({
    super.key,
    required this.mood,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    // Theme colors: Monochrome with subtle pastel accents
    const blockColor = Color(0xFFE0E0E0); // Light grey/white
    const accentColor = Color(0xFFB0BEC5); // Blue-grey

    return Transform.scale(
      scale: scale,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Head
          _buildHead(mood, blockColor),
          const SizedBox(height: 2),
          // Torso
          _buildTorso(mood, blockColor, accentColor),
          const SizedBox(height: 2),
          // Legs
          _buildLegs(mood, blockColor),
        ],
      ),
    );
  }

  Widget _buildHead(String mood, Color color) {
    return Stack(
      alignment: Alignment.center,
      children: [
        LegoBlock(
          width: 32,
          height: 28,
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
        // Face decal
        Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: _getFaceDecal(mood),
        ),
      ],
    );
  }

  Widget _getFaceDecal(String mood) {
    switch (mood) {
      case 'anger':
        return _buildAngryFace();
      case 'appreciation':
        return _buildHappyFace();
      case 'contentment':
      default:
        return _buildSereneFace();
    }
  }

  Widget _buildSereneFace() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _eye(),
            const SizedBox(width: 8),
            _eye(),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: 10,
          height: 2,
          color: Colors.black54,
        ),
      ],
    );
  }

  Widget _buildAngryFace() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(angle: 0.2, child: _eye(isAngry: true)),
            const SizedBox(width: 8),
            Transform.rotate(angle: -0.2, child: _eye(isAngry: true)),
          ],
        ),
        const SizedBox(height: 2),
        Container(
          width: 12,
          height: 3,
          decoration: const BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ),
      ],
    );
  }

  Widget _buildHappyFace() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _eye(),
            const SizedBox(width: 8),
            _eye(),
          ],
        ),
        const SizedBox(height: 2),
        Container(
          width: 12,
          height: 6,
          decoration: const BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
          ),
        ),
      ],
    );
  }

  Widget _eye({bool isAngry = false}) {
    return Container(
      width: 4,
      height: 4,
      decoration: const BoxDecoration(
        color: Colors.black87,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildTorso(String mood, Color color, Color accent) {
    bool isAngry = mood == 'anger';
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Arm
        Transform.translate(
          offset: Offset(4, isAngry ? -4 : 4),
          child: Transform.rotate(
            angle: isAngry ? 0.5 : -0.2,
            child: _buildArm(color),
          ),
        ),
        // Torso Block
        LegoBlock(
          width: 40,
          height: 44,
          color: accent,
          hasStud: false,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(2),
            bottom: Radius.circular(4),
          ),
        ),
        // Right Arm
        Transform.translate(
          offset: Offset(-4, isAngry ? -4 : 4),
          child: Transform.rotate(
            angle: isAngry ? -0.5 : 0.2,
            child: _buildArm(color),
          ),
        ),
      ],
    );
  }

  Widget _buildArm(Color color) {
    return Column(
      children: [
        LegoBlock(width: 10, height: 24, color: color, hasStud: false),
        Container(
          width: 12,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)),
          ),
        ),
      ],
    );
  }

  Widget _buildLegs(String mood, Color color) {
    bool isAngry = mood == 'anger';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildLeg(color, isAngry ? -0.1 : 0),
        const SizedBox(width: 4),
        _buildLeg(color, isAngry ? 0.1 : 0),
      ],
    );
  }

  Widget _buildLeg(Color color, double angle) {
    return Transform.rotate(
      angle: angle,
      child: Column(
        children: [
          LegoBlock(width: 14, height: 32, color: color, hasStud: false),
          LegoBlock(
            width: 18,
            height: 8,
            color: color,
            hasStud: false,
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
          ),
        ],
      ),
    );
  }
}
