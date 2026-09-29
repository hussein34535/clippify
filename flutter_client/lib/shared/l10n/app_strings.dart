import 'dart:ui';

/// Lightweight hand-rolled localization layer (no gen_l10n / no SDK deps).
///
/// Usage inside widgets: `final l10n = context.l10n; l10n.t('key')`.
/// Fallback chain: en[key] → ar[key] → key itself.
class L10n {
  final Locale locale;

  const L10n(this.locale);

  static const Locale fallbackLocale = Locale('ar');

  /// Arabic strings — EXACT copies of the pre-existing UI literals
  /// (zero visual diff for current users).
  static const Map<String, String> ar = {
    // ── common ──
    'common_ok': 'حسناً',
    'common_cancel': 'إلغاء',
    'common_save': 'حفظ',
    'common_close': 'إغلاق',
    'common_retry': 'إعادة المحاولة',
    'common_delete': 'حذف',
    'common_share': 'مشاركة',
    'common_back': 'رجوع',
    // ── language / settings ──
    'settings_language': 'اللغة',
    'lang_arabic': 'العربية',
    'lang_english': 'الإنجليزية',
    'lang_system': 'النظام',
    // ── wizard ──
    'wizard_title': '🪄 المونتاج التلقائي الذكي',
    'wizard_step_content': 'المحتوى',
    'wizard_step_shape': 'الشكل',
    'wizard_step_style': 'الستايل',
    'wizard_continue': 'متابعة',
    'wizard_start': '🚀 ابدأ المونتاج',
    'wizard_section_content_type': 'نوع المحتوى',
    'wizard_section_platform': 'منصة النشر',
    'wizard_content_auto': 'اكتشاف تلقائي ✨',
    'wizard_content_podcast': 'بودكاست',
    'wizard_content_comedy': 'كوميديا',
    'wizard_content_educational': 'تعليمي',
    'wizard_content_motivation': 'تحفيز',
    'wizard_content_interview': 'مقابلة',
    'wizard_content_awareness': 'توعوي',
    'wizard_content_gaming': 'جيمنج',
    'wizard_platform_tiktok': 'تيك توك',
    'wizard_platform_shorts': 'شورتس',
    'wizard_platform_reels': 'ريلز',
    'wizard_platform_square': 'مربع ١:١',
    'wizard_caption_default': 'افتراضي ذكي',
    'wizard_label_caption_theme': 'ثيم الكابشن',
    'wizard_n_clips': 'عدد المقاطع',
    'unit_clips': 'مقاطع',
    'wizard_clip_duration': 'مدة كل مقطع',
    'unit_seconds': 'ثانية',
    'wizard_translate_arabic': 'ترجمة الكابشن للعربية 🌍',
    'wizard_music': '🎵 إضافة موسيقى',
    'wizard_broll': '🎬 لقطات B-Roll',
    'wizard_instructions_hint': 'مثال: ركّز على اللقطات السريعة وضيف موسيقى حماسية...',
    'wizard_error_start_failed':
        'فشل بدء المونتاج — تأكد من تشغيل الباك إند ومن توفر رصيد كافٍ.',
    // ── progress ──
    'progress_title': '⏳ جاري المونتاج الذكي...',
    'progress_session_prefix': 'جلسة',
    'stage_queued': 'انتظار',
    'stage_transcribing': 'تفريغ الصوت',
    'stage_understanding': 'فهم الفيديو 🧠',
    'stage_selecting': 'اختيار أفضل اللحظات',
    'stage_hooks': 'صياغة الهوك',
    'stage_effects': 'تخطيط المؤثرات',
    'stage_rendering': 'الرندر النهائي',
    'stage_compiling': 'الدمج',
    'progress_disconnect': 'انقطع الاتصال دون نتيجة نهائية.',
    'progress_stalled': 'لم تصل تحديثات منذ 90 ثانية — تحقق من الخادم.',
    'progress_cancel_confirm_title': 'إلغاء عملية المونتاج؟',
    'progress_cancel_confirm_body': 'سيتم إيقاف العملية الحالية ولن تصل إلى النتائج.',
    'progress_keep_going': 'تراجع',
    'progress_confirm_cancel': 'تأكيد الإلغاء',
    'progress_cancel_button': 'إلغاء العملية',
    'progress_error_title': 'حدث خطأ أثناء المونتاج',
    'progress_retry': '🔁 إعادة المحاولة',
    'progress_restart_failed':
        'فشل إعادة بدء العملية — تحقق من الخادم وحصتك.',
    // ── results ──
    'results_title': '🎬 النتائج الفيروسية',
    'results_empty': 'لا توجد نتائج بعد.',
    'results_export_all': '⬇️ تصدير الكل',
    'results_add_all': '➕ إضافة الكل للتايملاين',
    'results_added_many_toast': 'تمت إضافة {n} مقاطع للتايملاين 🎬',
    'results_added_one_toast': 'أُضيف المقطع للتايملاين ➕',
    'results_preview_btn': '👁 معاينة',
    'results_save_btn': '💾 حفظ',
    'results_to_timeline_btn': '➕ للتايملاين',
    'results_no_hook': 'بدون هوك',
    'results_duration_badge': '⏱ {v}ث',
    'results_pick_save_dir': 'اختر مجلد الحفظ',
    'results_save_dialog_title': 'حفظ المقطع',
    'results_file_name_label': 'اسم الملف',
    'results_saved_toast': 'تم حفظ: {name} ✅',
    'results_save_failed': 'فشل الحفظ: {error}',
    'results_export_dir_title': 'مجلد تصدير الكل',
    'results_exported_toast': 'تم تصدير {n} مقاطع إلى {dir} 📦',
    'results_no_local_files': 'لا توجد ملفات محلية قابلة للتصدير.',
    'results_partial_export_toast': 'صُدّر {n} مقاطع، وفشل {failed}.',
    'results_preview_local_only': 'المعاينة متاحة للملفات المحلية على Windows فقط.',
    'results_file_missing': 'الملف غير موجود: {path}',
    'results_save_requires_local': 'الحفظ يتطلب ملفاً محلياً على Windows.',
    'preview_title': '👁 معاينة: {name}',
    // ── auth ──
    'auth_welcome': 'مرحباً بك في Clippify',
    'auth_login_subtitle': 'سجّل الدخول للمتابعة إلى مساحة عملك',
    'auth_register_subtitle': 'أنشئ حساباً جديداً للبدء',
    'auth_tab_login': 'تسجيل الدخول',
    'auth_tab_register': 'حساب جديد',
    'auth_field_name': 'الاسم',
    'auth_field_email': 'البريد الإلكتروني',
    'auth_field_password': 'كلمة المرور',
    'auth_err_name_required': 'أدخل اسمك',
    'auth_err_invalid_email': 'بريد غير صالح',
    'auth_err_short_password': '٦ أحرف على الأقل',
    'auth_skip': 'تخطى مؤقتاً',
    'auth_btn_login': 'تسجيل الدخول',
    'auth_btn_register': 'إنشاء الحساب',
    'auth_unexpected_error': 'حدث خطأ غير متوقع',
    // ── profile ──
    'profile_not_signed_in': 'لم تقم بتسجيل الدخول',
    'profile_logout_confirm_title': 'تسجيل الخروج',
    'profile_logout_confirm_body': 'هل أنت متأكد أنك تريد تسجيل الخروج؟',
    'profile_logout_confirm_btn': 'خروج',
    'profile_credits_used': 'الأرصدة المستخدمة',
    'profile_logout_btn': 'تسجيل الخروج',
  };

