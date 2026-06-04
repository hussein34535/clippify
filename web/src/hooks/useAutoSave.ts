// useAutoSave.ts
// Debounced localStorage auto-save for app state.
// Phase 10 — Project Management.

import { useEffect, useRef } from 'react';

const STORAGE_KEY = 'clipai_autosave';
const TIMESTAMP_KEY = 'clipai_last_saved';
const DEBOUNCE_MS = 1500;

export function useAutoSave(state: any, enabled = true) {
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lastSerializedRef = useRef<string>('');

  useEffect(() => {
    if (!enabled) return;
    if (!state) return;

    try {
      const serialized = JSON.stringify(state);
      if (serialized === lastSerializedRef.current) return;
      lastSerializedRef.current = serialized;

      if (timerRef.current) clearTimeout(timerRef.current);
      timerRef.current = setTimeout(() => {
        try {
          localStorage.setItem(STORAGE_KEY, serialized);
          localStorage.setItem(TIMESTAMP_KEY, new Date().toISOString());
        } catch (e) {
          // localStorage quota — fail silently
        }
      }, DEBOUNCE_MS);
    } catch (e) {
      // Circular references or other JSON issues — skip
    }

    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, [state, enabled]);
}

export function loadAutoSave<T = any>(): T | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

export function clearAutoSave() {
  try {
    localStorage.removeItem(STORAGE_KEY);
    localStorage.removeItem(TIMESTAMP_KEY);
  } catch {}
}
