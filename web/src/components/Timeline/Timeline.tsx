// Timeline.tsx
// Main Timeline component for ClipAI Pro NLE

import React, { useState, useRef, useEffect } from 'react';
import { produce } from 'immer';
import { Scissors, Trash2, ZoomIn, ZoomOut, Sparkles, Undo2, Redo2, Music } from 'lucide-react';
import type { TimelineState, VideoClip, OverlayClip, Clip } from '../../types';
import TrackLane from './TrackLane.tsx';

interface TimelineProps {
  timelineState: TimelineState;
  onChange: (newState: TimelineState) => void;
  currentTime: number;
  duration: number;
  onTimeSeek: (time: number) => void;
  selectedClipId: string | null;
  onSelectClip: (clipId: string | null, clipType: 'video' | 'audio' | 'overlay' | 'subtitle') => void;
  onAutoCut?: () => void;
  onAutoFrame?: () => void;
  onSyncBeats?: () => void;
  loading?: boolean;
  canUndo?: boolean;
  canRedo?: boolean;
  onUndo?: () => void;
  onRedo?: () => void;
  clips?: Clip[];
  activeClipIndex?: number;
  setClips?: (c: Clip[]) => void;
  onDropMedia?: (trackId: string, trackType: 'video' | 'audio' | 'overlay' | 'subtitle', dropTime: number, dropData: any) => void;
}

