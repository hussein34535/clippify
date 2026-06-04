// WorkspaceSwitcher.tsx
// Phase 9 — UI/UX: Quick workspace layout switcher.

import { useState, useEffect } from 'react';
import { Layout, ChevronDown } from 'lucide-react';
import { LAYOUT_PRESETS, getLayout, setLayout, type WorkspaceLayout } from '../../lib/themeManager';

interface WorkspaceSwitcherProps {
  onLayoutChange: (layout: WorkspaceLayout) => void;
}

export default function WorkspaceSwitcher({ onLayoutChange }: WorkspaceSwitcherProps) {
  const [open, setOpen] = useState(false);
  const [current, setCurrent] = useState<WorkspaceLayout>('editing');

  useEffect(() => {
    setCurrent(getLayout());
  }, []);

  const handleSelect = (layout: WorkspaceLayout) => {
    setLayout(layout);
    setCurrent(layout);
    onLayoutChange(layout);
    setOpen(false);
  };

  return (
    <div className="relative">
      <button
        onClick={() => setOpen(!open)}
        className="flex items-center gap-1.5 px-2 py-1 rounded text-[11px] font-semibold transition-all cursor-pointer"
        style={{ background: 'var(--bg-surface-3)', border: '1px solid var(--border-default)', color: 'var(--text-primary)' }}
        title="تخطيط مساحة العمل"
      >
        <Layout className="w-3.5 h-3.5" />
        {LAYOUT_PRESETS[current].nameAr}
        <ChevronDown className="w-3 h-3" />
      </button>

      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div
            className="absolute top-9 left-0 w-48 rounded-lg border shadow-xl z-50 overflow-hidden"
            style={{ background: 'var(--bg-surface-1)', borderColor: 'var(--border-default)' }}
          >
            {(Object.keys(LAYOUT_PRESETS) as WorkspaceLayout[]).map((key) => {
              const p = LAYOUT_PRESETS[key];
              return (
                <button
                  key={key}
                  onClick={() => handleSelect(key)}
                  className="w-full text-right px-3 py-2 hover:bg-[var(--bg-surface-2)] transition-colors flex items-center justify-between"
                  style={{ color: current === key ? 'var(--accent)' : 'var(--text-primary)' }}
                >
                  <span className="text-[11px] font-semibold">{p.nameAr}</span>
                  <span className="text-[9px]" style={{ color: 'var(--text-tertiary)' }}>
                    {p.leftWidth}/{p.rightWidth}/{p.bottomHeight}
                  </span>
                </button>
              );
            })}
          </div>
        </>
      )}
    </div>
  );
}
