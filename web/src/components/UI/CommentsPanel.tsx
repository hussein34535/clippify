// CommentsPanel.tsx
// Phase 11 — Collaboration: Comments UI.

import { useState, useEffect } from 'react';
import { MessageSquare, Trash2, Check, X, Plus } from 'lucide-react';
import { listComments, addComment, deleteComment, toggleResolved, type Comment } from '../../lib/comments';

interface CommentsPanelProps {
  currentTime: number;
}

export default function CommentsPanel({ currentTime }: CommentsPanelProps) {
  const [comments, setComments] = useState<Comment[]>([]);
  const [text, setText] = useState('');
  const [open, setOpen] = useState(false);

  useEffect(() => {
    setComments(listComments().sort((a, b) => a.time - b.time));
  }, [open]);

  const reload = () => setComments(listComments().sort((a, b) => a.time - b.time));

  const handleAdd = () => {
    if (!text.trim()) return;
    addComment(text, { time: currentTime });
    setText('');
    reload();
  };

  const fmt = (t: number) => {
    const m = Math.floor(t / 60);
    const s = Math.floor(t % 60);
    const ms = Math.floor((t % 1) * 100);
    return `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}.${ms.toString().padStart(2, '0')}`;
  };

  const unresolved = comments.filter((c) => !c.resolved).length;

  return (
    <div className="relative">
      <button
        onClick={() => setOpen(!open)}
        className="w-7 h-7 rounded-full flex items-center justify-center transition-all cursor-pointer hover:bg-[var(--bg-surface-3)]"
        style={{ color: 'var(--text-secondary)' }}
        title={`التعليقات (${comments.length}${unresolved ? ` — ${unresolved} غير محلولة` : ''})`}
      >
        <MessageSquare className="w-4 h-4" />
        {unresolved > 0 && (
          <span
            className="absolute -top-0.5 -right-0.5 w-3.5 h-3.5 rounded-full text-[8px] font-bold flex items-center justify-center"
            style={{ background: '#FF453A', color: '#fff' }}
          >
            {unresolved}
          </span>
        )}
      </button>

      {open && (
        <div
          className="absolute top-9 left-0 w-80 rounded-lg border shadow-xl z-50 overflow-hidden"
          style={{ background: 'var(--bg-surface-1)', borderColor: 'var(--border-default)' }}
        >
          <div className="p-3 border-b" style={{ borderColor: 'var(--border-subtle)' }}>
            <div className="flex items-center justify-between mb-2">
              <p className="text-[11px] font-semibold" style={{ color: 'var(--text-primary)' }}>
                التعليقات ({comments.length})
              </p>
              <button
                onClick={() => setOpen(false)}
                className="p-0.5 rounded hover:bg-[var(--bg-surface-3)]"
                style={{ color: 'var(--text-secondary)' }}
              >
                <X className="w-3.5 h-3.5" />
              </button>
            </div>
            <div className="flex gap-1.5">
              <input
                type="text"
                value={text}
                onChange={(e) => setText(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && handleAdd()}
                placeholder={`تعليق على ${fmt(currentTime)}...`}
                className="flex-1 px-2 py-1.5 rounded text-[11px]"
                style={{ background: 'var(--bg-surface-3)', border: '1px solid var(--border-default)', color: 'var(--text-primary)' }}
              />
              <button
                onClick={handleAdd}
                disabled={!text.trim()}
                className="px-2 py-1.5 rounded text-[11px] font-semibold disabled:opacity-40"
                style={{ background: 'var(--accent)', color: '#fff' }}
              >
                <Plus className="w-3 h-3" />
              </button>
            </div>
          </div>

          <div className="max-h-80 overflow-y-auto">
            {comments.length === 0 ? (
              <p className="p-4 text-center text-[10px]" style={{ color: 'var(--text-tertiary)' }}>
                مفيش تعليقات
              </p>
            ) : (
              comments.map((c) => (
                <div
                  key={c.id}
                  className="px-3 py-2 border-b"
                  style={{ borderColor: 'var(--border-subtle)', opacity: c.resolved ? 0.5 : 1 }}
                >
                  <div className="flex items-center gap-2 mb-1">
                    <span className="text-[9px] font-mono px-1 py-0.5 rounded" style={{ background: 'var(--bg-surface-3)', color: 'var(--accent)' }}>
                      {fmt(c.time)}
                    </span>
                    <span className="text-[10px] flex-1" style={{ color: 'var(--text-secondary)' }}>
                      {c.author}
                    </span>
                    <button
                      onClick={() => { toggleResolved(c.id); reload(); }}
                      className="p-0.5 rounded hover:bg-[var(--bg-surface-3)]"
                      style={{ color: c.resolved ? 'var(--accent)' : 'var(--text-tertiary)' }}
                      title={c.resolved ? 'إلغاء الحل' : 'تحديد كمحلول'}
                    >
                      <Check className="w-3 h-3" />
                    </button>
                    <button
                      onClick={() => { deleteComment(c.id); reload(); }}
                      className="p-0.5 rounded hover:bg-[var(--bg-surface-3)]"
                      style={{ color: 'var(--text-tertiary)' }}
                    >
                      <Trash2 className="w-3 h-3" />
                    </button>
                  </div>
                  <p className="text-[11px] leading-snug" style={{ color: 'var(--text-primary)' }}>
                    {c.text}
                  </p>
                </div>
              ))
            )}
          </div>
        </div>
      )}
    </div>
  );
}
