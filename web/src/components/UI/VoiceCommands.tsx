// VoiceCommands.tsx
// Phase 8 — Voice Commands: Web Speech API integration for hands-free editing.

import { useState, useEffect, useRef } from 'react';
import { Mic, MicOff, Volume2, X } from 'lucide-react';
import { executeAIAction } from '../../lib/aiActions';

interface VoiceCommandsProps {
  onTranscript?: (text: string) => void;
}

// Simple keyword-based intent recognition (can be upgraded to LLM)
function parseIntent(transcript: string): { name: string; args: Record<string, any> } | null {
  const t = transcript.toLowerCase().trim();
  
  // Playback
  if (/(play|شغل|تشغيل|إبدأ|ابدأ)/.test(t)) return { name: 'playback.play', args: {} };
  if (/(pause|وقف|إيقاف|مهل|اسكت)/.test(t)) return { name: 'playback.pause', args: {} };
  if (/(stop|قف|توقف)/.test(t)) return { name: 'playback.stop', args: {} };
  if (/(full ?screen|ملء|كامل الشاشة|كامل)/.test(t)) return { name: 'playback.toggle_fullscreen', args: {} };
  
  // Timeline
  if (/(split|cut|قسم|تقسيم|قص)/.test(t)) return { name: 'timeline.split_clip', args: {} };
  if (/(delete|remove|احذف|حذف|شيل)/.test(t)) return { name: 'timeline.delete_clip', args: {} };
  if (/(undo|تراجع|رجوع)/.test(t)) return { name: 'timeline.undo', args: {} };
  if (/(redo|إعادة|تقدم)/.test(t)) return { name: 'timeline.redo', args: {} };
  if (/(marker|علامة|ماركر)/.test(t)) return { name: 'timeline.add_marker', args: {} };
  
  // Audio
  if (/(mute|كتم|اسكت)/.test(t)) return { name: 'audio.toggle_mute', args: {} };
  if (/(louder|higher|أعلى|ارفع|زود)/.test(t)) return { name: 'audio.set_volume', args: { volume: 80 } };
  if (/(quieter|lower|أخفض|واطي)/.test(t)) return { name: 'audio.set_volume', args: { volume: 30 } };
  
  // Subtitles
  if (/(subtitle|ترجمة|سبتايتل)/.test(t)) return { name: 'subtitles.toggle_visibility', args: {} };
  
  // Export
  if (/(export|تصدير|صدّر)/.test(t)) return { name: 'export.start', args: {} };
  
  return null;
}

