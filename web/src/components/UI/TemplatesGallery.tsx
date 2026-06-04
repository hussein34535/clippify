// TemplatesGallery.tsx
// Phase 18 — Templates: Browse, apply, save, delete timeline templates.

import { useState, useEffect } from 'react';
import { X, FolderOpen, Save, Trash2, Plus } from 'lucide-react';
import { listTemplates, saveTemplate, deleteTemplate, applyTemplate, ensureBuiltinTemplates, type TimelineTemplate } from '../../lib/templates';
import type { TimelineState } from '../../types';

interface TemplatesGalleryProps {
  current: TimelineState;
  onApply: (state: TimelineState) => void;
  onClose: () => void;
}

const CATEGORY_LABELS: Record<TimelineTemplate['category'], string> = {
  intro: 'مقدمات',
  outro: 'خواتم',
  transition: 'انتقالات',
  'lower-third': 'شعارات',
  full: 'مشاريع كاملة',
};

export default function TemplatesGallery({ current, onApply, onClose }: TemplatesGalleryProps) {
  const [templates, setTemplates] = useState<TimelineTemplate[]>([]);
  const [filter, setFilter] = useState<TimelineTemplate['category'] | 'all'>('all');
  const [saveDialog, setSaveDialog] = useState(false);
  const [name, setName] = useState('');
  const [nameAr, setNameAr] = useState('');
  const [category, setCategory] = useState<TimelineTemplate['category']>('full');

  useEffect(() => {
    ensureBuiltinTemplates();
    setTemplates(listTemplates());
  }, []);

  const filtered = filter === 'all' ? templates : templates.filter((t) => t.category === filter);

  const handleApply = (tpl: TimelineTemplate) => {
    const newState = applyTemplate(tpl, current);
    onApply(newState);
    onClose();
  };

  const handleSave = () => {
    if (!name.trim()) return;
    saveTemplate(name, nameAr || name, category, current);
    setTemplates(listTemplates());
    setSaveDialog(false);
    setName('');
    setNameAr('');
  };

  const handleDelete = (id: string) => {
    deleteTemplate(id);
    setTemplates(listTemplates());
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center"
      style={{ background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(4px)' }}
      onClick={onClose}
    >
      <div
        className="w-[640px] max-h-[80vh] rounded-xl border shadow-2xl overflow-hidden flex flex-col"
        style={{ background: 'var(--bg-surface-1)', borderColor: 'var(--border-default)' }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="p-4 border-b flex items-center justify-between" style={{ borderColor: 'var(--border-subtle)' }}>
          <div>
            <h2 className="text-sm font-semibold flex items-center gap-2" style={{ color: 'var(--text-primary)' }}>
              <FolderOpen className="w-4 h-4" style={{ color: 'var(--accent)' }} />
              معرض القوالب
            </h2>
            <p className="text-[10px] mt-0.5" style={{ color: 'var(--text-tertiary)' }}>
              {templates.length} قالب متاح
            </p>
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={() => setSaveDialog(true)}
              className="flex items-center gap-1 px-2.5 py-1.5 rounded text-[11px] font-semibold"
              style={{ background: 'var(--accent)', color: '#fff' }}
            >
              <Plus className="w-3.5 h-3.5" /> حفظ كقالب
            </button>
            <button
              onClick={onClose}
              className="p-1.5 rounded hover:bg-[var(--bg-surface-3)]"
              style={{ color: 'var(--text-secondary)' }}
            >
              <X className="w-4 h-4" />
            </button>
          </div>
        </div>

        <div className="px-4 py-2 border-b flex gap-1" style={{ borderColor: 'var(--border-subtle)' }}>
          <button
            onClick={() => setFilter('all')}
            className="px-2.5 py-1 rounded text-[11px] font-semibold transition-colors"
            style={{
              background: filter === 'all' ? 'var(--bg-surface-3)' : 'transparent',
              color: filter === 'all' ? 'var(--text-primary)' : 'var(--text-secondary)',
            }}
          >
            الكل
          </button>
          {(Object.keys(CATEGORY_LABELS) as TimelineTemplate['category'][]).map((cat) => (
            <button
              key={cat}
              onClick={() => setFilter(cat)}
              className="px-2.5 py-1 rounded text-[11px] font-semibold transition-colors"
              style={{
                background: filter === cat ? 'var(--bg-surface-3)' : 'transparent',
                color: filter === cat ? 'var(--text-primary)' : 'var(--text-secondary)',
              }}
            >
              {CATEGORY_LABELS[cat]}
            </button>
          ))}
        </div>

        <div className="overflow-y-auto p-4 grid grid-cols-3 gap-2">
          {filtered.map((tpl) => (
            <div
              key={tpl.id}
              className="rounded-lg border overflow-hidden transition-all hover:border-[var(--accent)]"
              style={{ background: 'var(--bg-surface-2)', borderColor: 'var(--border-subtle)' }}
            >
              <div
                className="aspect-video flex items-center justify-center text-3xl"
                style={{ background: 'linear-gradient(135deg, var(--accent) 0%, #8B5CF6 100%)' }}
              >
                {tpl.category === 'intro' ? '🎬' : tpl.category === 'outro' ? '🎞️' : tpl.category === 'transition' ? '✨' : tpl.category === 'lower-third' ? '📺' : '🎙️'}
              </div>
              <div className="p-2.5">
                <p className="text-[12px] font-semibold truncate" style={{ color: 'var(--text-primary)' }}>
                  {tpl.nameAr}
                </p>
                <p className="text-[9px] mt-0.5" style={{ color: 'var(--text-tertiary)' }}>
                  {CATEGORY_LABELS[tpl.category]}
                  {tpl.createdAt > 0 && ` • ${new Date(tpl.createdAt).toLocaleDateString('ar-EG')}`}
                </p>
                <div className="flex gap-1 mt-2">
                  <button
                    onClick={() => handleApply(tpl)}
                    className="flex-1 py-1 rounded text-[10px] font-semibold"
                    style={{ background: 'var(--accent)', color: '#fff' }}
                  >
                    تطبيق
                  </button>
                  {tpl.createdAt > 0 && (
                    <button
                      onClick={() => handleDelete(tpl.id)}
                      className="p-1 rounded hover:bg-[var(--bg-surface-3)]"
                      style={{ color: 'var(--text-tertiary)' }}
                    >
                      <Trash2 className="w-3 h-3" />
                    </button>
                  )}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>

      {saveDialog && (
        <div
          className="fixed inset-0 z-[60] flex items-center justify-center"
          style={{ background: 'rgba(0,0,0,0.7)' }}
          onClick={() => setSaveDialog(false)}
        >
          <div
            className="w-80 rounded-xl border shadow-2xl p-4"
            style={{ background: 'var(--bg-surface-1)', borderColor: 'var(--border-default)' }}
            onClick={(e) => e.stopPropagation()}
          >
            <p className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>
              <Save className="w-4 h-4 inline ml-1" style={{ color: 'var(--accent)' }} />
              حفظ كقالب
            </p>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="اسم القالب (English)"
              className="w-full px-2 py-1.5 mb-2 rounded text-[11px]"
              style={{ background: 'var(--bg-surface-3)', border: '1px solid var(--border-default)', color: 'var(--text-primary)' }}
            />
            <input
              type="text"
              value={nameAr}
              onChange={(e) => setNameAr(e.target.value)}
              placeholder="اسم القالب (عربي)"
              className="w-full px-2 py-1.5 mb-2 rounded text-[11px]"
              style={{ background: 'var(--bg-surface-3)', border: '1px solid var(--border-default)', color: 'var(--text-primary)' }}
            />
            <select
              value={category}
              onChange={(e) => setCategory(e.target.value as any)}
              className="w-full px-2 py-1.5 mb-3 rounded text-[11px]"
              style={{ background: 'var(--bg-surface-3)', border: '1px solid var(--border-default)', color: 'var(--text-primary)' }}
            >
              {(Object.keys(CATEGORY_LABELS) as TimelineTemplate['category'][]).map((cat) => (
                <option key={cat} value={cat}>{CATEGORY_LABELS[cat]}</option>
              ))}
            </select>
            <div className="flex gap-2">
              <button
                onClick={() => setSaveDialog(false)}
                className="flex-1 py-1.5 rounded text-[11px] font-semibold"
                style={{ background: 'var(--bg-surface-3)', color: 'var(--text-primary)' }}
              >
                إلغاء
              </button>
              <button
                onClick={handleSave}
                className="flex-1 py-1.5 rounded text-[11px] font-semibold"
                style={{ background: 'var(--accent)', color: '#fff' }}
              >
                حفظ
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
