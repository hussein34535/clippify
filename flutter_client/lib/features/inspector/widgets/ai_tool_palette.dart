import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/timeline_models.dart';
import '../../../core/theme/app_theme.dart';
import '../../timeline/providers/timeline_provider.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/providers/macro_provider.dart';

class ToolInfo {
  final String name;
  final String description;
  final String descriptionAr;
  final String category;
  final Map<String, dynamic> params;
  final bool requiresConfirmation;
  final bool destructive;

  ToolInfo({
    required this.name,
    required this.description,
    required this.descriptionAr,
    required this.category,
    required this.params,
    required this.requiresConfirmation,
    required this.destructive,
  });

  factory ToolInfo.fromJson(Map<String, dynamic> json) {
    return ToolInfo(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      descriptionAr: json['description_ar'] as String? ?? json['description'] as String? ?? '',
      category: json['category'] as String? ?? '',
      params: json['params'] as Map<String, dynamic>? ?? {},
      requiresConfirmation: json['requires_confirmation'] as bool? ?? false,
      destructive: json['destructive'] as bool? ?? false,
    );
  }
}

class AIToolPalette extends ConsumerStatefulWidget {
  final String? selectedClipId;

  const AIToolPalette({
    super.key,
    required this.selectedClipId,
  });

  @override
  ConsumerState<AIToolPalette> createState() => _AIToolPaletteState();
}

class _AIToolPaletteState extends ConsumerState<AIToolPalette> {
  Map<String, List<ToolInfo>> _tools = {};
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final Map<String, bool> _expandedCategories = {
    'timeline': true,
    'playback': false,
    'effects': false,
    'audio': false,
    'subtitles': false,
    'ai': false,
    'export': false,
  };
  String? _executingToolName;

  final Map<String, IconData> _categoryIcons = {
    'timeline': Icons.content_cut_rounded,
    'playback': Icons.play_circle_outline_rounded,
    'effects': Icons.auto_awesome_rounded,
    'audio': Icons.music_note_rounded,
    'subtitles': Icons.subtitles_rounded,
    'ai': Icons.bolt_rounded,
    'export': Icons.download_rounded,
  };

  final Map<String, String> _categoryLabels = {
    'timeline': 'التايملاين (40)',
    'playback': 'المشغل (25)',
    'effects': 'التأثيرات (35)',
    'audio': 'الصوت (25)',
    'subtitles': 'الترجمة (22)',
    'ai': 'ذكاء اصطناعي (46)',
    'export': 'التصدير (26)',
  };

  final Map<String, Color> _categoryColors = {
    'timeline': const Color(0xFF5E5CE6),
    'playback': const Color(0xFF34C759),
    'effects': const Color(0xFFFF9F0A),
    'audio': const Color(0xFFBF5AF2),
    'subtitles': const Color(0xFFFF453A),
    'ai': const Color(0xFF0A84FF),
    'export': const Color(0xFFFF375F),
  };

  @override
  void initState() {
    super.initState();
    _loadTools();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTools() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ApiClient().getAITools();
    switch (result) {
      case Success(data: final data):
        if (data['status'] == 'success') {
          final toolsMap = data['tools'] as Map<String, dynamic>? ?? {};
          final Map<String, List<ToolInfo>> parsedTools = {};
          
          toolsMap.forEach((category, list) {
            if (list is List) {
              parsedTools[category] = list
                  .map((t) => ToolInfo.fromJson(t as Map<String, dynamic>))
                  .toList();
            }
          });
          
          setState(() {
            _tools = parsedTools;
            _loading = false;
          });
        } else {
          setState(() {
            _error = 'فشل جلب أدوات الذكاء الاصطناعي من السيرفر.';
            _loading = false;
          });
        }
      case Failure(message: final msg):
        setState(() {
          _error = 'حدث خطأ أثناء الاتصال بالخادم: $msg';
          _loading = false;
        });
    }
  }

