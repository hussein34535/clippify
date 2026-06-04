// AIToolPalette.tsx
// Comprehensive UI to browse + execute all 219 AI tools from TOOL_REGISTRY
// Categories: timeline (40) + playback (25) + effects (35) + audio (25) + subtitles (22) + ai (46) + export (26)

import { useEffect, useState } from 'react';
import axios from 'axios';
import {
  Sparkles, Play, Scissors, Music, Type,
  Wand2, Wand, Download, Search, ChevronDown, ChevronRight,
  Loader2, AlertCircle
} from 'lucide-react';
import { API_BASE } from '../../api';
import { executeAIAction } from '../../lib/aiActions';
import { useStore } from '../../store';

interface Tool {
  name: string;
  description: string;
  description_ar: string;
  category: string;
  params: Record<string, any>;
  requires_confirmation: boolean;
  destructive: boolean;
}

const CATEGORY_ICONS: Record<string, React.ComponentType<any>> = {
  timeline: Scissors,
  playback: Play,
  effects: Wand2,
  audio: Music,
  subtitles: Type,
  ai: Sparkles,
  export: Download,
};

const CATEGORY_LABELS: Record<string, string> = {
  timeline: 'التايملاين (40)',
  playback: 'المشغل (25)',
  effects: 'التأثيرات (35)',
  audio: 'الصوت (25)',
  subtitles: 'الترجمة (22)',
  ai: 'ذكاء اصطناعي (46)',
  export: 'التصدير (26)',
};

const CATEGORY_COLORS: Record<string, string> = {
  timeline: '#5e5ce6',
  playback: '#34c759',
  effects: '#ff9f0a',
  audio: '#bf5af2',
  subtitles: '#ff453a',
  ai: '#0a84ff',
  export: '#ff375f',
};

