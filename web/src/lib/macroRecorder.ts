// macroRecorder.ts
// Phase 5 — Macro Recording (cross-cutting AI).
// Records a sequence of AI actions and replays them on demand.

import { useRef, useState, useCallback } from 'react';
import { executeAIAction } from './aiActions';
import type { AIAction } from './aiActions';

export interface Macro {
  id: string;
  name: string;
  actions: AIAction[];
  createdAt: number;
}

const STORAGE_KEY = 'clipai_macros';

export function listMacros(): Macro[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

export function saveMacro(name: string, actions: AIAction[]): Macro {
  const macros = listMacros();
  const macro: Macro = {
    id: `macro_${Date.now()}`,
    name,
    actions,
    createdAt: Date.now(),
  };
  macros.unshift(macro);
  localStorage.setItem(STORAGE_KEY, JSON.stringify(macros.slice(0, 50)));
  return macro;
}

export function deleteMacro(id: string) {
  const macros = listMacros().filter((m) => m.id !== id);
  localStorage.setItem(STORAGE_KEY, JSON.stringify(macros));
}

export function replayMacro(macro: Macro, opts?: { onProgress?: (i: number, total: number) => void; onComplete?: () => void }) {
  macro.actions.forEach((action, i) => {
    setTimeout(() => {
      executeAIAction(action.name, action.args).then(() => {
        opts?.onProgress?.(i + 1, macro.actions.length);
        if (i === macro.actions.length - 1) opts?.onComplete?.();
      });
    }, i * 200);
  });
}

export function useMacroRecorder() {
  const [recording, setRecording] = useState(false);
  const [recorded, setRecorded] = useState<AIAction[]>([]);
  const bufferRef = useRef<AIAction[]>([]);

  const record = useCallback((action: AIAction) => {
    if (!recording) return;
    bufferRef.current.push(action);
  }, [recording]);

  const start = useCallback(() => {
    bufferRef.current = [];
    setRecorded([]);
    setRecording(true);
  }, []);

  const stop = useCallback(() => {
    setRecording(false);
    setRecorded([...bufferRef.current]);
    return [...bufferRef.current];
  }, []);

  const clear = useCallback(() => {
    bufferRef.current = [];
    setRecorded([]);
  }, []);

  return { recording, recorded, record, start, stop, clear };
}
