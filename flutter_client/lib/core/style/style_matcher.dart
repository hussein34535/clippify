import 'reference_dna.dart';

/// ملف المشروع الحالي — ما نعرفه عن فيديو المستخدم لاختيار ما يناسبه.
class ProjectProfile {
  final double durationSec;
  final bool hasSpeech;
  final double speechFraction;
  final bool isVertical;
  final bool hasCameraMotion;

  const ProjectProfile({
    required this.durationSec,
    this.hasSpeech = false,
    this.speechFraction = 0,
    this.isVertical = true,
    this.hasCameraMotion = false,
  });
}

/// قرار عنصر واحد: يُطبق أم يُتخطى + السبب المعلن للمستخدم.
class MatchDecision {
  final String element;
  final bool apply;
  final String reason;

  const MatchDecision({
    required this.element,
    required this.apply,
    required this.reason,
  });
}

/// محرك الملاءمة: يفهم DNA المرجع كله، ويطبق ما يتطلبه فيديو المستخدم فقط.
///
/// القاعدة الذهبية: لا حذف لمحتوى المستخدم أبدًا — إضافة/تحويل فقط، وكل
/// عنصر يُعلن سببه (انظر docs/STYLE_DNA_REFERENCE.md §3).
List<MatchDecision> matchDnaToProject(ReferenceDna dna, ProjectProfile p) {
  final out = <MatchDecision>[];

  String num(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  // إيقاع القص — دائمًا (بمعامل حد أقصى يُضبط عند التنفيذ).
  out.add(MatchDecision(
    element: 'rhythm',
    apply: true,
    reason:
        'إيقاع القص ${num(dna.rhythm.cutsPerMin)}/دقيقة من المرجع',
  ));

  // الكابشن — فقط عند وجود كلام.
  out.add(p.hasSpeech
      ? const MatchDecision(
          element: 'captions',
          apply: true,
          reason: 'يوجد كلام — يُطبق ثيم الكابشن المرجعي',
        )
      : const MatchDecision(
          element: 'captions',
          apply: false,
          reason: 'لا كلام في الفيديو — الكابشن لا معنى له',
        ));

  // punch-ins — كلام + كاميرا ثابتة.
  if (p.hasSpeech && !p.hasCameraMotion) {
    out.add(const MatchDecision(
      element: 'punch_ins',
      apply: true,
      reason: 'لقطة ثابتة مع كلام — زومات إيقاعية مثل المرجع',
    ));
  } else {
    out.add(MatchDecision(
      element: 'punch_ins',
      apply: false,
      reason: p.hasSpeech
          ? 'حركة الكاميرا كافية — الزومات الإضافية تشتت'
          : 'لا كلام — لا مواضع للزوم عليها',
    ));
  }

  // B-roll — الطويل البطيء فقط.
  if (p.durationSec > 60 && dna.rhythm.avgShot > 3.0) {
    out.add(const MatchDecision(
      element: 'broll',
      apply: true,
      reason: 'فيديو طويل بإيقاع هادئ — يحتاج تغطية',
    ));
  } else {
    out.add(MatchDecision(
      element: 'broll',
      apply: false,
      reason: p.durationSec <= 60
          ? 'فيديو قصير — الـ B-roll سيخنق الإيقاع'
          : 'إيقاعك أسرع من المرجع — لا حاجة لتغطية',
    ));
  }

  // طبقة موسيقية — كلام + مدة كافية + المرجع يستخدمها.
  if (p.hasSpeech && p.durationSec > 30 && dna.music.hasBed) {
    out.add(MatchDecision(
      element: 'music_bed',
      apply: true,
      reason:
          'طبقة ${dna.music.mood} بسرعة ${num(dna.music.tempoBpm)} — بديل حر من مكتبتنا',
    ));
  } else {
    out.add(MatchDecision(
      element: 'music_bed',
      apply: false,
      reason: !dna.music.hasBed
          ? 'المرجع نفسه بلا طبقة موسيقية'
          : p.durationSec <= 30
              ? 'فيديو قصير — الطبقة ستزحم المقدمة'
              : 'لا كلام — لا طبقة تحتاج فرشًا',
    ));
  }

  // مقدمة/نهاية — الطويل فقط.
  if (dna.bookends.hasIntro && p.durationSec > 45) {
    out.add(MatchDecision(
      element: 'intro',
      apply: true,
      reason:
          'مقدمة ${num(dna.bookends.introSec)} ثوانٍ مثل المرجع',
    ));
  } else {
    out.add(MatchDecision(
      element: 'intro',
      apply: false,
      reason: !dna.bookends.hasIntro
          ? 'المرجع بلا مقدمة مميزة'
          : 'فيديو قصير — المقدمة ستأكل الهوك',
    ));
  }
  if (dna.bookends.hasOutro && p.durationSec > 45) {
    out.add(MatchDecision(
      element: 'outro',
      apply: true,
      reason:
          'نهاية ${num(dna.bookends.outroSec)} ثوانٍ مثل المرجع',
    ));
  } else {
    out.add(MatchDecision(
      element: 'outro',
      apply: false,
      reason: !dna.bookends.hasOutro
          ? 'المرجع بلا نهاية مميزة'
          : 'فيديو قصير — اختم بالهوك مباشرة',
    ));
  }

  // مؤثرات مولّدة — حسب كثافة المرجع.
  if (dna.sfx.eventsPerMin > 2.0) {
    out.add(MatchDecision(
      element: 'sfx',
      apply: true,
      reason:
          'كثافة ${num(dna.sfx.eventsPerMin)}/دقيقة — توليد محلي من مكتبتنا',
    ));
  } else {
    out.add(const MatchDecision(
      element: 'sfx',
      apply: false,
      reason: 'المرجع هادئ صوتيًا — المؤثرات ستبدو دخيلة',
    ));
  }

  // الألوان — بريسِت قابل للضبط دائمًا.
  out.add(MatchDecision(
    element: 'color',
    apply: true,
    reason: 'مزاج ${dna.color.mood} كبريسِت قابل للضبط',
  ));

  // الهوك — معالجة الثواني الأولى.
  if (dna.hook.style != 'statement' && p.durationSec > 10) {
    out.add(MatchDecision(
      element: 'hook',
      apply: true,
      reason: 'هوك ${dna.hook.style} على أول ${num(dna.hook.firstShotSec)} ثوانٍ',
    ));
  } else {
    out.add(MatchDecision(
      element: 'hook',
      apply: false,
      reason: dna.hook.style == 'statement'
          ? 'المرجع يبدأ بجملة عادية — لا نمط يُنسخ'
          : 'فيديو قصير جدًا — ابدأ بالمحتوى مباشرة',
    ));
  }

  return out;
}
