import { Settings, Film, Download, Save, FolderOpen } from 'lucide-react';

interface HeaderProps {
  contentType: string;
  setContentType: (val: string) => void;
  showSettings: boolean;
  setShowSettings: (val: boolean) => void;
  onExport: () => void;
  onSave: () => void;
  onLoad: () => void;
}

export default function Header({ contentType, setContentType, showSettings, setShowSettings, onExport, onSave, onLoad }: HeaderProps) {
  const contentTypes = [
    { value: 'podcast', label: 'بودكاست' },
    { value: 'awareness', label: 'توعوي' },
    { value: 'comedy', label: 'كوميدي' },
    { value: 'interview', label: 'مقابلة' },
    { value: 'motivation', label: 'تحفيزي' },
    { value: 'educational', label: 'تعليمي' }
  ];

  return (
    <header className="h-11 border-b px-4 flex items-center justify-between z-40 flex-shrink-0" style={{ background: 'var(--bg-surface-1)', borderColor: 'var(--border-subtle)', backdropFilter: 'blur(20px)' }}>
      <div className="flex items-center gap-2.5">
        <div className="w-7 h-7 rounded-[8px] flex items-center justify-center shadow-sm" style={{ background: 'var(--accent)' }}>
          <Film className="w-3.5 h-3.5 text-white" />
        </div>
        <div className="flex items-center gap-2">
          <h1 className="text-xs font-semibold leading-none" style={{ color: 'var(--text-primary)' }}>
            ClipAI Studio
          </h1>
          <span className="text-[9px] px-1.5 py-0.5 rounded-full border leading-none font-medium" style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-default)', color: 'var(--text-secondary)' }}>
            v1.0
          </span>
        </div>
      </div>

      <div className="flex items-center gap-4">
        <div className="flex items-center gap-2">
          <span className="text-[11px] font-medium" style={{ color: 'var(--text-secondary)' }}>نوع المحتوى:</span>
          <div style={{ background: 'var(--bg-surface-3)', borderRadius: '8px', padding: '2px', display: 'flex', gap: '2px', border: '0.5px solid var(--border-default)' }}>
            {contentTypes.map(item => (
              <button
                key={item.value}
                style={{
                  background: contentType === item.value ? 'var(--bg-surface-1)' : 'transparent',
                  borderRadius: '6px',
                  padding: '3px 10px',
                  fontSize: '11px',
                  fontWeight: contentType === item.value ? 600 : 400,
                  color: contentType === item.value ? 'var(--text-primary)' : 'var(--text-secondary)',
                  border: contentType === item.value ? '0.5px solid var(--border-strong)' : '0.5px solid transparent',
                  boxShadow: contentType === item.value ? '0 1px 3px rgba(0,0,0,0.2)' : 'none',
                  transition: 'all 120ms ease-out',
                  cursor: 'pointer',
                }}
                onClick={() => setContentType(item.value)}
              >
                {item.label}
              </button>
            ))}
          </div>
        </div>

        <button
          onClick={onSave}
          className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-[6px] text-[11px] font-semibold transition-all cursor-pointer"
          style={{ background: 'var(--bg-surface-3)', border: '1.5px solid var(--border-default)', color: 'var(--text-primary)' }}
        >
          <Save className="w-3.5 h-3.5" />
          حفظ
        </button>

        <button
          onClick={onLoad}
          className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-[6px] text-[11px] font-semibold transition-all cursor-pointer"
          style={{ background: 'var(--bg-surface-3)', border: '1.5px solid var(--border-default)', color: 'var(--text-primary)' }}
        >
          <FolderOpen className="w-3.5 h-3.5" />
          فتح
        </button>

        <button
          onClick={onExport}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-[6px] text-[11px] font-semibold transition-all cursor-pointer"
          style={{ background: 'var(--accent)', color: '#fff', boxShadow: '0 2px 5px rgba(59, 130, 246, 0.3)' }}
        >
          <Download className="w-3.5 h-3.5" />
          تصدير
        </button>

        <button
          onClick={() => setShowSettings(!showSettings)}
          className="w-7 h-7 rounded-full flex items-center justify-center transition-all cursor-pointer"
          style={{ 
            background: showSettings ? 'var(--bg-surface-3)' : 'transparent',
            color: showSettings ? 'var(--accent)' : 'var(--text-secondary)' 
          }}
          onMouseEnter={(e) => {
            if (!showSettings) {
              e.currentTarget.style.background = 'var(--bg-surface-3)';
              e.currentTarget.style.color = 'var(--text-primary)';
            }
          }}
          onMouseLeave={(e) => {
            if (!showSettings) {
              e.currentTarget.style.background = 'transparent';
              e.currentTarget.style.color = 'var(--text-secondary)';
            }
          }}
          title="الإعدادات المتقدمة"
        >
          <Settings className="w-4 h-4" />
        </button>
      </div>
    </header>
  );
}
