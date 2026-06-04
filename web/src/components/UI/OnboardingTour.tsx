// OnboardingTour.tsx
// Phase 17 — Onboarding: First-time user walkthrough.

import { useState, useEffect } from 'react';
import { X, ChevronLeft, ChevronRight, Sparkles } from 'lucide-react';

interface TourStep {
  target?: string;  // CSS selector
  title: string;
  description: string;
  position?: 'top' | 'bottom' | 'left' | 'right' | 'center';
}

const STEPS: TourStep[] = [
  {
    title: 'مرحباً بك في ClipAI Studio! 👋',
    description: 'محرك مونتاج احترافي بالذكاء الاصطناعي. خلينا ناخد جولة سريعة.',
    position: 'center',
  },
  {
    title: 'مكتبة الوسائط (يسار)',
    description: 'اسحب الفيديو والصور من هنا، أو اسقط ملفات من Windows File Explorer مباشرة.',
    position: 'left',
  },
  {
    title: 'المعاينة (وسط)',
    description: 'شغل الفيديو هنا. اضغط Space للتشغيل/الإيقاف، وF لملء الشاشة.',
    position: 'center',
  },
  {
    title: 'التفتيش (يمين)',
    description: 'عدّل المقاطع المختارة: القص، الألوان، الصوت، الذكاء الاصطناعي، وأكثر.',
    position: 'right',
  },
  {
    title: 'الخط الزمني (أسفل)',
    description: 'C للقسمة، Delete للحذف، Ctrl+Z للتراجع. اسحب المقاطع لإعادة ترتيبها.',
    position: 'bottom',
  },
  {
    title: '🤖 Copilot (الذكاء الاصطناعي)',
    description: 'افتح تبويب Copilot واكتب أوامر بالعربي: "قسم المقطع"، "أضف علامة"، "غيّر اللون"...',
    position: 'right',
  },
  {
    title: 'لوحة المفاتيح',
    description: 'اضغط "?" في أي وقت لفتح قائمة الاختصارات الكاملة.',
    position: 'center',
  },
  {
    title: 'جاهز للإنطلاق! 🚀',
    description: 'اسحب فيديو للبدء، أو اسأل Copilot عن أي شيء. حظاً موفقاً!',
    position: 'center',
  },
];

const STORAGE_KEY = 'clipai_onboarding_completed';

export default function OnboardingTour() {
  const [open, setOpen] = useState(false);
  const [step, setStep] = useState(0);

  useEffect(() => {
    if (typeof window === 'undefined') return;
    // Show tour if not completed and no timeline clips exist
    const completed = localStorage.getItem(STORAGE_KEY);
    if (!completed) {
      // Delay to let app render
      setTimeout(() => setOpen(true), 1500);
    }
  }, []);

  const handleNext = () => {
    if (step < STEPS.length - 1) setStep(step + 1);
    else handleComplete();
  };

  const handlePrev = () => {
    if (step > 0) setStep(step - 1);
  };

  const handleComplete = () => {
    localStorage.setItem(STORAGE_KEY, new Date().toISOString());
    setOpen(false);
  };

  if (!open) return null;

  const current = STEPS[step];

  return (
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center"
      style={{ background: 'rgba(0,0,0,0.75)', backdropFilter: 'blur(8px)' }}
    >
      <div
        className="w-[440px] rounded-2xl border shadow-2xl overflow-hidden"
        style={{ background: 'var(--bg-surface-1)', borderColor: 'var(--border-default)' }}
      >
        <div className="relative h-32 flex items-center justify-center" style={{ background: 'linear-gradient(135deg, var(--accent) 0%, #8B5CF6 100%)' }}>
          <Sparkles className="w-12 h-12 text-white opacity-50" />
          <button
            onClick={handleComplete}
            className="absolute top-3 left-3 p-1.5 rounded-full bg-white/20 hover:bg-white/30 transition-colors"
          >
            <X className="w-4 h-4 text-white" />
          </button>
          <div className="absolute bottom-2 right-3 text-[10px] text-white/80 font-mono">
            {step + 1} / {STEPS.length}
          </div>
        </div>

        <div className="p-6">
          <h2 className="text-base font-bold mb-2" style={{ color: 'var(--text-primary)' }}>
            {current.title}
          </h2>
          <p className="text-[12px] leading-relaxed" style={{ color: 'var(--text-secondary)' }}>
            {current.description}
          </p>
        </div>

        <div className="px-6 pb-4 flex items-center justify-between">
          <div className="flex gap-1">
            {STEPS.map((_, i) => (
              <div
                key={i}
                className="w-1.5 h-1.5 rounded-full transition-all"
                style={{
                  background: i === step ? 'var(--accent)' : 'var(--bg-surface-3)',
                  width: i === step ? 16 : 6,
                }}
              />
            ))}
          </div>

          <div className="flex gap-2">
            {step > 0 && (
              <button
                onClick={handlePrev}
                className="flex items-center gap-1 px-3 py-1.5 rounded text-[11px] font-semibold"
                style={{ background: 'var(--bg-surface-3)', color: 'var(--text-primary)' }}
              >
                <ChevronRight className="w-3.5 h-3.5" /> السابق
              </button>
            )}
            <button
              onClick={handleNext}
              className="flex items-center gap-1 px-4 py-1.5 rounded text-[11px] font-semibold"
              style={{ background: 'var(--accent)', color: '#fff' }}
            >
              {step === STEPS.length - 1 ? 'إنهاء' : 'التالي'}
              {step < STEPS.length - 1 && <ChevronLeft className="w-3.5 h-3.5" />}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
