// CanvasPreview.tsx
// NLE Real-time player preview using HTML5 Canvas to support grading, transform, overlays, and subtitle renderings

import React, { useRef, useEffect, useState, useCallback } from 'react';
import { Play, Pause, Volume2, VolumeX, Maximize2, Minimize2, AlertCircle, Film } from 'lucide-react';
import VideoScopes from './VideoScopes';
import type { TimelineState, VideoClip, SubtitleClip } from '../../types';

type AspectRatio = '9:16' | '16:9' | '1:1' | '4:5';
type FitMode = 'fit' | 'fill';

const ASPECT_RATIOS: Record<AspectRatio, number> = {
  '9:16': 9 / 16,
  '16:9': 16 / 9,
  '1:1': 1,
  '4:5': 4 / 5,
};

interface CanvasPreviewProps {
  timelineState: TimelineState;
  currentTime: number;
  duration: number;
  onTimeUpdate: (time: number) => void;
  playing: boolean;
  setPlaying: (playing: boolean) => void;
  videoPath: string; // fallback or main video source
}

export const CanvasPreview: React.FC<CanvasPreviewProps> = ({
  timelineState,
  currentTime,
  duration: _duration,
  onTimeUpdate,
  playing,
  setPlaying,
  videoPath,
}) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const hiddenVideoRef = useRef<HTMLVideoElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const [muted, setMuted] = useState(false);
  const [activeScope, setActiveScope] = useState<'histogram' | 'waveform' | 'none'>('none');
  const [aspectRatio, setAspectRatio] = useState<AspectRatio>('9:16');
  const [fitMode, setFitMode] = useState<FitMode>('fit');
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [videoState, setVideoState] = useState<'idle' | 'loading' | 'ready' | 'error'>('idle');
  const [videoError, setVideoError] = useState<string>('');
  const requestRef = useRef<number | null>(null);

  // Keep refs updated to prevent re-triggering the rendering useEffect
  const timelineStateRef = useRef(timelineState);
  const currentTimeRef = useRef(currentTime);
  const playingRef = useRef(playing);
  const aspectRatioRef = useRef(aspectRatio);
  const fitModeRef = useRef(fitMode);

  useEffect(() => { timelineStateRef.current = timelineState; }, [timelineState]);
  useEffect(() => { currentTimeRef.current = currentTime; }, [currentTime]);
  useEffect(() => { playingRef.current = playing; }, [playing]);
  useEffect(() => { aspectRatioRef.current = aspectRatio; }, [aspectRatio]);
  useEffect(() => { fitModeRef.current = fitMode; }, [fitMode]);

  // Convert absolute local path to web-safe URL for preview (Tauri convertFileSrc or local dev server)
  const getWebUrl = (path: string) => {
    if (!path) return '';
    if (path.startsWith('http') || path.startsWith('blob:')) return path;
    // Always use backend video-stream endpoint. It handles byte ranges perfectly,
    // has no restrictive Tauri scope limitations for arbitrary folders, and bypasses
    // Tauri's strict asset protocol CSP which was blocking media-src.
    return `http://localhost:8000/api/video-stream?path=${encodeURIComponent(path)}`;
  };


  // Find active video clip at current timeline position
  const getActiveVideoClip = (): VideoClip | null => {
    const state = timelineStateRef.current;
    const time = currentTimeRef.current;
    for (const track of state.tracks.video) {
      for (const clip of track.clips) {
        if (time >= clip.start_time_in_timeline && time <= clip.end_time_in_timeline) {
          return clip;
        }
      }
    }
    return null;
  };

  // Find active subtitle
  const getActiveSubtitle = (): SubtitleClip | null => {
    const state = timelineStateRef.current;
    const time = currentTimeRef.current;
    for (const track of state.tracks.subtitles) {
      for (const clip of track.clips) {
        if (time >= clip.start_time && time <= clip.end_time) {
          return clip;
        }
      }
    }
    return null;
  };

  // Sync hidden video playback with playing state and currentTime
  useEffect(() => {
    const video = hiddenVideoRef.current;
    if (!video) return;

    if (playing) {
      // Sync time and play
      if (Math.abs(video.currentTime - currentTime) > 0.3) {
        video.currentTime = currentTime;
      }
      video.play().catch(() => {});
    } else {
      video.pause();
      video.currentTime = currentTime;
    }
  }, [playing]);

  // Sync seek events
  useEffect(() => {
    const video = hiddenVideoRef.current;
    if (!video || playing) return;
    video.currentTime = currentTime;
  }, [currentTime]);

  // Track video state when src changes
  useEffect(() => {
    if (!videoPath) {
      setVideoState('idle');
      setVideoError('');
      return;
    }
    setVideoState('loading');
    setVideoError('');
  }, [videoPath]);

  // Linear Interpolation helper for keyframes
  const interpolateKeyframe = (time: number, keyframes: any[], property: string, defaultValue: any) => {
    const filtered = keyframes.filter(k => k.property === property).sort((a, b) => a.time - b.time);
    if (filtered.length === 0) return defaultValue;
    if (time <= filtered[0].time) return filtered[0].value;
    if (time >= filtered[filtered.length - 1].time) return filtered[filtered.length - 1].value;

    for (let i = 0; i < filtered.length - 1; i++) {
      const kf1 = filtered[i];
      const kf2 = filtered[i + 1];
      if (time >= kf1.time && time <= kf2.time) {
        const ratio = (time - kf1.time) / (kf2.time - kf1.time);

        // Easing interpolation
        let t = ratio;
        if (kf1.easing === 'ease-in-out') {
          t = (1 - Math.cos(ratio * Math.PI)) / 2;
        } else if (kf1.easing === 'ease-in') {
          t = ratio * ratio;
        } else if (kf1.easing === 'ease-out') {
          t = ratio * (2 - ratio);
        }

        if (typeof defaultValue === 'object') {
          return {
            x: kf1.value.x + (kf2.value.x - kf1.value.x) * t,
            y: kf1.value.y + (kf2.value.y - kf1.value.y) * t
          };
        }
        return kf1.value + (kf2.value - kf1.value) * t;
      }
    }
    return defaultValue;
  };

  // Main Canvas Rendering Loop
  const renderFrame = () => {
    const canvas = canvasRef.current;
    const video = hiddenVideoRef.current;
    if (!canvas || !video) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const activeClip = getActiveVideoClip();

    // Clear screen
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = '#000000';
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    // Show video: either from active timeline clip, or fallback = raw video if loaded
    const canRenderVideo = video.readyState >= 2 && !video.error && video.videoWidth > 0;

    if (canRenderVideo) {
      ctx.save();

      if (activeClip) {
        // Get interpolated Transform attributes
        const clipTime = currentTimeRef.current - activeClip.start_time_in_timeline;
        const keyframes = activeClip.transform?.keyframes || [];

        const position = interpolateKeyframe(clipTime, keyframes, 'position', activeClip.transform?.position || { x: 0, y: 0 });
        const scale = interpolateKeyframe(clipTime, keyframes, 'scale', activeClip.transform?.scale || { x: 100, y: 100 });
        const rotation = interpolateKeyframe(clipTime, keyframes, 'rotation', activeClip.transform?.rotation || 0);

        // 1. Color Grading & Filters
        const grade = activeClip.color_grading;
        if (grade) {
          const liftVal = grade.lift || { r: 0, g: 0, b: 0 };
          const gammaVal = grade.gamma || { r: 1, g: 1, b: 1 };
          const gainVal = grade.gain || { r: 1, g: 1, b: 1 };
          const avgLift = (liftVal.r + liftVal.g + liftVal.b) / 3;
          const avgGamma = (gammaVal.r + gammaVal.g + gammaVal.b) / 3;
          const avgGain = (gainVal.r + gainVal.g + gainVal.b) / 3;
          const baseBrightness = 1 + (grade.brightness || 0);
          const baseContrast = grade.contrast || 1;
          const baseSaturation = grade.saturation || 1;
          const finalBrightness = baseBrightness * avgGain + avgLift;
          const finalContrast = baseContrast * (2 - avgGamma);
          const finalSaturation = baseSaturation;
          ctx.filter = `brightness(${finalBrightness}) contrast(${finalContrast}) saturate(${finalSaturation})`;
        }

        // 2. Transform Operations
        ctx.translate(canvas.width / 2 + position.x, canvas.height / 2 + position.y);
        ctx.rotate((rotation * Math.PI) / 180);

        const scaleX = scale.x / 100;
        const scaleY = scale.y / 100;

        // Source cropping
        const crop = (activeClip.transform as any)?.crop;
        let sx = 0, sy = 0, sw = video.videoWidth, sh = video.videoHeight;
        if (crop && typeof crop === 'object') {
          const left = (crop.left || 0) / 100;
          const right = (crop.right || 0) / 100;
          const top = (crop.top || 0) / 100;
          const bottom = (crop.bottom || 0) / 100;
          sx = video.videoWidth * left;
          sy = video.videoHeight * top;
          sw = video.videoWidth * (1 - left - right);
          sh = video.videoHeight * (1 - top - bottom);
          if (sw <= 0) sw = video.videoWidth;
          if (sh <= 0) sh = video.videoHeight;
        }

        const sourceRatio = sw / sh;
        let drawW = canvas.width;
        let drawH = canvas.width / sourceRatio;

        if (fitModeRef.current === 'fill') {
          // Fill: cover entire canvas (may crop)
          const canvasRatio = canvas.width / canvas.height;
          if (sourceRatio > canvasRatio) {
            drawH = canvas.height;
            drawW = canvas.height * sourceRatio;
          } else {
            drawW = canvas.width;
            drawH = canvas.width / sourceRatio;
          }
        } else {
          // Fit: contain (may letterbox)
          if (drawH < canvas.height) { drawH = canvas.height; drawW = canvas.height * sourceRatio; }
        }

        ctx.drawImage(
          video,
          sx, sy, sw, sh,
          -drawW / 2 * scaleX, -drawH / 2 * scaleY, drawW * scaleX, drawH * scaleY
        );
      } else {
        // ─── FALLBACK: No timeline clip — show raw video frame centered ───
        ctx.filter = 'none';
        if (video.videoWidth > 0 && video.videoHeight > 0) {
          const sourceRatio = video.videoWidth / video.videoHeight;
          let drawW = canvas.width;
          let drawH = canvas.width / sourceRatio;

          if (fitModeRef.current === 'fill') {
            const canvasRatio = canvas.width / canvas.height;
            if (sourceRatio > canvasRatio) {
              drawH = canvas.height;
              drawW = canvas.height * sourceRatio;
            } else {
              drawW = canvas.width;
              drawH = canvas.width / sourceRatio;
            }
          } else {
            if (drawH < canvas.height) { drawH = canvas.height; drawW = canvas.height * sourceRatio; }
          }
          ctx.translate(canvas.width / 2, canvas.height / 2);
          ctx.drawImage(video, -drawW / 2, -drawH / 2, drawW, drawH);
        }
      }

      ctx.restore();
      ctx.filter = 'none';
    }

    // 3. Render Subtitles on top
    const activeSub = getActiveSubtitle();
    if (activeSub) {
      ctx.save();
      const style = activeSub.style;
      ctx.font = `bold ${style.font_size || 40}px "${style.font_name || 'Arial'}"`;
      ctx.textAlign = 'center';
      ctx.lineWidth = style.stroke_width || 4;
      ctx.strokeStyle = style.stroke_color || '#000000';
      ctx.fillStyle = style.primary_color || '#FFFFFF';
      const xPos = canvas.width / 2;
      const yPos = style.alignment === 'center_top' ? 120 : style.alignment === 'center_middle' ? canvas.height / 2 : canvas.height - 150;
      ctx.strokeText(activeSub.text, xPos, yPos);
      ctx.fillText(activeSub.text, xPos, yPos);
      ctx.restore();
    }

    // Update parent current time in play state
    if (playingRef.current) {
      if (video.ended) {
        setPlaying(false);
        return;
      }
      onTimeUpdate(video.currentTime);
      requestRef.current = requestAnimationFrame(renderFrame);
    }
  };

  // Trigger render when playing state changes
  useEffect(() => {
    if (playing) {
      requestRef.current = requestAnimationFrame(renderFrame);
    } else {
      requestAnimationFrame(renderFrame);
    }
    return () => {
      if (requestRef.current) cancelAnimationFrame(requestRef.current);
    };
  }, [playing]);

  // Trigger a fresh render when videoPath changes (video selected or changed)
  useEffect(() => {
    if (!videoPath) return;
    // Small delay to let the video element update its src
    const timer = setTimeout(() => requestAnimationFrame(renderFrame), 100);
    return () => clearTimeout(timer);
  }, [videoPath]);

  // Trigger render when seeking while paused
  useEffect(() => {
    if (!playing) {
      requestAnimationFrame(renderFrame);
    }
  }, [currentTime]);

  // Trigger render when aspect ratio or fit mode changes (so canvas dimensions update visually)
  useEffect(() => {
    requestAnimationFrame(renderFrame);
  }, [aspectRatio, fitMode]);

  const togglePlay = () => {
    setPlaying(!playing);
  };

  // Fullscreen toggle
  const toggleFullscreen = useCallback(async () => {
    const el = containerRef.current;
    if (!el) return;

    try {
      if (!document.fullscreenElement) {
        await el.requestFullscreen();
        setIsFullscreen(true);
      } else {
        await document.exitFullscreen();
        setIsFullscreen(false);
      }
    } catch (err) {
      console.error('Fullscreen error:', err);
    }
  }, []);

  // Listen for fullscreen changes (e.g. user pressed Escape)
  useEffect(() => {
    const onChange = () => setIsFullscreen(!!document.fullscreenElement);
    document.addEventListener('fullscreenchange', onChange);
    return () => document.removeEventListener('fullscreenchange', onChange);
  }, []);

  // Compute canvas dimensions based on selected aspect ratio (for rendering quality)
  const targetRatio = ASPECT_RATIOS[aspectRatio];
  const baseW = 540;
  const baseH = Math.round(baseW / targetRatio);

  return (
    <div
      ref={containerRef}
      className="flex flex-col rounded-xl overflow-hidden flex-shrink-0 select-none shadow-2xl relative border"
      style={{
        background: 'var(--bg-surface-1)',
        borderColor: 'var(--border-subtle)',
        boxShadow: '0 20px 60px rgba(0,0,0,0.6)',
        height: '100%',
        maxHeight: '100%',
        width: isFullscreen ? '100%' : 'auto',
        maxWidth: '100%',
        minHeight: 0,
        minWidth: 0
      }}
    >
      {/* Hidden Video element for decoding */}
      <video
        ref={hiddenVideoRef}
        src={videoPath ? getWebUrl(videoPath) : undefined}
        crossOrigin="anonymous"
        className="hidden"
        muted={muted}
        playsInline
        preload="auto"
        onLoadStart={() => setVideoState('loading')}
        onLoadedData={() => {
          setVideoState('ready');
          setVideoError('');
          requestAnimationFrame(renderFrame);
        }}
        onError={() => {
          setVideoState('error');
          setVideoError('فشل تحميل الفيديو. تأكد من صحة المسار والصيغة.');
        }}
        onSeeked={() => { if (!playing) requestAnimationFrame(renderFrame); }}
      />


      {/* Render Canvas Area */}
      <div className="flex-1 bg-black flex items-center justify-center relative overflow-hidden min-h-0">
        <canvas
          ref={canvasRef}
          width={baseW}
          height={baseH}
          className="w-full h-full object-contain bg-black shadow-inner"
          style={{
            maxWidth: '100%',
            maxHeight: '100%',
            aspectRatio: `${aspectRatio.replace(':', '/')}`,
          }}
        />

        {/* Empty state - no video loaded */}
        {videoState === 'idle' && (
          <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 text-center px-6 pointer-events-none">
            <Film className="w-12 h-12" style={{ color: 'var(--text-tertiary)' }} />
            <div>
              <p className="text-sm font-semibold mb-1" style={{ color: 'var(--text-secondary)' }}>لا يوجد فيديو محمّل</p>
              <p className="text-xs" style={{ color: 'var(--text-tertiary)' }}>قم باستيراد فيديو من القائمة الجانبية لبدء المونتاج</p>
            </div>
          </div>
        )}

        {/* Loading state */}
        {videoState === 'loading' && (
          <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 pointer-events-none">
            <div className="w-8 h-8 border-2 border-t-transparent rounded-full animate-spin" style={{ borderColor: 'var(--accent)', borderTopColor: 'transparent' }} />
            <p className="text-xs" style={{ color: 'var(--text-tertiary)' }}>جاري تحميل الفيديو...</p>
          </div>
        )}

        {/* Error state */}
        {videoState === 'error' && (
          <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 text-center px-6">
            <AlertCircle className="w-10 h-10" style={{ color: '#ff453a' }} />
            <div>
              <p className="text-sm font-semibold mb-1" style={{ color: '#ff453a' }}>خطأ في تشغيل الفيديو</p>
              <p className="text-xs" style={{ color: 'var(--text-tertiary)' }}>{videoError}</p>
            </div>
          </div>
        )}
      </div>

      {/* Video Scopes Panel */}
      {activeScope !== 'none' && (
        <div className="px-3 py-1 border-t shrink-0" style={{ borderColor: 'var(--border-subtle)', background: '#0a0a0c' }}>
          <VideoScopes playerCanvasRef={canvasRef} activeScope={activeScope} playing={playing} />
        </div>
      )}

      {/* Player Controller Bar */}
      <div className="h-12 border-t flex items-center justify-between px-3 shrink-0 gap-2" style={{ background: 'var(--bg-surface-1)', borderColor: 'var(--border-subtle)' }}>
        {/* Play/Pause */}
        <button
          onClick={togglePlay}
          className="w-8 h-8 rounded-full flex items-center justify-center text-white transition-all cursor-pointer hover:opacity-90 active:scale-95 border-none flex-shrink-0"
          style={{ background: 'var(--accent)' }}
          title={playing ? 'إيقاف (Space)' : 'تشغيل (Space)'}
        >
          {playing ? <Pause className="w-4 h-4 fill-current" /> : <Play className="w-4 h-4 fill-current translate-x-0.5" />}
        </button>

        {/* Aspect Ratio Selector */}
        <div className="flex items-center gap-1 bg-[var(--bg-surface-3)] rounded-md p-0.5 border" style={{ borderColor: 'var(--border-subtle)' }}>
          {(['9:16', '16:9', '1:1', '4:5'] as AspectRatio[]).map((ratio) => (
            <button
              key={ratio}
              onClick={() => setAspectRatio(ratio)}
              className="px-1.5 py-0.5 rounded text-[10px] font-semibold transition-all cursor-pointer"
              style={{
                background: aspectRatio === ratio ? 'var(--accent)' : 'transparent',
                color: aspectRatio === ratio ? '#fff' : 'var(--text-secondary)',
              }}
              title={`أبعاد ${ratio}`}
            >
              {ratio}
            </button>
          ))}
        </div>

        {/* Fit/Fill Toggle */}
        <button
          onClick={() => setFitMode(prev => prev === 'fit' ? 'fill' : 'fit')}
          className="px-2 py-1 rounded text-[10px] font-semibold border transition-all cursor-pointer"
          style={{
            background: 'var(--bg-surface-3)',
            borderColor: 'var(--border-subtle)',
            color: 'var(--text-secondary)'
          }}
          title={fitMode === 'fit' ? 'وضع الاحتواء (Fit) - اضغط للملء' : 'وضع الملء (Fill) - اضغط للاحتواء'}
        >
          {fitMode === 'fit' ? '⤢ Fit' : '⛶ Fill'}
        </button>

        {/* Spacer */}
        <div className="flex-1" />

        {/* Scopes Toggle */}
        <button
          onClick={() => setActiveScope(prev => prev === 'none' ? 'histogram' : prev === 'histogram' ? 'waveform' : 'none')}
          className="px-2 py-1 rounded-md border text-[10px] font-semibold transition-all cursor-pointer select-none"
          style={{
            background: activeScope !== 'none' ? 'var(--accent-bg)' : 'transparent',
            borderColor: activeScope !== 'none' ? 'var(--accent)' : 'var(--border-subtle)',
            color: activeScope !== 'none' ? 'var(--accent)' : 'var(--text-secondary)'
          }}
          title="تبديل لوحة القياس البصرية"
        >
          {activeScope === 'none' ? 'Scopes' : activeScope === 'histogram' ? 'Histogram' : 'Waveform'}
        </button>

        {/* Timecode */}
        <span className="text-[11px] font-mono px-1" style={{ color: 'var(--text-secondary)' }}>
          {Math.floor(currentTime / 60).toString().padStart(2, '0')}:{(Math.floor(currentTime) % 60).toString().padStart(2, '0')}
        </span>

        {/* Mute */}
        <button
          onClick={() => setMuted(!muted)}
          className="w-7 h-7 rounded-full flex items-center justify-center transition-all cursor-pointer flex-shrink-0"
          style={{ color: 'var(--text-secondary)' }}
          onMouseEnter={(e) => {
            e.currentTarget.style.background = 'var(--bg-surface-3)';
            e.currentTarget.style.color = 'var(--text-primary)';
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.background = 'transparent';
            e.currentTarget.style.color = 'var(--text-secondary)';
          }}
          title={muted ? 'إلغاء الكتم' : 'كتم الصوت'}
        >
          {muted ? <VolumeX className="w-4 h-4" /> : <Volume2 className="w-4 h-4" />}
        </button>

        {/* Fullscreen */}
        <button
          onClick={toggleFullscreen}
          className="w-7 h-7 rounded-full flex items-center justify-center transition-all cursor-pointer flex-shrink-0"
          style={{ color: 'var(--text-secondary)' }}
          onMouseEnter={(e) => {
            e.currentTarget.style.background = 'var(--bg-surface-3)';
            e.currentTarget.style.color = 'var(--text-primary)';
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.background = 'transparent';
            e.currentTarget.style.color = 'var(--text-secondary)';
          }}
          title={isFullscreen ? 'إنهاء ملء الشاشة (Esc)' : 'ملء الشاشة (F)'}
        >
          {isFullscreen ? <Minimize2 className="w-4 h-4" /> : <Maximize2 className="w-4 h-4" />}
        </button>
      </div>
    </div>
  );
};

export default CanvasPreview;
