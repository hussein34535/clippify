// MacroMenu.tsx
// Phase 5 — Macro Recording UI.
// Provides Record/Stop/Save/Replay/Delete macros.

import { useState, useEffect, useRef } from 'react';
import { Circle, Square, Play, Trash2, Save, FolderOpen } from 'lucide-react';
import { useMacroRecorder, listMacros, saveMacro, deleteMacro, replayMacro, type Macro } from '../../lib/macroRecorder';
import { setMacroRecorder } from '../../lib/aiActions';

export default function MacroMenu() {
  const [open, setOpen] = useState(false);
  const [macros, setMacros] = useState<Macro[]>([]);
  const [recordingName, setRecordingName] = useState('');
  const menuRef = useRef<HTMLDivElement>(null);
  const { recording, recorded, record, start, stop, clear } = useMacroRecorder();

  useEffect(() => {
    setMacroRecorder(record);
    return () => setMacroRecorder(null);
  }, [record]);

  useEffect(() => {
    if (open) setMacros(listMacros());
  }, [open]);

  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) setOpen(false);
    };
    if (open) document.addEventListener('mousedown', onClick);
    return () => document.removeEventListener('mousedown', onClick);
  }, [open]);

  const handleStart = () => {
    setRecordingName(`ماكرو ${listMacros().length + 1}`);
    start();
    setOpen(false);
  };

  const handleStop = () => {
    stop();
  };

  const handleSave = () => {
    if (recorded.length === 0) return;
    saveMacro(recordingName || `ماكرو ${listMacros().length + 1}`, recorded);
    clear();
    setRecordingName('');
    setMacros(listMacros());
  };

  const handleReplay = (macro: Macro) => {
    setOpen(false);
    replayMacro(macro, {
      onComplete: () => console.log(`[Macro] replayed ${macro.name}`),
    });
  };

  const handleDelete = (id: string) => {
    deleteMacro(id);
    setMacros(listMacros());
  };

  return (
    <div className="relative" ref={menuRef}>
      <button
        onClick={() => setOpen(!open)}
        className="w-7 h-7 rounded-full flex items-center justify-center transition-all cursor-pointer hover:bg-[var(--bg-surface-3)]"
        style={{ color: recording ? '#FF453A' : 'var(--text-secondary)' }}
        title={recording ? `جاري التسجيل: ${recorded.length} إجراء` : 'الماكرو (تسجيل/تشغيل)'}
      >
        {recording ? <Circle className="w-3.5 h-3.5 fill-current animate-pulse" /> : <FolderOpen className="w-4 h-4" />}
      </button>

      {open && (
        <div
          className="absolute top-9 left-0 w-72 rounded-lg border shadow-xl z-50 overflow-hidden"
          style={{ background: 'var(--bg-surface-1)', borderColor: 'var(--border-default)' }}
        >
          <div className="p-3 border-b" style={{ borderColor: 'var(--border-subtle)' }}>
            <p className="text-[11px] font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>الماكرو</p>
            {recording ? (
              <div className="flex gap-2">
                <button
                  onClick={handleStop}
                  className="flex-1 flex items-center justify-center gap-1.5 py-1.5 rounded text-[11px] font-semibold"
                  style={{ background: '#FF453A', color: '#fff' }}
                >
                  <Square className="w-3 h-3 fill-current" /> إيقاف ({recorded.length})
                </button>
              </div>
            ) : recorded.length > 0 ? (
              <div className="flex gap-2">
                <input
                  type="text"
                  value={recordingName}
                  onChange={(e) => setRecordingName(e.target.value)}
                  placeholder="اسم الماكرو"
                  className="flex-1 px-2 py-1 rounded text-[11px]"
                  style={{ background: 'var(--bg-surface-3)', border: '1px solid var(--border-default)', color: 'var(--text-primary)' }}
                />
                <button
                  onClick={handleSave}
                  className="px-2 py-1 rounded text-[11px] font-semibold flex items-center gap-1"
                  style={{ background: 'var(--accent)', color: '#fff' }}
                  title="حفظ"
                >
                  <Save className="w-3 h-3" />
                </button>
                <button
                  onClick={clear}
                  className="px-2 py-1 rounded text-[11px]"
                  style={{ background: 'var(--bg-surface-3)', color: 'var(--text-secondary)' }}
                  title="حذف"
                >
                  <Trash2 className="w-3 h-3" />
                </button>
              </div>
            ) : (
              <button
                onClick={handleStart}
                className="w-full flex items-center justify-center gap-1.5 py-1.5 rounded text-[11px] font-semibold"
                style={{ background: 'var(--bg-surface-3)', color: 'var(--text-primary)' }}
              >
                <Circle className="w-3 h-3 fill-current" style={{ color: '#FF453A' }} /> ابدأ التسجيل
              </button>
            )}
          </div>

          <div className="max-h-64 overflow-y-auto">
            {macros.length === 0 ? (
              <p className="p-4 text-center text-[10px]" style={{ color: 'var(--text-tertiary)' }}>
                مفيش ماكرو محفوظ
              </p>
            ) : (
              macros.map((m) => (
                <div
                  key={m.id}
                  className="flex items-center gap-2 px-3 py-2 hover:bg-[var(--bg-surface-2)] transition-colors"
                >
                  <button
                    onClick={() => handleReplay(m)}
                    className="flex-1 text-right text-[11px] truncate"
                    style={{ color: 'var(--text-primary)' }}
                    title={`${m.actions.length} إجراء — ${new Date(m.createdAt).toLocaleString('ar-EG')}`}
                  >
                    <Play className="w-3 h-3 inline ml-1" style={{ color: 'var(--accent)' }} />
                    {m.name} <span style={{ color: 'var(--text-tertiary)' }}>({m.actions.length})</span>
                  </button>
                  <button
                    onClick={() => handleDelete(m.id)}
                    className="p-1 rounded hover:bg-[var(--bg-surface-3)]"
                    style={{ color: 'var(--text-tertiary)' }}
                  >
                    <Trash2 className="w-3 h-3" />
                  </button>
                </div>
              ))
            )}
          </div>
        </div>
      )}
    </div>
  );
}