  Map<String, dynamic> _getDefaultArgs(ToolInfo tool) {
    final Map<String, dynamic> defaults = {};
    tool.params.forEach((k, v) {
      if (v is String) {
        if (v.contains('float') || v.contains('int')) {
          final rangeRegExp = RegExp(r'\(([0-9.-]+)\s*(?:to|and|-)\s*([0-9.-]+)');
          final match = rangeRegExp.firstMatch(v);
          if (match != null) {
            final min = double.tryParse(match.group(1) ?? '0') ?? 0.0;
            final max = double.tryParse(match.group(2) ?? '1') ?? 1.0;
            defaults[k] = (min + max) / 2.0;
          } else {
            defaults[k] = 0.5;
          }
        } else if (v.contains('boolean') || v == 'bool') {
          defaults[k] = true;
        } else if (v.contains('array') || v.contains('list')) {
          defaults[k] = [];
        } else {
          defaults[k] = v;
        }
      } else {
        defaults[k] = v;
      }
    });
    return defaults;
  }

  Future<void> _handleToolClick(ToolInfo tool) async {
    if (tool.destructive || tool.requiresConfirmation) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            tool.destructive ? '⚠️ عملية مدمرة' : 'تأكيد الإجراء',
            style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
            textAlign: TextAlign.right,
          ),
          content: Text(
            'هل أنت متأكد من تنفيذ: "${tool.descriptionAr}"؟\n\nلا يمكن التراجع عن هذه العملية بعد بدئها.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            textAlign: TextAlign.right,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء', style: TextStyle(color: AppColors.textMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                'تأكيد وتنفيذ',
                style: TextStyle(color: tool.destructive ? Colors.redAccent : AppColors.primary),
              ),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() {
      _executingToolName = tool.name;
    });

    try {
      final timelineState = ref.read(timelineProvider).timeline;
      final args = _getDefaultArgs(tool);
      if (tool.params.containsKey('clip_id') && widget.selectedClipId != null) {
        args['clip_id'] = widget.selectedClipId;
      }

      final response = await ApiClient().executeAIActions(
        [
          {
            'name': tool.name,
            'args': args,
          }
        ],
        timelineState.toJson(),
      );

      switch (response) {
        case Success(data: final data):
          if (data['status'] == 'success') {
            if (data['new_state'] != null) {
              final newState = TimelineState.fromJson(data['new_state'] as Map<String, dynamic>);
              ref.read(timelineProvider.notifier).updateTimelineState(newState);
            }
            
            ref.read(macroProvider.notifier).recordAction(tool.name, args);
            
            final messages = data['messages'] as List<dynamic>? ?? [];
            final summary = messages.isNotEmpty ? messages.join(' • ') : 'تم تنفيذ الأداة بنجاح';
            ref.read(toastProvider.notifier).success(summary);
          } else {
            final errors = data['errors'] is List 
                ? (data['errors'] as List).join('\n') 
                : 'فشل تنفيذ الإجراء بالباك إند.';
            ref.read(toastProvider.notifier).error('❌ $errors');
          }
        case Failure(message: final msg):
          ref.read(toastProvider.notifier).error('❌ $msg');
      }
    } catch (e) {
      ref.read(toastProvider.notifier).error('❌ حدث خطأ أثناء إرسال الطلب: $e');
    } finally {
      setState(() {
        _executingToolName = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // تصفية الأدوات بناءً على البحث
    final Map<String, List<ToolInfo>> filteredTools = {};
    int totalCount = 0;
    int filteredCount = 0;

    _tools.forEach((cat, list) {
      totalCount += list.length;
      final filteredList = list.where((t) {
        if (_searchQuery.trim().isEmpty) return true;
        final q = _searchQuery.toLowerCase();
        return t.name.toLowerCase().contains(q) ||
            t.description.toLowerCase().contains(q) ||
            t.descriptionAr.contains(_searchQuery);
      }).toList();

      if (filteredList.isNotEmpty) {
        filteredTools[cat] = filteredList;
        filteredCount += filteredList.length;
      }
    });

    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Text(
                      'لوحة الأدوات (AI Control)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '$filteredCount/$totalCount',
                    style: const TextStyle(fontSize: 9, color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),

          // ── Search ──
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _searchController,
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'ابحث في 219 أداة ذكاء اصطناعي...',
                    hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                    prefixIcon: const Icon(Icons.search_rounded, size: 14, color: AppColors.textMuted),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    filled: true,
                    fillColor: AppColors.card,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                    });
                  },
                ),
                if (widget.selectedClipId != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'الكليب المحدد: ${widget.selectedClipId!.substring(0, widget.selectedClipId!.length > 12 ? 12 : widget.selectedClipId!.length)}',
                        style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),

