// utils/tauri.ts
// Helpers to detect Tauri runtime and register OS-level drag-drop listeners.

export const isTauri = (): boolean => {
  if (typeof window === 'undefined') return false;
  return '__TAURI_INTERNALS__' in window || '__TAURI__' in window;
};

export type TauriDragDropHandler = (paths: string[]) => void;

export const registerTauriDragDrop = async (
  onDrop: TauriDragDropHandler
): Promise<() => void> => {
  if (!isTauri()) return () => {};

  try {
    const webviewModule = await import('@tauri-apps/api/webview');
    const webview = webviewModule.getCurrentWebview();
    const unlisten = await webview.onDragDropEvent((event) => {
      const payload = event.payload as { type: string; paths?: string[] };
      if (payload?.type === 'drop' && Array.isArray(payload.paths) && payload.paths.length > 0) {
        onDrop(payload.paths);
      }
    });
    return unlisten;
  } catch (err) {
    console.warn('Tauri drag-drop listener failed:', err);
    return () => {};
  }
};
