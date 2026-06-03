// SubtitleEditor.tsx
// Panel for editing individual subtitle clip texts, timings, styles, colors, and animations.

import React from 'react';

interface SubtitleEditorProps {
  clip: any;
  onUpdate: (updatedClip: any) => void;
}

export const SubtitleEditor: React.FC<SubtitleEditorProps> = ({ clip, onUpdate }) => {
  const style = clip.style || {
    font_name: 'Impact',
    font_size: 48,
    primary_color: '#FFFFFF',
    stroke_color: '#000000',
    stroke_width: 2,
    animation: 'pop_in',
    alignment: 'center_bottom',
  };

  const handleTextChange = (text: string) => {
    onUpdate({
      ...clip,
      text,
    });
  };

  const handleTimingChange = (field: 'start_time' | 'end_time', value: number) => {
    onUpdate({
      ...clip,
      [field]: Math.max(0, value),
    });
  };

  const handleStyleChange = (key: string, value: any) => {
    onUpdate({
      ...clip,
      style: {
        ...style,
        [key]: value,
      },
    });
  };

  return (
    <div className="w-full flex flex-col gap-4 text-right font-sans" dir="rtl">
      <h4 className="text-[11px] font-bold uppercase tracking-wider" style={{ color: 'var(--accent)' }}>
        تعديل نص الترجمة والستايل
      </h4>

      {/* Text Area */}
      <div className="flex flex-col gap-1">
        <label className="apple-label">نص الترجمة</label>
        <textarea
          value={clip.text || ''}
          onChange={(e) => handleTextChange(e.target.value)}
          rows={3}
          style={{
            background: 'var(--bg-surface-3)',
            borderColor: 'var(--border-default)',
            color: 'var(--text-primary)',
          }}
          className="w-full text-xs rounded-[6px] border p-2 focus:outline-none focus:border-[var(--accent)] resize-none"
        />
      </div>

      <div className="apple-separator" />

      {/* Timings */}
      <div className="flex flex-col gap-1">
        <label className="apple-label">التوقيت (بالثواني)</label>
        <div className="flex gap-2">
          <div className="flex-1 flex items-center px-2 py-1 rounded-[6px] border" style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-default)' }}>
            <span className="text-[10px] pl-2 font-semibold" style={{ color: 'var(--text-tertiary)' }}>البداية</span>
            <input
              type="number"
              step="0.1"
              value={clip.start_time || 0}
              onChange={(e) => handleTimingChange('start_time', Number(e.target.value))}
              className="w-full bg-transparent border-none text-xs text-white focus:outline-none text-left"
            />
          </div>
          <div className="flex-1 flex items-center px-2 py-1 rounded-[6px] border" style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-default)' }}>
            <span className="text-[10px] pl-2 font-semibold" style={{ color: 'var(--text-tertiary)' }}>النهاية</span>
            <input
              type="number"
              step="0.1"
              value={clip.end_time || 0}
              onChange={(e) => handleTimingChange('end_time', Number(e.target.value))}
              className="w-full bg-transparent border-none text-xs text-white focus:outline-none text-left"
            />
          </div>
        </div>
      </div>

      <div className="apple-separator" />

      {/* Typography */}
      <div className="flex flex-col gap-3">
        <div className="flex flex-col gap-1">
          <label className="apple-label">الخط</label>
          <select
            value={style.font_name}
            onChange={(e) => handleStyleChange('font_name', e.target.value)}
            style={{
              background: 'var(--bg-surface-3)',
              borderColor: 'var(--border-default)',
              color: 'var(--text-primary)',
            }}
            className="w-full text-xs rounded-[6px] border p-1.5 focus:outline-none cursor-pointer"
          >
            <option value="Impact">Impact (TikTok Bold)</option>
            <option value="Inter">Inter (Sleek Sans)</option>
            <option value="Arial">Arial (Standard)</option>
            <option value="Courier New">Courier New (Typewriter)</option>
            <option value="Georgia">Georgia (Serif)</option>
          </select>
        </div>

        {/* Font Size */}
        <div className="flex flex-col gap-1.5">
          <div className="flex justify-between text-xs items-center">
            <span className="font-mono text-[11px]" style={{ color: 'var(--text-secondary)' }}>{style.font_size}px</span>
            <span className="apple-label">حجم الخط</span>
          </div>
          <input
            type="range"
            min="12"
            max="120"
            value={style.font_size}
            onChange={(e) => handleStyleChange('font_size', Number(e.target.value))}
            className="w-full h-1 bg-gray-800 rounded-lg appearance-none cursor-pointer"
            style={{ accentColor: 'var(--accent)' }}
          />
        </div>
      </div>

      <div className="apple-separator" />

      {/* Colors */}
      <div className="flex flex-col gap-3">
        <div className="flex items-center justify-between">
          <input
            type="color"
            value={style.primary_color}
            onChange={(e) => handleStyleChange('primary_color', e.target.value)}
            className="w-8 h-8 rounded border cursor-pointer bg-transparent"
            style={{ borderColor: 'var(--border-default)' }}
          />
          <span className="apple-label">اللون الأساسي</span>
        </div>

        <div className="flex items-center justify-between">
          <input
            type="color"
            value={style.stroke_color}
            onChange={(e) => handleStyleChange('stroke_color', e.target.value)}
            className="w-8 h-8 rounded border cursor-pointer bg-transparent"
            style={{ borderColor: 'var(--border-default)' }}
          />
          <span className="apple-label">لون الحواف (Stroke)</span>
        </div>

        {/* Stroke Width */}
        <div className="flex flex-col gap-1.5">
          <div className="flex justify-between text-xs items-center">
            <span className="font-mono text-[11px]" style={{ color: 'var(--text-secondary)' }}>{style.stroke_width}px</span>
            <span className="apple-label">عرض الحواف</span>
          </div>
          <input
            type="range"
            min="0"
            max="10"
            value={style.stroke_width}
            onChange={(e) => handleStyleChange('stroke_width', Number(e.target.value))}
            className="w-full h-1 bg-gray-800 rounded-lg appearance-none cursor-pointer"
            style={{ accentColor: 'var(--accent)' }}
          />
        </div>
      </div>

      <div className="apple-separator" />

      {/* Animation & Alignment */}
      <div className="flex flex-col gap-3">
        <div className="flex flex-col gap-1">
          <label className="apple-label">طريقة الظهور (Animation)</label>
          <select
            value={style.animation}
            onChange={(e) => handleStyleChange('animation', e.target.value)}
            style={{
              background: 'var(--bg-surface-3)',
              borderColor: 'var(--border-default)',
              color: 'var(--text-primary)',
            }}
            className="w-full text-xs rounded-[6px] border p-1.5 focus:outline-none cursor-pointer"
          >
            <option value="none">بدون حركة (Static)</option>
            <option value="pop_in">تكبير مفاجئ (Pop In)</option>
            <option value="fade_in">ظهور تدريجي (Fade In)</option>
            <option value="slide_up">صعود لأعلى (Slide Up)</option>
          </select>
        </div>

        <div className="flex flex-col gap-1">
          <label className="apple-label">الموضع (Alignment)</label>
          <select
            value={style.alignment}
            onChange={(e) => handleStyleChange('alignment', e.target.value)}
            style={{
              background: 'var(--bg-surface-3)',
              borderColor: 'var(--border-default)',
              color: 'var(--text-primary)',
            }}
            className="w-full text-xs rounded-[6px] border p-1.5 focus:outline-none cursor-pointer"
          >
            <option value="center_bottom">المنتصف بالأسفل</option>
            <option value="center_top">المنتصف بالأعلى</option>
            <option value="middle">المنتصف تماماً</option>
          </select>
        </div>
      </div>
    </div>
  );
};

export default SubtitleEditor;
