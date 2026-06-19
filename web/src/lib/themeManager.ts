// themeManager.ts
// Centralized theme + density + reduced-motion management (Phase 9 + 15)

export type Theme = 'dark' | 'light' | 'high-contrast';
export type Density = 'normal' | 'compact';

const THEME_KEY = 'clipai_theme';
const DENSITY_KEY = 'clipai_density';
const REDUCED_MOTION_KEY = 'clipai_reduced_motion';

export function getTheme(): Theme {
  const t = localStorage.getItem(THEME_KEY) as Theme | null;
  if (t === 'light' || t === 'high-contrast') return t;
  return 'dark';
}

export function setTheme(theme: Theme) {
  localStorage.setItem(THEME_KEY, theme);
  if (theme === 'dark') {
    document.documentElement.removeAttribute('data-theme');
  } else {
    document.documentElement.setAttribute('data-theme', theme);
  }
}

export function cycleTheme(): Theme {
  const current = getTheme();
  const next: Theme = current === 'dark' ? 'light' : current === 'light' ? 'high-contrast' : 'dark';
  setTheme(next);
  return next;
}

export function getDensity(): Density {
  const d = localStorage.getItem(DENSITY_KEY) as Density | null;
  return d === 'compact' ? 'compact' : 'normal';
}

export function setDensity(d: Density) {
  localStorage.setItem(DENSITY_KEY, d);
  if (d === 'compact') {
    document.documentElement.setAttribute('data-density', 'compact');
  } else {
    document.documentElement.removeAttribute('data-density');
  }
}

export function toggleDensity(): Density {
  const next: Density = getDensity() === 'compact' ? 'normal' : 'compact';
  setDensity(next);
  return next;
}

