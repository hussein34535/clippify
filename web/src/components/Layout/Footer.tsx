import { RefreshCw, Sparkles } from 'lucide-react';

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
  return (
    <footer className="h-11 border-t px-4 flex items-center justify-between gap-4 flex-shrink-0 z-40" style={{ background: 'var(--bg-surface-1)', borderColor: 'var(--border-subtle)' }}>
      <div className="flex-1">
        {loading ? (
          <div className="flex flex-col gap-1 text-right max-w-xs ml-auto">
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
          <p className="text-[11px] text-right" style={{ color: 'var(--text-secondary)' }}>جاهز ومستعد للمونتاج الذكي والتصدير.</p>
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
