// AnalyticsDashboard.tsx
// Phase 14 — Analytics: User productivity stats, AI usage, time saved.

import { useState, useEffect } from 'react';
import { BarChart3, X, TrendingUp, Clock, Zap, Trash2 } from 'lucide-react';
import { getSummary, clearAnalytics, type AnalyticsSummary } from '../../lib/analytics';

export default function AnalyticsDashboard() {
  const [open, setOpen] = useState(false);
  const [summary, setSummary] = useState<AnalyticsSummary | null>(null);

  useEffect(() => {
    if (open) setSummary(getSummary());
  }, [open]);

  if (!open) return (
    <button
      onClick={() => setOpen(true)}
      className="w-7 h-7 rounded-full flex items-center justify-center transition-all cursor-pointer hover:bg-[var(--bg-surface-3)]"
      style={{ color: 'var(--text-secondary)' }}
      title="إحصائيات الاستخدام"
    >
      <BarChart3 className="w-4 h-4" />
    </button>
  );

  if (!summary) return null;

  const maxHour = Math.max(1, ...summary.byHour);
  const maxDay = Math.max(1, ...summary.byDay);

  return (
    <div className="relative">
      <button
        onClick={() => setOpen(false)}
        className="fixed inset-0 z-40 bg-transparent"
        aria-label="إغلاق"
      />
      <div
        className="absolute top-9 left-0 w-80 rounded-lg border shadow-xl z-50 overflow-hidden max-h-[80vh] flex flex-col"
        style={{ background: 'var(--bg-surface-1)', borderColor: 'var(--border-default)' }}
      >
        <div className="p-3 border-b flex items-center justify-between" style={{ borderColor: 'var(--border-subtle)' }}>
          <p className="text-[11px] font-semibold flex items-center gap-1.5" style={{ color: 'var(--text-primary)' }}>
            <BarChart3 className="w-3.5 h-3.5" style={{ color: 'var(--accent)' }} />
            إحصائيات الاستخدام
          </p>
          <div className="flex items-center gap-1">
            <button
              onClick={() => { clearAnalytics(); setSummary(getSummary()); }}
              className="p-1 rounded hover:bg-[var(--bg-surface-3)]"
              style={{ color: 'var(--text-tertiary)' }}
              title="مسح الإحصائيات"
            >
              <Trash2 className="w-3.5 h-3.5" />
            </button>
            <button
              onClick={() => setOpen(false)}
              className="p-1 rounded hover:bg-[var(--bg-surface-3)]"
              style={{ color: 'var(--text-secondary)' }}
            >
              <X className="w-3.5 h-3.5" />
            </button>
          </div>
        </div>

        <div className="overflow-y-auto p-3 space-y-3">
          {/* Top stats */}
          <div className="grid grid-cols-2 gap-2">
            <div className="p-2 rounded" style={{ background: 'var(--bg-surface-2)' }}>
              <p className="text-[9px] flex items-center gap-1" style={{ color: 'var(--text-tertiary)' }}>
                <Zap className="w-2.5 h-2.5" /> إجراءات AI
              </p>
              <p className="text-base font-bold" style={{ color: 'var(--accent)' }}>{summary.totalAiActions}</p>
            </div>
            <div className="p-2 rounded" style={{ background: 'var(--bg-surface-2)' }}>
              <p className="text-[9px] flex items-center gap-1" style={{ color: 'var(--text-tertiary)' }}>
                <Clock className="w-2.5 h-2.5" /> وقت موفّر
              </p>
              <p className="text-base font-bold" style={{ color: '#30D158' }}>{summary.estimatedTimeSavedMin}<span className="text-[9px]">د</span></p>
            </div>
            <div className="p-2 rounded" style={{ background: 'var(--bg-surface-2)' }}>
              <p className="text-[9px]" style={{ color: 'var(--text-tertiary)' }}>تعديلات يدوية</p>
              <p className="text-base font-bold" style={{ color: 'var(--text-primary)' }}>{summary.totalEdits}</p>
            </div>
            <div className="p-2 rounded" style={{ background: 'var(--bg-surface-2)' }}>
              <p className="text-[9px]" style={{ color: 'var(--text-tertiary)' }}>صادرات</p>
              <p className="text-base font-bold" style={{ color: 'var(--text-primary)' }}>{summary.totalExports}</p>
            </div>
          </div>

          {/* Hour histogram */}
          <div>
            <p className="text-[9px] font-bold uppercase tracking-wider mb-1" style={{ color: 'var(--text-tertiary)' }}>
              نشاط اليوم (24 ساعة)
            </p>
            <div className="flex items-end gap-px h-12">
              {summary.byHour.map((v, i) => (
                <div
                  key={i}
                  className="flex-1 rounded-t"
                  style={{
                    height: `${(v / maxHour) * 100}%`,
                    background: v > 0 ? 'var(--accent)' : 'var(--bg-surface-3)',
                    minHeight: 1,
                  }}
                  title={`${i}:00 — ${v} إجراء`}
                />
              ))}
            </div>
          </div>

          {/* Day histogram */}
          <div>
            <p className="text-[9px] font-bold uppercase tracking-wider mb-1" style={{ color: 'var(--text-tertiary)' }}>
              آخر 7 أيام
            </p>
            <div className="flex items-end gap-1 h-10">
              {summary.byDay.map((v, i) => (
                <div key={i} className="flex-1 flex flex-col items-center">
                  <div
                    className="w-full rounded-t"
                    style={{
                      height: `${(v / maxDay) * 100}%`,
                      background: v > 0 ? 'var(--accent)' : 'var(--bg-surface-3)',
                      minHeight: 1,
                    }}
                  />
                  <span className="text-[8px] mt-0.5" style={{ color: 'var(--text-tertiary)' }}>
                    {['ح', 'ن', 'ث', 'ر', 'خ', 'ج', 'س'][i]}
                  </span>
                </div>
              ))}
            </div>
          </div>

          {/* Top tools */}
          {summary.topTools.length > 0 && (
            <div>
              <p className="text-[9px] font-bold uppercase tracking-wider mb-1.5 flex items-center gap-1" style={{ color: 'var(--text-tertiary)' }}>
                <TrendingUp className="w-2.5 h-2.5" /> أكثر الأدوات استخداماً
              </p>
              <div className="space-y-1">
                {summary.topTools.slice(0, 5).map((t) => {
                  const max = summary.topTools[0].count;
                  return (
                    <div key={t.name} className="flex items-center gap-2">
                      <span className="text-[10px] truncate w-32" style={{ color: 'var(--text-primary)' }}>{t.name}</span>
                      <div className="flex-1 h-1.5 rounded-full overflow-hidden" style={{ background: 'var(--bg-surface-3)' }}>
                        <div
                          className="h-full rounded-full"
                          style={{ width: `${(t.count / max) * 100}%`, background: 'var(--accent)' }}
                        />
                      </div>
                      <span className="text-[9px] font-mono w-6 text-left" style={{ color: 'var(--text-tertiary)' }}>{t.count}</span>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {summary.totalEvents === 0 && (
            <p className="text-center text-[10px] py-4" style={{ color: 'var(--text-tertiary)' }}>
              مفيش بيانات بعد. ابدأ باستخدام الأدوات لرؤية الإحصائيات.
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
