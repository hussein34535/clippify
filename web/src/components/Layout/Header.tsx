import { useState, useEffect } from 'react';
import { Settings, Film, Download, Save, FolderOpen, Sun, Moon, Contrast, Minimize2, Maximize2, HelpCircle, LayoutTemplate } from 'lucide-react';
import { getTheme, cycleTheme, getDensity, toggleDensity, type Theme, type WorkspaceLayout } from '../../lib/themeManager';
import MacroMenu from '../UI/MacroMenu';
import CommentsPanel from '../UI/CommentsPanel';
import ShortcutsHelp from '../UI/ShortcutsHelp';
import WorkspaceSwitcher from '../UI/WorkspaceSwitcher';
import PerformanceDashboard from '../UI/PerformanceDashboard';
import VoiceCommands from '../UI/VoiceCommands';
import OnboardingTour from '../UI/OnboardingTour';
import TemplatesGallery from '../UI/TemplatesGallery';
import { useStore } from '../../store';
import type { TimelineState } from '../../types';

interface HeaderProps {
  contentType: string;
  setContentType: (val: string) => void;
  showSettings: boolean;
  setShowSettings: (val: boolean) => void;
  onExport: () => void;
  onSave: () => void;
  onLoad: () => void;
  onWorkspaceChange?: (layout: WorkspaceLayout) => void;
  timelineState?: TimelineState;
  onApplyTemplate?: (state: TimelineState) => void;
}

const THEME_ICONS: Record<Theme, React.ComponentType<any>> = {
  'dark': Moon,
  'light': Sun,
  'high-contrast': Contrast,
};

const THEME_LABELS: Record<Theme, string> = {
  'dark': 'داكن',
  'light': 'فاتح',
  'high-contrast': 'تباين عالي',
};

export default function Header({ contentType, setContentType, showSettings, setShowSettings, onExport, onSave, onLoad, onWorkspaceChange, timelineState, onApplyTemplate }: HeaderProps) {
  const [theme, setThemeState] = useState<Theme>('dark');
  const [density, setDensityState] = useState<'normal' | 'compact'>('normal');
  const [showTemplates, setShowTemplates] = useState(false);

  useEffect(() => {
    setThemeState(getTheme());
    setDensityState(getDensity());
  }, []);

  const handleThemeToggle = () => {
    const next = cycleTheme();
    setThemeState(next);
  };

  const handleDensityToggle = () => {
    const next = toggleDensity();
    setDensityState(next);
  };

  const ThemeIcon = THEME_ICONS[theme];
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

        {/* Templates gallery (Phase 18) */}
        {timelineState && onApplyTemplate && (
          <button
            onClick={() => setShowTemplates(true)}
            className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-[6px] text-[11px] font-semibold transition-all cursor-pointer"
            style={{ background: 'var(--bg-surface-3)', border: '1.5px solid var(--border-default)', color: 'var(--text-primary)' }}
            title="معرض القوالب"
          >
            <LayoutTemplate className="w-3.5 h-3.5" />
            القوالب
          </button>
        )}

        <button
          onClick={onExport}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-[6px] text-[11px] font-semibold transition-all cursor-pointer"
          style={{ background: 'var(--accent)', color: '#fff', boxShadow: '0 2px 5px rgba(59, 130, 246, 0.3)' }}
        >
          <Download className="w-3.5 h-3.5" />
          تصدير
        </button>

        {/* Workspace layout switcher (Phase 9 — UI/UX) */}
        {onWorkspaceChange && <WorkspaceSwitcher onLayoutChange={onWorkspaceChange} />}

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

        {/* Theme toggle (Phase 9 — UI/UX) */}
        <button
          onClick={handleThemeToggle}
          className="w-7 h-7 rounded-full flex items-center justify-center transition-all cursor-pointer hover:bg-[var(--bg-surface-3)]"
          style={{ color: 'var(--text-secondary)' }}
          title={`الثيم: ${THEME_LABELS[theme]} (اضغط للتبديل)`}
        >
          <ThemeIcon className="w-4 h-4" />
        </button>

        {/* Density toggle (Phase 9) */}
        <button
          onClick={handleDensityToggle}
          className="w-7 h-7 rounded-full flex items-center justify-center transition-all cursor-pointer hover:bg-[var(--bg-surface-3)]"
          style={{ color: density === 'compact' ? 'var(--accent)' : 'var(--text-secondary)' }}
          title={density === 'compact' ? 'كثافة عادية' : 'كثافة مضغوطة'}
        >
          {density === 'compact' ? <Maximize2 className="w-3.5 h-3.5" /> : <Minimize2 className="w-3.5 h-3.5" />}
        </button>

        {/* Macro menu (Phase 5 — Macro Recording) */}
        <MacroMenu />

        {/* Comments panel (Phase 11 — Collaboration) */}
        <CommentsPanel currentTime={useStore.getState().currentTime} />

        {/* Help / Shortcuts (Phase 15 — Accessibility) */}
        <HelpButton />

        {/* Performance dashboard (Phase 12 — Performance) */}
        <PerformanceDashboard />

        {/* Voice commands (Phase 8 — Voice Control) */}
        <VoiceCommands />
      </div>
      <ShortcutsHelp />
      <OnboardingTourWrapper />
      {showTemplates && timelineState && onApplyTemplate && (
        <TemplatesGallery
          current={timelineState}
          onApply={onApplyTemplate}
          onClose={() => setShowTemplates(false)}
        />
      )}
    </header>
  );
}

function OnboardingTourWrapper() {
  const [show, setShow] = useState(false);
  useEffect(() => {
    const completed = localStorage.getItem('clipai_onboarding_completed');
    if (!completed) setShow(true);
  }, []);
  if (!show) return null;
  return <OnboardingTour />;
}

function HelpButton() {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="w-7 h-7 rounded-full flex items-center justify-center transition-all cursor-pointer hover:bg-[var(--bg-surface-3)]"
        style={{ color: 'var(--text-secondary)' }}
        title="اختصارات لوحة المفاتيح (؟)"
      >
        <HelpCircle className="w-4 h-4" />
      </button>
      {open && <ShortcutsHelpTrigger onClose={() => setOpen(false)} />}
    </>
  );
}

function ShortcutsHelpTrigger({ onClose }: { onClose: () => void }) {
  return (
    <button
      onClick={onClose}
      className="fixed inset-0 z-30 bg-transparent"
      aria-label="إغلاق"
    />
  );
}
