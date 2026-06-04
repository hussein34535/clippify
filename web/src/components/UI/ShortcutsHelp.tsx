// ShortcutsHelp.tsx
// Phase 15 — Accessibility: Keyboard shortcuts help.

import { useState, useEffect } from 'react';
import { X, Keyboard } from 'lucide-react';

interface Shortcut {
  keys: string;
  desc: string;
  category: string;
}

const SHORTCUTS: Shortcut[] = [
  { keys: 'Space', desc: 'تشغيل/إيقاف', category: 'تشغيل' },
  { keys: 'J', desc: 'رجوع للخلف', category: 'تشغيل' },
  { keys: 'K', desc: 'إيقاف مؤقت', category: 'تشغيل' },
  { keys: 'L', desc: 'تقدم للأمام', category: 'تشغيل' },
  { keys: '← / →', desc: 'خطوة إطار', category: 'تشغيل' },
  { keys: 'Shift + ←/→', desc: 'تخطي 5 ثواني', category: 'تشغيل' },
  { keys: 'Home / End', desc: 'البداية/النهاية', category: 'تشغيل' },
  { keys: 'I', desc: 'تعليم In', category: 'تحرير' },
  { keys: 'O', desc: 'تعليم Out', category: 'تحرير' },
  { keys: 'C', desc: 'تقسيم (Cut) عند المؤشر', category: 'تحرير' },
  { keys: 'Del', desc: 'حذف المقطع المحدد (مع تأكيد)', category: 'تحرير' },
  { keys: 'Ctrl+Z', desc: 'تراجع', category: 'تحرير' },
  { keys: 'Ctrl+Y / Ctrl+Shift+Z', desc: 'إعادة', category: 'تحرير' },
  { keys: 'M', desc: 'إضافة Marker', category: 'تحرير' },
  { keys: 'F', desc: 'ملء الشاشة', category: 'عرض' },
  { keys: '+/-', desc: 'تكبير/تصغير التايملاين', category: 'عرض' },
  { keys: '?', desc: 'فتح/إغلاق قائمة الاختصارات', category: 'عام' },
  { keys: 'Esc', desc: 'إغلاق نوافذ', category: 'عام' },
];

export default function ShortcutsHelp() {
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === '?' && !e.ctrlKey && !e.metaKey) {
        const target = e.target as HTMLElement;
        if (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA') return;
        e.preventDefault();
        setOpen((o) => !o);
      } else if (e.key === 'Escape' && open) {
        setOpen(false);
      }
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [open]);

  if (!open) return null;

  const categories = Array.from(new Set(SHORTCUTS.map((s) => s.category)));

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center"
      style={{ background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(4px)' }}
      onClick={() => setOpen(false)}
    >
      <div
        className="w-[480px] max-h-[80vh] rounded-xl border shadow-2xl overflow-hidden"
        style={{ background: 'var(--bg-surface-1)', borderColor: 'var(--border-default)' }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="p-4 border-b flex items-center justify-between" style={{ borderColor: 'var(--border-subtle)' }}>
          <div className="flex items-center gap-2">
            <Keyboard className="w-4 h-4" style={{ color: 'var(--accent)' }} />
            <h2 className="text-sm font-semibold" style={{ color: 'var(--text-primary)' }}>اختصارات لوحة المفاتيح</h2>
          </div>
          <button
            onClick={() => setOpen(false)}
            className="p-1 rounded hover:bg-[var(--bg-surface-3)]"
            style={{ color: 'var(--text-secondary)' }}
          >
            <X className="w-4 h-4" />
          </button>
        </div>
        <div className="overflow-y-auto max-h-[60vh] p-4 space-y-4">
          {categories.map((cat) => (
            <div key={cat}>
              <p className="text-[10px] font-bold uppercase tracking-wider mb-1.5" style={{ color: 'var(--accent)' }}>
                {cat}
              </p>
              <div className="space-y-1">
                {SHORTCUTS.filter((s) => s.category === cat).map((s) => (
                  <div
                    key={s.keys}
                    className="flex items-center justify-between py-1.5 px-2 rounded"
                    style={{ background: 'var(--bg-surface-2)' }}
                  >
                    <span className="text-[11px]" style={{ color: 'var(--text-primary)' }}>{s.desc}</span>
                    <kbd
                      className="text-[10px] font-mono px-1.5 py-0.5 rounded"
                      style={{ background: 'var(--bg-surface-3)', color: 'var(--text-primary)', border: '1px solid var(--border-default)' }}
                    >
                      {s.keys}
                    </kbd>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
        <div className="p-3 border-t text-center" style={{ borderColor: 'var(--border-subtle)' }}>
          <p className="text-[10px]" style={{ color: 'var(--text-tertiary)' }}>
            اضغط <kbd className="px-1 rounded font-mono" style={{ background: 'var(--bg-surface-3)' }}>?</kbd> في أي وقت لفتح هذه القائمة
          </p>
        </div>
      </div>
    </div>
  );
}
