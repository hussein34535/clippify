import { useState } from 'react';
import axios from 'axios';
import { Download, Film, FileCode } from 'lucide-react';
import type { TimelineState, AppSettings } from '../../types';

interface ExportModalProps {
  timelineState: TimelineState;
  settings: AppSettings;
  API_BASE: string;
  onClose: () => void;
  setLoading: (v: boolean) => void;
  setStatusMsg: (v: string) => void;
  defaultTab?: 'video' | 'xml';
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

export default function ExportModal({
  timelineState,
  settings,
  API_BASE,
  onClose,
  setLoading,
  setStatusMsg,
  defaultTab = 'video'
}: ExportModalProps) {
  const [activeTab, setActiveTab] = useState<'video' | 'xml'>(defaultTab);
  const [outputFilename, setOutputFilename] = useState(`project_render_${Date.now()}.mp4`);
  const [exportQuality, setExportQuality] = useState(settings.export_quality || 'High');
  
  // XML Export states
  const [xmlFormat, setXmlFormat] = useState<'davinci' | 'premiere'>('davinci');
  const [includeSubtitles, setIncludeSubtitles] = useState(true);
  const [xmlOutputPath, setXmlOutputPath] = useState(
    `${settings.output_dir || './exports'}/nle_project_${Date.now()}.xml`
  );

  const handleVideoRender = async () => {
    onClose();
    setLoading(true);
    setStatusMsg('جاري ريندر ومونتاج الفيديو النهائي (FFmpeg)...');
    try {
      const res = await axios.post(`${API_BASE}/api/project/render/timeline`, {
        timeline: timelineState,
        output_filename: outputFilename
      });
      setLoading(false);
      setStatusMsg('');
      alert(`🎉 تم تصدير الفيديو بنجاح!\nالمسار: ${res.data.output_path}`);
    } catch (err: any) {
      setLoading(false);
      setStatusMsg('');
      alert(`❌ فشل تصدير الفيديو: ${err.response?.data?.detail || err.message}`);
    }
  };

  const handleXmlExport = async () => {
    onClose();
    setLoading(true);
    setStatusMsg(`جاري تصدير التايملاين بصيغة XML (${xmlFormat === 'davinci' ? 'Resolve' : 'Premiere'})...`);
    try {
      // Modify timeline state to include or exclude subtitles if needed, or backend resolve_exporter handles it
      const timelineData = { ...timelineState };
      if (!includeSubtitles) {
        // Temp clear subtitles track
        timelineData.tracks = {
          ...timelineData.tracks,
          subtitles: []
        };
      }

      const res = await axios.post(`${API_BASE}/api/project/export/xml`, {
        timeline: timelineData,
        output_path: xmlOutputPath,
        format: xmlFormat
      });
      setLoading(false);
      setStatusMsg('');
      alert(`🎉 تم تصدير ملف XML بنجاح!\nيمكنك الآن استيراده في ${xmlFormat === 'davinci' ? 'DaVinci Resolve' : 'Adobe Premiere Pro'}.\nالمسار: ${res.data.output_path}`);
    } catch (err: any) {
      setLoading(false);
      setStatusMsg('');
      alert(`❌ فشل تصدير ملف XML: ${err.response?.data?.detail || err.message}`);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center p-6 z-50 backdrop-blur-[8px]">
      <div 
        className="rounded-[20px] max-w-md w-full p-5 shadow-2xl flex flex-col gap-5 text-right border" 
        style={{ background: 'var(--bg-surface-1)', borderColor: 'var(--border-default)', boxShadow: '0 40px 80px rgba(0,0,0,0.8)' }}
      >
        <div className="flex items-center justify-between">
          <div className="w-8 h-8 rounded-[8px] flex items-center justify-center" style={{ background: 'var(--bg-surface-3)', border: '0.5px solid var(--border-default)' }}>
            <Download className="w-4 h-4" style={{ color: 'var(--accent)' }} />
          </div>
          <div>
            <h2 className="text-sm font-semibold" style={{ color: 'var(--text-primary)' }}>
              تصدير مشروع ClipAI
            </h2>
            <p className="text-[10px] mt-0.5" style={{ color: 'var(--text-tertiary)' }}>تصدير كفيديو نهائي أو كملف مشروع NLE لبرامج المونتاج</p>
          </div>
        </div>

        {/* Tab switcher */}
        <div className="flex p-0.5 rounded-[10px] bg-[var(--bg-surface-3)] border border-[var(--border-default)] shrink-0">
          <button
            onClick={() => setActiveTab('xml')}
            className={`flex-1 py-1.5 text-xs font-semibold text-center rounded-[8px] transition-all cursor-pointer flex items-center justify-center gap-1.5`}
            style={{
              background: activeTab === 'xml' ? 'var(--bg-surface-1)' : 'transparent',
              color: activeTab === 'xml' ? 'var(--text-primary)' : 'var(--text-secondary)',
              border: activeTab === 'xml' ? '0.5px solid var(--border-strong)' : '0.5px solid transparent',
              boxShadow: activeTab === 'xml' ? '0 1px 3px rgba(0,0,0,0.2)' : 'none',
            }}
          >
            <FileCode className="w-3.5 h-3.5" />
            تصدير XML احترافي
          </button>
          <button
            onClick={() => setActiveTab('video')}
            className={`flex-1 py-1.5 text-xs font-semibold text-center rounded-[8px] transition-all cursor-pointer flex items-center justify-center gap-1.5`}
            style={{
              background: activeTab === 'video' ? 'var(--bg-surface-1)' : 'transparent',
              color: activeTab === 'video' ? 'var(--text-primary)' : 'var(--text-secondary)',
              border: activeTab === 'video' ? '0.5px solid var(--border-strong)' : '0.5px solid transparent',
              boxShadow: activeTab === 'video' ? '0 1px 3px rgba(0,0,0,0.2)' : 'none',
            }}
          >
            <Film className="w-3.5 h-3.5" />
            ريندر فيديو نهائي
          </button>
        </div>

        <div className="apple-separator" />

        {/* Form Content */}
        <div className="flex flex-col gap-4 overflow-y-auto max-h-[350px] pr-1">
          {activeTab === 'video' ? (
            <>
              <div className="flex flex-col gap-1 text-right">
                <label className="apple-label">اسم ملف الفيديو المخرج:</label>
                <input
                  type="text"
                  value={outputFilename}
                  onChange={(e) => setOutputFilename(e.target.value)}
                  className="apple-input w-full text-left"
                />
              </div>

              <div className="flex flex-col gap-1 text-right">
                <label className="apple-label">جودة الريندر والضغط:</label>
                <select
                  value={exportQuality}
                  onChange={(e) => setExportQuality(e.target.value)}
                  className="bg-[var(--bg-surface-3)] border border-[var(--border-default)] text-xs text-[var(--text-primary)] rounded-[6px] p-2 focus:outline-none focus:border-[var(--accent)]"
                >
                  <option value="High">جودة عالية (High Quality - Low Compression)</option>
                  <option value="Medium">جودة متوسطة (Medium Quality)</option>
                  <option value="Low">جودة منخفضة (Low Quality - Fast Render)</option>
                </select>
              </div>

              <div className="rounded-[10px] p-3 text-[11px] leading-relaxed border" style={{ background: 'var(--bg-surface-2)', borderColor: 'var(--border-subtle)', color: 'var(--text-secondary)' }}>
                <span className="font-semibold block mb-1 text-[var(--text-primary)]">💡 ريندر المونتاج الشامل:</span>
                سيقوم هذا الخيار بدمج مقاطع الفيديو، وتطبيق الذكاء الاصطناعي لتتبع الوجه وإزالة الخلفية، وإضافة الترجمة الحركية والمؤثرات الصوتية والـ B-Rolls مباشرة وتصدير ملف فيديو MP4 جاهز للنشر.
              </div>
            </>
          ) : (
            <>
              <div className="flex flex-col gap-1 text-right">
                <label className="apple-label">تنسيق وتوافق برنامج المونتاج:</label>
                <select
                  value={xmlFormat}
                  onChange={(e) => setXmlFormat(e.target.value as any)}
                  className="bg-[var(--bg-surface-3)] border border-[var(--border-default)] text-xs text-[var(--text-primary)] rounded-[6px] p-2 focus:outline-none focus:border-[var(--accent)]"
                >
                  <option value="davinci">DaVinci Resolve (FCP 7 XML)</option>
                  <option value="premiere">Adobe Premiere Pro (FCP XML compatible)</option>
                </select>
              </div>

              <div className="flex flex-col gap-1 text-right">
                <label className="apple-label">مسار حفظ ملف الـ XML المخرج:</label>
                <input
                  type="text"
                  value={xmlOutputPath}
                  onChange={(e) => setXmlOutputPath(e.target.value)}
                  className="apple-input w-full text-left"
                />
              </div>

              <div className="apple-separator my-1" />

              <div className="flex items-center justify-between py-1">
                <ToggleSwitch
                  checked={includeSubtitles}
                  onChange={setIncludeSubtitles}
                />
                <div className="text-right">
                  <span className="text-xs block font-medium" style={{ color: 'var(--text-secondary)' }}>
                    تضمين الكلمات والترجمات كعلامات (Markers)
                  </span>
                  <span className="text-[9px]" style={{ color: 'var(--text-tertiary)' }}>
                    تظهر الكلمات كـ Markers صفراء فوق التايملاين لسهولة تعديلها
                  </span>
                </div>
              </div>

              <div className="rounded-[10px] p-3 text-[11px] leading-relaxed border" style={{ background: 'var(--bg-surface-2)', borderColor: 'var(--border-subtle)', color: 'var(--text-secondary)' }}>
                <span className="font-semibold block mb-1 text-[var(--text-primary)]">💡 سير العمل الاحترافي (XML):</span>
                تصدير التايملاين كـ XML يسمح لك بفتح نفس القصات، الكليبات، التعديلات الصوتية والترجمات داخل DaVinci Resolve أو Premiere Pro دون فقدان الجودة، لإكمال اللمسات الفنية وتصحيح الألوان.
              </div>
            </>
          )}
        </div>

        <div className="apple-separator" />

        <div className="flex gap-2.5">
          <button
            onClick={onClose}
            className="apple-btn-secondary flex-1 py-1.5 text-xs font-semibold"
          >
            إلغاء
          </button>
          <button
            onClick={activeTab === 'video' ? handleVideoRender : handleXmlExport}
            className="apple-btn-primary flex-1 py-1.5 text-xs font-semibold flex items-center justify-center gap-1.5"
          >
            <Download className="w-3.5 h-3.5" />
            {activeTab === 'video' ? 'بدء ريندر الفيديو' : 'تصدير ملف XML'}
          </button>
        </div>
      </div>
    </div>
  );
}
