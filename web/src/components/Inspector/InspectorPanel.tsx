// InspectorPanel.tsx
// Component for editing properties of the selected clip (Transform, Color, Filters, AI features)

import React, { useState } from 'react';
import { Video, Sparkles, Paintbrush, Volume2, Activity, Wand } from 'lucide-react';
import ColorWheels from './ColorWheels';
import ViralAnalyticsPanel from './ViralAnalyticsPanel';
import SubtitleEditor from './SubtitleEditor';
import AIToolPalette from './AIToolPalette';

interface InspectorPanelProps {
  selectedClip: any | null;
  clipType: 'video' | 'audio' | 'overlay' | 'subtitle' | null;
  onUpdateClip: (updatedClip: any) => void;
}

const ToggleSwitch = ({ checked, onChange }: { checked: boolean; onChange: (v: boolean) => void }) => {
  return (
    <div 
      onClick={() => onChange(!checked)}
      style={{
        width: 36,
        height: 20,
        borderRadius: 10,
        background: checked ? 'var(--accent)' : 'var(--bg-surface-3)',
        border: '0.5px solid var(--border-default)',
        transition: 'background 150ms ease-out',
        position: 'relative',
        cursor: 'pointer',
        flexShrink: 0
      }}
    >
      <div style={{
        position: 'absolute',
        top: 1,
        left: checked ? 17 : 1,
        width: 16,
        height: 16,
        borderRadius: '50%',
        background: '#fff',
        boxShadow: '0 1px 3px rgba(0,0,0,0.3)',
        transition: 'left 150ms cubic-bezier(0.25, 0.8, 0.25, 1)'
      }} />
    </div>
  );
};

