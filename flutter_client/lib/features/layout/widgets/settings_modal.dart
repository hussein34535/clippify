import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/providers/theme_provider.dart';

class SettingsModal extends ConsumerStatefulWidget {
  const SettingsModal({super.key});

  @override
  ConsumerState<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends ConsumerState<SettingsModal>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _saving = false;
  late TabController _tabController;
  
  final _outputDirController = TextEditingController();
  final _nClipsController = TextEditingController();
  final _durationController = TextEditingController();
  final _pexelsKeyController = TextEditingController();
  final _pixabayKeyController = TextEditingController();

  String _subtitleStyle = 'TikTok Yellow';
  String _exportMode = 'ffmpeg';
  String _whisperModel = 'tiny';
  bool _translateToArabic = false;
  bool _autoBroll = false;
  int _autosaveIntervalMin = 5;
  int _cacheSizeMB = 500;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _outputDirController.dispose();
    _nClipsController.dispose();
    _durationController.dispose();
    _pexelsKeyController.dispose();
    _pixabayKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
    });
    final result = await ApiClient().getSettings();
    switch (result) {
      case Success(data: final settings):
        setState(() {
          _outputDirController.text = settings['output_dir'] as String? ?? './output';
          _nClipsController.text = (settings['n_clips'] ?? 5).toString();
          _durationController.text = (settings['duration'] ?? 60).toString();
          _pexelsKeyController.text = settings['pexels_api_key'] as String? ?? '';
          _pixabayKeyController.text = settings['pixabay_api_key'] as String? ?? '';
          
          _subtitleStyle = settings['subtitle_style'] as String? ?? 'TikTok Yellow';
          _exportMode = settings['export_mode'] as String? ?? 'ffmpeg';
          _whisperModel = settings['whisper_model'] as String? ?? 'tiny';
          _translateToArabic = settings['translate_to_arabic'] as bool? ?? false;
          _autoBroll = settings['auto_broll'] as bool? ?? false;
          _autosaveIntervalMin = settings['autosave_interval_min'] as int? ?? 5;
          _cacheSizeMB = settings['cache_size_mb'] as int? ?? 500;
          
          _loading = false;
        });
      case Failure(message: final msg):
        ref.read(toastProvider.notifier).error('فشل تحميل الإعدادات من السيرفر: $msg');
        setState(() {
          _loading = false;
        });
    }
  }

  Future<void> _saveSettings() async {
    setState(() {
      _saving = true;
    });
    try {
      final Map<String, dynamic> settingsData = {
        'output_dir': _outputDirController.text.trim(),
        'n_clips': int.tryParse(_nClipsController.text) ?? 5,
        'duration': int.tryParse(_durationController.text) ?? 60,
        'subtitle_style': _subtitleStyle,
        'export_mode': _exportMode,
        'whisper_model': _whisperModel,
        'translate_to_arabic': _translateToArabic,
        'auto_broll': _autoBroll,
        'pexels_api_key': _pexelsKeyController.text.trim(),
        'pixabay_api_key': _pixabayKeyController.text.trim(),
        'autosave_interval_min': _autosaveIntervalMin,
        'cache_size_mb': _cacheSizeMB,
      };

      final postResult = await ApiClient().postSettings(settingsData);
      switch (postResult) {
        case Success(data: true):
          ref.read(toastProvider.notifier).success('تم حفظ الإعدادات بنجاح! 💾');
          if (mounted) Navigator.pop(context, true);
        case Success(data: false):
          ref.read(toastProvider.notifier).error('فشل حفظ الإعدادات بالخادم.');
        case Failure(message: final msg):
          ref.read(toastProvider.notifier).error('خطأ أثناء حفظ الإعدادات: $msg');
      }
    } catch (e) {
      ref.read(toastProvider.notifier).error('خطأ أثناء حفظ الإعدادات: $e');
    } finally {
      setState(() {
        _saving = false;
      });
    }
  }

  Future<void> _clearCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('تنظيف الكاش 🧹', style: TextStyle(color: Colors.white, fontFamily: 'Outfit'), textAlign: TextAlign.right),
        content: const Text(
          'هل تريد حذف كافة الملفات المؤقتة ولفتات الكروما القديمة لتوفير مساحة على القرص؟',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تنظيف', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final res = await ApiClient().clearCache();
      switch (res) {
        case Success(data: final data):
          ref.read(toastProvider.notifier).info(data['message'] ?? 'تم تفريغ الذاكرة المؤقتة بنجاح.');
        case Failure(message: final msg):
          ref.read(toastProvider.notifier).error('فشل تنظيف الذاكرة المؤقتة: $msg');
      }
    } catch (e) {
      ref.read(toastProvider.notifier).error('فشل تنظيف الذاكرة المؤقتة: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(appPrefsProvider);
    final prefsNotifier = ref.read(appPrefsProvider.notifier);

    if (_loading) {
      return Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          side: const BorderSide(color: AppColors.border),
        ),
        child: const SizedBox(
          width: 300, height: 150,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(strokeWidth: 2),
                SizedBox(height: 12),
                Text('جاري تحميل الإعدادات...', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 620,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 48, offset: const Offset(0, 24)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: prefs.accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: prefs.accentColor.withValues(alpha: 0.3)),
                    ),
                    child: Icon(Icons.tune_rounded, color: prefs.accentColor, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('إعدادات Clippify', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontFamily: 'Inter')),
                        Text('تخصيص المظهر وإعدادات الذكاء الاصطناعي', style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'Inter')),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: const Icon(Icons.close_rounded, size: 14, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Tab Bar ─────────────────────────────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              padding: const EdgeInsets.all(3),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0, 1)),
                  ],
                ),
                labelColor: AppColors.textPrimary,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
                unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, fontFamily: 'Inter'),
                tabs: const [
                  Tab(text: '🎨  المظهر'),
                  Tab(text: '⚙️  الذكاء الاصطناعي'),
                ],
              ),
            ),

            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.borderSubtle),

            // ── Tab Views ───────────────────────────
            Flexible(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // ── Tab 1: Appearance ──────────────
                  _buildAppearanceTab(prefs, prefsNotifier),

                  // ── Tab 2: AI Settings ─────────────
                  _buildAISettingsTab(),
                ],
              ),
            ),

            // ── Footer (AI tab only) ────────────────
            AnimatedBuilder(
              animation: _tabController,
              builder: (_, __) {
                if (_tabController.index != 1) return const SizedBox.shrink();
                return Column(
                  children: [
                    const Divider(height: 1, color: AppColors.borderSubtle),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _saving ? null : _saveSettings,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: prefs.accentColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                                padding: const EdgeInsets.symmetric(vertical: 11),
                              ),
                              child: _saving
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
                                  : const Text('حفظ الإعدادات', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              side: const BorderSide(color: AppColors.border),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 20),
                            ),
                            child: const Text('إلغاء', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Appearance Tab ──────────────────────────
  Widget _buildAppearanceTab(AppPrefsState prefs, AppPrefsNotifier prefsNotifier) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Theme mode
          _sectionLabel('وضع العرض'),
          const SizedBox(height: 8),
          Row(
            children: [
              _ThemeModeChip(
                label: '🌑 داكن',
                selected: prefs.themeMode == AppThemeMode.dark,
                accent: prefs.accentColor,
                onTap: () => prefsNotifier.setTheme(AppThemeMode.dark),
              ),
              const SizedBox(width: 8),
              _ThemeModeChip(
                label: '☀️ فاتح',
                selected: prefs.themeMode == AppThemeMode.light,
                accent: prefs.accentColor,
                onTap: () => prefsNotifier.setTheme(AppThemeMode.light),
              ),
              const SizedBox(width: 8),
              _ThemeModeChip(
                label: '⬜ تباين',
                selected: prefs.themeMode == AppThemeMode.highContrast,
                accent: prefs.accentColor,
                onTap: () => prefsNotifier.setTheme(AppThemeMode.highContrast),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Font scale
          _sectionLabel('حجم الخط (${(prefs.fontScale * 100).round()}%)'),
          Slider(
            value: prefs.fontScale,
            min: 0.9,
            max: 1.1,
            divisions: 3,
            activeColor: prefs.accentColor,
            inactiveColor: AppColors.surfaceVariant,
            label: '${(prefs.fontScale * 100).round()}%',
            onChanged: (v) => prefsNotifier.setFontScale(v),
          ),

          const SizedBox(height: 24),
          const Divider(height: 1, color: AppColors.borderSubtle),
          const SizedBox(height: 16),

          // Preview swatch
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('معاينة مباشرة', style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'Inter')),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: prefs.accentColor,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        boxShadow: [BoxShadow(color: prefs.accentColor.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: const Text('زر أساسي', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Text('زر ثانوي', style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontFamily: 'Inter')),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── AI Settings Tab ─────────────────────────
  Widget _buildAISettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildTextSetting(label: 'مجلد حفظ مخرجات الريندر:', controller: _outputDirController, alignLeft: true),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildTextSetting(label: 'مدة كل مقطع (ثوانٍ):', controller: _durationController, isNumber: true)),
              const SizedBox(width: 16),
              Expanded(child: _buildTextSetting(label: 'عدد المقاطع الافتراضي:', controller: _nClipsController, isNumber: true)),
            ],
          ),
          const SizedBox(height: 12),
          _buildDropdownSetting(label: 'ستايل الترجمة الافتراضي:', value: _subtitleStyle, items: const ['TikTok Yellow', 'Cyberpunk Neon', 'Minimalist Clean'], onChanged: (val) => setState(() => _subtitleStyle = val!)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildDropdownSetting(label: 'نموذج Whisper:', value: _whisperModel, items: const ['tiny', 'base', 'small', 'medium', 'large-v3'], onChanged: (val) => setState(() => _whisperModel = val!))),
              const SizedBox(width: 16),
              Expanded(child: _buildDropdownSetting(label: 'تنسيق التصدير:', value: _exportMode, items: const ['ffmpeg', 'davinci'], onChanged: (val) => setState(() => _exportMode = val!))),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.borderSubtle),
          const SizedBox(height: 8),
          _buildSwitchSetting(label: 'ترجمة الكلام إلى العربية تلقائياً', value: _translateToArabic, onChanged: (val) => setState(() => _translateToArabic = val)),
          _buildSwitchSetting(label: 'تنزيل ودمج B-roll تلقائياً', value: _autoBroll, onChanged: (val) => setState(() => _autoBroll = val)),
          const SizedBox(height: 8),
          const Divider(height: 1, color: AppColors.borderSubtle),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildTextSetting(label: 'مفتاح Pixabay API:', controller: _pixabayKeyController, obscure: true, alignLeft: true)),
              const SizedBox(width: 16),
              Expanded(child: _buildTextSetting(label: 'مفتاح Pexels API:', controller: _pexelsKeyController, obscure: true, alignLeft: true)),
            ],
          ),
          const SizedBox(height: 12),
          _buildSliderSetting(
            label: 'مدة الحفظ التلقائي (دقائق)',
            value: _autosaveIntervalMin.toDouble(),
            min: 1, max: 30, divisions: 29,
            onChanged: (v) => setState(() => _autosaveIntervalMin = v.round()),
          ),
          const SizedBox(height: 12),
          _buildSliderSetting(
            label: 'حجم الكاش (MB)',
            value: _cacheSizeMB.toDouble(),
            min: 100, max: 2000, divisions: 19,
            onChanged: (v) => setState(() => _cacheSizeMB = v.round()),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.borderSubtle),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _clearCache,
              icon: const Icon(Icons.delete_sweep_rounded, size: 14, color: AppColors.destructive),
              label: const Text('تنظيف الملفات المؤقتة', style: TextStyle(color: AppColors.destructive, fontSize: 11)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.destructive.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) => Text(
    label,
    style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600, fontFamily: 'Inter', letterSpacing: 0.5),
  );

  Widget _buildTextSetting({
    required String label,
    required TextEditingController controller,
    bool isNumber = false,
    bool obscure = false,
    bool alignLeft = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: TextFormField(
            controller: controller,
            style: const TextStyle(fontSize: 11, color: Colors.white, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              isDense: true,
            ),
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            obscureText: obscure,
            textAlign: alignLeft ? TextAlign.left : (isNumber ? TextAlign.center : TextAlign.right),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownSetting({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: AppColors.card,
              items: items
                  .map((item) => DropdownMenuItem(value: item, child: Text(item, style: const TextStyle(fontSize: 11))))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchSetting({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final accent = ref.read(appPrefsProvider).accentColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: accent,
            activeThumbColor: Colors.white,
            inactiveTrackColor: AppColors.surfaceVariant,
            inactiveThumbColor: AppColors.textMuted,
          ),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildSliderSetting({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('$label (${value.toInt()})', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Slider(
          value: value.clamp(min, max),
          min: min, max: max, divisions: divisions,
          activeColor: ref.read(appPrefsProvider).accentColor,
          inactiveColor: AppColors.surfaceVariant,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  _ThemeModeChip
// ─────────────────────────────────────────────
class _ThemeModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _ThemeModeChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.15) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? accent : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? accent : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }
}
