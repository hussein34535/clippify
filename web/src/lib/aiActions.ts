// aiActions.ts
// Client-side wrapper for AI tool execution (Phase 0+)
// Sends tool calls to backend /api/ai/execute and applies state patches

import axios from 'axios';
import { API_BASE } from '../api';
import { produce } from 'immer';
import { useStore } from '../store';
import { trackEvent } from './analytics';

export interface AIAction {
  name: string;
  args: Record<string, any>;
}

export interface ExecutionResult {
  ok: boolean;
  new_state: any;
  messages: string[];
  errors: string[];
  results: Array<{ name: string; ok: boolean; message: string; patch: any }>;
}

let _toastFn: ((msg: string, type?: 'success' | 'error' | 'info') => void) | null = null;
let _recorder: ((action: AIAction) => void) | null = null;

export function setToastHandler(fn: typeof _toastFn) {
  _toastFn = fn;
}

export function setMacroRecorder(fn: typeof _recorder) {
  _recorder = fn;
}

function notify(msg: string, type: 'success' | 'error' | 'info' = 'success') {
  if (_toastFn) _toastFn(msg, type);
  else console.log(`[AI ${type}] ${msg}`);
}

export async function executeAIActions(actions: AIAction[]): Promise<ExecutionResult | null> {
  if (actions.length === 0) return null;
  // Record to macro buffer if recording (Phase 5)
  if (_recorder) actions.forEach((a) => _recorder!(a));
  // Track in analytics (Phase 14)
  const start = performance.now();
  const timelineState = useStore.getState().timelineState;
  if (!timelineState) {
    notify('مفيش timeline state', 'error');
    return null;
  }
  try {
    const resp = await axios.post(`${API_BASE}/api/ai/execute`, {
      actions,
      timeline_state: timelineState,
    });
    const data = resp.data;
    if (data.new_state) {
      applyStatePatch(data.new_state);
    }
    const summary = data.messages?.slice(0, 3).join(' • ') || 'تم';
    notify(summary, data.ok ? 'success' : 'error');
    // Analytics: track each action
    actions.forEach((a) => {
      const [cat] = a.name.split('.');
      trackEvent({ type: 'ai_action', category: cat, toolName: a.name, durationMs: performance.now() - start, projectId: timelineState.project_id });
    });
    return data;
  } catch (err: any) {
    const msg = err.response?.data?.detail || err.message || 'فشل';
    notify(`❌ ${msg}`, 'error');
    return null;
  }
}

export async function executeAIAction(name: string, args: Record<string, any> = {}): Promise<ExecutionResult | null> {
  return executeAIActions([{ name, args }]);
}

function applyStatePatch(patch: any) {
  const current = useStore.getState().timelineState;
  if (!current) return;
  const newState = produce(current, (draft: any) => {
    // Top-level scalars
    for (const key of ['currentTime', 'volume', 'muted', 'loop', 'aspectRatio', 'fitMode', 'fullscreen', 'zoomLevel', 'canvasZoom', 'mute', 'playbackSpeed', 'fps', 'timecodeFormat', 'fitMode', 'snapMode', 'magneticEnabled', 'inPoint', 'outPoint', 'linkedSelection', 'editMode', 'safeArea', 'gridOverlay', 'waveformOverlay', 'zebra', 'focusPeaking', 'falseColor', 'jogMode', 'abCompare', 'autoDucking', 'noiseReduction', 'sfxVolume', 'musicVolume', 'voiceVolume', 'sampleRate', 'bitDepth', 'lufsTarget', 'silenceThreshold', 'duckingAmount', 'masterLimiter', 'roi', 'exportPreset', 'exportQuality', 'exportFormat', 'exportCodec', 'exportBitrate', 'exportFramerate', 'exportResolution', 'exportHDR', 'exportEmbedMeta', 'exportJob', 'aiJob', 'audioJob', 'cancelRender', 'jogMode']) {
      if (key in patch) {
        draft[key] = patch[key];
      }
    }
    // Special: tracks
    if (patch.tracks) {
      draft.tracks = patch.tracks;
    }
    // Special: markers list
    if (patch.markers !== undefined) {
      draft.markers = patch.markers;
    }
    // Special: nested sequences
    if (patch.nested_sequences !== undefined) {
      draft.nested_sequences = patch.nested_sequences;
    }
    // Special: subtitles list
    if (patch.subtitles !== undefined) {
      draft.subtitles = patch.subtitles;
    }
    // Special: words
    if (patch.words !== undefined) {
      // words live in store, not in timelineState — but update if present
      useStore.getState().setWords(patch.words);
    }
    // Special: audio_settings
    if (patch.audio_settings) {
      draft.audio_settings = { ...(draft.audio_settings || {}), ...patch.audio_settings };
    }
    // Special: subtitle_settings
    if (patch.subtitle_settings) {
      draft.subtitle_settings = { ...(draft.subtitle_settings || {}), ...patch.subtitle_settings };
    }
    // Special: sfx_plan
    if (patch.sfx_plan !== undefined) {
      draft.sfx_plan = patch.sfx_plan;
    }
  });
  useStore.getState().setTimelineState(newState);
  // Mirror certain properties to top-level store for components that read them
  if (patch.currentTime !== undefined) useStore.getState().seek(patch.currentTime);
  if (patch.isPlaying !== undefined) useStore.getState().setPlaying(patch.isPlaying);
}

