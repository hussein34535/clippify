// templates.ts
// Phase 18 — Templates: Save/load timeline templates (intro, outro, transition, etc.)

import type { TimelineState } from '../types';

export interface TimelineTemplate {
  id: string;
  name: string;
  nameAr: string;
  category: 'intro' | 'outro' | 'transition' | 'lower-third' | 'full';
  thumbnail?: string;
  state: Partial<TimelineState>;
  createdAt: number;
}

const STORAGE_KEY = 'clipai_templates';
const BUILTIN_KEY = 'clipai_builtin_templates_seeded';

const BUILTIN_TEMPLATES: TimelineTemplate[] = [
  {
    id: 'tpl_intro_classic',
    name: 'Classic Intro',
    nameAr: 'مقدمة كلاسيكية',
    category: 'intro',
    state: {
      project_name: 'مقدمة كلاسيكية',
      settings: { width: 1080, height: 1920, fps: 30, sample_rate: 44100, aspect_ratio: '9:16' },
      tracks: {
        video: [{ id: 'v1', name: 'V1', index: 0, clips: [] }],
        audio: [{ id: 'a1', name: 'A1', index: 0, clips: [] }],
        subtitles: [{ id: 'sub1', clips: [] }],
        overlays: [{ id: 'ov1', clips: [] }],
      },
    },
    createdAt: 0,
  },
  {
    id: 'tpl_outro_subscribe',
    name: 'Subscribe Outro',
    nameAr: 'خاتمة (اشترك)',
    category: 'outro',
    state: {
      project_name: 'خاتمة',
      settings: { width: 1080, height: 1920, fps: 30, sample_rate: 44100, aspect_ratio: '9:16' },
      tracks: {
        video: [{ id: 'v1', name: 'V1', index: 0, clips: [] }],
        audio: [{ id: 'a1', name: 'A1', index: 0, clips: [] }],
        subtitles: [{ id: 'sub1', clips: [] }],
        overlays: [{ id: 'ov1', clips: [] }],
      },
    },
    createdAt: 0,
  },
  {
    id: 'tpl_podcast',
    name: 'Podcast Style',
    nameAr: 'ستايل بودكاست',
    category: 'full',
    state: {
      project_name: 'بودكاست',
      settings: { width: 1080, height: 1920, fps: 30, sample_rate: 44100, aspect_ratio: '9:16' },
      tracks: {
        video: [{ id: 'v1', name: 'V1', index: 0, clips: [] }],
        audio: [{ id: 'a1', name: 'Music', index: 0, clips: [] }],
        subtitles: [{ id: 'sub1', clips: [] }],
        overlays: [{ id: 'ov1', clips: [] }],
      },
    },
    createdAt: 0,
  },
];

export function ensureBuiltinTemplates() {
  if (typeof window === 'undefined') return;
  if (localStorage.getItem(BUILTIN_KEY)) return;
  const existing = listTemplates();
  const merged = [...BUILTIN_TEMPLATES, ...existing];
  localStorage.setItem(STORAGE_KEY, JSON.stringify(merged));
  localStorage.setItem(BUILTIN_KEY, '1');
}

export function listTemplates(): TimelineTemplate[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

export function saveTemplate(name: string, nameAr: string, category: TimelineTemplate['category'], state: Partial<TimelineState>): TimelineTemplate {
  const tpl: TimelineTemplate = {
    id: `tpl_${Date.now()}`,
    name,
    nameAr,
    category,
    state,
    createdAt: Date.now(),
  };
  const list = listTemplates();
  list.unshift(tpl);
  localStorage.setItem(STORAGE_KEY, JSON.stringify(list.slice(0, 100)));
  return tpl;
}

export function deleteTemplate(id: string) {
  const list = listTemplates().filter((t) => t.id !== id || id.startsWith('tpl_intro') || id.startsWith('tpl_outro') || id.startsWith('tpl_podcast'));
  localStorage.setItem(STORAGE_KEY, JSON.stringify(list));
}

export function applyTemplate(tpl: TimelineTemplate, current: TimelineState): TimelineState {
  return {
    ...current,
    project_name: tpl.state.project_name || current.project_name,
    settings: tpl.state.settings || current.settings,
    tracks: tpl.state.tracks || current.tracks,
  };
}