          // ── Tools List ──
          Expanded(
            child: _loading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(strokeWidth: 2),
                        SizedBox(height: 12),
                        Text('جاري تحميل الأدوات من السيرفر...', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      ],
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 24),
                              const SizedBox(height: 12),
                              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 11), textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _loadTools,
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.card),
                                child: const Text('إعادة المحاولة', style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                        ),
                      )
                    : filteredTools.isEmpty
                        ? const Center(
                            child: Text('لم يتم العثور على أدوات مطابقة.', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: filteredTools.length,
                            itemBuilder: (context, index) {
                              final category = filteredTools.keys.elementAt(index);
                              final list = filteredTools[category]!;
                              final isExpanded = _expandedCategories[category] == true || _searchQuery.isNotEmpty;
                              
                              final icon = _categoryIcons[category] ?? Icons.settings;
                              final color = _categoryColors[category] ?? Colors.white;
                              final label = _categoryLabels[category] ?? category;

                              return Card(
                                color: AppColors.card,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: const BorderSide(color: AppColors.border, width: 0.5),
                                ),
                                margin: const EdgeInsets.only(bottom: 8),
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  children: [
                                    ListTile(
                                      onTap: () {
                                        setState(() {
                                          _expandedCategories[category] = !isExpanded;
                                        });
                                      },
                                      dense: true,
                                      leading: Icon(icon, color: color, size: 16),
                                      title: Text(
                                        label,
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                        textAlign: TextAlign.right,
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('${list.length}', style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                                          const SizedBox(width: 4),
                                          Icon(
                                            isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                            size: 14,
                                            color: AppColors.textMuted,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isExpanded) ...[
                                      const Divider(height: 1, color: AppColors.divider),
                                      ...list.map((tool) {
                                        final isRunning = _executingToolName == tool.name;
                                        return InkWell(
                                          onTap: isRunning ? null : () => _handleToolClick(tool),
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            decoration: const BoxDecoration(
                                              border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
                                            ),
                                            child: Row(
                                              children: [
                                                if (isRunning)
                                                  const SizedBox(
                                                    width: 12,
                                                    height: 12,
                                                    child: CircularProgressIndicator(strokeWidth: 1.5),
                                                  )
                                                else
                                                  Icon(Icons.play_arrow_rounded, size: 12, color: color.withValues(alpha: 0.5)),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.end,
                                                    children: [
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.end,
                                                        children: [
                                                          if (tool.destructive) ...[
                                                            Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                              decoration: BoxDecoration(
                                                                color: Colors.redAccent.withValues(alpha: 0.15),
                                                                borderRadius: BorderRadius.circular(4),
                                                              ),
                                                              child: const Text(
                                                                'حساس',
                                                                style: TextStyle(fontSize: 7, color: Colors.redAccent, fontWeight: FontWeight.bold),
                                                              ),
                                                            ),
                                                            const SizedBox(width: 6),
                                                          ],
                                                          Flexible(
                                                            child: Text(
                                                              tool.descriptionAr,
                                                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white),
                                                              textAlign: TextAlign.right,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        tool.name,
                                                        style: const TextStyle(fontSize: 8.5, fontFamily: 'monospace', color: AppColors.textMuted),
                                                        textAlign: TextAlign.right,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8.0),
            color: AppColors.card,
            child: const Text(
              'اضغط على أي أداة لتنفيذها فورياً. العمليات الحساسة تظهر نافذة تأكيد.',
              style: TextStyle(fontSize: 9, color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
