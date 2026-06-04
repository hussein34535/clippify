import { Sliders, Trash2 } from 'lucide-react';
import type { AppSettings } from '../../types';
import axios from 'axios';
import { API_BASE } from '../../api';
import { useToast } from '../UI/Toast';

interface SettingsModalProps {
  settings: AppSettings;
  setSettings: (s: AppSettings) => void;
  onSave: () => void;
  onClose: () => void;
}

const ToggleSwitch = ({ checked, onChange }: { checked: boolean; onChange: (v: boolean) => void }) => {
  return (
    <div 
      onClick={() => onChange(!checked)}
      style={{
        width: 36,
        height: 20,
        borderRadius: 10,
        background: checked ? 'var(--accent)' : 'var(--bg-surface-3)',
        border: '0.5px solid var(--border-default)',
        transition: 'background 150ms ease-out',
        position: 'relative',
        cursor: 'pointer',
        flexShrink: 0
      }}
    >
      <div style={{
        position: 'absolute',
        top: 1,
        left: checked ? 17 : 1,
        width: 16,
        height: 16,
        borderRadius: '50%',
        background: '#fff',
        boxShadow: '0 1px 3px rgba(0,0,0,0.3)',
        transition: 'left 150ms cubic-bezier(0.25, 0.8, 0.25, 1)'
      }} />
    </div>
  );
};

