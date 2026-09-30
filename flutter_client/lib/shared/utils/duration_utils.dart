/// توحيد وحدات مُدد المسبار (probe) بالثواني.
///
/// بعض الباك إندات تُرجع المدّة بملّي الثانية بدل الثانية. أي قيمة فوق
/// 6 ساعات لمقطع واحد تُعامل كـ ms وتُقسَّم على 1000، ثم تُقصّ النتيجة
/// على [0.1, 6h] حتى لا تتمدد التايملاين بقيمة مسمومة أبدًا.
const double kMaxSingleClipSeconds = 6 * 3600.0;

double normalizeProbeDurationSeconds(double raw) {
  var dur = raw;
  if (dur > kMaxSingleClipSeconds) dur /= 1000.0;
  return dur.clamp(0.1, kMaxSingleClipSeconds).toDouble();
}
