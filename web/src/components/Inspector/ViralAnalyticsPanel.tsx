import React, { useState } from 'react';
import type { ViralRecommendation } from '../../types';

interface ViralAnalyticsPanelProps {
  clip: any;
  onApplyRecommendation?: (rec: ViralRecommendation) => void;
}

const ViralAnalyticsPanel: React.FC<ViralAnalyticsPanelProps> = ({ clip, onApplyRecommendation }) => {
  // Use clip just to bypass unused var for now
  console.log(clip?.id);
  const [loading, setLoading] = useState(false);
  const [recommendations, setRecommendations] = useState<ViralRecommendation[]>([]);

  const handleGenerate = async () => {
    setLoading(true);
    // Simulate API call to backend for recommendations
    // In a real app, this would call /api/viral/recommendations
    setTimeout(() => {
      setRecommendations([
        { time_sec: 0.0, type: 'zoom', description: 'أضف زووم سريع (Quick Zoom) لتقوية الهوك.', reason: 'أول 3 ثواني حاسمة للمشاهدة.' },
        { time_sec: 12.5, type: 'broll', description: 'أضف مقطع B-roll ذي صلة.', reason: 'انخفاض في مستوى الطاقة البصرية.' },
        { time_sec: 25.0, type: 'sfx', description: 'أضف مؤثر صوتي (Whoosh) هنا.', reason: 'إعادة جذب انتباه المشاهد.' }
      ]);
      setLoading(false);
    }, 2000);
  };

  return (
    <div className="flex flex-col gap-4 text-right">
      <h4 className="text-[10px] font-semibold uppercase tracking-wider" style={{ color: '#F97316' }}>
        تحليل الذكاء الفيروسي
      </h4>
      
      {/* Viral Score Chart */}
      <div className="p-3 rounded-lg border text-right" style={{ background: 'var(--bg-surface-2)', borderColor: 'var(--border-default)' }}>
        <div className="flex justify-between items-center mb-2">
          <span className="text-2xl font-bold text-green-400">88<span className="text-sm text-gray-500">/100</span></span>
          <span className="text-xs font-semibold">Viral Score</span>
        </div>
        <div className="h-16 w-full rounded flex items-end justify-between px-1" style={{ background: 'var(--bg-surface-3)' }}>
          {/* Simulated chart bars */}
          {[40, 60, 90, 100, 80, 50, 40, 60, 90, 70, 50, 85].map((h, i) => (
            <div 
              key={i} 
              className="w-[6%] rounded-t transition-all duration-500" 
              style={{ 
                height: `${h}%`, 
                background: h > 80 ? '#4ADE80' : h > 50 ? '#FBBF24' : '#F87171' 
              }}
            ></div>
          ))}
        </div>
        <div className="text-[9px] mt-2 text-center" style={{ color: 'var(--text-tertiary)' }}>الطاقة الفيروسية عبر الزمن</div>
      </div>

      <div className="apple-separator" />

      <h4 className="text-[10px] font-semibold uppercase tracking-wider" style={{ color: '#F97316' }}>
        توصيات التحسين (Gemma 4)
      </h4>
      
      {recommendations.length === 0 ? (
        <button 
          onClick={handleGenerate}
          disabled={loading}
          className="w-full py-2.5 rounded text-xs font-semibold transition"
          style={{ 
            background: loading ? 'var(--bg-surface-3)' : '#F97316', 
            color: loading ? 'var(--text-secondary)' : '#FFF' 
          }}
        >
          {loading ? 'جاري التحليل عبر Gemma 4...' : 'توليد توصيات المونتاج'}
        </button>
      ) : (
        <div className="flex flex-col gap-2">
          {recommendations.map((rec, i) => (
            <div key={i} className="p-2.5 border rounded-lg flex flex-col gap-1.5 text-right" style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-subtle)' }}>
              <div className="flex justify-between items-start">
                <span className="text-[9px] px-1.5 py-0.5 rounded font-bold" style={{ background: 'rgba(249, 115, 22, 0.2)', color: '#F97316' }}>
                  {rec.type.toUpperCase()}
                </span>
                <span className="text-xs font-bold" style={{ color: 'var(--text-primary)' }}>{rec.time_sec}ث</span>
              </div>
              <p className="text-[11px]" style={{ color: 'var(--text-secondary)' }}>{rec.description}</p>
              <p className="text-[9px]" style={{ color: 'var(--text-tertiary)' }}>السبب: {rec.reason}</p>
              {onApplyRecommendation && (
                <button 
                  onClick={() => onApplyRecommendation(rec)}
                  className="mt-1 text-[10px] text-left w-full hover:underline transition"
                  style={{ color: 'var(--accent)' }}
                >
                  تطبيق تلقائياً &larr;
                </button>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

export default ViralAnalyticsPanel;