export const InspectorPanel: React.FC<InspectorPanelProps> = ({
  selectedClip,
  clipType,
  onUpdateClip,
}) => {
  const [activeTab, setActiveTab] = useState<'transform' | 'color' | 'audio' | 'ai' | 'tools' | 'viral'>('transform');

  if (!selectedClip) {
    return (
      <div className="w-full h-full flex flex-col items-center justify-center p-6 text-center text-xs font-sans" style={{ background: 'var(--bg-surface-1)', color: 'var(--text-secondary)' }}>
        حدد كليباً على التايم لاين لتعديل خصائصه.
      </div>
    );
  }

  if (clipType === 'subtitle') {
    return (
      <div className="w-full h-full flex flex-col font-sans" style={{ background: 'var(--bg-surface-1)', color: 'var(--text-primary)' }}>
        {/* Panel Header */}
        <div className="p-3 border-b flex items-center justify-between" style={{ borderColor: 'var(--border-subtle)' }}>
          <h3 className="text-xs font-semibold" style={{ color: 'var(--text-primary)' }}>خصائص العنصر</h3>
          <span className="text-[9px] px-1.5 py-0.5 rounded border leading-none font-semibold uppercase" style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-default)', color: 'var(--text-secondary)' }}>
            {getClipTypeLabel(clipType)}
          </span>
        </div>
        <div className="flex-1 overflow-y-auto p-3.5 flex flex-col gap-4">
          <SubtitleEditor clip={selectedClip} onUpdate={onUpdateClip} />
        </div>
      </div>
    );
  }

  const handleTransformChange = (key: string, value: any) => {
    const updated = {
      ...selectedClip,
      transform: {
        ...selectedClip.transform,
        [key]: value,
      },
    };
    onUpdateClip(updated);
  };

  const handleVectorChange = (field: 'position' | 'scale', axis: 'x' | 'y', value: number) => {
    const updated = {
      ...selectedClip,
      transform: {
        ...selectedClip.transform,
        [field]: {
          ...selectedClip.transform[field],
          [axis]: value,
        },
      },
    };
    onUpdateClip(updated);
  };

  const handleCropChange = (key: 'left' | 'right' | 'top' | 'bottom', value: number) => {
    const clamped = Math.max(0, Math.min(95, value));
    const currentCrop = (selectedClip.transform as any)?.crop || { left: 0, right: 0, top: 0, bottom: 0 };
    const newCrop = { ...currentCrop, [key]: clamped };

    // Reset scale to 100% on the affected axis if total crop exceeds limits
    if ((key === 'left' || key === 'right') && newCrop.left + newCrop.right >= 100) {
      newCrop[key] = Math.max(0, 95 - (key === 'left' ? newCrop.right : newCrop.left));
    }
    if ((key === 'top' || key === 'bottom') && newCrop.top + newCrop.bottom >= 100) {
      newCrop[key] = Math.max(0, 95 - (key === 'top' ? newCrop.bottom : newCrop.top));
    }

    const updated = {
      ...selectedClip,
      transform: {
        ...selectedClip.transform,
        crop: newCrop,
      },
    };
    onUpdateClip(updated);
  };

  const applyAspectRatio = (ratio: '9:16' | '16:9' | '1:1' | '4:5') => {
    // Map target aspect ratio to scale values that produce the crop
    // The canvas always fits the video; we adjust the canvas/viewport size conceptually.
    // For our renderer, we store aspect_ratio on the transform, and the canvas adapts.
    const updated = {
      ...selectedClip,
      transform: {
        ...selectedClip.transform,
        aspect_ratio: ratio,
      },
    };
    onUpdateClip(updated);
  };

  const resetTransform = () => {
    const updated = {
      ...selectedClip,
      transform: {
        ...selectedClip.transform,
        position: { x: 0, y: 0 },
        scale: { x: 100, y: 100 },
        rotation: 0,
        crop: { left: 0, right: 0, top: 0, bottom: 0 },
        aspect_ratio: undefined,
        keyframes: [],
      },
    };
    onUpdateClip(updated);
  };

  const resetCrop = () => {
    const updated = {
      ...selectedClip,
      transform: {
        ...selectedClip.transform,
        crop: { left: 0, right: 0, top: 0, bottom: 0 },
      },
    };
    onUpdateClip(updated);
  };

  const handleColorChange = (key: string, value: number) => {
    const updated = {
      ...selectedClip,
      color_grading: {
        ...selectedClip.color_grading,
        [key]: value,
      },
    };
    onUpdateClip(updated);
  };

  const handleAiChange = (key: string, value: any) => {
    const updated = {
      ...selectedClip,
      ai_features: {
        ...selectedClip.ai_features,
        [key]: value,
      },
    };
    onUpdateClip(updated);
  };

  function getClipTypeLabel(type: string | null) {
    if (type === 'video') return 'فيديو';
    if (type === 'audio') return 'صوت';
    if (type === 'overlay') return 'تراكب';
    if (type === 'subtitle') return 'ترجمة';
    return type || '';
  }

  return (
    <div className="w-full h-full flex flex-col font-sans" style={{ background: 'var(--bg-surface-1)', color: 'var(--text-primary)' }}>
      {/* Panel Header */}
      <div className="p-3 border-b flex items-center justify-between" style={{ borderColor: 'var(--border-subtle)' }}>
        <h3 className="text-xs font-semibold" style={{ color: 'var(--text-primary)' }}>خصائص العنصر</h3>
        <span className="text-[9px] px-1.5 py-0.5 rounded border leading-none font-semibold uppercase" style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-default)', color: 'var(--text-secondary)' }}>
          {getClipTypeLabel(clipType)}
        </span>
      </div>

      {/* Tabs Selector */}
      <div className="flex border-b" style={{ borderColor: 'var(--border-subtle)' }}>
        <button
          onClick={() => setActiveTab('transform')}
          className="flex-1 py-3 text-xs flex items-center justify-center gap-1.5 transition-all cursor-pointer font-medium"
          style={{
            color: activeTab === 'transform' ? 'var(--accent)' : 'var(--text-secondary)',
            borderBottom: activeTab === 'transform' ? '2px solid var(--accent)' : '2px solid transparent',
          }}
        >
          <Video className="w-4 h-4" />
          أبعاد
        </button>
        <button
          onClick={() => setActiveTab('color')}
          className="flex-1 py-3 text-xs flex items-center justify-center gap-1.5 transition-all cursor-pointer font-medium"
          style={{
            color: activeTab === 'color' ? 'var(--accent)' : 'var(--text-secondary)',
            borderBottom: activeTab === 'color' ? '2px solid var(--accent)' : '2px solid transparent',
          }}
        >
          <Paintbrush className="w-4 h-4" />
          ألوان
        </button>
        <button
          onClick={() => setActiveTab('audio')}
          className="flex-1 py-3 text-xs flex items-center justify-center gap-1.5 transition-all cursor-pointer font-medium"
          style={{
            color: activeTab === 'audio' ? 'var(--accent)' : 'var(--text-secondary)',
            borderBottom: activeTab === 'audio' ? '2px solid var(--accent)' : '2px solid transparent',
          }}
        >
          <Volume2 className="w-4 h-4" />
          صوت
        </button>
        <button
          onClick={() => setActiveTab('ai')}
          className="flex-1 py-3 text-xs flex items-center justify-center gap-1.5 transition-all cursor-pointer font-medium"
          style={{
            color: activeTab === 'ai' ? 'var(--accent-violet)' : 'var(--text-secondary)',
            borderBottom: activeTab === 'ai' ? '2px solid var(--accent-violet)' : '2px solid transparent',
          }}
        >
          <Sparkles className="w-4 h-4" />
          ذكاء اصطناعي
        </button>
        <button
          onClick={() => setActiveTab('tools')}
          className="flex-1 py-3 text-xs flex items-center justify-center gap-1.5 transition-all cursor-pointer font-medium"
          style={{
            color: activeTab === 'tools' ? '#0a84ff' : 'var(--text-secondary)',
            borderBottom: activeTab === 'tools' ? '2px solid #0a84ff' : '2px solid transparent',
          }}
          title="219 أداة AI"
        >
          <Wand className="w-4 h-4" />
          AI Tools
        </button>
        <button
          onClick={() => setActiveTab('viral')}
          className="flex-1 py-3 text-xs flex items-center justify-center gap-1.5 transition-all cursor-pointer font-medium"
          style={{
            color: activeTab === 'viral' ? '#F97316' : 'var(--text-secondary)',
            borderBottom: activeTab === 'viral' ? '2px solid #F97316' : '2px solid transparent',
          }}
        >
          <Activity className="w-4 h-4" />
          Viral
        </button>
      </div>

      {/* Panel Body */}
      <div className="flex-1 overflow-y-auto p-4 flex flex-col gap-5">
        {/* Transform Tab */}
        {activeTab === 'transform' && selectedClip.transform && (
          <div className="flex flex-col gap-4">
            {/* Position */}
            <div className="flex flex-col gap-1 text-right">
              <label className="apple-label">الموضع (X, Y)</label>
              <div className="flex gap-2">
                <div className="flex-1 flex items-center px-3 py-2 rounded-[7px] border" style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-default)' }}>
                  <span className="text-[10px] w-4 font-semibold" style={{ color: 'var(--text-tertiary)' }}>X</span>
                  <input
                    type="number"
                    value={selectedClip.transform.position?.x || 0}
                    onChange={(e) => handleVectorChange('position', 'x', Number(e.target.value))}
                    className="w-full bg-transparent border-none text-xs text-white focus:outline-none text-left"
                  />
                </div>
                <div className="flex-1 flex items-center px-3 py-2 rounded-[7px] border" style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-default)' }}>
                  <span className="text-[10px] w-4 font-semibold" style={{ color: 'var(--text-tertiary)' }}>Y</span>
                  <input
                    type="number"
                    value={selectedClip.transform.position?.y || 0}
                    onChange={(e) => handleVectorChange('position', 'y', Number(e.target.value))}
                    className="w-full bg-transparent border-none text-xs text-white focus:outline-none text-left"
                  />
                </div>
              </div>
            </div>

            <div className="apple-separator" />

            {/* Scale */}
            <div className="flex flex-col gap-1 text-right">
              <label className="apple-label">الحجم (W, H) %</label>
              <div className="flex gap-2">
                <div className="flex-1 flex items-center px-3 py-2 rounded-[7px] border" style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-default)' }}>
                  <span className="text-[10px] w-4 font-semibold" style={{ color: 'var(--text-tertiary)' }}>W</span>
                  <input
                    type="number"
                    value={selectedClip.transform.scale?.x || 100}
                    onChange={(e) => handleVectorChange('scale', 'x', Number(e.target.value))}
                    className="w-full bg-transparent border-none text-xs text-white focus:outline-none text-left"
                  />
                </div>
                <div className="flex-1 flex items-center px-3 py-2 rounded-[7px] border" style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-default)' }}>
                  <span className="text-[10px] w-4 font-semibold" style={{ color: 'var(--text-tertiary)' }}>H</span>
                  <input
                    type="number"
                    value={selectedClip.transform.scale?.y || 100}
                    onChange={(e) => handleVectorChange('scale', 'y', Number(e.target.value))}
                    className="w-full bg-transparent border-none text-xs text-white focus:outline-none text-left"
                  />
                </div>
              </div>
            </div>

            <div className="apple-separator" />

            {/* Rotation */}
            <div className="flex flex-col gap-1.5 text-right">
              <div className="flex justify-between text-xs items-center">
                <span className="font-mono text-[11px]" style={{ color: 'var(--text-secondary)' }}>{selectedClip.transform.rotation || 0}°</span>
                <span className="apple-label">الدوران</span>
              </div>
              <input
                type="range"
                min="-180"
                max="180"
                value={selectedClip.transform.rotation || 0}
                onChange={(e) => handleTransformChange('rotation', Number(e.target.value))}
                className="w-full h-1 bg-gray-800 rounded-lg appearance-none cursor-pointer"
                style={{ accentColor: 'var(--accent)' }}
              />
            </div>

            <div className="apple-separator" />

            {/* Aspect Ratio Presets */}
            <div className="flex flex-col gap-1.5 text-right">
              <div className="flex justify-between text-xs items-center">
                <button
                  onClick={resetTransform}
                  className="text-[10px] font-semibold transition-colors cursor-pointer"
                  style={{ color: 'var(--accent)' }}
                  title="إعادة تعيين كل التحويلات"
                >
                  ↺ إعادة تعيين
                </button>
                <span className="apple-label">أبعاد الإطار</span>
              </div>
              <div className="grid grid-cols-4 gap-1.5" dir="ltr">
                {(['9:16', '16:9', '1:1', '4:5'] as const).map((ratio) => {
                  const isActive = (selectedClip.transform as any)?.aspect_ratio === ratio;
                  return (
                    <button
                      key={ratio}
                      onClick={() => applyAspectRatio(ratio)}
                      className="py-1.5 px-2 rounded-[7px] border text-[11px] font-semibold transition-all cursor-pointer"
                      style={{
                        background: isActive ? 'var(--accent)' : 'var(--bg-surface-3)',
                        borderColor: isActive ? 'var(--accent)' : 'var(--border-default)',
                        color: isActive ? '#fff' : 'var(--text-secondary)',
                      }}
                      title={`تطبيق أبعاد ${ratio}`}
                    >
                      {ratio}
                    </button>
                  );
                })}
              </div>
              <p className="text-[10px] mt-0.5" style={{ color: 'var(--text-tertiary)' }}>
                السوشيال ميديا: 9:16 (تيك توك/ريلز) · 16:9 (يوتيوب) · 1:1 (إنستا) · 4:5 (إنستا فيد)
              </p>
            </div>

            <div className="apple-separator" />

            {/* Crop Controls */}
            <div className="flex flex-col gap-1.5 text-right">
              <div className="flex justify-between text-xs items-center">
                <button
                  onClick={resetCrop}
                  className="text-[10px] font-semibold transition-colors cursor-pointer"
                  style={{ color: 'var(--accent)' }}
                  title="إعادة تعيين الكروب"
                >
                  ↺ إعادة
                </button>
                <span className="apple-label">الكروب (Crop) %</span>
              </div>

              <div className="grid grid-cols-2 gap-2">
                <div className="flex flex-col gap-1">
                  <span className="text-[10px] text-right" style={{ color: 'var(--text-tertiary)' }}>يسار</span>
                  <div className="flex items-center px-2.5 py-1.5 rounded-[6px] border" style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-default)' }}>
                    <input
                      type="number"
                      min="0"
                      max="95"
                      value={(selectedClip.transform as any)?.crop?.left || 0}
                      onChange={(e) => handleCropChange('left', Number(e.target.value))}
                      className="w-full bg-transparent border-none text-xs text-white focus:outline-none text-left"
                    />
                    <span className="text-[10px] mr-1" style={{ color: 'var(--text-tertiary)' }}>%</span>
                  </div>
                </div>
                <div className="flex flex-col gap-1">
                  <span className="text-[10px] text-right" style={{ color: 'var(--text-tertiary)' }}>يمين</span>
                  <div className="flex items-center px-2.5 py-1.5 rounded-[6px] border" style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-default)' }}>
                    <input
                      type="number"
                      min="0"
                      max="95"
                      value={(selectedClip.transform as any)?.crop?.right || 0}
                      onChange={(e) => handleCropChange('right', Number(e.target.value))}
                      className="w-full bg-transparent border-none text-xs text-white focus:outline-none text-left"
                    />
                    <span className="text-[10px] mr-1" style={{ color: 'var(--text-tertiary)' }}>%</span>
                  </div>
                </div>
                <div className="flex flex-col gap-1">
                  <span className="text-[10px] text-right" style={{ color: 'var(--text-tertiary)' }}>أعلى</span>
                  <div className="flex items-center px-2.5 py-1.5 rounded-[6px] border" style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-default)' }}>
                    <input
                      type="number"
                      min="0"
                      max="95"
                      value={(selectedClip.transform as any)?.crop?.top || 0}
                      onChange={(e) => handleCropChange('top', Number(e.target.value))}
                      className="w-full bg-transparent border-none text-xs text-white focus:outline-none text-left"
                    />
                    <span className="text-[10px] mr-1" style={{ color: 'var(--text-tertiary)' }}>%</span>
                  </div>
                </div>
                <div className="flex flex-col gap-1">
                  <span className="text-[10px] text-right" style={{ color: 'var(--text-tertiary)' }}>أسفل</span>
                  <div className="flex items-center px-2.5 py-1.5 rounded-[6px] border" style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-default)' }}>
                    <input
                      type="number"
                      min="0"
                      max="95"
                      value={(selectedClip.transform as any)?.crop?.bottom || 0}
                      onChange={(e) => handleCropChange('bottom', Number(e.target.value))}
                      className="w-full bg-transparent border-none text-xs text-white focus:outline-none text-left"
                    />
                    <span className="text-[10px] mr-1" style={{ color: 'var(--text-tertiary)' }}>%</span>
                  </div>
                </div>
              </div>

              <p className="text-[10px] mt-1" style={{ color: 'var(--text-tertiary)' }}>
                قص أطراف الفيديو لإزالة الحواف غير المرغوبة
              </p>
            </div>
          </div>
        )}

        {/* Color Grading Tab */}
        {activeTab === 'color' && selectedClip.color_grading && (
          <div className="flex flex-col gap-4">
            <ColorWheels
              lift={selectedClip.color_grading.lift || { r: 0, g: 0, b: 0 }}
              gamma={selectedClip.color_grading.gamma || { r: 1, g: 1, b: 1 }}
              gain={selectedClip.color_grading.gain || { r: 1, g: 1, b: 1 }}
              onChange={(newLift, newGamma, newGain) => {
                const updated = {
                  ...selectedClip,
                  color_grading: {
                    ...selectedClip.color_grading,
                    lift: newLift,
                    gamma: newGamma,
                    gain: newGain
                  }
                };
                onUpdateClip(updated);
              }}
            />

            <div className="apple-separator" />

            {/* Saturation */}
            <div className="flex flex-col gap-1.5 text-right">
              <div className="flex justify-between text-xs items-center">
                <span className="font-mono text-[11px]" style={{ color: 'var(--text-secondary)' }}>{selectedClip.color_grading.saturation?.toFixed(2)}x</span>
                <span className="apple-label">التشبع</span>
              </div>
              <input
                type="range"
                min="0"
                max="3"
                step="0.05"
                value={selectedClip.color_grading.saturation || 1.0}
                onChange={(e) => handleColorChange('saturation', Number(e.target.value))}
                className="w-full h-1 bg-gray-800 rounded-lg appearance-none cursor-pointer"
                style={{ accentColor: 'var(--accent)' }}
              />
            </div>

            <div className="apple-separator" />

            {/* Temperature */}
            <div className="flex flex-col gap-1.5 text-right">
              <div className="flex justify-between text-xs items-center">
                <span className="font-mono text-[11px]" style={{ color: 'var(--text-secondary)' }}>{selectedClip.color_grading.temperature || 6500}K</span>
                <span className="apple-label">حرارة اللون</span>
              </div>
              <input
                type="range"
                min="2000"
                max="12000"
                step="100"
                value={selectedClip.color_grading.temperature || 6500}
                onChange={(e) => handleColorChange('temperature', Number(e.target.value))}
                className="w-full h-1 bg-gray-800 rounded-lg appearance-none cursor-pointer"
                style={{ accentColor: 'var(--accent)' }}
              />
            </div>
          </div>
        )}

        {/* Audio / Smart Audio Tab */}
        {activeTab === 'audio' && selectedClip.ai_features && (
          <div className="flex flex-col gap-4 text-right">
            <h4 className="text-[10px] font-semibold uppercase tracking-wider text-right" style={{ color: 'var(--accent)' }}>التحكم بالصوت</h4>
            
            {/* General Volume */}
            <div className="flex flex-col gap-1.5 text-right">
              <div className="flex justify-between text-xs items-center">
                <span className="font-mono text-[11px]" style={{ color: 'var(--text-secondary)' }}>{(selectedClip.volume * 100).toFixed(0)}%</span>
                <span className="apple-label">مستوى الصوت العام</span>
              </div>
              <input
                type="range"
                min="0"
                max="2"
                step="0.05"
                value={selectedClip.volume !== undefined ? selectedClip.volume : 1.0}
                onChange={(e) => {
                  const updated = {
                    ...selectedClip,
                    volume: Number(e.target.value)
                  };
                  onUpdateClip(updated);
                }}
                className="w-full h-1 bg-gray-800 rounded-lg appearance-none cursor-pointer"
                style={{ accentColor: 'var(--accent)' }}
              />
            </div>

            <div className="apple-separator" />

            <h4 className="text-[10px] font-semibold uppercase tracking-wider text-right" style={{ color: 'var(--accent-violet)' }}>تحسينات الصوت بالذكاء الاصطناعي</h4>

            {/* Vocal Isolation */}
            <div className="flex items-center justify-between p-3 rounded-lg border text-right" style={{ background: 'var(--bg-surface-2)', borderColor: 'var(--border-default)' }}>
              <ToggleSwitch
                checked={selectedClip.ai_features.vocal_isolation || false}
                onChange={(val) => handleAiChange('vocal_isolation', val)}
              />
              <div>
                <div className="text-xs font-semibold">عزل صوت المتحدث (Vocals Isolation)</div>
                <div className="text-[9px] mt-0.5" style={{ color: 'var(--text-tertiary)' }}>عزل الضوضاء والموسيقى الخلفية محلياً بالكامل</div>
              </div>
            </div>

            {/* Auto Ducking */}
            <div className="p-3 rounded-lg border flex flex-col gap-3 text-right" style={{ background: 'var(--bg-surface-2)', borderColor: 'var(--border-default)' }}>
              <div className="flex items-center justify-between">
                <ToggleSwitch
                  checked={selectedClip.ai_features.auto_ducking || false}
                  onChange={(val) => handleAiChange('auto_ducking', val)}
                />
                <div>
                  <div className="text-xs font-semibold">خفض الموسيقى التلقائي (Auto-Ducking)</div>
                  <div className="text-[9px] mt-0.5" style={{ color: 'var(--text-tertiary)' }}>تخفيض الموسيقى الخلفية تلقائياً أثناء كلام المتحدث</div>
                </div>
              </div>

              {selectedClip.ai_features.auto_ducking && (
                <div className="space-y-2 pt-2 border-t" style={{ borderColor: 'var(--border-subtle)' }}>
                  <div className="flex justify-between text-xs items-center">
                    <span className="font-mono text-[11px]" style={{ color: 'var(--text-secondary)' }}>
                      {((selectedClip.ai_features.ducking_level !== undefined ? selectedClip.ai_features.ducking_level : 0.2) * 100).toFixed(0)}%
                    </span>
                    <span className="apple-label">حجم صوت الخلفية عند الكلام</span>
                  </div>
                  <input
                    type="range"
                    min="0"
                    max="1"
                    step="0.05"
                    value={selectedClip.ai_features.ducking_level !== undefined ? selectedClip.ai_features.ducking_level : 0.2}
                    onChange={(e) => handleAiChange('ducking_level', Number(e.target.value))}
                    className="w-full h-1 bg-gray-800 rounded-lg appearance-none cursor-pointer"
                    style={{ accentColor: 'var(--accent)' }}
                  />
                </div>
              )}
            </div>
          </div>
        )}

        {/* AI Co-pilot Tab */}
        {activeTab === 'ai' && selectedClip.ai_features && (
          <div className="flex flex-col gap-4">
            <h4 className="text-[10px] font-semibold uppercase tracking-wider text-right" style={{ color: 'var(--accent-violet)' }}>أدوات الذكاء الاصطناعي المحلية</h4>
            
            {/* Face Tracking */}
            <div className="flex items-center justify-between p-3 rounded-lg border text-right" style={{ background: 'var(--bg-surface-2)', borderColor: 'var(--border-default)' }}>
              <ToggleSwitch
                checked={selectedClip.ai_features.face_tracking || false}
                onChange={(val) => handleAiChange('face_tracking', val)}
              />
              <div>
                <div className="text-xs font-semibold">تتبع الوجه (Auto-Framing)</div>
                <div className="text-[9px] mt-0.5" style={{ color: 'var(--text-tertiary)' }}>توسيط المتحدث تلقائياً في كادر 9:16</div>
              </div>
            </div>

            {/* Background Removal */}
            <div className="p-3 rounded-lg border flex flex-col gap-3 text-right" style={{ background: 'var(--bg-surface-2)', borderColor: 'var(--border-default)' }}>
              <div className="flex items-center justify-between">
                <ToggleSwitch
                  checked={selectedClip.ai_features.bg_removed || false}
                  onChange={(val) => handleAiChange('bg_removed', val)}
                />
                <div>
                  <div className="text-xs font-semibold">عزل الخلفية</div>
                  <div className="text-[9px] mt-0.5" style={{ color: 'var(--text-tertiary)' }}>إزالة الخلفية بذكاء اصطناعي محلي</div>
                </div>
              </div>

              {selectedClip.ai_features.bg_removed && (
                <div className="space-y-2 pt-2 border-t" style={{ borderColor: 'var(--border-subtle)' }}>
                  <div className="space-y-1">
                    <label className="apple-label">طريقة العزل</label>
                    <select
                      value={selectedClip.ai_features.bg_remove_method || 'rmbg'}
                      onChange={(e) => handleAiChange('bg_remove_method', e.target.value)}
                      className="w-full bg-[var(--bg-surface-3)] border border-[var(--border-default)] text-xs text-[var(--text-primary)] rounded-[6px] p-1.5 focus:outline-none focus:border-[var(--accent)]"
                    >
                      <option value="rmbg">موديل RMBG-1.4 (محلي وسريع)</option>
                      <option value="chromakey">الكروما الخضراء (Chroma Key)</option>
                      <option value="sam">تحديد كائنات SAM (دقة عالية)</option>
                    </select>
                  </div>

                  {selectedClip.ai_features.bg_remove_method === 'chromakey' && (
                    <div className="space-y-1">
                      <label className="apple-label">اللون المراد إزالته</label>
                      <div className="flex gap-2 items-center justify-end">
                        <span className="text-xs font-mono" style={{ color: 'var(--text-secondary)' }}>{selectedClip.ai_features.chromakey_color || '#00FF00'}</span>
                        <input
                          type="color"
                          value={selectedClip.ai_features.chromakey_color || '#00FF00'}
                          onChange={(e) => handleAiChange('chromakey_color', e.target.value)}
                          className="w-8 h-8 rounded border cursor-pointer bg-transparent"
                          style={{ borderColor: 'var(--border-default)' }}
                        />
                      </div>
                    </div>
                  )}
                </div>
              )}
            </div>
          </div>
        )}

        {/* Viral Analytics Tab */}
        {activeTab === 'viral' && (
          <ViralAnalyticsPanel
            clip={selectedClip}
            onApplyRecommendation={(rec) => {
              console.log('Applying recommendation:', rec);
              // This is where we'd auto-apply the recommendation to the clip
            }}
          />
        )}

        {/* AI Tools Tab — 219 tools from TOOL_REGISTRY */}
        {activeTab === 'tools' && (
          <div className="absolute inset-0 top-0 pt-12">
            <AIToolPalette />
          </div>
        )}
      </div>
    </div>
  );
};

export default InspectorPanel;
