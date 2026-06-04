import { useState } from 'react';
import { useStore } from '../../store';
import { Scissors } from 'lucide-react';

interface TranscriptWordsProps {
  onDeleteWords?: (indices: number[]) => void;
}

export default function TranscriptWords({ onDeleteWords }: TranscriptWordsProps) {
  const words = useStore((s) => s.words);
  const currentTime = useStore((s) => s.currentTime);
  const seek = useStore((s) => s.seek);
  const [isEditMode, setIsEditMode] = useState(false);
  const [selectedIndices, setSelectedIndices] = useState<number[]>([]);

  const handleWordClick = (index: number, start: number) => {
    if (isEditMode) {
      if (selectedIndices.includes(index)) {
        setSelectedIndices(prev => prev.filter(i => i !== index));
      } else {
        setSelectedIndices(prev => [...prev, index]);
      }
    } else {
      seek(start);
    }
  };

  const handleApplyDelete = () => {
    if (selectedIndices.length === 0 || !onDeleteWords) return;
    onDeleteWords(selectedIndices);
    setSelectedIndices([]);
  };

  return (
    <div className="border-t p-3 flex flex-col gap-1.5 flex-shrink-0 relative" style={{ background: 'var(--bg-surface-1)', borderColor: 'var(--border-subtle)', height: isEditMode ? '160px' : '112px', transition: 'height 150ms ease-out' }}>
      {/* Header bar */}
      <div className="flex items-center justify-between shrink-0">
        <button
          onClick={() => {
            setIsEditMode(!isEditMode);
            setSelectedIndices([]);
          }}
          style={{
            background: isEditMode ? 'var(--accent-red-bg || rgba(255, 69, 58, 0.15))' : 'var(--bg-surface-3)',
            borderColor: isEditMode ? 'var(--accent-red || #ff453a)' : 'var(--border-default)',
            color: isEditMode ? 'var(--accent-red || #ff453a)' : 'var(--text-secondary)'
          }}
          className="px-2 py-0.5 rounded-[6px] border text-[10px] flex items-center gap-1 transition-all cursor-pointer font-medium"
        >
          <Scissors className="w-3 h-3" />
          {isEditMode ? 'إلغاء وضع التعديل' : 'تفعيل التعديل بالنص'}
        </button>

        <span className="text-[10px] font-semibold block text-right tracking-wider uppercase" style={{ color: 'var(--text-secondary)' }}>
          {isEditMode ? 'وضع التعديل: اختر الكلمات لحذفها من الفيديو' : 'كلام الفيديو والترجمات النشطة (انقر للتنقل):'}
        </span>
      </div>

      {/* Editing Actions Bar */}
      {isEditMode && selectedIndices.length > 0 && (
        <div 
          className="p-1.5 rounded-[6px] border flex items-center justify-between shrink-0 animate-fade-in"
          style={{ background: 'rgba(255, 69, 58, 0.08)', borderColor: 'rgba(255, 69, 58, 0.25)' }}
        >
          <div className="flex gap-2">
            <button
              onClick={handleApplyDelete}
              className="px-3 py-1 rounded-[6px] text-[10px] font-semibold text-white bg-red-600 hover:bg-red-700 transition-all cursor-pointer flex items-center gap-1"
            >
              حذف الكلمات المحددة من الفيديو ({selectedIndices.length})
            </button>
            <button
              onClick={() => setSelectedIndices([])}
              className="px-2.5 py-1 rounded-[6px] text-[10px] font-semibold transition-all cursor-pointer border hover:bg-[var(--bg-surface-3)]"
              style={{ background: 'var(--bg-surface-2)', borderColor: 'var(--border-default)', color: 'var(--text-secondary)' }}
            >
              إلغاء التحديد
            </button>
          </div>
          <span className="text-[9px] font-medium text-red-400">
            سيتم قص هذه الأجزاء وإزاحتها متموجاً (Ripple Delete)
          </span>
        </div>
      )}

      {/* Words Box */}
      <div className="flex-1 overflow-y-auto pr-0.5">
        <div className="text-[11px] text-right leading-relaxed flex flex-wrap gap-x-1 gap-y-1 justify-end pb-2" style={{ color: 'var(--text-secondary)' }}>
          {words.map((w, i) => {
            const isActive = currentTime >= w.start && currentTime <= w.end;
            const isSelected = selectedIndices.includes(i);
            const duration = w.end - w.start;
            
            // Context-Aware Subtitles: Color based on speaking speed
            let speedColor = 'var(--text-secondary)';
            if (!isActive && !isSelected) {
                if (duration > 0.6) speedColor = '#fbbf24'; // Slow / Emphasized (Amber)
                else if (duration < 0.15) speedColor = '#94a3b8'; // Fast / Filler (Slate)
            }
            
            return (
              <span
                key={i}
                onClick={() => handleWordClick(i, w.start)}
                className="cursor-pointer px-1 py-0.5 rounded select-none"
                style={{
                  background: isSelected 
                    ? 'rgba(239, 68, 68, 0.25)' 
                    : isActive 
                      ? 'var(--accent-bg)' 
                      : 'transparent',
                  color: isSelected 
                    ? '#ff6b6b' 
                    : isActive 
                      ? 'var(--accent)' 
                      : speedColor,
                  fontWeight: isActive || isSelected ? 700 : (duration > 0.6 ? 600 : 400),
                  border: isSelected 
                    ? '0.5px solid rgba(239, 68, 68, 0.4)' 
                    : isActive 
                      ? '0.5px solid rgba(10, 132, 255, 0.25)' 
                      : '0.5px solid transparent',
                  textDecoration: isSelected ? 'line-through' : 'none',
                  transform: isActive ? 'scale(1.2) translateY(-2px)' : 'scale(1)',
                  transition: 'all 0.2s cubic-bezier(0.34, 1.56, 0.64, 1)',
                  display: 'inline-block'
                }}
                onMouseEnter={(e) => {
                  if (!isActive && !isSelected) {
                    e.currentTarget.style.background = 'var(--bg-surface-3)';
                    e.currentTarget.style.color = 'var(--text-primary)';
                  }
                }}
                onMouseLeave={(e) => {
                  if (!isActive && !isSelected) {
                    e.currentTarget.style.background = 'transparent';
                    e.currentTarget.style.color = speedColor;
                  }
                }}
              >
                {w.text}
              </span>
            );
          })}
          {words.length === 0 && (
            <span className="w-full text-center py-4" style={{ color: 'var(--text-tertiary)' }}>لا يوجد نصوص تفريغ حالياً</span>
          )}
        </div>
      </div>
    </div>
  );
}