export default function SettingsModal({ settings, setSettings, onSave, onClose }: SettingsModalProps) {
  const { showToast } = useToast();
  const handleClearCache = async () => {
    try {
      const res = await axios.post(`${API_BASE}/api/clear-cache`);
      showToast(res.data.message, 'success');
    } catch (e: any) {
      showToast('فشل تنظيف الكاش: ' + e.message, 'error');
    }
  };
  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center p-8 z-50 backdrop-blur-[8px]">
      <div
        className="rounded-[20px] max-w-3xl w-full max-h-[90vh] p-7 shadow-2xl flex flex-col gap-5 text-right border"
        style={{ background: 'var(--bg-surface-1)', borderColor: 'var(--border-default)', boxShadow: '0 40px 80px rgba(0,0,0,0.8)' }}
      >
        <div className="flex items-center justify-between flex-shrink-0">
          <div className="w-10 h-10 rounded-[10px] flex items-center justify-center" style={{ background: 'var(--bg-surface-3)', border: '0.5px solid var(--border-default)' }}>
            <Sliders className="w-5 h-5" style={{ color: 'var(--accent)' }} />
          </div>
          <div>
            <h2 className="text-base font-semibold" style={{ color: 'var(--text-primary)' }}>
              إعدادات ClipAI المتقدمة
            </h2>
            <p className="text-[11px] mt-0.5" style={{ color: 'var(--text-tertiary)' }}>ضبط تفاصيل وخيارات الريندر والذكاء الاصطناعي</p>
          </div>
        </div>

        <div className="apple-separator" />

        <div className="flex flex-col gap-5 overflow-y-auto max-h-[calc(90vh-180px)] pr-2">
          <div className="flex flex-col gap-1.5 text-right">
            <label className="apple-label">مجلد حفظ مخرجات الريندر:</label>
            <input
              type="text"
              value={settings.output_dir}
              onChange={(e) => setSettings({ ...settings, output_dir: e.target.value })}
              className="apple-input w-full text-left py-2.5"
            />
          </div>

          <div className="grid grid-cols-2 gap-5">
            <div className="flex flex-col gap-1.5 text-right">
              <label className="apple-label">عدد المقاطع:</label>
              <input
                type="number"
                value={settings.n_clips}
                onChange={(e) => setSettings({ ...settings, n_clips: parseInt(e.target.value) || 5 })}
                className="apple-input w-full text-center py-2.5"
              />
            </div>
            <div className="flex flex-col gap-1.5 text-right">
              <label className="apple-label">مدة كل مقطع (ثوانٍ):</label>
              <input
                type="number"
                value={settings.duration}
                onChange={(e) => setSettings({ ...settings, duration: parseInt(e.target.value) || 60 })}
                className="apple-input w-full text-center py-2.5"
              />
            </div>
          </div>

          <div className="flex flex-col gap-1.5 text-right">
            <label className="apple-label">ستايل النص والترجمة (Subtitle style):</label>
            <select
              value={settings.subtitle_style}
              onChange={(e) => setSettings({ ...settings, subtitle_style: e.target.value })}
              className="bg-[var(--bg-surface-3)] border border-[var(--border-default)] text-sm text-[var(--text-primary)] rounded-[7px] p-2.5 focus:outline-none focus:border-[var(--accent)]"
            >
              <option value="TikTok Yellow">TikTok Yellow</option>
              <option value="Cyberpunk Neon">Cyberpunk Neon</option>
              <option value="Minimalist Clean">Minimalist Clean</option>
            </select>
          </div>

          <div className="grid grid-cols-2 gap-5">
            <div className="flex flex-col gap-1.5 text-right">
              <label className="apple-label">تنسيق التصدير:</label>
              <select
                value={settings.export_mode || 'ffmpeg'}
                onChange={(e) => setSettings({ ...settings, export_mode: e.target.value })}
                className="bg-[var(--bg-surface-3)] border border-[var(--border-default)] text-sm text-[var(--text-primary)] rounded-[7px] p-2.5 focus:outline-none focus:border-[var(--accent)]"
              >
                <option value="ffmpeg">FFmpeg (فيديو نهائي)</option>
                <option value="davinci">DaVinci Resolve (ملف XML)</option>
              </select>
            </div>
            <div className="flex flex-col gap-1.5 text-right">
              <label className="apple-label">حجم نموذج تفريغ الصوت (Whisper):</label>
              <select
                value={settings.whisper_model || 'tiny'}
                onChange={(e) => setSettings({ ...settings, whisper_model: e.target.value })}
                className="bg-[var(--bg-surface-3)] border border-[var(--border-default)] text-sm text-[var(--text-primary)] rounded-[7px] p-2.5 focus:outline-none focus:border-[var(--accent)]"
              >
                <option value="tiny">Tiny (سريع جداً - 39MB)</option>
                <option value="base">Base (سريع - 74MB)</option>
                <option value="small">Small (متوسط - 244MB)</option>
                <option value="medium">Medium (دقيق - 769MB)</option>
                <option value="large-v3">Large v3 (دقيق جداً - 1.5GB)</option>
              </select>
            </div>
          </div>

          <div className="apple-separator my-1" />

          <div className="flex items-center justify-between py-1.5">
            <ToggleSwitch
              checked={settings.translate_to_arabic}
              onChange={(val) => setSettings({ ...settings, translate_to_arabic: val })}
            />
            <span className="text-sm" style={{ color: 'var(--text-secondary)' }}>ترجمة الكلام تلقائياً إلى اللغة العربية</span>
          </div>

          <div className="flex items-center justify-between py-1.5">
            <ToggleSwitch
              checked={settings.auto_broll}
              onChange={(val) => setSettings({ ...settings, auto_broll: val })}
            />
            <span className="text-sm" style={{ color: 'var(--text-secondary)' }}>تنزيل ودمج لقطات تعبيرية (Auto B-roll) تلقائياً</span>
          </div>

          <div className="apple-separator my-1" />

          <div className="grid grid-cols-2 gap-5">
            <div className="flex flex-col gap-1.5 text-right">
              <label className="apple-label">مفتاح API لـ Pexels:</label>
              <input
                type="password"
                value={settings.pexels_api_key}
                onChange={(e) => setSettings({ ...settings, pexels_api_key: e.target.value })}
                className="apple-input w-full text-left py-2.5"
                placeholder="Pexels API Key"
              />
            </div>
            <div className="flex flex-col gap-1.5 text-right">
              <label className="apple-label">مفتاح API لـ Pixabay:</label>
              <input
                type="password"
                value={settings.pixabay_api_key}
                onChange={(e) => setSettings({ ...settings, pixabay_api_key: e.target.value })}
                className="apple-input w-full text-left py-2.5"
                placeholder="Pixabay API Key"
              />
            </div>
          </div>

          <div className="apple-separator my-1" />

          <div className="flex items-center justify-between py-1.5">
            <button
              onClick={handleClearCache}
              className="px-4 py-2 rounded-lg flex items-center gap-2 text-sm font-semibold hover:bg-red-950/40 border border-red-500/20 text-red-400 transition-colors"
            >
              <Trash2 className="w-4 h-4" />
              تنظيف الملفات المؤقتة (Cache)
            </button>
            <span className="text-[11px]" style={{ color: 'var(--text-tertiary)' }}>تفريغ المساحة من مقاطع الكروما والـ B-Roll القديمة</span>
          </div>
        </div>

        <div className="apple-separator" />

        <div className="flex gap-3 flex-shrink-0">
          <button
            onClick={onClose}
            className="apple-btn-secondary flex-1 py-2.5 text-sm font-semibold"
          >
            إلغاء
          </button>
          <button
            onClick={onSave}
            className="apple-btn-primary flex-1 py-2.5 text-sm font-semibold"
          >
            حفظ الإعدادات
          </button>
        </div>
      </div>
    </div>
  );
}
