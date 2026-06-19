import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class Particle {
  Offset position;
  Offset velocity;
  double life;
  double maxLife;
  double size;
  Color color;
  double alpha;

  Particle({
    required this.position,
    required this.velocity,
    required this.maxLife,
    this.life = 0,
    this.size = 4,
    this.color = Colors.white,
    this.alpha = 1.0,
  });

  bool get isDead => life >= maxLife;

  void update(double dt) {
    position += velocity * dt;
    life += dt;
    alpha = (1.0 - life / maxLife).clamp(0.0, 1.0);
  }
}

class ParticleEmitter {
  final List<Particle> particles = [];
  final math.Random _random = math.Random();
  bool _emitting = true;

  Offset position;
  double emitRate;
  double emitLifetime;
  double particleLifetime;
  double particleSpeed;
  double particleSize;
  Color particleColor;
  double spread;

  ParticleEmitter({
    this.position = Offset.zero,
    this.emitRate = 50,
    this.emitLifetime = -1,
    this.particleLifetime = 2.0,
    this.particleSpeed = 100,
    this.particleSize = 4,
    this.particleColor = Colors.white,
    this.spread = 6.2832, // 2 * pi (approx)
  });

  double _accumulator = 0;

  void update(double dt, Size size) {
    if (!_emitting) return;

    _accumulator += dt * emitRate;
    while (_accumulator >= 1) {
      _accumulator -= 1;
      final angle = _random.nextDouble() * spread - spread / 2 - math.pi / 2;
      final speed = particleSpeed * (0.5 + _random.nextDouble() * 0.5);
      particles.add(Particle(
        position: position,
        velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
        maxLife: particleLifetime * (0.5 + _random.nextDouble() * 0.5),
        size: particleSize * (0.5 + _random.nextDouble() * 0.5),
        color: particleColor,
      ));
    }

    for (int i = particles.length - 1; i >= 0; i--) {
      particles[i].update(dt);
      if (particles[i].isDead) {
        particles.removeAt(i);
      }
    }
  }

  void stop() => _emitting = false;

  void dispose() {
    particles.clear();
  }

  static ParticleEmitter fire(Offset position) => ParticleEmitter(
    position: position, emitRate: 60, particleLifetime: 1.5,
    particleSpeed: 80, particleSize: 6, particleColor: const Color(0xFFFF6600),
    spread: math.pi / 2,
  );

  static ParticleEmitter smoke(Offset position) => ParticleEmitter(
    position: position, emitRate: 20, particleLifetime: 3.0,
    particleSpeed: 30, particleSize: 12, particleColor: const Color(0x88AAAAAA),
    spread: math.pi / 3,
  );

  static ParticleEmitter sparkles(Offset position) => ParticleEmitter(
    position: position, emitRate: 30, particleLifetime: 1.0,
    particleSpeed: 150, particleSize: 3, particleColor: Colors.yellow,
    spread: 2 * math.pi,
  );

  static ParticleEmitter rain(Offset position) {
    final e = ParticleEmitter(
      position: position, emitRate: 100, particleLifetime: 2.0,
      particleSpeed: 400, particleSize: 2, particleColor: const Color(0x44FFFFFF),
      spread: 0.2,
    );
    e.emitRate = 200;
    return e;
  }

  static ParticleEmitter snow(Offset position) {
    final e = ParticleEmitter(
      position: position, emitRate: 40, particleLifetime: 4.0,
      particleSpeed: 40, particleSize: 5, particleColor: const Color(0x66FFFFFF),
      spread: 0.3,
    );
    e.emitRate = 80;
    return e;
  }

  static ParticleEmitter explosion(Offset position) {
    final e = ParticleEmitter(
      position: position, emitRate: 200, particleLifetime: 1.0,
      particleSpeed: 200, particleSize: 5, particleColor: const Color(0xFFFF4400),
      spread: 2 * math.pi,
    );
    e.emitLifetime = 0.1;
    return e;
  }
}

class ParticleRenderer extends CustomPainter {
  final List<Particle> particles;

  ParticleRenderer({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()..color = p.color.withValues(alpha: p.alpha);
      canvas.drawCircle(p.position, p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ParticleRenderer oldDelegate) => true;
}

class ParticleWidget extends StatefulWidget {
  final ParticleEmitter emitter;

  const ParticleWidget({super.key, required this.emitter});

  @override
  State<ParticleWidget> createState() => _ParticleWidgetState();
}

class _ParticleWidgetState extends State<ParticleWidget>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  final Stopwatch _stopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    _ticker = createTicker((elapsed) {
      final dt = elapsed.inMicroseconds / 1000000.0;
      widget.emitter.update(dt, Size.zero);
      if (mounted) setState(() {});
    });
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    widget.emitter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: ParticleRenderer(particles: widget.emitter.particles),
      size: Size.infinite,
    );
  }
}
