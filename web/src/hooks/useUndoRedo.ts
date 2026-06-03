import { useState, useCallback, useRef } from 'react';

const MAX_HISTORY = 50;

export function useUndoRedo<T>(initial: T) {
  // Keep full history in a ref — avoids stale closure issues completely
  const historyRef = useRef<T[]>([initial]);
  const indexRef = useRef<number>(0);

  // We use a counter state just to trigger re-renders when history changes
  const [, rerender] = useState(0);
  const forceUpdate = useCallback(() => rerender(c => c + 1), []);

  const current = historyRef.current[indexRef.current];
  const canUndo = indexRef.current > 0;
  const canRedo = indexRef.current < historyRef.current.length - 1;

  const push = useCallback((next: T) => {
    // Discard any "future" states after current index
    const trimmed = historyRef.current.slice(0, indexRef.current + 1);
    trimmed.push(next);
    if (trimmed.length > MAX_HISTORY) trimmed.shift();
    historyRef.current = trimmed;
    indexRef.current = trimmed.length - 1;
    forceUpdate();
  }, [forceUpdate]);

  const undo = useCallback(() => {
    if (indexRef.current > 0) {
      indexRef.current -= 1;
      forceUpdate();
    }
  }, [forceUpdate]);

  const redo = useCallback(() => {
    if (indexRef.current < historyRef.current.length - 1) {
      indexRef.current += 1;
      forceUpdate();
    }
  }, [forceUpdate]);

  return { current, push, undo, redo, canUndo, canRedo };
}
