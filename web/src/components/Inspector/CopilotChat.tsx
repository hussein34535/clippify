import { useState, useRef, useEffect } from 'react';
import axios from 'axios';
import { Send, Sparkles, MessageSquare, AlertCircle, Shield, X, Check, ChevronRight } from 'lucide-react';
import { API_BASE } from '../../api';
import { useStore } from '../../store';

interface Message {
  sender: 'user' | 'assistant';
  text: string;
  isError?: boolean;
  actions?: AIAction[];
  pendingConfirmation?: boolean;
}

interface AIAction {
  name: string;
  args: Record<string, any>;
  description?: string;
  descriptionAr?: string;
}

interface ConfirmationGroup {
  trusted: AIAction[];
  destructive: AIAction[];
}

interface CopilotChatProps {
  onApplyActionPlan?: (actions: AIAction[]) => void;
}

const QUICK_COMMANDS = [
  'احذف الكليب المحدد',
  'زوّم التايملاين لـ fit',
  'فعّل Loop',
  'حط Aspect ratio 9:16',
  'ابحث عن B-roll عن "نجاح"',
  'اقطع عند البلاي هيد',
  'اقلب الألوان لـ Cinematic',
  'صدّر الفيديو 1080p',
];

function getCategory(name: string): string {
  return name.split('.')[0] || 'other';
}

function getToolLabel(name: string): string {
  const labels: Record<string, string> = {
    'timeline.delete_clip': 'حذف الكليب',
    'timeline.ripple_delete': 'حذف مع سد الفجوة',
    'timeline.split_clip': 'قص عند نقطة',
    'timeline.razor_at_playhead': 'قص الكل عند البلاي هيد',
    'timeline.set_zoom_level': 'زووم التايملاين',
    'timeline.zoom_to_fit': 'زووم لـ fit',
    'timeline.set_in_point': 'نقطة In',
    'timeline.set_out_point': 'نقطة Out',
    'timeline.toggle_magnetic': 'Magnetic',
    'timeline.set_snap_mode': 'وضع السناب',
    'timeline.lock_track': 'قفل تراك',
    'timeline.hide_track': 'إخفاء تراك',
    'timeline.solo_track': 'Solo تراك',
    'timeline.freeze_frame': 'تجميد فريم',
    'timeline.reverse_clip': 'عكس الكليب',
    'timeline.add_marker': 'إضافة Marker',
    'timeline.add_chapter_marker': 'إضافة Chapter',
    'playback.play': 'تشغيل',
    'playback.pause': 'إيقاف',
    'playback.toggle_play': 'تشغيل/إيقاف',
    'playback.seek': 'انتقال لوقت',
    'playback.frame_step_forward': '+1 فريم',
    'playback.frame_step_backward': '-1 فريم',
    'playback.skip_forward_5s': '+5 ثواني',
    'playback.skip_backward_5s': '-5 ثواني',
    'playback.toggle_loop': 'Loop',
    'playback.set_aspect_ratio': 'Aspect Ratio',
    'playback.set_fit_mode': 'وضع الاحتواء',
    'playback.toggle_fullscreen': 'ملء الشاشة',
    'playback.toggle_mute': 'كتم الصوت',
    'playback.set_volume': 'مستوى الصوت',
    'effects.set_brightness': 'السطوع',
    'effects.set_contrast': 'التباين',
    'effects.set_saturation': 'التشبع',
    'effects.set_opacity': 'الشفافية',
    'effects.set_exposure': 'التعرض',
    'effects.set_temperature': 'حرارة اللون',
    'effects.apply_lut': 'LUT',
    'effects.apply_blur': 'ضبابية',
    'effects.apply_sharpen': 'حدة',
    'effects.apply_vignette': 'Vignette',
    'effects.apply_film_grain': 'حبيبات فيلم',
    'effects.apply_vhs': 'VHS',
    'effects.apply_glow': 'توهج',
    'effects.reset_color': 'إعادة تعيين اللون',
    'effects.warp_stabilize': 'تثبيت',
    'audio.adjust_volume': 'مستوى الصوت',
    'audio.apply_eq': 'EQ',
    'audio.apply_compressor': 'Compressor',
    'audio.apply_reverb': 'Reverb',
    'audio.apply_delay': 'Delay',
    'audio.normalize_loudness': 'تطبيع الصوت',
    'audio.noise_reduction': 'إزالة الضوضاء',
    'audio.ducking': 'Ducking',
    'audio.set_fade_in': 'Fade In',
    'audio.set_fade_out': 'Fade Out',
    'audio.voice_isolation': 'عزل الصوت',
    'subtitles.set_animation': 'حركة الترجمة',
    'subtitles.set_alignment': 'محاذاة',
    'subtitles.apply_template': 'قالب',
    'subtitles.apply_style': 'ستايل',
    'subtitles.translate': 'ترجمة',
    'subtitles.toggle_burn_in': 'Burn-in',
    'subtitles.toggle_karaoke': 'Karaoke',
    'subtitles.generate_from_audio': 'توليد من الصوت',
    'export.render': 'تصدير',
    'export.upload_youtube': 'رفع يوتيوب',
    'export.upload_tiktok': 'رفع تيك توك',
    'ai.auto_cut_silences': 'قص الصمت تلقائياً',
    'ai.auto_framing': 'تتبع تلقائي',
    'ai.remove_filler_words': 'إزالة Filler Words',
    'ai.remove_background': 'إزالة الخلفية',
    'ai.beat_sync': 'مزامنة الإيقاع',
    'ai.score_virality': 'Viral Score',
    'ai.generate_thumbnail': 'توليد Thumbnail',
    'ai.generate_voiceover': 'توليد Voice-over',
    'ai.suggest_brolls': 'اقتراح B-roll',
    'ai.detect_scenes': 'كشف المشاهد',
  };
  return labels[name] || name;
}

