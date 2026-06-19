import 'package:flutter/material.dart';

class TrackConfig {
  final String name;
  final IconData icon;
  final Color color;
  final List<dynamic> clips;
  final String type;
  final double height;

  TrackConfig({
    required this.name,
    required this.icon,
    required this.color,
    required this.clips,
    required this.type,
    required this.height,
  });
}

class RecordingIndicator extends StatefulWidget {
  const RecordingIndicator({super.key});

  @override
  State<RecordingIndicator> createState() => RecordingIndicatorState();
}

class RecordingIndicatorState extends State<RecordingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: const Icon(
        Icons.fiber_manual_record_rounded,
        color: Colors.redAccent,
        size: 16,
      ),
    );
  }
}

class PlayheadTriangle extends CustomClipper<Path> {
  const PlayheadTriangle();

  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(size.width / 2, size.height);
    path.lineTo(0, 0);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
