// analytics.ts
// Phase 14 — Analytics: Track user actions, AI usage, productivity stats.

const STORAGE_KEY = 'clipai_analytics';
const MAX_EVENTS = 5000;

export interface AnalyticsEvent {
  type: 'edit' | 'ai_action' | 'export' | 'comment' | 'macro' | 'voice';
  category?: string;        // e.g. "timeline", "effects"
  toolName?: string;        // e.g. "timeline.split_clip"
  durationMs?: number;
  timestamp: number;
  projectId?: string;
}

export interface AnalyticsSummary {
  totalEvents: number;
  totalAiActions: number;
  totalExports: number;
  totalComments: number;
  totalMacros: number;
  totalEdits: number;
  totalVoiceCommands: number;
  topTools: Array<{ name: string; count: number }>;
  topCategories: Array<{ name: string; count: number }>;
  byHour: number[];         // 24h histogram
  byDay: number[];          // last 7 days
  averageEditMs: number;
  estimatedTimeSavedMin: number;
}

function loadEvents(): AnalyticsEvent[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

function saveEvents(events: AnalyticsEvent[]) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(events.slice(-MAX_EVENTS)));
  } catch {}
}

export function trackEvent(event: Omit<AnalyticsEvent, 'timestamp'>) {
  const events = loadEvents();
  events.push({ ...event, timestamp: Date.now() });
  saveEvents(events);
}

export function getSummary(): AnalyticsSummary {
  const events = loadEvents();
  const toolCounts: Record<string, number> = {};
  const categoryCounts: Record<string, number> = {};
  const byHour = new Array(24).fill(0);
  const byDay = new Array(7).fill(0);
  let totalEditMs = 0;
  let editCount = 0;
  const now = Date.now();
  const dayMs = 24 * 60 * 60 * 1000;

  for (const e of events) {
    if (e.toolName) toolCounts[e.toolName] = (toolCounts[e.toolName] || 0) + 1;
    if (e.category) categoryCounts[e.category] = (categoryCounts[e.category] || 0) + 1;
    const hour = new Date(e.timestamp).getHours();
    byHour[hour]++;
    const daysAgo = Math.floor((now - e.timestamp) / dayMs);
    if (daysAgo >= 0 && daysAgo < 7) byDay[6 - daysAgo]++;
    if (e.type === 'edit' && e.durationMs) {
      totalEditMs += e.durationMs;
      editCount++;
    }
  }

  const topTools = Object.entries(toolCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10)
    .map(([name, count]) => ({ name, count }));

  const topCategories = Object.entries(categoryCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 7)
    .map(([name, count]) => ({ name, count }));

  return {
    totalEvents: events.length,
    totalAiActions: events.filter((e) => e.type === 'ai_action').length,
    totalExports: events.filter((e) => e.type === 'export').length,
    totalComments: events.filter((e) => e.type === 'comment').length,
    totalMacros: events.filter((e) => e.type === 'macro').length,
    totalEdits: events.filter((e) => e.type === 'edit').length,
    totalVoiceCommands: events.filter((e) => e.type === 'voice').length,
    topTools,
    topCategories,
    byHour,
    byDay,
    averageEditMs: editCount > 0 ? Math.round(totalEditMs / editCount) : 0,
    // Rough estimate: 1 AI action = 30s manual work
    estimatedTimeSavedMin: Math.round(events.filter((e) => e.type === 'ai_action').length * 0.5),
  };
}

export function clearAnalytics() {
  localStorage.removeItem(STORAGE_KEY);
}
