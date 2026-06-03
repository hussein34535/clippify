import React, { createContext, useContext, useState, useCallback, type ReactNode } from 'react';
import { AlertCircle, CheckCircle, Info, X } from 'lucide-react';

export type ToastType = 'success' | 'error' | 'info';

interface Toast {
  id: string;
  message: string;
  type: ToastType;
}

interface ToastContextValue {
  showToast: (message: string, type?: ToastType) => void;
}

const ToastContext = createContext<ToastContextValue | undefined>(undefined);

export const useToast = () => {
  const context = useContext(ToastContext);
  if (!context) throw new Error('useToast must be used within a ToastProvider');
  return context;
};

export const ToastProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const [toasts, setToasts] = useState<Toast[]>([]);

  const showToast = useCallback((message: string, type: ToastType = 'info') => {
    const id = Date.now().toString();
    setToasts(prev => [...prev, { id, message, type }]);
    
    // Auto remove after 4 seconds
    setTimeout(() => {
      setToasts(prev => prev.filter(t => t.id !== id));
    }, 4000);
  }, []);

  const removeToast = (id: string) => {
    setToasts(prev => prev.filter(t => t.id !== id));
  };

  return (
    <ToastContext.Provider value={{ showToast }}>
      {children}
      <div className="fixed bottom-4 left-1/2 -translate-x-1/2 z-[9999] flex flex-col items-center gap-2 pointer-events-none">
        {toasts.map(toast => (
          <div 
            key={toast.id}
            className="flex items-center gap-3 px-4 py-3 rounded-lg shadow-lg pointer-events-auto transition-all animate-in slide-in-from-bottom-5 fade-in duration-300"
            style={{ 
              background: 'var(--bg-surface-1)', 
              border: `1px solid ${toast.type === 'error' ? 'var(--accent-red)' : toast.type === 'success' ? 'var(--accent-green)' : 'var(--border-strong)'}`,
              color: 'var(--text-primary)',
              minWidth: '300px'
            }}
          >
            {toast.type === 'error' && <AlertCircle className="w-5 h-5 text-[var(--accent-red)]" />}
            {toast.type === 'success' && <CheckCircle className="w-5 h-5 text-[var(--accent-green)]" />}
            {toast.type === 'info' && <Info className="w-5 h-5 text-[var(--text-secondary)]" />}
            
            <span className="flex-1 text-sm font-medium text-right">{toast.message}</span>
            
            <button 
              onClick={() => removeToast(toast.id)}
              className="text-[var(--text-tertiary)] hover:text-white transition-colors"
            >
              <X className="w-4 h-4" />
            </button>
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
};
