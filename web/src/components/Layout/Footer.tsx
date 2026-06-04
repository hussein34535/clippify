import { useState, useEffect } from 'react';
import { RefreshCw, Sparkles, Save, Circle } from 'lucide-react';

interface FooterProps {
  loading: boolean;
  statusMsg: string;
  sessionProgress: number;
  onExportClick?: (tab: 'video' | 'xml') => void;
}

export default function Footer({
  loading, statusMsg, sessionProgress,
  onExportClick,
}: FooterProps) {
  const [autoSaveStatus, setAutoSaveStatus] = useState<'saved' | 'saving' | 'idle'>('saved');
  const [lastSavedAt, setLastSavedAt] = useState<Date | null>(null);

  // Auto-save indicator (Phase 10 — Project Management)
  useEffect(() => {
    const interval = setInterval(() => {
      // Check localStorage for any recent project state
      try {
        const last = localStorage.getItem('clipai_last_saved');
        if (last) {
          setLastSavedAt(new Date(last));
          setAutoSaveStatus('saved');
        }
      } catch (e) {}
    }, 5000);
    return () => clearInterval(interval);
  }, []);

  const formatLastSaved = (d: Date | null) => {
    if (!d) return 'لم يحفظ بعد';
    const diff = Math.floor((Date.now() - d.getTime()) / 1000);
    if (diff < 60) return `حفظ تلقائي قبل ${diff} ثانية`;
    if (diff < 3600) return `حفظ تلقائي قبل ${Math.floor(diff / 60)} دقيقة`;
    return `حفظ تلقائي قبل ${Math.floor(diff / 3600)} ساعة`;
  };

  return (
    <footer className="h-11 border-t px-4 flex items-center justify-between gap-4 flex-shrink-0 z-40" style={{ background: 'var(--bg-surface-1)', borderColor: 'var(--border-subtle)' }}>
      <div className="flex-1 flex items-center gap-3 justify-end">
        {loading ? (
          <div className="flex flex-col gap-1 text-right max-w-xs">
            <span className="text-[10px] font-medium flex items-center gap-1.5 justify-end" style={{ color: 'var(--accent)' }}>
              {statusMsg} <RefreshCw className="w-3 h-3 animate-spin" />
            </span>
            <div className="w-full h-[2px] overflow-hidden rounded-full" style={{ background: 'var(--bg-surface-3)' }}>
              <div
                className="h-full rounded-full transition-all duration-300"
                style={{ width: `${sessionProgress}%`, background: 'var(--accent)' }}
              ></div>
            </div>
          </div>
        ) : (
          <>
            <p className="text-[11px] text-right" style={{ color: 'var(--text-secondary)' }}>جاهز ومستعد للمونتاج الذكي والتصدير.</p>
            <div className="w-px h-4" style={{ background: 'var(--border-subtle)' }} />
            <div className="flex items-center gap-1.5 text-[10px]" style={{ color: 'var(--text-tertiary)' }} title="حفظ تلقائي في localStorage">
              <Circle className="w-1.5 h-1.5 fill-current" style={{ color: autoSaveStatus === 'saved' ? '#30D158' : 'var(--text-tertiary)' }} />
              <Save className="w-3 h-3" />
              <span>{formatLastSaved(lastSavedAt)}</span>
            </div>
          </>
        )}
      </div>

      <div className="flex gap-2 justify-end">
        <button
          onClick={() => onExportClick && onExportClick('xml')}
          className="apple-btn-secondary py-1.5 px-3 text-xs"
        >
          تصدير XML (Resolve)
        </button>

        <button
          onClick={() => onExportClick && onExportClick('video')}
          className="apple-btn-primary py-1.5 px-4 text-xs flex items-center gap-1.5"
        >
          <Sparkles className="w-3.5 h-3.5" /> ريندر الفيديو النهائي
        </button>
      </div>
    </footer>
  );
}
