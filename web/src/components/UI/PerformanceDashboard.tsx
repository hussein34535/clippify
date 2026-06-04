// PerformanceDashboard.tsx
// Phase 12 — Performance: FPS monitor, memory, render time.

import { useState, useEffect } from 'react';
import { Activity, X } from 'lucide-react';

interface PerfStats {
  fps: number;
  frameTime: number;  // ms
  memory: number;     // MB (if available)
}

export default function PerformanceDashboard() {
  const [open, setOpen] = useState(false);
  const [stats, setStats] = useState<PerfStats>({ fps: 0, frameTime: 0, memory: 0 });
  const [samples, setSamples] = useState<number[]>([]);

  useEffect(() => {
    if (!open) return;
    let frameCount = 0;
    let lastTime = performance.now();
    let raf: number;

    const tick = () => {
      frameCount++;
      const now = performance.now();
      const elapsed = now - lastTime;
      if (elapsed >= 1000) {
        const fps = Math.round((frameCount * 1000) / elapsed);
        const frameTime = elapsed / frameCount;
        const memory = (performance as any).memory?.usedJSHeapSize
          ? Math.round((performance as any).memory.usedJSHeapSize / (1024 * 1024))
          : 0;
        setStats({ fps, frameTime, memory });
        setSamples((s) => [...s.slice(-30), fps]);
        frameCount = 0;
        lastTime = now;
      }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [open]);

  const max = Math.max(60, ...samples);

  return (
    <div className="relative">
      <button
        onClick={() => setOpen(!open)}
        className="w-7 h-7 rounded-full flex items-center justify-center transition-all cursor-pointer hover:bg-[var(--bg-surface-3)]"
        style={{ color: stats.fps > 0 && stats.fps < 30 ? '#FF453A' : 'var(--text-secondary)' }}
        title="مراقب الأداء"
      >
        <Activity className="w-4 h-4" />
      </button>

      {open && (
        <div
          className="absolute top-9 left-0 w-72 rounded-lg border shadow-xl z-50 overflow-hidden"
          style={{ background: 'var(--bg-surface-1)', borderColor: 'var(--border-default)' }}
        >
          <div className="p-3 border-b flex items-center justify-between" style={{ borderColor: 'var(--border-subtle)' }}>
            <p className="text-[11px] font-semibold flex items-center gap-1.5" style={{ color: 'var(--text-primary)' }}>
              <Activity className="w-3.5 h-3.5" style={{ color: 'var(--accent)' }} />
              مراقب الأداء
            </p>
            <button
              onClick={() => setOpen(false)}
              className="p-0.5 rounded hover:bg-[var(--bg-surface-3)]"
              style={{ color: 'var(--text-secondary)' }}
            >
              <X className="w-3.5 h-3.5" />
            </button>
          </div>

          <div className="p-3 grid grid-cols-3 gap-2">
            <div className="text-center p-2 rounded" style={{ background: 'var(--bg-surface-2)' }}>
              <p className="text-[9px] mb-0.5" style={{ color: 'var(--text-tertiary)' }}>FPS</p>
              <p className="text-base font-bold" style={{ color: stats.fps >= 50 ? '#30D158' : stats.fps >= 30 ? 'var(--accent)' : '#FF453A' }}>
                {stats.fps}
              </p>
            </div>
            <div className="text-center p-2 rounded" style={{ background: 'var(--bg-surface-2)' }}>
              <p className="text-[9px] mb-0.5" style={{ color: 'var(--text-tertiary)' }}>Frame</p>
              <p className="text-base font-bold" style={{ color: 'var(--text-primary)' }}>
                {stats.frameTime.toFixed(1)}<span className="text-[9px]">ms</span>
              </p>
            </div>
            <div className="text-center p-2 rounded" style={{ background: 'var(--bg-surface-2)' }}>
              <p className="text-[9px] mb-0.5" style={{ color: 'var(--text-tertiary)' }}>RAM</p>
              <p className="text-base font-bold" style={{ color: 'var(--text-primary)' }}>
                {stats.memory > 0 ? `${stats.memory}` : '–'}<span className="text-[9px]">MB</span>
              </p>
            </div>
          </div>

          <div className="px-3 pb-3">
            <p className="text-[9px] mb-1" style={{ color: 'var(--text-tertiary)' }}>آخر 30 ثانية</p>
            <div className="flex items-end gap-px h-12">
              {Array.from({ length: 30 }).map((_, i) => {
                const v = samples[i] || 0;
                const h = (v / max) * 100;
                return (
                  <div
                    key={i}
                    className="flex-1 rounded-t"
                    style={{
                      height: `${h}%`,
                      background: v >= 50 ? '#30D158' : v >= 30 ? 'var(--accent)' : '#FF453A',
                      minHeight: 1,
                    }}
                  />
                );
              })}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