export default function AIToolPalette() {
  const [tools, setTools] = useState<Record<string, Tool[]>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [expanded, setExpanded] = useState<Record<string, boolean>>({ timeline: true, playback: true });
  const [executing, setExecuting] = useState<string | null>(null);
  const selectedClipId = useStore((s) => s.selectedClipId);

  useEffect(() => {
    loadTools();
  }, []);

  const loadTools = async () => {
    setLoading(true);
    setError(null);
    try {
      const resp = await axios.get(`${API_BASE}/api/ai/tools`);
      setTools(resp.data.tools || {});
    } catch (e: any) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  };

  const handleToolClick = async (tool: Tool) => {
    if (tool.destructive || tool.requires_confirmation) {
      if (!window.confirm(`تنفيذ "${tool.description_ar}"؟\n\nهذه العملية ${tool.destructive ? 'مدمرة' : 'تحتاج تأكيد'} — لا يمكن التراجع.`)) {
        return;
      }
    }
    setExecuting(tool.name);
    try {
      // Auto-fill selectedClipId for tools that need it
      const args: Record<string, any> = { ...getDefaultArgs(tool) };
      if (tool.params.clip_id && selectedClipId) {
        args.clip_id = selectedClipId;
      }
      await executeAIAction(tool.name, args);
    } finally {
      setTimeout(() => setExecuting(null), 500);
    }
  };

  const getDefaultArgs = (tool: Tool): Record<string, any> => {
    const defaults: Record<string, any> = {};
    for (const [k, v] of Object.entries(tool.params)) {
      if (typeof v === 'string') {
        if (v.includes('float') || v.includes('int')) {
          // Try to extract a sensible default from the param description
          const rangeMatch = v.match(/\(([0-9.-]+)\s*(?:to|and|-)\s*([0-9.-]+)/i);
          if (rangeMatch) {
            const min = parseFloat(rangeMatch[1]);
            const max = parseFloat(rangeMatch[2]);
            defaults[k] = (min + max) / 2;
          } else {
            defaults[k] = 0.5;
          }
        } else if (v.includes('boolean') || v === 'bool') {
          defaults[k] = true;
        } else if (v.includes('array')) {
          defaults[k] = [];
        } else {
          defaults[k] = v;
        }
      } else {
        defaults[k] = v;
      }
    }
    return defaults;
  };

  const toggleCategory = (cat: string) => {
    setExpanded(prev => ({ ...prev, [cat]: !prev[cat] }));
  };

  // Filter tools
  const filtered: Record<string, Tool[]> = {};
  for (const [cat, list] of Object.entries(tools)) {
    const filteredList = list.filter(t => {
      if (!search.trim()) return true;
      const q = search.toLowerCase();
      return t.name.toLowerCase().includes(q) ||
        (t.description || '').toLowerCase().includes(q) ||
        (t.description_ar || '').includes(search);
    });
    if (filteredList.length > 0) filtered[cat] = filteredList;
  }

  const totalCount = Object.values(tools).reduce((s, l) => s + l.length, 0);
  const filteredCount = Object.values(filtered).reduce((s, l) => s + l.length, 0);

  return (
    <div className="flex flex-col h-full font-sans select-none" style={{ color: 'var(--text-primary)' }}>
      {/* Header */}
      <div className="p-3 border-b flex items-center justify-between" style={{ borderColor: 'var(--border-subtle)' }}>
        <h3 className="text-xs font-semibold flex items-center gap-1.5" style={{ color: 'var(--accent)' }}>
          <Wand className="w-3.5 h-3.5" />
          لوحة الأدوات (AI Control)
        </h3>
        <span className="text-[9px] px-1.5 py-0.5 rounded border leading-none font-semibold" style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-default)', color: 'var(--text-secondary)' }}>
          {filteredCount}/{totalCount}
        </span>
      </div>

      {/* Search */}
      <div className="p-2 border-b" style={{ borderColor: 'var(--border-subtle)' }}>
        <div className="relative">
          <Search className="w-3.5 h-3.5 absolute left-2 top-1/2 -translate-y-1/2 opacity-50" />
          <input
            type="text"
            value={search}
            onChange={e => setSearch(e.target.value)}
            placeholder="ابحث في 219 أداة..."
            className="w-full bg-[var(--bg-surface-3)] border border-[var(--border-default)] rounded-[6px] pl-7 pr-2 py-1.5 text-[11px] text-right focus:outline-none focus:border-[var(--accent)] text-white placeholder-[var(--text-tertiary)]"
          />
        </div>
        {selectedClipId && (
          <div className="mt-1.5 text-[9px] opacity-70 flex items-center gap-1">
            <span className="w-1.5 h-1.5 rounded-full bg-[var(--accent)] animate-pulse" />
            <span>الكليب المحدد: {selectedClipId.slice(0, 12)}</span>
          </div>
        )}
      </div>

      {/* Tools List */}
      <div className="flex-1 overflow-y-auto p-2 space-y-1.5 min-h-0">
        {loading && (
          <div className="flex items-center justify-center gap-2 py-8 text-[11px] opacity-60">
            <Loader2 className="w-3.5 h-3.5 animate-spin" />
            جاري تحميل الأدوات...
          </div>
        )}
        {error && (
          <div className="flex items-center gap-2 p-2 text-[11px] text-red-300 bg-red-950/30 border border-red-500/20 rounded">
            <AlertCircle className="w-3.5 h-3.5" />
            {error}
          </div>
        )}
        {!loading && !error && Object.entries(filtered).map(([cat, list]) => {
          const Icon = CATEGORY_ICONS[cat] || Sparkles;
          const isOpen = expanded[cat] || !!search.trim();
          const color = CATEGORY_COLORS[cat] || '#888';
          return (
            <div key={cat} className="rounded-lg border overflow-hidden" style={{ borderColor: 'var(--border-subtle)', background: 'var(--bg-surface-1)' }}>
              <button
                onClick={() => toggleCategory(cat)}
                className="w-full flex items-center gap-2 p-2 hover:bg-[var(--bg-surface-2)] transition-colors"
              >
                {isOpen ? <ChevronDown className="w-3 h-3 opacity-50" /> : <ChevronRight className="w-3 h-3 opacity-50" />}
                <Icon className="w-3.5 h-3.5" style={{ color }} />
                <span className="text-[11px] font-semibold flex-1 text-right">{CATEGORY_LABELS[cat] || cat}</span>
                <span className="text-[9px] opacity-50">{list.length}</span>
              </button>
              {isOpen && (
                <div className="border-t" style={{ borderColor: 'var(--border-subtle)' }}>
                  {list.map(tool => {
                    const isExec = executing === tool.name;
                    return (
                      <button
                        key={tool.name}
                        onClick={() => handleToolClick(tool)}
                        disabled={isExec}
                        className="w-full flex items-start gap-2 p-2 hover:bg-[var(--bg-surface-2)] transition-colors text-right disabled:opacity-50 disabled:cursor-wait border-b last:border-b-0"
                        style={{ borderColor: 'var(--border-subtle)' }}
                        title={tool.description}
                      >
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-1.5 text-[10px] font-semibold">
                            <span className="truncate">{tool.description_ar || tool.name}</span>
                            {tool.destructive && <span className="text-[8px] px-1 rounded" style={{ background: 'rgba(255,69,58,0.2)', color: '#ff453a' }}>حساس</span>}
                          </div>
                          <div className="text-[9px] opacity-50 font-mono mt-0.5 truncate">{tool.name}</div>
                        </div>
                        {isExec && <Loader2 className="w-3 h-3 animate-spin flex-shrink-0" style={{ color }} />}
                      </button>
                    );
                  })}
                </div>
              )}
            </div>
          );
        })}
      </div>

      {/* Footer hint */}
      <div className="p-2 border-t text-[9px] opacity-50" style={{ borderColor: 'var(--border-subtle)' }}>
        اضغط على أي أداة لتنفيذها. الأدوات الحساسة (الحذف/التصدير) محتاجة تأكيد.
      </div>
    </div>
  );
}