export default function VoiceCommands({ onTranscript }: VoiceCommandsProps) {
  const [listening, setListening] = useState(false);
  const [transcript, setTranscript] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [open, setOpen] = useState(false);
  const recognitionRef = useRef<any>(null);
  const languageRef = useRef<'ar-SA' | 'en-US'>('ar-SA');

  useEffect(() => {
    if (typeof window === 'undefined') return;
    const SR = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (!SR) {
      setError('متصفحك لا يدعم التعرف على الصوت');
      return;
    }
    const recognition = new SR();
    recognition.continuous = true;
    recognition.interimResults = true;
    recognition.lang = languageRef.current;
    recognition.maxAlternatives = 1;

    recognition.onresult = (event: any) => {
      const last = event.results[event.results.length - 1];
      const text = last[0].transcript;
      setTranscript(text);
      onTranscript?.(text);
      if (last.isFinal) {
        const intent = parseIntent(text);
        if (intent) {
          executeAIAction(intent.name, intent.args);
          setTranscript(`✓ ${text}`);
          setTimeout(() => setTranscript(''), 1500);
        }
      }
    };

    recognition.onerror = (event: any) => {
      setError(`خطأ: ${event.error}`);
      setListening(false);
    };

    recognition.onend = () => {
      if (listening) {
        try { recognition.start(); } catch {}
      }
    };

    recognitionRef.current = recognition;
    return () => {
      try { recognition.stop(); } catch {}
    };
  }, [listening, onTranscript]);

  const toggleListening = () => {
    if (!recognitionRef.current) return;
    if (listening) {
      recognitionRef.current.stop();
      setListening(false);
    } else {
      try {
        recognitionRef.current.start();
        setListening(true);
        setError(null);
      } catch (e: any) {
        setError(e.message);
      }
    }
  };

  const toggleLanguage = () => {
    languageRef.current = languageRef.current === 'ar-SA' ? 'en-US' : 'ar-SA';
    if (recognitionRef.current) {
      recognitionRef.current.lang = languageRef.current;
      setTranscript('');
    }
  };

  if (error && !recognitionRef.current) {
    return (
      <button
        disabled
        className="w-7 h-7 rounded-full flex items-center justify-center opacity-30 cursor-not-allowed"
        style={{ color: 'var(--text-secondary)' }}
        title={error}
      >
        <MicOff className="w-4 h-4" />
      </button>
    );
  }

  return (
    <div className="relative">
      <button
        onClick={() => setOpen(!open)}
        className="w-7 h-7 rounded-full flex items-center justify-center transition-all cursor-pointer hover:bg-[var(--bg-surface-3)]"
        style={{ color: listening ? '#FF453A' : 'var(--text-secondary)' }}
        title="الأوامر الصوتية (عربي / English)"
      >
        {listening ? <Mic className="w-4 h-4 animate-pulse" /> : <MicOff className="w-4 h-4" />}
      </button>

      {open && (
        <div
          className="absolute top-9 left-0 w-72 rounded-lg border shadow-xl z-50 overflow-hidden"
          style={{ background: 'var(--bg-surface-1)', borderColor: 'var(--border-default)' }}
        >
          <div className="p-3 border-b flex items-center justify-between" style={{ borderColor: 'var(--border-subtle)' }}>
            <p className="text-[11px] font-semibold flex items-center gap-1.5" style={{ color: 'var(--text-primary)' }}>
              <Volume2 className="w-3.5 h-3.5" style={{ color: 'var(--accent)' }} />
              الأوامر الصوتية
            </p>
            <button
              onClick={() => setOpen(false)}
              className="p-0.5 rounded hover:bg-[var(--bg-surface-3)]"
              style={{ color: 'var(--text-secondary)' }}
            >
              <X className="w-3.5 h-3.5" />
            </button>
          </div>

          <div className="p-3">
            <button
              onClick={toggleListening}
              className="w-full py-2.5 rounded text-[12px] font-semibold flex items-center justify-center gap-2"
              style={{ background: listening ? '#FF453A' : 'var(--accent)', color: '#fff' }}
            >
              {listening ? <Mic className="w-4 h-4 animate-pulse" /> : <MicOff className="w-4 h-4" />}
              {listening ? 'جاري الاستماع...' : 'ابدأ الاستماع'}
            </button>

            <button
              onClick={toggleLanguage}
              className="w-full mt-2 py-1.5 rounded text-[10px] font-semibold"
              style={{ background: 'var(--bg-surface-3)', color: 'var(--text-primary)' }}
            >
              اللغة: {languageRef.current === 'ar-SA' ? '🇸🇦 العربية' : '🇺🇸 English'}
            </button>

            {transcript && (
              <div
                className="mt-3 p-2 rounded text-[11px] text-center"
                style={{ background: 'var(--bg-surface-2)', color: 'var(--text-primary)' }}
              >
                {transcript}
              </div>
            )}

            {error && (
              <div className="mt-2 p-2 rounded text-[10px] text-center" style={{ background: 'rgba(255,69,58,0.1)', color: '#FF453A' }}>
                {error}
              </div>
            )}

            <details className="mt-3">
              <summary className="text-[10px] cursor-pointer" style={{ color: 'var(--accent)' }}>
                الأوامر المدعومة
              </summary>
              <div className="mt-2 space-y-0.5 text-[10px]" style={{ color: 'var(--text-secondary)' }}>
                <p>• "شغل" / "play" — تشغيل</p>
                <p>• "وقف" / "pause" — إيقاف</p>
                <p>• "قسم" / "split" — تقسيم</p>
                <p>• "احذف" / "delete" — حذف</p>
                <p>• "تراجع" / "undo" — تراجع</p>
                <p>• "أعلى الصوت" / "louder" — رفع الصوت</p>
                <p>• "كتم" / "mute" — كتم</p>
                <p>• "علامة" / "marker" — إضافة Marker</p>
                <p>• "ملء الشاشة" / "fullscreen"</p>
              </div>
            </details>
          </div>
        </div>
      )}
    </div>
  );
}
