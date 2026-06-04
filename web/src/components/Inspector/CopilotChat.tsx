import { useState, useRef, useEffect } from 'react';
import axios from 'axios';
import { Send, Sparkles, MessageSquare, AlertCircle } from 'lucide-react';
import { API_BASE } from '../../api';
import { useStore } from '../../store';

interface Message {
  sender: 'user' | 'assistant';
  text: string;
  isError?: boolean;
}

interface CopilotChatProps {
  onApplyActionPlan: (actions: any[]) => void;
}

const QUICK_COMMANDS = [
  'تتبع المتحدث تلقائياً',
  'قص الفترات الصامتة',
  'عزل صوت المتحدث وإلغاء الضوضاء',
  'تفعيل خفض الموسيقى التلقائي (Ducking)'
];

export default function CopilotChat({ onApplyActionPlan }: CopilotChatProps) {
  const [messages, setMessages] = useState<Message[]>([
    {
      sender: 'assistant',
      text: 'أهلاً بك! أنا مساعد المونتاج الذكي الخاص بك. يمكنك كتابة أوامر مثل "تتبع وجه المتحدث"، "أزل الخلفية"، أو "قص الصمت" وسأقوم بتعديل التايم لاين فورياً بالذكاء الاصطناعي.'
    }
  ]);
  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(false);
  const chatEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const handleSend = async (textToSend: string) => {
    if (!textToSend.trim() || loading) return;

    const userMessage: Message = { sender: 'user', text: textToSend };
    setMessages(prev => [...prev, userMessage]);
    setInput('');
    setLoading(true);

    const words = useStore.getState().words;
    const timelineState = useStore.getState().timelineState;

    try {
      const response = await axios.post(`${API_BASE}/api/copilot/chat`, {
        prompt: textToSend,
        transcript: words,
        timeline_state: timelineState,
      });

      const data = response.data;
      if (data.response_message) {
        setMessages(prev => [...prev, { sender: 'assistant', text: data.response_message }]);
      } else {
        setMessages(prev => [...prev, { sender: 'assistant', text: 'تمت معالجة الأمر بنجاح!' }]);
      }

      if (data.actions && Array.isArray(data.actions) && data.actions.length > 0) {
        onApplyActionPlan(data.actions);
      }
    } catch (err: any) {
      const errMsg = err.response?.data?.detail || err.message || 'فشل الاتصال بخادم الذكاء الاصطناعي.';
      setMessages(prev => [...prev, { sender: 'assistant', text: `خطأ: ${errMsg}`, isError: true }]);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="flex flex-col h-full font-sans select-none" style={{ color: 'var(--text-primary)' }}>
      {/* Header */}
      <div className="p-3 border-b flex items-center justify-between" style={{ borderColor: 'var(--border-subtle)' }}>
        <h3 className="text-xs font-semibold flex items-center gap-1.5" style={{ color: 'var(--accent)' }}>
          <Sparkles className="w-3.5 h-3.5 animate-pulse" />
          مساعد المونتاج الذكي (Co-pilot)
        </h3>
        <span className="text-[9px] px-1.5 py-0.5 rounded border leading-none font-semibold uppercase" style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-default)', color: 'var(--text-secondary)' }}>
          Gemma 4
        </span>
      </div>

      {/* Chat Area */}
      <div className="flex-1 overflow-y-auto p-3 flex flex-col gap-3.5 min-h-0">
        {messages.map((msg, i) => {
          const isAssistant = msg.sender === 'assistant';
          return (
            <div
              key={i}
              className={`flex flex-col max-w-[85%] rounded-[12px] p-2.5 text-xs text-right leading-relaxed ${
                isAssistant
                  ? msg.isError
                    ? 'self-start bg-red-950/40 border border-red-500/20 text-red-300'
                    : 'self-start bg-[var(--bg-surface-2)] border border-[var(--border-default)]'
                  : 'self-end bg-[var(--accent)] text-white'
              }`}
            >
              <div className="flex items-center gap-1.5 mb-1 justify-end">
                <span className="text-[10px] font-semibold opacity-75">
                  {isAssistant ? 'المساعد الذكي' : 'أنت'}
                </span>
                {isAssistant ? (
                  msg.isError ? <AlertCircle className="w-3 h-3" /> : <Sparkles className="w-3 h-3 text-[var(--accent-violet)]" />
                ) : (
                  <MessageSquare className="w-3 h-3" />
                )}
              </div>
              <p className="whitespace-pre-line text-right">{msg.text}</p>
            </div>
          );
        })}
        {loading && (
          <div className="self-start bg-[var(--bg-surface-2)] border border-[var(--border-default)] rounded-[12px] p-3 text-xs text-right flex items-center gap-2">
            <div className="flex gap-1">
              <span className="w-1.5 h-1.5 bg-[var(--accent)] rounded-full animate-bounce" style={{ animationDelay: '0ms' }}></span>
              <span className="w-1.5 h-1.5 bg-[var(--accent)] rounded-full animate-bounce" style={{ animationDelay: '150ms' }}></span>
              <span className="w-1.5 h-1.5 bg-[var(--accent)] rounded-full animate-bounce" style={{ animationDelay: '300ms' }}></span>
            </div>
            <span>جاري التفكير وتعديل الفيديو...</span>
          </div>
        )}
        <div ref={chatEndRef} />
      </div>

      {/* Quick Commands */}
      <div className="px-3 py-1 flex flex-wrap gap-1.5 justify-end border-t" style={{ borderColor: 'var(--border-subtle)', background: 'var(--bg-surface-1)' }}>
        {QUICK_COMMANDS.map((cmd, i) => (
          <button
            key={i}
            onClick={() => handleSend(cmd)}
            disabled={loading}
            className="text-[10px] px-2 py-1 rounded-[6px] border transition-all cursor-pointer hover:border-[var(--accent)] disabled:cursor-not-allowed"
            style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-default)', color: 'var(--text-secondary)' }}
          >
            {cmd}
          </button>
        ))}
      </div>

      {/* Input Box */}
      <div className="p-3 border-t flex gap-2" style={{ borderColor: 'var(--border-subtle)', background: 'var(--bg-surface-1)' }}>
        <button
          onClick={() => handleSend(input)}
          disabled={!input.trim() || loading}
          className="w-8 h-8 rounded-[8px] flex items-center justify-center transition-all cursor-pointer disabled:cursor-not-allowed bg-[var(--accent)] hover:opacity-90 text-white"
        >
          <Send className="w-4.5 h-4.5 rotate-180" />
        </button>
        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && handleSend(input)}
          placeholder="اكتب أمراً هنا (مثال: ركز الكادر، أزل الخلفية)..."
          className="flex-1 bg-[var(--bg-surface-3)] border border-[var(--border-default)] rounded-[8px] px-3 py-1.5 text-xs text-right focus:outline-none focus:border-[var(--accent)] text-white placeholder-[var(--text-tertiary)]"
        />
      </div>
    </div>
  );
}