function describeAction(action: AIAction): string {
  const label = getToolLabel(action.name);
  const args = action.args;
  const parts: string[] = [label];

  if (args.clip_id) parts.push(`(كليب: ${args.clip_id.slice(0, 6)})`);
  if (args.time !== undefined) parts.push(`@ ${args.time}ث`);
  if (args.track_id) parts.push(`(تراك: ${args.track_id})`);
  if (args.brightness !== undefined) parts.push(`= ${args.brightness}`);
  if (args.contrast !== undefined) parts.push(`= ${args.contrast}`);
  if (args.saturation !== undefined) parts.push(`= ${args.saturation}`);
  if (args.opacity !== undefined) parts.push(`= ${args.opacity}`);
  if (args.exposure !== undefined) parts.push(`= ${args.exposure}`);
  if (args.temperature !== undefined) parts.push(`= ${args.temperature}`);
  if (args.volume !== undefined && typeof args.volume === 'number' && args.volume <= 2) parts.push(`= ${args.volume}`);
  if (args.ratio) parts.push(`= ${args.ratio}`);
  if (args.mode) parts.push(`= ${args.mode}`);
  if (args.enabled !== undefined) parts.push(args.enabled ? '(تشغيل)' : '(إيقاف)');
  if (args.pixels_per_second) parts.push(`= ${args.pixels_per_second}px/s`);
  if (args.duration) parts.push(`(${args.duration}ث)`);
  if (args.preset) parts.push(`(${args.preset})`);
  if (args.format) parts.push(`(${args.format})`);
  if (args.lut_path) parts.push(`(${args.lut_path.split(/[\\/]/).pop()})`);

  return parts.join(' ');
}

interface ConfirmationDialogProps {
  trusted: AIAction[];
  destructive: AIAction[];
  onApprove: (approved: AIAction[]) => void;
  onCancel: () => void;
}

