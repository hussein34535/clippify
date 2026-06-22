import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/copilot_provider.dart';
import '../../timeline/providers/timeline_provider.dart';
import '../../../core/models/timeline_models.dart';
import '../../../core/theme/app_theme.dart';
import 'ai_tool_palette.dart';
import 'subtitle_editor.dart';
import 'speed_ramp_editor.dart';
import 'color_grading_panel.dart';
import 'inspector_shared.dart';
import '../../../shared/providers/comments_provider.dart';
import '../../../shared/widgets/audio_mixer.dart';
import '../../ai/widgets/ai_panels.dart';
import '../../audio/widgets/audio_automation.dart';
import '../../tracking/tracker_system.dart';
import '../../color/pro_color_wheels.dart';
import '../../keyframes/curve_editor.dart';
import '../../ai/widgets/ai_suite_pro.dart';

class InspectorWidget extends ConsumerStatefulWidget {
  final String? selectedClipId;
  final String selectedClipType;
  final VoidCallback? onAutoCut;

  const InspectorWidget({
    super.key,
    required this.selectedClipId,
    required this.selectedClipType,
    this.onAutoCut,
  });

  @override
  ConsumerState<InspectorWidget> createState() => _InspectorWidgetState();
}

class _InspectorWidgetState extends ConsumerState<InspectorWidget>
    with TickerProviderStateMixin {

  late TabController _tabController;
  late TabController _videoTabController;
  late TabController _audioTabController;
  late TabController _aiTabController;
  final TextEditingController _chatController = TextEditingController();
  final TextEditingController _dashboardChatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final TextEditingController _commentTextController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _videoTabController = TabController(length: 3, vsync: this);
    _audioTabController = TabController(length: 3, vsync: this);
    _aiTabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _videoTabController.dispose();
    _audioTabController.dispose();
    _aiTabController.dispose();
    _chatController.dispose();
    _dashboardChatController.dispose();
    _chatScrollController.dispose();
    _commentTextController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final copilotData = ref.watch(copilotProvider);

    final selectedVideoClip = ref.watch(timelineProvider.select((data) {
      if (widget.selectedClipId != null && widget.selectedClipType == 'video') {
        for (var track in data.timeline.tracks.video) {
          for (var clip in track.clips) {
            if (clip.id == widget.selectedClipId) {
              return clip;
            }
          }
        }
      }
      return null;
    }));

    if (widget.selectedClipId != null && widget.selectedClipType == 'subtitle') {
      final selectedSubtitleClip = ref.watch(timelineProvider.select((data) {
        for (var track in data.timeline.tracks.subtitles) {
          for (var clip in track.clips) {
            if (clip.id == widget.selectedClipId) {
              return clip;
            }
          }
        }
        return null;
      }));
      if (selectedSubtitleClip != null) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(left: BorderSide(color: AppColors.divider)),
          ),
          child: SubtitleEditorWidget(clip: selectedSubtitleClip),
        );
      }
    }

    if (widget.selectedClipId == null) {
      return Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(left: BorderSide(color: AppColors.divider)),
        ),
        child: _buildDashboard(copilotData),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: const [
              Tab(text: 'فيديو', icon: Icon(Icons.video_settings_rounded, size: 14)),
              Tab(text: 'صوت', icon: Icon(Icons.volume_up_rounded, size: 14)),
              Tab(text: 'ذكاء اصطناعي', icon: Icon(Icons.auto_awesome_rounded, size: 14)),
              Tab(text: 'تعليقات', icon: Icon(Icons.comment_rounded, size: 14)),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildVideoTab(selectedVideoClip),
                selectedVideoClip != null ? _buildAudioTab(selectedVideoClip) : const InspectorPlaceholder(),
                _buildAITabContainer(selectedVideoClip, copilotData),
                _buildCommentsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard(CopilotStateData copilotData) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF7B2FF7)]),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(Icons.auto_awesome_rounded, size: 14, color: Colors.white),
              ),
              const SizedBox(width: 8),
              const Text(
                'AI Copilot',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...List.generate(6, (i) {
                final suggestions = ['تقطيع ذكي', 'إزالة الخلفية', 'تحسين الصوت', 'تتبع الكادر', 'ترجمة تلقائية', 'ضبط الألوان'];
                final icons = [Icons.content_cut_rounded, Icons.backup_table_rounded, Icons.hearing_rounded, Icons.center_focus_strong_rounded, Icons.translate_rounded, Icons.color_lens_rounded];
                return Card(
                  color: AppColors.card,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                      radius: 18,
                      child: Icon(icons[i], size: 18, color: AppColors.primary),
                    ),
                    title: Text(suggestions[i], style: const TextStyle(fontSize: 13, color: Colors.white)),
                    trailing: const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: AppColors.textMuted),
                    onTap: () {
                      ref.read(copilotProvider.notifier).sendPrompt(suggestions[i], ref);
                    },
                  ),
                );
              }),
              const SizedBox(height: 24),
              const Text('مساعد الذكاء الاصطناعي', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                          child: const Icon(Icons.psychology, size: 16, color: AppColors.primary),
                        ),
                        const SizedBox(width: 10),
                        const Text('المساعد الذكي', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('مرحباً! أنا مساعد Clippify الذكي. كيف يمكنني مساعدتك في تحرير الفيديو اليوم؟', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              Expanded(
                  child: TextField(
                    controller: _dashboardChatController,
                    decoration: InputDecoration(
                      hintText: 'اسأل المساعد الذكي...',
                      hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        ref.read(copilotProvider.notifier).sendPrompt(val.trim(), ref);
                        _dashboardChatController.clear();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primary,
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                    onPressed: () {
                      if (_dashboardChatController.text.trim().isNotEmpty) {
                        ref.read(copilotProvider.notifier).sendPrompt(_dashboardChatController.text.trim(), ref);
                        _dashboardChatController.clear();
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTransformTab(VideoClip clip) {
    final notifier = ref.read(timelineProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        InspectorSectionHeader(title: 'الموقع (Position)'),
        const SizedBox(height: 8),
        InspectorPropertySlider(
          label: 'الموقع X',
          value: clip.transform.position.x,
          min: -500, max: 500,
          onChanged: (v) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(transform: c.transform.copyWith(position: c.transform.position.copyWith(x: v)))),
        ),
        InspectorPropertySlider(
          label: 'الموقع Y',
          value: clip.transform.position.y,
          min: -500, max: 500,
          onChanged: (v) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(transform: c.transform.copyWith(position: c.transform.position.copyWith(y: v)))),
        ),
        const SizedBox(height: 16),
        InspectorSectionHeader(title: 'القياس (Scale)'),
        const SizedBox(height: 8),
        InspectorPropertySlider(
          label: 'العرض %',
          value: clip.transform.scale.x,
          min: 1, max: 200,
          onChanged: (v) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(transform: c.transform.copyWith(scale: c.transform.scale.copyWith(x: v)))),
        ),
        InspectorPropertySlider(
          label: 'الارتفاع %',
          value: clip.transform.scale.y,
          min: 1, max: 200,
          onChanged: (v) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(transform: c.transform.copyWith(scale: c.transform.scale.copyWith(y: v)))),
        ),
        const SizedBox(height: 16),
        InspectorSectionHeader(title: 'الدوران (Rotation)'),
        const SizedBox(height: 8),
        InspectorPropertySlider(
          label: 'زاوية الدوران',
          value: clip.transform.rotation,
          min: -180, max: 180,
          onChanged: (v) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(transform: c.transform.copyWith(rotation: v))),
        ),
      ],
    );
  }

  Widget _buildColorTab(VideoClip clip) {
    final notifier = ref.read(timelineProvider.notifier);
    return ColorGradingPanel(
      clip: clip,
      onChanged: (cg) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(colorGrading: cg)),
    );
  }

  Widget _buildProColorTab(VideoClip clip) {
    final notifier = ref.read(timelineProvider.notifier);
    return ProColorPanel(
      proColor: clip.proColor,
      basicColor: clip.colorGrading,
      onProChanged: (pc) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(proColor: pc)),
      onBasicChanged: (cg) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(colorGrading: cg)),
    );
  }

  Widget _buildAudioTab(VideoClip clip) {
    final notifier = ref.read(timelineProvider.notifier);
    final cd = clip.endTimeInTimeline - clip.startTimeInTimeline;

    return Column(
      children: [
        Container(
          color: AppColors.surface,
          child: TabBar(
            controller: _audioTabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: const [
              Tab(text: 'مؤثرات', icon: Icon(Icons.tune_rounded, size: 12)),
              Tab(text: 'أتمتة', icon: Icon(Icons.timeline_rounded, size: 12)),
              Tab(text: 'ميكسر', icon: Icon(Icons.equalizer, size: 12)),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _audioTabController,
            children: [
              _buildEffectsSubTab(clip, notifier, cd),
              _buildAutomationSubTab(clip, notifier, cd),
              _buildMixerSubTab(notifier),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEffectsSubTab(VideoClip clip, dynamic notifier, double clipDuration) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        InspectorSectionHeader(title: 'مؤثرات الصوت'),
        const SizedBox(height: 8),
        AudioEffectsRack(
          effectChain: clip.effectChain,
          onEffectChainChanged: (chain) {
            notifier.updateVideoClip(clip.id, (c) => c.copyWith(effectChain: chain));
          },
          clipDuration: clipDuration,
        ),
        const SizedBox(height: 16),
        InspectorSectionHeader(title: 'تحسينات الصوت'),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('عزل الصوت', style: TextStyle(fontSize: 12)),
          value: clip.aiFeatures.vocalIsolation,
          onChanged: (v) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(aiFeatures: c.aiFeatures.copyWith(vocalIsolation: v))),
          activeTrackColor: AppColors.primary,
        ),
        SwitchListTile(
          title: const Text('Auto Ducking', style: TextStyle(fontSize: 12)),
          value: clip.aiFeatures.autoDucking,
          onChanged: (v) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(aiFeatures: c.aiFeatures.copyWith(autoDucking: v))),
          activeTrackColor: AppColors.primary,
        ),
        const SizedBox(height: 16),
        SidechainCompressor(
          sourceTrack: null,
          threshold: 0.5,
          ratio: 4,
          attack: 0.002,
          release: 0.1,
          makeupGain: 0,
          onSourceTrackChanged: (_) {},
          onThresholdChanged: (_) {},
          onRatioChanged: (_) {},
          onAttackChanged: (_) {},
          onReleaseChanged: (_) {},
          onMakeupGainChanged: (_) {},
          gainReduction: 0.2,
        ),
        const SizedBox(height: 16),
        InspectorSectionHeader(title: 'سرعة التشغيل'),
        const SizedBox(height: 8),
        SpeedRampEditor(
          speedRamp: clip.speedRamp,
          clipDuration: clipDuration,
          onChanged: (ramp) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(speedRamp: ramp)),
        ),
      ],
    );
  }

  Widget _buildAutomationSubTab(VideoClip clip, dynamic notifier, double clipDuration) {
    final automationPoints = clip.automationLanes.isNotEmpty
        ? clip.automationLanes.map((lane) {
            final pts = lane['points'] as List<dynamic>? ?? [];
            return pts.map((p) => AutomationPoint.fromJson(p as Map<String, dynamic>)).toList();
          }).toList()
        : <List<AutomationPoint>>[];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        AutomationLane(
          parameterName: 'Volume',
          parameterId: 'volume',
          parameterMin: 0.0,
          parameterMax: 2.0,
          currentValue: clip.volume,
          points: automationPoints.isNotEmpty ? automationPoints[0] : [],
          onPointsChanged: (pts) {
            final lanes = List<Map<String, dynamic>>.from(clip.automationLanes);
            if (lanes.isEmpty) {
              lanes.add({'parameter': 'volume', 'points': pts.map((p) => p.toJson()).toList()});
            } else {
              lanes[0] = {'parameter': 'volume', 'points': pts.map((p) => p.toJson()).toList()};
            }
            notifier.updateVideoClip(clip.id, (c) => c.copyWith(automationLanes: lanes));
          },
          clipDuration: clipDuration > 0 ? clipDuration : 10.0,
          curveColor: AppColors.secondary,
        ),
        const SizedBox(height: 16),
        AutomationLane(
          parameterName: 'Pan',
          parameterId: 'pan',
          parameterMin: -1.0,
          parameterMax: 1.0,
          currentValue: 0.0,
          points: automationPoints.length > 1 ? automationPoints[1] : [],
          onPointsChanged: (pts) {
            final lanes = List<Map<String, dynamic>>.from(clip.automationLanes);
            while (lanes.length < 2) {
              lanes.add({'parameter': 'pan', 'points': <Map<String, dynamic>>[]});
            }
            lanes[1] = {'parameter': 'pan', 'points': pts.map((p) => p.toJson()).toList()};
            notifier.updateVideoClip(clip.id, (c) => c.copyWith(automationLanes: lanes));
          },
          clipDuration: clipDuration > 0 ? clipDuration : 10.0,
          curveColor: AppColors.warning,
        ),
        const SizedBox(height: 16),
        AutomationLane(
          parameterName: 'Bass EQ',
          parameterId: 'bass',
          parameterMin: 0.0,
          parameterMax: 1.0,
          currentValue: clip.bass,
          points: automationPoints.length > 2 ? automationPoints[2] : [],
          onPointsChanged: (pts) {
            final lanes = List<Map<String, dynamic>>.from(clip.automationLanes);
            while (lanes.length < 3) {
              lanes.add({'parameter': 'bass', 'points': <Map<String, dynamic>>[]});
            }
            lanes[2] = {'parameter': 'bass', 'points': pts.map((p) => p.toJson()).toList()};
            notifier.updateVideoClip(clip.id, (c) => c.copyWith(automationLanes: lanes));
          },
          clipDuration: clipDuration > 0 ? clipDuration : 10.0,
          curveColor: AppColors.primary,
        ),
        const SizedBox(height: 16),
        AutomationLane(
          parameterName: 'Treble EQ',
          parameterId: 'treble',
          parameterMin: 0.0,
          parameterMax: 1.0,
          currentValue: clip.treble,
          points: automationPoints.length > 3 ? automationPoints[3] : [],
          onPointsChanged: (pts) {
            final lanes = List<Map<String, dynamic>>.from(clip.automationLanes);
            while (lanes.length < 4) {
              lanes.add({'parameter': 'treble', 'points': <Map<String, dynamic>>[]});
            }
            lanes[3] = {'parameter': 'treble', 'points': pts.map((p) => p.toJson()).toList()};
            notifier.updateVideoClip(clip.id, (c) => c.copyWith(automationLanes: lanes));
          },
          clipDuration: clipDuration > 0 ? clipDuration : 10.0,
          curveColor: Colors.purpleAccent,
        ),
      ],
    );
  }

  Widget _buildMixerSubTab(dynamic notifier) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildLegacyEqSection(notifier),
        const SizedBox(height: 16),
        AudioMixerPro(
          trackIds: const ['master'],
          trackNames: const ['Master'],
        ),
      ],
    );
  }

  Widget _buildLegacyEqSection(dynamic notifier) {
    final timelineData = ref.watch(timelineProvider);
    VideoClip? clip;
    if (widget.selectedClipId != null && widget.selectedClipType == 'video') {
      for (var track in timelineData.timeline.tracks.video) {
        for (var c in track.clips) {
          if (c.id == widget.selectedClipId) {
            clip = c;
            break;
          }
        }
      }
    }
    if (clip == null) return const SizedBox.shrink();
    final clipId = clip.id;
    return AudioEQControls(
      bass: clip.bass, mid: clip.mid, treble: clip.treble,
      volume: clip.volume,
      onVolumeChanged: (v) => notifier.updateVideoClip(clipId, (c) => c.copyWith(volume: v)),
      onBassChanged: (v) => notifier.updateVideoClip(clipId, (c) => c.copyWith(bass: v)),
      onMidChanged: (v) => notifier.updateVideoClip(clipId, (c) => c.copyWith(mid: v)),
      onTrebleChanged: (v) => notifier.updateVideoClip(clipId, (c) => c.copyWith(treble: v)),
    );
  }

  Widget _buildKeyframesTab(VideoClip clip) {
    final notifier = ref.read(timelineProvider.notifier);
    final cd = clip.endTimeInTimeline - clip.startTimeInTimeline;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InspectorSectionHeader(title: 'Graph Editor'),
          const SizedBox(height: 8),
          Text('حرر keyframes بالجراف',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 16),
          CurveEditorWidget(
            allKeyframes: clip.transform.keyframes,
            clipDuration: cd,
            initialProperty: 'position_x',
            onChanged: (kfs) {
              notifier.updateVideoClip(clip.id, (c) => c.copyWith(
                  transform: c.transform.copyWith(keyframes: kfs)));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAITab(VideoClip clip) {
    final notifier = ref.read(timelineProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        InspectorSectionHeader(title: 'Smart Cut (قص ذكي)'),
        const SizedBox(height: 8),
        SmartCutPanel(videoPath: clip.sourcePath),
        const Divider(height: 24, color: AppColors.divider),
        InspectorSectionHeader(title: 'إزالة الخلفية'),
        const SizedBox(height: 8),
        BackgroundRemovalPanel(
          currentMethod: clip.aiFeatures.bgRemoveMethod,
          chromakeyColor: clip.aiFeatures.chromakeyColor,
          onMethodChanged: (v) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(aiFeatures: c.aiFeatures.copyWith(bgRemoveMethod: v))),
          onColorChanged: (v) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(aiFeatures: c.aiFeatures.copyWith(chromakeyColor: v))),
        ),
        const Divider(height: 24, color: AppColors.divider),
        InspectorSectionHeader(title: 'تتبع الكادر الذكي'),
        SwitchListTile(
          title: const Text('عزل الصوت', style: TextStyle(fontSize: 12)),
          value: clip.aiFeatures.vocalIsolation,
          onChanged: (v) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(aiFeatures: c.aiFeatures.copyWith(vocalIsolation: v))),
          activeTrackColor: AppColors.primary,
        ),
        SwitchListTile(
          title: const Text('خفض الضوضاء', style: TextStyle(fontSize: 12)),
          value: clip.aiFeatures.autoDucking,
          onChanged: (v) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(aiFeatures: c.aiFeatures.copyWith(autoDucking: v))),
          activeTrackColor: AppColors.primary,
        ),
      ],
    );
  }

  Widget _buildCopilotChat(CopilotStateData data) {
    return Column(
      children: [
        Expanded(
          child: data.messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.smart_toy_rounded, size: 48, color: AppColors.primary.withValues(alpha: 0.5)),
                      const SizedBox(height: 16),
                      const Text('اسأل المساعد الذكي', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _chatScrollController,
                  itemCount: data.messages.length,
                  itemBuilder: (context, index) {
                    final msg = data.messages[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Row(
                        mainAxisAlignment: msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                        children: [
                          Container(
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: msg.isUser ? AppColors.primary : AppColors.card,
                              borderRadius: BorderRadius.circular(12).copyWith(
                                bottomRight: msg.isUser ? const Radius.circular(0) : null,
                                bottomLeft: !msg.isUser ? const Radius.circular(0) : null,
                              ),
                            ),
                            child: Text(msg.text, style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  decoration: InputDecoration(
                    hintText: 'اسأل المساعد...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  onSubmitted: (val) {
                    if (val.trim().isNotEmpty) {
                      ref.read(copilotProvider.notifier).sendPrompt(val.trim(), ref);
                      _chatController.clear();
                      _scrollToBottom();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primary,
                child: IconButton(
                  icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                  onPressed: data.isLoading
                      ? null
                      : () {
                          if (_chatController.text.trim().isNotEmpty) {
                            ref.read(copilotProvider.notifier).sendPrompt(_chatController.text.trim(), ref);
                            _chatController.clear();
                            _scrollToBottom();
                          }
                        },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildViralTab() {
    final suggestions = [
      {'icon': Icons.trending_up_rounded, 'title': 'TikTok Trending Sounds', 'subtitle': 'أضف الأصوات الرائجة'},
      {'icon': Icons.speed_rounded, 'title': 'Fast Cut (كل 2 ثانية)', 'subtitle': 'قص الفيديو لمقاطع قصيرة'},
      {'icon': Icons.closed_caption_outlined, 'title': 'Auto Captions', 'subtitle': 'ترجمة تلقائية جذابة'},
      {'icon': Icons.animation_rounded, 'title': 'Transition Pack', 'subtitle': 'انتقالات عصرية'},
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        InspectorSectionHeader(title: 'توصيات Viral'),
        const SizedBox(height: 12),
        ...suggestions.map((s) => Card(
          color: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            onTap: () {
              ref.read(copilotProvider.notifier).sendPrompt(s['subtitle'] as String, ref);
              _aiTabController.animateTo(0);
            },
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              child: Icon(s['icon'] as IconData, size: 20, color: AppColors.primary),
            ),
            title: Text(s['title'] as String, style: const TextStyle(fontSize: 13, color: Colors.white)),
            subtitle: Text(s['subtitle'] as String, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ),
        )),
      ],
    );
  }

  Widget _buildCommentsTab() {
    final comments = ref.watch(commentsProvider);
    final notifier = ref.read(timelineProvider.notifier);
    final playhead = ref.read(timelineProvider).timeline.playheadSec;

    String formatTimecode(double totalSeconds) {
      final minutes = (totalSeconds / 60).floor();
      final seconds = (totalSeconds % 60).floor();
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }

    return Column(
      children: [
        Expanded(
          child: comments.isEmpty
              ? const Center(child: Text('لا توجد تعليقات', style: TextStyle(color: AppColors.textMuted)))
              : ListView.builder(
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final c = comments[index];
                    return Card(
                      color: AppColors.card,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                        side: const BorderSide(color: AppColors.border, width: 0.5),
                      ),
                      child: ListTile(
                        dense: true,
                        onTap: () => notifier.setPlayhead(c.timeSec),
                        leading: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            formatTimecode(c.timeSec),
                            style: const TextStyle(fontSize: 9, fontFamily: 'monospace', color: AppColors.primary, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(c.text, style: const TextStyle(fontSize: 11, color: Colors.white), textAlign: TextAlign.right),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 14, color: Colors.redAccent),
                          onPressed: () => ref.read(commentsProvider.notifier).removeComment(c.id),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.divider)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatTimecode(playhead),
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.primary, fontWeight: FontWeight.bold)),
                  const Text('إضافة تعليق', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentTextController,
                      decoration: InputDecoration(
                        hintText: 'نص التعليق...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        filled: true,
                        fillColor: AppColors.background,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primary,
                    child: IconButton(
                      icon: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                      onPressed: () {
                        if (_commentTextController.text.trim().isNotEmpty) {
                          ref.read(commentsProvider.notifier).addComment(playhead, _commentTextController.text.trim());
                          _commentTextController.clear();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVideoTab(VideoClip? clip) {
    if (clip == null) return const InspectorPlaceholder();
    return Column(
      children: [
        TabBar(
          controller: _videoTabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: 'التحويل'),
            Tab(text: 'الألوان'),
            Tab(text: 'التتبع'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _videoTabController,
            children: [
              _buildTransformAndKeyframesTab(clip),
              _buildProColorTab(clip),
              TrackingPanel(clip: clip),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTransformAndKeyframesTab(VideoClip clip) {
    final notifier = ref.read(timelineProvider.notifier);
    final cd = clip.endTimeInTimeline - clip.startTimeInTimeline;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        InspectorSectionHeader(title: 'الموقع (Position)'),
        const SizedBox(height: 8),
        InspectorPropertySlider(
          label: 'الموقع X',
          value: clip.transform.position.x,
          min: -500, max: 500,
          onChanged: (v) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(transform: c.transform.copyWith(position: c.transform.position.copyWith(x: v)))),
        ),
        InspectorPropertySlider(
          label: 'الموقع Y',
          value: clip.transform.position.y,
          min: -500, max: 500,
          onChanged: (v) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(transform: c.transform.copyWith(position: c.transform.position.copyWith(y: v)))),
        ),
        const SizedBox(height: 16),
        InspectorSectionHeader(title: 'القياس (Scale)'),
        const SizedBox(height: 8),
        InspectorPropertySlider(
          label: 'العرض %',
          value: clip.transform.scale.x,
          min: 1, max: 200,
          onChanged: (v) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(transform: c.transform.copyWith(scale: c.transform.scale.copyWith(x: v)))),
        ),
        InspectorPropertySlider(
          label: 'الارتفاع %',
          value: clip.transform.scale.y,
          min: 1, max: 200,
          onChanged: (v) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(transform: c.transform.copyWith(scale: c.transform.scale.copyWith(y: v)))),
        ),
        const SizedBox(height: 16),
        InspectorSectionHeader(title: 'الدوران (Rotation)'),
        const SizedBox(height: 8),
        InspectorPropertySlider(
          label: 'زاوية الدوران',
          value: clip.transform.rotation,
          min: -180, max: 180,
          onChanged: (v) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(transform: c.transform.copyWith(rotation: v))),
        ),
        const Divider(height: 32, color: AppColors.divider),
        InspectorSectionHeader(title: 'Keyframes (مخطط الحركة)'),
        const SizedBox(height: 8),
        const Text('حرر keyframes بالجراف', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        const SizedBox(height: 16),
        CurveEditorWidget(
          allKeyframes: clip.transform.keyframes,
          clipDuration: cd,
          initialProperty: 'position_x',
          onChanged: (kfs) {
            notifier.updateVideoClip(clip.id, (c) => c.copyWith(
                transform: c.transform.copyWith(keyframes: kfs)));
          },
        ),
      ],
    );
  }

  Widget _buildAITabContainer(VideoClip? clip, CopilotStateData copilotData) {
    return Column(
      children: [
        TabBar(
          controller: _aiTabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: 'مساعد AI'),
            Tab(text: 'أدوات ذكية'),
            Tab(text: 'Viral'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _aiTabController,
            children: [
              _buildCopilotChat(copilotData),
              _buildAIUtilitiesTab(clip),
              _buildViralTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAIUtilitiesTab(VideoClip? clip) {
    if (clip == null) return const InspectorPlaceholder();
    final notifier = ref.read(timelineProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SmartCutPanel(videoPath: clip.sourcePath),
        const Divider(height: 24, color: AppColors.divider),
        InspectorSectionHeader(title: 'إزالة الخلفية'),
        const SizedBox(height: 8),
        BackgroundRemovalPanel(
          currentMethod: clip.aiFeatures.bgRemoveMethod,
          chromakeyColor: clip.aiFeatures.chromakeyColor,
          onMethodChanged: (v) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(aiFeatures: c.aiFeatures.copyWith(bgRemoveMethod: v))),
          onColorChanged: (v) => notifier.updateVideoClip(clip.id, (c) => c.copyWith(aiFeatures: c.aiFeatures.copyWith(chromakeyColor: v))),
        ),
        const Divider(height: 24, color: AppColors.divider),
        AIProTab(videoPath: clip.sourcePath),
        const Divider(height: 24, color: AppColors.divider),
        AIToolPalette(selectedClipId: clip.id),
      ],
    );
  }
}