export function getReducedMotion(): boolean {
  const v = localStorage.getItem(REDUCED_MOTION_KEY);
  if (v === 'true') return true;
  if (v === 'false') return false;
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

export function setReducedMotion(v: boolean) {
  localStorage.setItem(REDUCED_MOTION_KEY, String(v));
  if (v) {
    document.documentElement.setAttribute('data-reduced-motion', 'true');
  } else {
    document.documentElement.removeAttribute('data-reduced-motion');
  }
}

export function initTheme() {
  setTheme(getTheme());
  setDensity(getDensity());
  setReducedMotion(getReducedMotion());
}

// Workspace layout presets (Phase 9)
export type WorkspaceLayout = 'editing' | 'color' | 'audio' | 'review';

export interface LayoutPreset {
  name: string;
  nameAr: string;
  leftWidth: number;
  rightWidth: number;
  bottomHeight: number;
  inspectorTab: 'transform' | 'color' | 'audio' | 'ai' | 'tools' | 'viral';
}

export const LAYOUT_PRESETS: Record<WorkspaceLayout, LayoutPreset> = {
  editing: { name: 'Editing', nameAr: 'مونتاج', leftWidth: 260, rightWidth: 320, bottomHeight: 280, inspectorTab: 'transform' },
  color: { name: 'Color', nameAr: 'ألوان', leftWidth: 220, rightWidth: 380, bottomHeight: 200, inspectorTab: 'color' },
  audio: { name: 'Audio', nameAr: 'صوت', leftWidth: 240, rightWidth: 360, bottomHeight: 320, inspectorTab: 'audio' },
  review: { name: 'Review', nameAr: 'مراجعة', leftWidth: 280, rightWidth: 280, bottomHeight: 200, inspectorTab: 'tools' },
};

const LAYOUT_KEY = 'clipai_layout';

export function getLayout(): WorkspaceLayout {
  return (localStorage.getItem(LAYOUT_KEY) as WorkspaceLayout) || 'editing';
}

export function setLayout(l: WorkspaceLayout) {
  localStorage.setItem(LAYOUT_KEY, l);
}

// Color presets (Phase 18)
export interface ColorPreset {
  name: string;
  nameAr: string;
  effects: Record<string, number>;
}

export const COLOR_PRESETS: ColorPreset[] = [
  { name: 'Cinematic', nameAr: 'سينمائي', effects: { contrast: 1.15, saturation: 0.85, temperature: -10, shadows: -10 } },
  { name: 'Vintage', nameAr: 'كلاسيكي', effects: { saturation: 0.7, temperature: 15, vignette: 0.3, grain: 0.2 } },
  { name: 'Vibrant', nameAr: 'نابض', effects: { saturation: 1.3, vibrance: 0.3, contrast: 1.1 } },
  { name: 'Noir', nameAr: 'نوار', effects: { saturation: 0.0, contrast: 1.3, exposure: -0.1 } },
  { name: 'Warm', nameAr: 'دافئ', effects: { temperature: 20, saturation: 1.1 } },
  { name: 'Cool', nameAr: 'بارد', effects: { temperature: -20, tint: -5 } },
  { name: 'Punch', nameAr: 'حاد', effects: { contrast: 1.2, saturation: 1.15, vibrance: 0.2 } },
  { name: 'Soft', nameAr: 'ناعم', effects: { contrast: 0.9, saturation: 0.95, shadows: 10 } },
];

// Export presets (Phase 18)
export interface ExportPreset {
  name: string;
  nameAr: string;
  resolution: string;
  fps: number;
  codec: string;
  bitrate: number;
  platform: string;
}

export const EXPORT_PRESETS: ExportPreset[] = [
  { name: 'TikTok', nameAr: 'تيك توك', resolution: '1080x1920', fps: 30, codec: 'h264', bitrate: 6000, platform: 'tiktok' },
  { name: 'YouTube', nameAr: 'يوتيوب', resolution: '1920x1080', fps: 30, codec: 'h264', bitrate: 8000, platform: 'youtube' },
  { name: 'YouTube Shorts', nameAr: 'يوتيوب شورتس', resolution: '1080x1920', fps: 30, codec: 'h264', bitrate: 6000, platform: 'youtube_shorts' },
  { name: 'Instagram Reels', nameAr: 'إنستجرام ريلز', resolution: '1080x1920', fps: 30, codec: 'h264', bitrate: 5000, platform: 'instagram' },
  { name: 'Instagram Post', nameAr: 'بوست إنستجرام', resolution: '1080x1080', fps: 30, codec: 'h264', bitrate: 5000, platform: 'instagram' },
  { name: 'Twitter/X', nameAr: 'تويتر', resolution: '1920x1080', fps: 30, codec: 'h264', bitrate: 5000, platform: 'twitter' },
  { name: 'Facebook', nameAr: 'فيسبوك', resolution: '1920x1080', fps: 30, codec: 'h264', bitrate: 6000, platform: 'facebook' },
  { name: 'LinkedIn', nameAr: 'لينكدإن', resolution: '1920x1080', fps: 30, codec: 'h264', bitrate: 5000, platform: 'linkedin' },
  { name: '4K Master', nameAr: '4K ماستر', resolution: '3840x2160', fps: 60, codec: 'h265', bitrate: 25000, platform: 'youtube' },
  { name: 'ProRes 422', nameAr: 'برورس 422', resolution: '1920x1080', fps: 30, codec: 'prores', bitrate: 50000, platform: 'master' },
];

// Subtitle templates (Phase 18)
export interface SubtitleTemplate {
  name: string;
  nameAr: string;
  fontFamily: string;
  fontSize: number;
  color: string;
  outlineColor: string;
  outlineWidth: number;
  animation: string;
}

export const SUBTITLE_TEMPLATES: SubtitleTemplate[] = [
  { name: 'TikTok Yellow', nameAr: 'تيك توك أصفر', fontFamily: 'Impact', fontSize: 48, color: '#FFEB3B', outlineColor: '#000000', outlineWidth: 3, animation: 'pop_in' },
  { name: 'YouTube White', nameAr: 'يوتيوب أبيض', fontFamily: 'Arial', fontSize: 42, color: '#FFFFFF', outlineColor: '#000000', outlineWidth: 2, animation: 'fade' },
  { name: 'Instagram Gradient', nameAr: 'إنستجرام متدرج', fontFamily: 'Helvetica', fontSize: 44, color: '#FF6B6B', outlineColor: '#FFFFFF', outlineWidth: 2, animation: 'typewriter' },
  { name: 'Bold Black', nameAr: 'أسود عريض', fontFamily: 'Impact', fontSize: 50, color: '#000000', outlineColor: '#FFFFFF', outlineWidth: 3, animation: 'pop_in' },
  { name: 'Minimal', nameAr: 'بسيط', fontFamily: 'Inter', fontSize: 36, color: '#FFFFFF', outlineColor: '#000000', outlineWidth: 1, animation: 'fade' },
];

// Subtitle animations (Phase 7)
export const SUBTITLE_ANIMATIONS = [
  'none', 'fade', 'pop_in', 'pop_out', 'typewriter', 'slide_up', 'slide_down', 'slide_left', 'slide_right',
  'bounce', 'shake', 'glow', 'scale', 'rotate', 'flip', 'blur_in', 'elastic', 'wave', 'glitch', 'rainbow',
];

// Aspect ratios (Phase 3)
export const ASPECT_RATIOS = [
  { value: '16:9', label: '16:9 (YouTube)', labelAr: '16:9 (يوتيوب)' },
  { value: '9:16', label: '9:16 (TikTok/Reels)', labelAr: '9:16 (تيك توك/ريلز)' },
  { value: '1:1', label: '1:1 (Instagram Post)', labelAr: '1:1 (بوست)' },
  { value: '4:5', label: '4:5 (Instagram Feed)', labelAr: '4:5 (فيد)' },
  { value: '2.39:1', label: '2.39:1 (Cinema)', labelAr: '2.39:1 (سينما)' },
  { value: '21:9', label: '21:9 (Ultrawide)', labelAr: '21:9 (فائق العرض)' },
];
