// store.ts
// Centralized Zustand store for high-frequency, cross-cutting state
// that previously caused prop-drilling re-renders across many components.

import { create } from 'zustand';
import type { Word, TimelineState } from './types';

export type ClipType = 'video' | 'audio' | 'overlay' | 'subtitle';

interface AppState {
  // Playback (updated at 60fps from CanvasPreview)
  currentTime: number;
  duration: number;
  playing: boolean;

  // Selection (medium frequency)
  selectedClipId: string | null;
  selectedClipType: ClipType | null;

  // Transcript & media (read by Canvas, Inspector, Copilot)
  words: Word[];
  videoPath: string;

  // Timeline state mirror (synced from App.tsx useUndoRedo for read-only consumers like CopilotChat)
  // Editing goes through App.tsx's onChange to keep undo/redo intact.
  timelineState: TimelineState | null;

  // Actions
  setCurrentTime: (t: number) => void;
  setDuration: (d: number) => void;
  setPlaying: (p: boolean) => void;
  togglePlaying: () => void;
  seek: (t: number) => void;
  setSelectedClip: (id: string | null, type: ClipType | null) => void;
  setWords: (w: Word[]) => void;
  setVideoPath: (p: string) => void;
  setTimelineState: (s: TimelineState) => void;
}

export const useStore = create<AppState>((set) => ({
  currentTime: 0,
  duration: 0,
  playing: false,
  selectedClipId: null,
  selectedClipType: null,
  words: [],
  videoPath: '',
  timelineState: null,

  setCurrentTime: (currentTime) => set({ currentTime }),
  setDuration: (duration) => set({ duration }),
  setPlaying: (playing) => set({ playing }),
  togglePlaying: () => set((s) => ({ playing: !s.playing })),
  seek: (currentTime) => set({ currentTime }),
  setSelectedClip: (selectedClipId, selectedClipType) => set({ selectedClipId, selectedClipType }),
  setWords: (words) => set({ words }),
  setVideoPath: (videoPath) => set({ videoPath }),
  setTimelineState: (timelineState) => set({ timelineState }),
}));

// Convenience selector hooks (memoized-friendly, no re-render if slice is shallow-equal)
export const useCurrentTime = () => useStore((s) => s.currentTime);
export const useDuration = () => useStore((s) => s.duration);
export const usePlaying = () => useStore((s) => s.playing);
export const useSelectedClipId = () => useStore((s) => s.selectedClipId);
export const useSelectedClipType = () => useStore((s) => s.selectedClipType);
export const useWords = () => useStore((s) => s.words);
export const useVideoPath = () => useStore((s) => s.videoPath);
