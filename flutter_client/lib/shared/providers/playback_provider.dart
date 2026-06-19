import 'package:flutter_riverpod/flutter_riverpod.dart';

/// بروفايدر يمثل ما إذا كان الفيديو قيد التشغيل حالياً أم لا
final isPlayingProvider = StateProvider<bool>((ref) => false);
