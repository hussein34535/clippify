// ClipItem.tsx
// Component for individual clips on a track lane, with support for dragging & trimming

import React, { useState, useEffect, useRef } from 'react';

interface ClipItemProps {
  clip: any;
  clipType: 'video' | 'audio' | 'overlay' | 'subtitle';
  zoomLevel: number;
  isSelected: boolean;
  onSelect: () => void;
  onUpdate: (updatedClip: any) => void;
}

export const ClipItem: React.FC<ClipItemProps> = ({
  clip,
  clipType,
  zoomLevel,
  isSelected,
  onSelect,
  onUpdate,
}) => {
  const start = clipType === 'subtitle' ? clip.start_time : clip.start_time_in_timeline;
  const end = clipType === 'subtitle' ? clip.end_time : clip.end_time_in_timeline;

  const [localStart, setLocalStart] = useState(start);
  const [localEnd, setLocalEnd] = useState(end);
  const [isDragging, setIsDragging] = useState(false);
  const [isResizingLeft, setIsResizingLeft] = useState(false);
  const [isResizingRight, setIsResizingRight] = useState(false);
  const startX = useRef(0);
  const startLeft = useRef(0);
  const startWidth = useRef(0);
  const localClipRef = useRef(clip);

  // Sync with prop updates when clip changes externally
  useEffect(() => {
    setLocalStart(start);
    setLocalEnd(end);
    localClipRef.current = clip;
  }, [start, end, clip]);

  const duration = localEnd - localStart;

  // Convert timeline bounds to CSS pixel styles (local state for immediate smooth rendering)
  const leftPx = localStart * zoomLevel;
  const widthPx = duration * zoomLevel;

  const handleMouseDown = (e: React.MouseEvent, action: 'drag' | 'resize-left' | 'resize-right') => {
    e.stopPropagation();
    onSelect(); // select clip on click
    
    startX.current = e.clientX;
    startLeft.current = leftPx;
    startWidth.current = widthPx;
    localClipRef.current = clip;

    if (action === 'drag') setIsDragging(true);
    else if (action === 'resize-left') setIsResizingLeft(true);
    else if (action === 'resize-right') setIsResizingRight(true);
  };

  useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      const deltaX = e.clientX - startX.current;
      const snap = (val: number) => Math.round(val * 10) / 10;

      if (isDragging) {
        const newLeft = Math.max(0, startLeft.current + deltaX);
        const rawStart = newLeft / zoomLevel;
        const snappedStart = snap(rawStart);
        const snappedEnd = snap(snappedStart + (end - start)); // keep original duration during drag

        if (snappedStart !== localStart) {
          setLocalStart(snappedStart);
          setLocalEnd(snappedEnd);

          const updated = { ...localClipRef.current };
          if (clipType === 'subtitle') {
            updated.start_time = snappedStart;
            updated.end_time = snappedEnd;
          } else {
            updated.start_time_in_timeline = snappedStart;
            updated.end_time_in_timeline = snappedEnd;
          }
          localClipRef.current = updated;
        }
      }

      if (isResizingLeft) {
        const newLeft = Math.max(0, Math.min(startLeft.current + startWidth.current - 10, startLeft.current + deltaX));
        const rawStart = newLeft / zoomLevel;
        const snappedStart = snap(rawStart);
        const deltaSec = snappedStart - start;

        if (snappedStart !== localStart) {
          setLocalStart(snappedStart);
          
          const updated = { ...localClipRef.current };
          if (clipType === 'subtitle') {
            updated.start_time = snappedStart;
          } else {
            updated.start_time_in_timeline = snappedStart;
            updated.source_trim_start = Math.max(0, snap((clip.source_trim_start || 0) + deltaSec));
          }
          localClipRef.current = updated;
        }
      }

      if (isResizingRight) {
        const newWidth = Math.max(10, startWidth.current + deltaX);
        const rawEnd = (startLeft.current + newWidth) / zoomLevel;
        const snappedEnd = snap(rawEnd);
        const deltaSec = snappedEnd - end;

        if (snappedEnd !== localEnd) {
          setLocalEnd(snappedEnd);

          const updated = { ...localClipRef.current };
          if (clipType === 'subtitle') {
            updated.end_time = snappedEnd;
          } else {
            updated.end_time_in_timeline = snappedEnd;
            updated.source_trim_end = snap((clip.source_trim_end || clip.end_time_in_timeline) + deltaSec);
          }
          localClipRef.current = updated;
        }
      }
    };

    const handleMouseUp = () => {
      setIsDragging(false);
      setIsResizingLeft(false);
      setIsResizingRight(false);
      // Fire single update to parent state on drag finish
      onUpdate(localClipRef.current);
    };

    if (isDragging || isResizingLeft || isResizingRight) {
      window.addEventListener('mousemove', handleMouseMove);
      window.addEventListener('mouseup', handleMouseUp);
    }

    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isDragging, isResizingLeft, isResizingRight, start, end, localStart, localEnd, zoomLevel, clip, clipType, onUpdate]);

  const getClipTitle = () => {
    if (clipType === 'subtitle') return clip.text;
    const path = clip.source_path || '';
    return path.substring(path.lastIndexOf('/') + 1) || 'Clip';
  };

  const getClipStyle = (): React.CSSProperties => {
    let background = 'transparent';
    let borderColor = 'transparent';
    let color = 'var(--text-primary)';
    
    if (isSelected) {
      switch (clipType) {
        case 'video':
          background = 'rgba(10, 132, 255, 0.28)';
          borderColor = 'rgba(10, 132, 255, 0.85)';
          break;
        case 'overlay':
          background = 'rgba(125, 122, 255, 0.28)';
          borderColor = 'rgba(125, 122, 255, 0.85)';
          break;
        case 'subtitle':
          background = 'rgba(48, 209, 88, 0.25)';
          borderColor = 'rgba(48, 209, 88, 0.85)';
          break;
        case 'audio':
          background = 'rgba(255, 159, 10, 0.25)';
          borderColor = 'rgba(255, 159, 10, 0.85)';
          break;
      }
    } else {
      switch (clipType) {
        case 'video':
          background = 'rgba(10, 132, 255, 0.14)';
          borderColor = 'rgba(10, 132, 255, 0.35)';
          color = 'rgba(10, 132, 255, 0.9)';
          break;
        case 'overlay':
          background = 'rgba(125, 122, 255, 0.14)';
          borderColor = 'rgba(125, 122, 255, 0.35)';
          color = 'rgba(125, 122, 255, 0.9)';
          break;
        case 'subtitle':
          background = 'rgba(48, 209, 88, 0.12)';
          borderColor = 'rgba(48, 209, 88, 0.3)';
          color = 'rgba(48, 209, 88, 0.9)';
          break;
        case 'audio':
          background = 'rgba(255, 159, 10, 0.12)';
          borderColor = 'rgba(255, 159, 10, 0.3)';
          color = 'rgba(255, 159, 10, 0.9)';
          break;
      }
    }
    
    return {
      background,
      borderColor,
      color,
      left: `${leftPx}px`,
      width: `${widthPx}px`,
      borderRadius: '6px',
      borderWidth: '1px',
      borderStyle: 'solid',
      boxShadow: 'none',
      outline: isSelected ? `1px solid ${borderColor}` : 'none',
      outlineOffset: isSelected ? '1px' : '0',
    };
  };

  return (
    <div
      onMouseDown={(e) => handleMouseDown(e, 'drag')}
      className="absolute top-1 bottom-1 flex items-center justify-between px-2 cursor-grab active:cursor-grabbing overflow-hidden transition-shadow select-none"
      style={getClipStyle()}
    >
      {/* Left Trim Handle */}
      <div
        onMouseDown={(e) => handleMouseDown(e, 'resize-left')}
        className="absolute left-0 top-0 bottom-0 w-1 bg-black/25 hover:bg-white/20 cursor-ew-resize transition-colors"
      />

      {/* Clip Content Label */}
      <span className="text-[10px] font-medium truncate pointer-events-none w-full text-center px-1">
        {getClipTitle()}
      </span>

      {/* Right Trim Handle */}
      <div
        onMouseDown={(e) => handleMouseDown(e, 'resize-right')}
        className="absolute right-0 top-0 bottom-0 w-1 bg-black/25 hover:bg-white/20 cursor-ew-resize transition-colors"
      />
    </div>
  );
};

export default ClipItem;
