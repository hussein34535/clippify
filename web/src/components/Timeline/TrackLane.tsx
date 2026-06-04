// TrackLane.tsx
// Component for individual track lanes in the timeline

import React, { useState } from 'react';
import { produce } from 'immer';
import type { TimelineState } from '../../types';
import ClipItem from './ClipItem.tsx';

interface TrackLaneProps {
  track: any;
  trackType: 'video' | 'audio' | 'overlay' | 'subtitle';
  zoomLevel: number;
  selectedClipId: string | null;
  onSelectClip: (clipId: string | null, clipType: 'video' | 'audio' | 'overlay' | 'subtitle') => void;
  timelineState: TimelineState;
  onChange: (newState: TimelineState) => void;
  onDropMedia?: (trackId: string, trackType: 'video' | 'audio' | 'overlay' | 'subtitle', dropTime: number, dropData: any) => void;
}

export const TrackLane: React.FC<TrackLaneProps> = ({
  track,
  trackType,
  zoomLevel,
  selectedClipId,
  onSelectClip,
  timelineState,
  onChange,
  onDropMedia,
}) => {
  const [isDragOver, setIsDragOver] = useState(false);

  const handleClipUpdate = (updatedClip: any) => {
    const nextTimeline = produce(timelineState, (draft: any) => {
      const updateClips = (trackList: any[]) => {
        const t = trackList.find((x: any) => x.id === track.id);
        if (t && t.clips) {
          const idx = t.clips.findIndex((c: any) => c.id === updatedClip.id);
          if (idx !== -1) {
            t.clips[idx] = updatedClip;
          }
        }
      };

      if (trackType === 'video') {
        updateClips(draft.tracks.video);
      } else if (trackType === 'audio') {
        updateClips(draft.tracks.audio);
      } else if (trackType === 'overlay') {
        updateClips(draft.tracks.overlays);
      } else if (trackType === 'subtitle') {
        updateClips(draft.tracks.subtitles);
      }
    });

    onChange(nextTimeline);
  };
  const getTrackName = () => {
    switch (trackType) {
      case 'video': return track.name || 'Video Track';
      case 'overlay': return track.name || 'Overlay Track';
      case 'subtitle': return 'Subtitle Track';
      case 'audio': return track.name || 'Audio Track';
    }
  };

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (e.dataTransfer) {
      e.dataTransfer.dropEffect = 'copy';
    }
    if (!isDragOver) setIsDragOver(true);
  };

  const handleDragLeave = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragOver(false);
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragOver(false);
    if (!onDropMedia) return;

    const rect = e.currentTarget.getBoundingClientRect();
    const relativeX = Math.max(0, e.clientX - rect.left - 100);
    const dropTime = Math.max(0, relativeX / zoomLevel);

    const files = e.dataTransfer?.files;
    if (files && files.length > 0) {
      const file = files[0];
      const filePath: string =
        (file as unknown as { path?: string }).path ||
        (file as unknown as { webkitRelativePath?: string }).webkitRelativePath ||
        file.name;
      onDropMedia(track.id, trackType, dropTime, {
        type: 'raw_video',
        path: filePath,
        name: file.name,
        duration: 15.0,
      });
      return;
    }

    const dropDataStr = e.dataTransfer.getData('text/plain');
    if (!dropDataStr) return;
    try {
      const dropData = JSON.parse(dropDataStr);
      onDropMedia(track.id, trackType, dropTime, dropData);
    } catch (err) {
      console.error("Failed to parse drop data", err);
    }
  };

  return (
    <div
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
      className={`flex h-[42px] border-2 border-dashed rounded-[7px] relative mb-1.5 items-center flex-shrink-0 transition-all ${isDragOver ? 'border-[var(--accent)] bg-[var(--accent-bg)]' : 'border-transparent'}`}
      style={{
        background: isDragOver ? 'var(--accent-bg)' : 'transparent',
        boxShadow: isDragOver ? '0 0 0 2px var(--accent) inset, 0 0 12px rgba(10,132,255,0.4)' : 'none',
      }}
    >
      {/* Track Label Panel */}
      <div 
        className="w-[100px] h-full flex flex-col justify-center px-2 select-none z-10 sticky left-0 border-r"
        style={{ background: 'var(--bg-surface-2)', borderColor: 'var(--border-subtle)' }}
      >
        <span className="text-[10px] font-semibold truncate" style={{ color: 'var(--text-primary)' }}>{getTrackName()}</span>
        <span className="text-[8px] uppercase tracking-wider font-semibold" style={{ color: 'var(--text-tertiary)' }}>
          {trackType === 'overlay' ? 'تراكب' : trackType === 'subtitle' ? 'ترجمة' : trackType === 'video' ? 'فيديو' : 'صوت'}
        </span>
      </div>

      {/* Clips Area */}
      <div className="flex-1 h-full relative overflow-visible">
        {track.clips.map((clip: any) => (
          <ClipItem
            key={clip.id}
            clip={clip}
            clipType={trackType}
            zoomLevel={zoomLevel}
            isSelected={selectedClipId === clip.id}
            onSelect={() => onSelectClip(clip.id, trackType)}
            onUpdate={handleClipUpdate}
          />
        ))}
      </div>
    </div>
  );
};

export default TrackLane;
