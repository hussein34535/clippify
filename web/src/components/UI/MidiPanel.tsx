// MidiPanel.tsx
// Phase 19 — Hardware: MIDI controller setup & mapping.

import { useState, useEffect } from 'react';
import { Piano, X, Usb } from 'lucide-react';
import { midiController, DEFAULT_MAPPINGS, buildMappingKey } from '../../lib/midiController';
import { executeAIAction } from '../../lib/aiActions';

const STORAGE_KEY = 'clipai_midi_mappings';

function loadMappings(): Record<string, string> {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? { ...DEFAULT_MAPPINGS, ...JSON.parse(raw) } : { ...DEFAULT_MAPPINGS };
  } catch {
    return { ...DEFAULT_MAPPINGS };
  }
}

export default function MidiPanel() {
  const [open, setOpen] = useState(false);
  const [enabled, setEnabled] = useState(false);
  const [devices, setDevices] = useState<Array<{ id: string; name: string; manufacturer: string }>>([]);
  const [mappings] = useState<Record<string, string>>(loadMappings());
  const [lastEvent, setLastEvent] = useState<string>('');

  useEffect(() => {
    if (open) {
      setEnabled(midiController.isEnabled());
      setDevices(midiController.listDevices());
    }
  }, [open]);

  const handleEnable = async () => {
    const ok = await midiController.enable();
    setEnabled(ok);
    setDevices(midiController.listDevices());
  };

  useEffect(() => {
    if (!enabled) return;
    const unsub = midiController.onMessage((event) => {
      const key = buildMappingKey(event);
      setLastEvent(`${event.type} ch${event.channel} ${event.note !== undefined ? `note ${event.note}` : `cc ${event.controller}`} → v${event.value}`);
      const action = mappings[key];
      if (action) {
        executeAIAction(action);
      }
    });
    return unsub;
  }, [enabled, mappings]);

  return (
    <div className="relative">
      <button
        onClick={() => setOpen(!open)}
        className="w-7 h-7 rounded-full flex items-center justify-center transition-all cursor-pointer hover:bg-[var(--bg-surface-3)]"
        style={{ color: enabled ? 'var(--accent)' : 'var(--text-secondary)' }}
        title={`MIDI Controller (${enabled ? 'مفعّل' : 'معطل'})`}
      >
        <Piano className="w-4 h-4" />
      </button>

      {open && (
        <div
          className="absolute top-9 left-0 w-80 rounded-lg border shadow-xl z-50 overflow-hidden"
          style={{ background: 'var(--bg-surface-1)', borderColor: 'var(--border-default)' }}
        >
          <div className="p-3 border-b flex items-center justify-between" style={{ borderColor: 'var(--border-subtle)' }}>
            <p className="text-[11px] font-semibold flex items-center gap-1.5" style={{ color: 'var(--text-primary)' }}>
              <Usb className="w-3.5 h-3.5" style={{ color: 'var(--accent)' }} />
              MIDI Controller
            </p>
            <button
              onClick={() => setOpen(false)}
              className="p-0.5 rounded hover:bg-[var(--bg-surface-3)]"
              style={{ color: 'var(--text-secondary)' }}
            >
              <X className="w-3.5 h-3.5" />
            </button>
          </div>

          <div className="p-3">
            <button
              onClick={handleEnable}
              disabled={enabled}
              className="w-full py-2 rounded text-[11px] font-semibold disabled:opacity-40"
              style={{ background: enabled ? 'var(--bg-surface-3)' : 'var(--accent)', color: enabled ? 'var(--text-secondary)' : '#fff' }}
            >
              {enabled ? '✓ مفعّل' : 'فعّل MIDI'}
            </button>

            {devices.length > 0 && (
              <div className="mt-3">
                <p className="text-[9px] font-bold uppercase tracking-wider mb-1" style={{ color: 'var(--text-tertiary)' }}>
                  الأجهزة المتصلة
                </p>
                {devices.map((d) => (
                  <p key={d.id} className="text-[11px] py-0.5" style={{ color: 'var(--text-primary)' }}>
                    🎹 {d.name} <span style={{ color: 'var(--text-tertiary)' }}>({d.manufacturer})</span>
                  </p>
                ))}
              </div>
            )}

            {lastEvent && (
              <p className="mt-2 p-2 rounded text-[10px] font-mono" style={{ background: 'var(--bg-surface-2)', color: 'var(--accent)' }}>
                {lastEvent}
              </p>
            )}

            <details className="mt-3">
              <summary className="text-[10px] cursor-pointer" style={{ color: 'var(--accent)' }}>
                المابنجز الافتراضية ({Object.keys(mappings).length})
              </summary>
              <div className="mt-2 space-y-0.5 text-[10px]" style={{ color: 'var(--text-secondary)' }}>
                {Object.entries(mappings).map(([key, action]) => (
                  <div key={key} className="flex justify-between">
                    <span className="font-mono">{key}</span>
                    <span style={{ color: 'var(--text-tertiary)' }}>→ {action}</span>
                  </div>
                ))}
              </div>
            </details>
          </div>
        </div>
      )}
    </div>
  );
}