  /// English strings — natural product English.
  static const Map<String, String> en = {
    // ── common ──
    'common_ok': 'OK',
    'common_cancel': 'Cancel',
    'common_save': 'Save',
    'common_close': 'Close',
    'common_retry': 'Retry',
    'common_delete': 'Delete',
    'common_share': 'Share',
    'common_back': 'Back',
    // ── language / settings ──
    'settings_language': 'Language',
    'lang_arabic': 'العربية',
    'lang_english': 'English',
    'lang_system': 'System',
    // ── wizard ──
    'wizard_title': '🪄 Smart Auto Edit',
    'wizard_step_content': 'Content',
    'wizard_step_shape': 'Format',
    'wizard_step_style': 'Style',
    'wizard_continue': 'Continue',
    'wizard_start': '🚀 Start Editing',
    'wizard_section_content_type': 'Content type',
    'wizard_section_platform': 'Publishing platform',
    'wizard_content_auto': 'Auto-detect ✨',
    'wizard_content_podcast': 'Podcast',
    'wizard_content_comedy': 'Comedy',
    'wizard_content_educational': 'Educational',
    'wizard_content_motivation': 'Motivation',
    'wizard_content_interview': 'Interview',
    'wizard_content_awareness': 'Awareness',
    'wizard_content_gaming': 'Gaming',
    'wizard_platform_tiktok': 'TikTok',
    'wizard_platform_shorts': 'Shorts',
    'wizard_platform_reels': 'Reels',
    'wizard_platform_square': 'Square 1:1',
    'wizard_caption_default': 'Smart default',
    'wizard_label_caption_theme': 'Caption theme',
    'wizard_n_clips': 'Number of clips',
    'unit_clips': 'clips',
    'wizard_clip_duration': 'Clip duration',
    'unit_seconds': 'sec',
    'wizard_translate_arabic': 'Translate captions to Arabic 🌍',
    'wizard_music': '🎵 Add music',
    'wizard_broll': '🎬 B-Roll footage',
    'wizard_instructions_hint':
        'e.g. focus on fast cuts and add upbeat music...',
    'wizard_error_start_failed':
        'Failed to start editing — make sure the backend is running and you have enough credits.',
    // ── progress ──
    'progress_title': '⏳ Smart editing in progress...',
    'progress_session_prefix': 'Session',
    'stage_queued': 'Queued',
    'stage_transcribing': 'Transcribing audio',
    'stage_understanding': 'Understanding the video 🧠',
    'stage_selecting': 'Picking the best moments',
    'stage_hooks': 'Crafting hooks',
    'stage_effects': 'Planning effects',
    'stage_rendering': 'Final render',
    'stage_compiling': 'Compiling',
    'progress_disconnect': 'Connection lost without a final result.',
    'progress_stalled': 'No updates for 90 seconds — check the server.',
    'progress_cancel_confirm_title': 'Cancel this edit?',
    'progress_cancel_confirm_body':
        'The current job will be stopped and you will not reach the results.',
    'progress_keep_going': 'Never mind',
    'progress_confirm_cancel': 'Yes, cancel',
    'progress_cancel_button': 'Cancel job',
    'progress_error_title': 'Something went wrong while editing',
    'progress_retry': '🔁 Try again',
    'progress_restart_failed':
        'Could not restart the job — check the server and your credits.',
    // ── results ──
    'results_title': '🎬 Viral Results',
    'results_empty': 'No results yet.',
    'results_export_all': '⬇️ Export all',
    'results_add_all': '➕ Add all to timeline',
    'results_added_many_toast': 'Added {n} clips to the timeline 🎬',
    'results_added_one_toast': 'Clip added to the timeline ➕',
    'results_preview_btn': '👁 Preview',
    'results_save_btn': '💾 Save',
    'results_to_timeline_btn': '➕ To timeline',
    'results_no_hook': 'No hook',
    'results_duration_badge': '⏱ {v}s',
    'results_pick_save_dir': 'Choose save folder',
    'results_save_dialog_title': 'Save clip',
    'results_file_name_label': 'File name',
    'results_saved_toast': 'Saved: {name} ✅',
    'results_save_failed': 'Save failed: {error}',
    'results_export_dir_title': 'Export-all folder',
    'results_exported_toast': 'Exported {n} clips to {dir} 📦',
    'results_no_local_files': 'No local files available for export.',
    'results_partial_export_toast': 'Exported {n} clips, {failed} failed.',
    'results_preview_local_only':
        'Preview is only available for local files on Windows.',
    'results_file_missing': 'File not found: {path}',
    'results_save_requires_local': 'Saving requires a local file on Windows.',
    'preview_title': '👁 Preview: {name}',
    // ── auth ──
    'auth_welcome': 'Welcome to Clippify',
    'auth_login_subtitle': 'Sign in to continue to your workspace',
    'auth_register_subtitle': 'Create a new account to get started',
    'auth_tab_login': 'Sign in',
    'auth_tab_register': 'New account',
    'auth_field_name': 'Name',
    'auth_field_email': 'Email',
    'auth_field_password': 'Password',
    'auth_err_name_required': 'Enter your name',
    'auth_err_invalid_email': 'Invalid email address',
    'auth_err_short_password': 'At least 6 characters',
    'auth_skip': 'Skip for now',
    'auth_btn_login': 'Sign in',
    'auth_btn_register': 'Create account',
    'auth_unexpected_error': 'An unexpected error occurred',
    // ── profile ──
    'profile_not_signed_in': "You're not signed in",
    'profile_logout_confirm_title': 'Log out',
    'profile_logout_confirm_body': 'Are you sure you want to log out?',
    'profile_logout_confirm_btn': 'Log out',
    'profile_credits_used': 'Credits used',
    'profile_logout_btn': 'Log out',
  };

  bool get _useEnglish =>
      locale.languageCode.toLowerCase().startsWith('en');

  /// Translate [key]; unknown keys fall back to the Arabic value, then to the
  /// key itself (never throws).
  String t(String key) {
    if (_useEnglish) {
      final v = en[key];
      if (v != null) return v;
    }
    return ar[key] ?? key;
  }

  /// Translate with `{token}` substitution.
  String tf(String key, [Map<String, String> params = const {}]) {
    var s = t(key);
    params.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }
}