export const Timeline: React.FC<TimelineProps> = ({
  timelineState,
  onChange,
  currentTime,
  duration,
  onTimeSeek,
  selectedClipId,
  onSelectClip,
  onAutoCut,
  onAutoFrame,
  onSyncBeats,
  loading,
  canUndo,
  canRedo,
  onUndo,
  onRedo,
  clips,
  activeClipIndex,
  setClips,
  onDropMedia,
}) => {
  const [zoomLevel, setZoomLevel] = useState<number>(30); // pixels per second
  const [isScrubbing, setIsScrubbing] = useState<boolean>(false);
  const timelineRulerRef = useRef<HTMLDivElement>(null);
  const scrollContainerRef = useRef<HTMLDivElement>(null);

  // Format time (MM:SS:FF or MM:SS.ms)
  const formatTimecode = (secs: number) => {
    const m = Math.floor(secs / 60);
    const s = Math.floor(secs % 60);
    const f = Math.floor((secs % 1) * 30); // 30 FPS representation
    return `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}:${f.toString().padStart(2, '0')}`;
  };

  // Convert client X to timeline seconds
  const getSecondsFromX = (clientX: number): number => {
    if (!timelineRulerRef.current) return 0;
    const rect = timelineRulerRef.current.getBoundingClientRect();
    const scrollLeft = scrollContainerRef.current ? scrollContainerRef.current.scrollLeft : 0;
    const x = clientX - rect.left + scrollLeft - 100;
    return Math.max(0, Math.min(duration, x / zoomLevel));
  };

  const handleMouseDown = (e: React.MouseEvent) => {
    setIsScrubbing(true);
    const sec = getSecondsFromX(e.clientX);
    onTimeSeek(sec);
  };

  useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      if (!isScrubbing) return;
      const sec = getSecondsFromX(e.clientX);
      onTimeSeek(sec);
    };

    const handleMouseUp = () => {
      if (isScrubbing) setIsScrubbing(false);
    };

    if (isScrubbing) {
      window.addEventListener('mousemove', handleMouseMove);
      window.addEventListener('mouseup', handleMouseUp);
    }

    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isScrubbing, duration, zoomLevel]);

  // Split the selected clip or the clip under the playhead
  const handleSplit = () => {
    const time = currentTime;
    let clipSplitPerformed = false;

    const nextTimeline = produce(timelineState, (draft: any) => {
      // 1. Search in video tracks
      draft.tracks.video.forEach((track: any) => {
        const newClips: VideoClip[] = [];
        track.clips.forEach((clip: VideoClip) => {
          if (time > clip.start_time_in_timeline && time < clip.end_time_in_timeline) {
            // Splitting point relative to clip's source timeline
            const splitOffset = time - clip.start_time_in_timeline;
            
            // First Half
            const clip1: VideoClip = {
              ...clip,
              id: `${clip.id}_split_${Date.now()}_1`,
              end_time_in_timeline: time,
              source_trim_end: clip.source_trim_start + splitOffset
            };

            // Second Half
            const clip2: VideoClip = {
              ...clip,
              id: `${clip.id}_split_${Date.now()}_2`,
              start_time_in_timeline: time,
              source_trim_start: clip.source_trim_start + splitOffset
            };

            newClips.push(clip1, clip2);
            clipSplitPerformed = true;
          } else {
            newClips.push(clip);
          }
        });
        track.clips = newClips;
      });

      // 2. Search in overlays
      if (draft.tracks.overlays) {
        draft.tracks.overlays.forEach((track: any) => {
          const newClips: OverlayClip[] = [];
          track.clips.forEach((clip: OverlayClip) => {
            if (time > clip.start_time_in_timeline && time < clip.end_time_in_timeline) {
              const splitOffset = time - clip.start_time_in_timeline;
              const clip1: OverlayClip = {
                ...clip,
                id: `${clip.id}_split_${Date.now()}_1`,
                end_time_in_timeline: time,
                source_trim_end: clip.source_trim_start + splitOffset
              };
              const clip2: OverlayClip = {
                ...clip,
                id: `${clip.id}_split_${Date.now()}_2`,
                start_time_in_timeline: time,
                source_trim_start: clip.source_trim_start + splitOffset
              };
              newClips.push(clip1, clip2);
              clipSplitPerformed = true;
            } else {
              newClips.push(clip);
            }
          });
          track.clips = newClips;
        });
      }
    });

    if (clipSplitPerformed) {
      onChange(nextTimeline);
    }
  };

  // Delete selected clip
  const handleDelete = () => {
    if (!selectedClipId) return;
    if (!window.confirm('هل أنت متأكد من حذف هذا الكليب؟ يمكنك التراجع بـ Ctrl+Z.')) return;
    const nextTimeline = produce(timelineState, (draft: any) => {
      draft.tracks.video.forEach((t: any) => { t.clips = t.clips.filter((c: any) => c.id !== selectedClipId); });
      draft.tracks.audio.forEach((t: any) => { t.clips = t.clips.filter((c: any) => c.id !== selectedClipId); });
      draft.tracks.overlays.forEach((t: any) => { t.clips = t.clips.filter((c: any) => c.id !== selectedClipId); });
      draft.tracks.subtitles.forEach((t: any) => { t.clips = t.clips.filter((c: any) => c.id !== selectedClipId); });
    });

    onChange(nextTimeline);
    onSelectClip(null, 'video');
  };

  // Render ticks on the timeline ruler
  const renderRulerTicks = () => {
    const ticks = [];
    const step = zoomLevel < 10 ? 10 : zoomLevel < 25 ? 5 : 1; // tick interval in seconds
    const totalDuration = duration || 30; // default duration

    for (let i = 0; i <= totalDuration; i += step) {
      ticks.push(
        <div 
          key={i} 
          className="absolute border-l h-2.5 text-[9px] pl-1 select-none pointer-events-none"
          style={{ left: `${i * zoomLevel + 100}px`, borderColor: 'var(--border-subtle)', color: 'var(--text-tertiary)' }}
        >
          {formatTimecode(i).split(':')[1]}:{formatTimecode(i).split(':')[2]}
        </div>
      );
    }
    return ticks;
  };

  return (
    <div className="flex flex-col h-full w-full select-none font-sans relative" style={{ background: 'var(--bg-base)' }}>
      {/* 🛠️ Timeline Toolbar */}
      <div className="flex items-center justify-between px-3.5 py-2 border-b h-11" style={{ background: 'var(--bg-surface-1)', borderColor: 'var(--border-subtle)' }}>
        <div className="flex items-center gap-1.5">
          <button onClick={handleSplit}
            style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-default)' }}
            className="w-7 h-7 rounded-[6px] border flex items-center justify-center transition-all cursor-pointer text-red-400"
            title="Split (C)"
          >
            <Scissors className="w-3.5 h-3.5" />
          </button>
          <button onClick={handleDelete} disabled={!selectedClipId}
            style={{ 
              background: selectedClipId ? 'var(--bg-surface-3)' : 'transparent',
              borderColor: selectedClipId ? 'var(--border-default)' : 'transparent',
              color: selectedClipId ? 'var(--accent-red)' : 'var(--text-tertiary)' 
            }}
            className="w-7 h-7 rounded-[6px] border flex items-center justify-center transition-all cursor-pointer disabled:cursor-not-allowed"
            title="Delete (Del)"
          >
            <Trash2 className="w-3.5 h-3.5" />
          </button>

          <div className="w-px h-4 mx-1" style={{ background: 'var(--border-subtle)' }} />

          <button onClick={onUndo} disabled={!canUndo}
            style={{ color: canUndo ? 'var(--text-primary)' : 'var(--text-tertiary)' }}
            className="w-7 h-7 rounded-full flex items-center justify-center transition-all hover:bg-[var(--bg-surface-3)] cursor-pointer disabled:cursor-not-allowed"
            title="Undo"
          >
            <Undo2 className="w-3.5 h-3.5" />
          </button>
          <button onClick={onRedo} disabled={!canRedo}
            style={{ color: canRedo ? 'var(--text-primary)' : 'var(--text-tertiary)' }}
            className="w-7 h-7 rounded-full flex items-center justify-center transition-all hover:bg-[var(--bg-surface-3)] cursor-pointer disabled:cursor-not-allowed"
            title="Redo"
          >
            <Redo2 className="w-3.5 h-3.5" />
          </button>

          <div className="w-px h-4 mx-1" style={{ background: 'var(--border-subtle)' }} />

          <button onClick={onAutoCut} disabled={loading || !selectedClipId}
            style={{
              background: !loading && selectedClipId ? 'var(--accent-bg)' : 'transparent',
              borderColor: !loading && selectedClipId ? 'rgba(10, 132, 255, 0.2)' : 'var(--border-subtle)',
              color: !loading && selectedClipId ? 'var(--accent)' : 'var(--text-tertiary)',
              borderWidth: '0.5px'
            }}
            className="px-2.5 py-1 rounded-[6px] text-[11px] flex items-center gap-1 transition-all cursor-pointer font-medium disabled:cursor-not-allowed"
            title="Auto-Cut Silences"
          >
            <Sparkles className="w-3 h-3" /> قص الصمت
          </button>
          <button onClick={onAutoFrame} disabled={loading || !selectedClipId}
            style={{
              background: !loading && selectedClipId ? 'rgba(125, 122, 255, 0.12)' : 'transparent',
              borderColor: !loading && selectedClipId ? 'rgba(125, 122, 255, 0.2)' : 'var(--border-subtle)',
              color: !loading && selectedClipId ? 'var(--accent-violet)' : 'var(--text-tertiary)',
              borderWidth: '0.5px'
            }}
            className="px-2.5 py-1 rounded-[6px] text-[11px] flex items-center gap-1 transition-all cursor-pointer font-medium disabled:cursor-not-allowed"
            title="AI Auto-Framing"
          >
            <Sparkles className="w-3 h-3" /> تتبع الكادر
          </button>
          
          <button onClick={onSyncBeats} disabled={loading || !selectedClipId}
            style={{
              background: !loading && selectedClipId ? 'rgba(52, 199, 89, 0.12)' : 'transparent',
              borderColor: !loading && selectedClipId ? 'rgba(52, 199, 89, 0.2)' : 'var(--border-subtle)',
              color: !loading && selectedClipId ? '#34c759' : 'var(--text-tertiary)',
              borderWidth: '0.5px'
            }}
            className="px-2.5 py-1 rounded-[6px] text-[11px] flex items-center gap-1 transition-all cursor-pointer font-medium disabled:cursor-not-allowed"
            title="Sync B-Rolls to Beats"
          >
            <Music className="w-3 h-3" /> مزامنة الإيقاع
          </button>

          {/* Hook selector for AI-generated clips */}
          {clips && clips.length > 0 && activeClipIndex !== undefined && activeClipIndex < clips.length && clips[activeClipIndex]?.hook_options?.length > 1 && (
            <>
              <div className="w-px h-4 mx-1" style={{ background: 'var(--border-subtle)' }} />
              <select
                value={clips[activeClipIndex].hook}
                onChange={(e) => {
                  const updated = [...clips];
                  updated[activeClipIndex].hook = e.target.value;
                  if (setClips) setClips(updated);
                }}
                style={{
                  background: 'var(--bg-surface-3)',
                  borderColor: 'var(--border-default)',
                  color: 'var(--text-primary)'
                }}
                className="border text-[11px] rounded-[6px] px-2 py-0.5 focus:outline-none cursor-pointer max-w-[160px]"
                title="Hook option"
              >
                {clips[activeClipIndex].hook_options.map((opt: string, i: number) => (
                  <option key={i} value={opt}>{opt}</option>
                ))}
              </select>
            </>
          )}
        </div>

        {/* Current Timecode Display */}
        <div className="text-[11px] font-mono px-2.5 py-1 rounded border" style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-default)', color: 'var(--accent)' }}>
          {formatTimecode(currentTime)} <span style={{ color: 'var(--text-tertiary)' }}>/ {formatTimecode(duration)}</span>
        </div>

        {/* Zoom Controls */}
        <div className="flex items-center gap-2">
          <button 
            onClick={() => setZoomLevel(prev => Math.max(5, prev - 5))}
            className="p-1 hover:bg-[var(--bg-surface-3)] rounded text-[var(--text-secondary)] hover:text-white transition-all cursor-pointer"
          >
            <ZoomOut className="w-3.5 h-3.5" />
          </button>
          <input 
            type="range" 
            min="5" 
            max="120" 
            value={zoomLevel} 
            onChange={(e) => setZoomLevel(Number(e.target.value))} 
            className="w-20 h-0.5 rounded-lg appearance-none cursor-pointer"
            style={{ accentColor: 'var(--accent)', background: 'var(--bg-surface-3)' }}
          />
          <button 
            onClick={() => setZoomLevel(prev => Math.min(120, prev + 5))}
            className="p-1 hover:bg-[var(--bg-surface-3)] rounded text-[var(--text-secondary)] hover:text-white transition-all cursor-pointer"
          >
            <ZoomIn className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>

      {/* 🚀 Main Track Lanes Container */}
      <div 
        ref={scrollContainerRef}
        className="flex-1 overflow-x-auto overflow-y-auto relative flex flex-col"
        style={{ background: 'var(--bg-base)' }}
      >
        {/* Timeline Ruler */}
        <div 
          ref={timelineRulerRef}
          onMouseDown={handleMouseDown}
          className="h-7 border-b sticky top-0 z-20 cursor-ew-resize relative select-none flex-shrink-0"
          style={{ width: `${(duration || 30) * zoomLevel + 100}px`, background: '#0d0d0d', borderColor: 'var(--border-subtle)' }}
        >
          {/* Ruler Left Spacer */}
          <div 
            className="absolute left-0 top-0 bottom-0 w-[100px] border-r z-30 sticky left-0"
            style={{ background: 'var(--bg-surface-2)', borderColor: 'var(--border-subtle)' }}
          />
          {renderRulerTicks()}
        </div>

        {/* Tracks Area */}
        <div 
          className="relative flex-1"
          style={{ width: `${(duration || 30) * zoomLevel + 100}px` }}
        >
          {/* Playhead Line */}
          <div 
            className="absolute top-0 bottom-0 w-[1px] z-10 pointer-events-none"
            style={{ left: `${currentTime * zoomLevel + 100}px`, background: 'var(--accent)' }}
          >
            <div 
              className="w-2.5 h-2.5 rotate-45 -translate-x-[4.5px] -translate-y-1 shadow-sm"
              style={{ background: 'var(--accent)' }}
            />
          </div>

          {/* Video Tracks */}
          <div className="flex flex-col gap-2 py-2.5">
            {timelineState.tracks.video.map((track) => (
              <TrackLane
                key={track.id}
                track={track}
                trackType="video"
                zoomLevel={zoomLevel}
                selectedClipId={selectedClipId}
                onSelectClip={onSelectClip}
                timelineState={timelineState}
                onChange={onChange}
                onDropMedia={onDropMedia}
              />
            ))}
          </div>

          {/* Audio Tracks (right under video for visibility) */}
          <div className="flex flex-col gap-2 py-2.5 border-t border-[0.5px]" style={{ borderColor: 'var(--border-subtle)' }}>
            <div className="flex items-center justify-between px-1">
              <span className="text-[9px] uppercase tracking-wider font-semibold" style={{ color: 'var(--text-tertiary)' }}>
                {timelineState.tracks.audio.length} تراك صوت
              </span>
              <span className="text-[9px] font-semibold flex items-center gap-1" style={{ color: '#34c759' }}>
                <Music className="w-3 h-3" /> موسيقى ومؤثرات
              </span>
            </div>
            {timelineState.tracks.audio.map((track) => (
              <TrackLane
                key={track.id}
                track={track}
                trackType="audio"
                zoomLevel={zoomLevel}
                selectedClipId={selectedClipId}
                onSelectClip={onSelectClip}
                timelineState={timelineState}
                onChange={onChange}
                onDropMedia={onDropMedia}
              />
            ))}
          </div>

          {/* Overlays Tracks */}
          <div className="flex flex-col gap-2 py-2.5 border-t border-[0.5px]" style={{ borderColor: 'var(--border-subtle)' }}>
            {timelineState.tracks.overlays.map((track) => (
              <TrackLane
                key={track.id}
                track={track}
                trackType="overlay"
                zoomLevel={zoomLevel}
                selectedClipId={selectedClipId}
                onSelectClip={onSelectClip}
                timelineState={timelineState}
                onChange={onChange}
                onDropMedia={onDropMedia}
              />
            ))}
          </div>

          {/* Subtitle Tracks */}
          <div className="flex flex-col gap-2 py-2.5 border-t border-[0.5px]" style={{ borderColor: 'var(--border-subtle)' }}>
            {timelineState.tracks.subtitles.map((track) => (
              <TrackLane
                key={track.id}
                track={track}
                trackType="subtitle"
                zoomLevel={zoomLevel}
                selectedClipId={selectedClipId}
                onSelectClip={onSelectClip}
                timelineState={timelineState}
                onChange={onChange}
                onDropMedia={onDropMedia}
              />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};

export default Timeline;