function ConfirmationDialog({ trusted, destructive, onApprove, onCancel }: ConfirmationDialogProps) {
  const [approvedDestructive, setApprovedDestructive] = useState<Set<string>>(new Set());
  const [approvedTrusted, setApprovedTrusted] = useState(true);

  const handleApprove = () => {
    const final: AIAction[] = [];
    if (approvedTrusted) final.push(...trusted);
    destructive.forEach(a => {
      if (approvedDestructive.has(a.name + JSON.stringify(a.args))) {
        final.push(a);
      }
    });
    onApprove(final);
  };

  const toggleDestructive = (action: AIAction) => {
    const key = action.name + JSON.stringify(action.args);
    const newSet = new Set(approvedDestructive);
    if (newSet.has(key)) newSet.delete(key);
    else newSet.add(key);
    setApprovedDestructive(newSet);
  };

  return (
    <div className="fixed inset-0 z-[200] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm" onClick={onCancel}>
      <div
        className="w-full max-w-md max-h-[80vh] rounded-2xl shadow-2xl flex flex-col"
        style={{ background: 'var(--bg-surface-1)', border: '1px solid var(--border-default)' }}
        onClick={e => e.stopPropagation()}
        dir="rtl"
      >
        <div className="p-4 border-b flex items-center justify-between" style={{ borderColor: 'var(--border-subtle)' }}>
          <h3 className="text-sm font-bold flex items-center gap-2" style={{ color: 'var(--accent)' }}>
            <Shield className="w-4 h-4" />
            مراجعة الإجراءات
          </h3>
          <button onClick={onCancel} className="opacity-60 hover:opacity-100">
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto p-4 space-y-3 text-right">
          {trusted.length > 0 && (
            <div>
              <div className="flex items-center gap-2 mb-2">
                <input
                  type="checkbox"
                  checked={approvedTrusted}
                  onChange={e => setApprovedTrusted(e.target.checked)}
                  className="w-4 h-4 cursor-pointer"
                />
                <span className="text-xs font-semibold" style={{ color: 'var(--text-secondary)' }}>
                  إجراءات آمنة ({trusted.length}) — هتنفذ تلقائي
                </span>
              </div>
              <div className="space-y-1.5 mr-6">
                {trusted.map((a, i) => (
                  <div
                    key={i}
                    className="flex items-center gap-2 p-2 rounded-lg text-[11px]"
                    style={{ background: 'var(--bg-surface-2)' }}
                  >
                    <ChevronRight className="w-3 h-3 opacity-40 flex-shrink-0" />
                    <span style={{ color: 'var(--text-primary)' }}>{describeAction(a)}</span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {destructive.length > 0 && (
            <div>
              <div className="text-xs font-semibold mb-2" style={{ color: '#f59e0b' }}>
                إجراءات حساسة ({destructive.length}) — محتاجة موافقتك
              </div>
              <div className="space-y-1.5">
                {destructive.map((a, i) => {
                  const key = a.name + JSON.stringify(a.args);
                  return (
                    <label
                      key={i}
                      className="flex items-center gap-2 p-2 rounded-lg text-[11px] cursor-pointer hover:opacity-80"
                      style={{ background: 'rgba(245, 158, 11, 0.08)', border: '1px solid rgba(245, 158, 11, 0.3)' }}
                    >
                      <input
                        type="checkbox"
                        checked={approvedDestructive.has(key)}
                        onChange={() => toggleDestructive(a)}
                        className="w-4 h-4 cursor-pointer"
                      />
                      <span style={{ color: 'var(--text-primary)' }}>{describeAction(a)}</span>
                    </label>
                  );
                })}
              </div>
            </div>
          )}
        </div>

        <div className="p-3 border-t flex gap-2" style={{ borderColor: 'var(--border-subtle)' }}>
          <button
            onClick={onCancel}
            className="flex-1 px-4 py-2 rounded-lg text-xs font-semibold border"
            style={{ background: 'var(--bg-surface-2)', borderColor: 'var(--border-default)', color: 'var(--text-primary)' }}
          >
            إلغاء
          </button>
          <button
            onClick={handleApprove}
            disabled={!approvedTrusted && approvedDestructive.size === 0}
            className="flex-1 px-4 py-2 rounded-lg text-xs font-semibold flex items-center justify-center gap-1.5 disabled:opacity-40"
            style={{ background: 'var(--accent)', color: 'white' }}
          >
            <Check className="w-3.5 h-3.5" />
            تنفيذ
          </button>
        </div>
      </div>
    </div>
  );
}

export default function CopilotChat(_: CopilotChatProps) {
  const [messages, setMessages] = useState<Message[]>([
    {
      sender: 'assistant',
      text: '👋 أهلاً! أنا ClipAI Copilot — بقدر أنفذ 219 أمر مختلف على التايم لاين. جرب مثلاً: "احذف الكليب المحدد"، "زوّم التايم لاين"، "فعّل loop"، أو "صدّر الفيديو 1080p".',
    }
  ]);
  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [pendingConfirmation, setPendingConfirmation] = useState<{
    trusted: AIAction[];
    destructive: AIAction[];
  } | null>(null);
  const chatEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const executeActions = async (actions: AIAction[]) => {
    if (actions.length === 0) return;
    setLoading(true);
    try {
      const timelineState = useStore.getState().timelineState;
      const response = await axios.post(`${API_BASE}/api/ai/execute`, {
        actions,
        timeline_state: timelineState,
      });
      const data = response.data;
      // Update timeline state in store with the new state
      if (data.new_state) {
        useStore.getState().setTimelineState(data.new_state);
      }
      const summary = data.messages?.length > 0
        ? data.messages.slice(0, 3).join(' • ')
        : 'تم تنفيذ الإجراءات';
      setMessages(prev => [...prev, { sender: 'assistant', text: `✅ ${summary}` }]);
    } catch (err: any) {
      const errMsg = err.response?.data?.detail || err.message || 'فشل التنفيذ';
      setMessages(prev => [...prev, { sender: 'assistant', text: `❌ ${errMsg}`, isError: true }]);
    } finally {
      setLoading(false);
    }
  };

  const handleSend = async (textToSend: string) => {
    if (!textToSend.trim() || loading) return;

    setMessages(prev => [...prev, { sender: 'user', text: textToSend }]);
    setInput('');
    setLoading(true);

    const words = useStore.getState().words;
    const timelineState = useStore.getState().timelineState;

    try {
      const response = await axios.post(`${API_BASE}/api/ai/copilot`, {
        prompt: textToSend,
        words,
        timeline_state: timelineState,
      });

      const data = response.data;
      const respMsg = data.response_message || 'تمت المعالجة';
      const groups: ConfirmationGroup = data.confirmation_groups || { trusted: [], destructive: [] };
      const needsConfirm = data.needs_confirmation || false;

      // Show response message
      setMessages(prev => [...prev, {
        sender: 'assistant',
        text: respMsg,
        actions: data.actions,
      }]);

      // Auto-execute trusted actions immediately
      if (groups.trusted.length > 0) {
        await executeActions(groups.trusted);
      }

      // If destructive, show confirmation dialog
      if (needsConfirm && groups.destructive.length > 0) {
        setPendingConfirmation({
          trusted: [], // already executed
          destructive: groups.destructive,
        });
      }
    } catch (err: any) {
      const errMsg = err.response?.data?.detail || err.message || 'فشل الاتصال';
      setMessages(prev => [...prev, { sender: 'assistant', text: `❌ ${errMsg}`, isError: true }]);
    } finally {
      setLoading(false);
    }
  };

  const handleConfirm = async (approved: AIAction[]) => {
    setPendingConfirmation(null);
    if (approved.length > 0) {
      await executeActions(approved);
    } else {
      setMessages(prev => [...prev, { sender: 'assistant', text: '❌ تم الإلغاء' }]);
    }
  };

  return (
    <div className="flex flex-col h-full font-sans select-none" style={{ color: 'var(--text-primary)' }}>
      {/* Header */}
      <div className="p-3 border-b flex items-center justify-between" style={{ borderColor: 'var(--border-subtle)' }}>
        <h3 className="text-xs font-semibold flex items-center gap-1.5" style={{ color: 'var(--accent)' }}>
          <Sparkles className="w-3.5 h-3.5 animate-pulse" />
          مساعد المونتاج الذكي
        </h3>
        <span className="text-[9px] px-1.5 py-0.5 rounded border leading-none font-semibold uppercase" style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-default)', color: 'var(--text-secondary)' }}>
          219 أداة
        </span>
      </div>

      {/* Chat Area */}
      <div className="flex-1 overflow-y-auto p-3 flex flex-col gap-3.5 min-h-0">
        {messages.map((msg, i) => {
          const isAssistant = msg.sender === 'assistant';
          return (
            <div
              key={i}
              className={`flex flex-col max-w-[85%] rounded-[12px] p-2.5 text-xs text-right leading-relaxed ${
                isAssistant
                  ? msg.isError
                    ? 'self-start bg-red-950/40 border border-red-500/20 text-red-300'
                    : 'self-start bg-[var(--bg-surface-2)] border border-[var(--border-default)]'
                  : 'self-end bg-[var(--accent)] text-white'
              }`}
            >
              <div className="flex items-center gap-1.5 mb-1 justify-end">
                <span className="text-[10px] font-semibold opacity-75">
                  {isAssistant ? 'المساعد الذكي' : 'أنت'}
                </span>
                {isAssistant ? (
                  msg.isError ? <AlertCircle className="w-3 h-3" /> : <Sparkles className="w-3 h-3 text-[var(--accent-violet)]" />
                ) : (
                  <MessageSquare className="w-3 h-3" />
                )}
              </div>
              <p className="whitespace-pre-line text-right">{msg.text}</p>
              {msg.actions && msg.actions.length > 0 && (
                <div className="mt-2 pt-2 border-t" style={{ borderColor: 'var(--border-subtle)' }}>
                  <div className="text-[10px] opacity-60 mb-1">الإجراءات:</div>
                  <div className="space-y-1">
                    {msg.actions.slice(0, 5).map((a, j) => (
                      <div key={j} className="flex items-center gap-1.5 text-[10px]">
                        <span className="px-1 rounded text-[8px] font-mono" style={{ background: 'var(--bg-surface-3)', color: 'var(--text-secondary)' }}>
                          {getCategory(a.name)}
                        </span>
                        <span className="opacity-80">{describeAction(a)}</span>
                      </div>
                    ))}
                    {msg.actions.length > 5 && (
                      <div className="text-[10px] opacity-50">+{msg.actions.length - 5} إجراء آخر</div>
                    )}
                  </div>
                </div>
              )}
            </div>
          );
        })}
        {loading && (
          <div className="self-start bg-[var(--bg-surface-2)] border border-[var(--border-default)] rounded-[12px] p-3 text-xs text-right flex items-center gap-2">
            <div className="flex gap-1">
              <span className="w-1.5 h-1.5 bg-[var(--accent)] rounded-full animate-bounce" style={{ animationDelay: '0ms' }}></span>
              <span className="w-1.5 h-1.5 bg-[var(--accent)] rounded-full animate-bounce" style={{ animationDelay: '150ms' }}></span>
              <span className="w-1.5 h-1.5 bg-[var(--accent)] rounded-full animate-bounce" style={{ animationDelay: '300ms' }}></span>
            </div>
            <span>جاري التفكير...</span>
          </div>
        )}
        <div ref={chatEndRef} />
      </div>

      {/* Quick Commands */}
      <div className="px-3 py-2 flex flex-wrap gap-1.5 justify-end border-t" style={{ borderColor: 'var(--border-subtle)', background: 'var(--bg-surface-1)' }}>
        {QUICK_COMMANDS.map((cmd, i) => (
          <button
            key={i}
            onClick={() => handleSend(cmd)}
            disabled={loading}
            className="text-[10px] px-2 py-1 rounded-[6px] border transition-all cursor-pointer hover:border-[var(--accent)] disabled:cursor-not-allowed"
            style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-default)', color: 'var(--text-secondary)' }}
          >
            {cmd}
          </button>
        ))}
      </div>

      {/* Input Box */}
      <div className="p-3 border-t flex gap-2" style={{ borderColor: 'var(--border-subtle)', background: 'var(--bg-surface-1)' }}>
        <button
          onClick={() => handleSend(input)}
          disabled={!input.trim() || loading}
          className="w-8 h-8 rounded-[8px] flex items-center justify-center transition-all cursor-pointer disabled:cursor-not-allowed bg-[var(--accent)] hover:opacity-90 text-white"
        >
          <Send className="w-4.5 h-4.5 rotate-180" />
        </button>
        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && handleSend(input)}
          placeholder="اكتب أمراً (مثال: احذف الكليب، زوّم، فعّل loop)..."
          className="flex-1 bg-[var(--bg-surface-3)] border border-[var(--border-default)] rounded-[8px] px-3 py-1.5 text-xs text-right focus:outline-none focus:border-[var(--accent)] text-white placeholder-[var(--text-tertiary)]"
        />
      </div>

      {/* Confirmation Dialog */}
      {pendingConfirmation && (
        <ConfirmationDialog
          trusted={pendingConfirmation.trusted}
          destructive={pendingConfirmation.destructive}
          onApprove={handleConfirm}
          onCancel={() => {
            setPendingConfirmation(null);
            setMessages(prev => [...prev, { sender: 'assistant', text: '❌ تم الإلغاء' }]);
          }}
        />
      )}
    </div>
  );
}