// ─── Convenience functions for common actions ───

export const ai = {
  // Playback
  play: () => useStore.getState().setPlaying(true),
  pause: () => useStore.getState().setPlaying(false),
  togglePlay: () => useStore.getState().togglePlaying(),
  seek: (t: number) => useStore.getState().seek(t),
  seekBy: (delta: number) => useStore.getState().seek(useStore.getState().currentTime + delta),
  frameStep: (dir: 1 | -1) => {
    const fps = useStore.getState().timelineState?.settings?.fps || 30;
    useStore.getState().seek(useStore.getState().currentTime + dir / fps);
  },
  skip: (sec: number) => useStore.getState().seek(useStore.getState().currentTime + sec),
  toggleLoop: () => executeAIAction('playback.toggle_loop'),
  toggleMute: () => executeAIAction('playback.toggle_mute'),
  setVolume: (v: number) => executeAIAction('playback.set_volume', { volume: v }),
  setAspect: (ratio: string) => executeAIAction('playback.set_aspect_ratio', { ratio }),
  toggleFullscreen: () => {
    if (document.fullscreenElement) {
      document.exitFullscreen();
    } else {
      document.documentElement.requestFullscreen();
    }
  },

  // Timeline
  setZoom: (px: number) => executeAIAction('timeline.set_zoom_level', { pixels_per_second: px }),
  split: () => executeAIAction('timeline.razor_at_playhead'),
  delete: (clipId: string) => executeAIAction('timeline.delete_clip', { clip_id: clipId }),
  toggleMagnetic: () => executeAIAction('timeline.toggle_magnetic', { enabled: true }),
  setSnapMode: (mode: 'off' | 'playhead' | 'clips' | 'grid') => executeAIAction('timeline.set_snap_mode', { mode }),
  setIn: () => executeAIAction('timeline.set_in_point', { time: useStore.getState().currentTime }),
  setOut: () => executeAIAction('timeline.set_out_point', { time: useStore.getState().currentTime }),
  addMarker: (color: string = 'yellow', name: string = 'Marker') => executeAIAction('timeline.add_marker', { time: useStore.getState().currentTime, color, name }),

  // Effects
  setBrightness: (v: number, clipId?: string) => executeAIAction('effects.set_brightness', { brightness: v, clip_id: clipId }),
  setContrast: (v: number, clipId?: string) => executeAIAction('effects.set_contrast', { contrast: v, clip_id: clipId }),
  setSaturation: (v: number, clipId?: string) => executeAIAction('effects.set_saturation', { saturation: v, clip_id: clipId }),
  setOpacity: (v: number, clipId?: string) => executeAIAction('effects.set_opacity', { opacity: v, clip_id: clipId }),

  // AI
  autoCut: () => executeAIAction('ai.auto_cut_silences'),
  autoFrame: () => executeAIAction('ai.auto_framing'),
  smartRecut: () => executeAIAction('ai.smart_recut'),
  removeFiller: () => executeAIAction('ai.remove_filler_words'),
  removeBackground: () => executeAIAction('ai.remove_background'),
  beatSync: () => executeAIAction('ai.beat_sync'),
  scoreVirality: () => executeAIAction('ai.score_virality'),
  generateThumbnail: () => executeAIAction('ai.generate_thumbnail'),
  suggestBrolls: (query: string) => executeAIAction('ai.suggest_brolls', { query }),
  detectScenes: () => executeAIAction('ai.detect_scenes'),
};
