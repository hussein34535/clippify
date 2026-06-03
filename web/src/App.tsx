import { useState, useEffect } from 'react';
import { produce } from 'immer';
import axios from 'axios';
import Timeline from './components/Timeline/Timeline';
import CanvasPreview from './components/Player/CanvasPreview';
import InspectorPanel from './components/Inspector/InspectorPanel';
import Header from './components/Layout/Header';
import Footer from './components/Layout/Footer';
import MediaPool from './components/Library/MediaPool';
import TranscriptWords from './components/Player/TranscriptWords';
import SettingsModal from './components/Settings/SettingsModal';
import ExportModal from './components/Export/ExportModal';
import CopilotChat from './components/Inspector/CopilotChat';
import { useUndoRedo } from './hooks/useUndoRedo';
import { useToast } from './components/UI/Toast';
import type { Word, Clip, AppSettings, TimelineState, VideoClip, OverlayClip, SubtitleClip } from './types';

const API_BASE = 'http://localhost:8000';

export default function App() {
const loadSavedData = (key: string, defaultValue: any) => {
    try {
      const saved = localStorage.getItem('clipai_' + key);
      return saved ? JSON.parse(saved) : defaultValue;
    } catch (e) { return defaultValue; }
  };

  const { showToast } = useToast();
  const [videoPath, setVideoPath] = useState<string>(() => loadSavedData('videoPath', ''));
  const [mediaBin, setMediaBin] = useState<string[]>(() => loadSavedData('mediaBin', []));
  const [ytUrl, setYtUrl] = useState('');
  const [contentType, setContentType] = useState('podcast');
  const [loading, setLoading] = useState(false);
  const [statusMsg, setStatusMsg] = useState('');
  const [sessionProgress, setSessionProgress] = useState(0);
  const [activeSessionId, setActiveSessionId] = useState<string | null>(null);
  const [words, setWords] = useState<Word[]>(() => loadSavedData('words', []));
  const [clips, setClips] = useState<Clip[]>(() => loadSavedData('clips', []));
  const [activeClipIndex, setActiveClipIndex] = useState(0);
  const [duration, setDuration] = useState(0);
  const [currentTime, setCurrentTime] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [, setMimicProfile] = useState<any>(null);
  const [settings, setSettings] = useState<AppSettings>({
    n_clips: 5, duration: 60, subtitle_style: 'TikTok Yellow', font_name: 'Impact',
    export_quality: 'High', sfx_mode: 'normal', translate_to_arabic: false,
    auto_broll: false, gemma_multimodal: false, pexels_api_key: '', pixabay_api_key: '',
    output_dir: './output', export_mode: 'ffmpeg', whisper_model: 'tiny'
  });
  const [showSettings, setShowSettings] = useState(false);
  const [showExport, setShowExport] = useState(false);
  const [exportDefaultTab, setExportDefaultTab] = useState<'video' | 'xml'>('video');
  const [leftWidth, setLeftWidth] = useState(300);
  const [rightWidth, setRightWidth] = useState(300);
  const [bottomHeight, setBottomHeight] = useState(320);
  const [activeDrag, setActiveDrag] = useState<'left' | 'right' | 'bottom' | null>(null);
  const [rightPanelTab, setRightPanelTab] = useState<'inspector' | 'copilot'>('copilot');

  const [selectedClipId, setSelectedClipId] = useState<string | null>(null);
  const [selectedClipType, setSelectedClipType] = useState<'video' | 'audio' | 'overlay' | 'subtitle' | null>(null);

const initialTimeline: TimelineState = loadSavedData('timelineState', {
    project_id: '', project_name: 'ClipAI NLE Project',
    settings: { width: 1080, height: 1920, fps: 30, sample_rate: 44100, aspect_ratio: '9:16' },
    tracks: {
      video: [{ id: 'v_track_main', name: 'Main Video Track', index: 0, clips: [] }],
      audio: [{ id: 'a_track_music', name: 'Background Music Track', index: 0, clips: [] }],
      subtitles: [{ id: 'sub_track_main', clips: [] }],
      overlays: [{ id: 'overlay_track_main', clips: [] }]
    }
  });

  const { current: timelineState, push: pushTimeline, undo, redo, canUndo, canRedo } = useUndoRedo(initialTimeline);

  const setTimelineState = (next: TimelineState) => pushTimeline(next);

  useEffect(() => {
    const t = timelineState;
    const needsFix =
      !t.tracks?.video?.length ||
      !t.tracks?.audio?.length ||
      !t.tracks?.subtitles?.length ||
      !t.tracks?.overlays?.length;
    if (needsFix) {
      const fixed: TimelineState = {
        ...t,
        tracks: {
          video: t.tracks?.video?.length ? t.tracks.video : [{ id: 'v_track_main', name: 'Main Video Track', index: 0, clips: [] }],
          audio: t.tracks?.audio?.length ? t.tracks.audio : [{ id: 'a_track_music', name: 'Background Music Track', index: 0, clips: [] }],
          subtitles: t.tracks?.subtitles?.length ? t.tracks.subtitles : [{ id: 'sub_track_main', clips: [] }],
          overlays: t.tracks?.overlays?.length ? t.tracks.overlays : [{ id: 'overlay_track_main', clips: [] }]
        }
      };
      pushTimeline(fixed);
    }
  }, []);

  const seekTo = (seconds: number) => setCurrentTime(Math.max(0, Math.min(duration || 0, seconds)));

  const getSelectedClip = () => {
    if (!selectedClipId || !selectedClipType) return null;
    const trackKey = selectedClipType === 'subtitle' ? 'subtitles' : selectedClipType === 'overlay' ? 'overlays' : `${selectedClipType}s`;
    for (const track of (timelineState.tracks as any)[trackKey]) {
      const found = track.clips?.find((c: any) => c.id === selectedClipId);
      if (found) return found;
    }
    return null;
  };

  const initTimelineState = (path: string, clipsList: any[], wordList: Word[]): TimelineState => {
    const subClips: SubtitleClip[] = [];
    for (let i = 0; i < wordList.length; i += 5) {
      const chunk = wordList.slice(i, i + 5);
      if (!chunk.length) continue;
      subClips.push({
        id: `sub_${i}`, text: chunk.map(w => w.text).join(' '),
        start_time: chunk[0].start, end_time: chunk[chunk.length - 1].end,
        style: { font_name: settings.font_name || 'Impact', font_size: 48, primary_color: '#FFFFFF', stroke_color: '#000000', stroke_width: 2, animation: 'pop_in', alignment: 'center_bottom' }
      });
    }
    const vClips: VideoClip[] = clipsList.map((clip: any, idx: number) => ({
      id: `clip_v_${idx}`, source_path: path,
      start_time_in_timeline: clip.start_sec, end_time_in_timeline: clip.end_sec,
      source_trim_start: clip.start_sec, source_trim_end: clip.end_sec,
      speed: clip.slow_motion_speed || 1.0, volume: 1.0,
      transform: { position: { x: 0, y: 0 }, scale: { x: 100, y: 100 }, rotation: 0, keyframes: [] },
      color_grading: { brightness: 0, contrast: 1, saturation: 1, temperature: 6500, lut_path: '' },
      filters: [],
      ai_features: { face_tracking: false, bg_removed: false, bg_remove_method: 'none', chromakey_color: '#00FF00' }
    }));
    const oClips: OverlayClip[] = [];
    clipsList.forEach((clip: any, cIdx: number) => {
      (clip.planned_brolls || []).forEach((broll: any, bIdx: number) => {
        oClips.push({
          id: `broll_${cIdx}_${bIdx}`, type: 'broll', source_path: broll.video_path || broll.url || '',
          start_time_in_timeline: clip.start_sec + (broll.start_sec || 0),
          end_time_in_timeline: clip.start_sec + (broll.end_sec || 5),
          source_trim_start: 0, source_trim_end: (broll.end_sec || 5) - (broll.start_sec || 0),
          transform: { position: { x: 0, y: 0 }, scale: { x: 100, y: 100 }, rotation: 0, keyframes: [] }
        });
      });
    });
    return {
      project_id: `proj_${Date.now()}`, project_name: 'ClipAI NLE Project',
      settings: { width: 1080, height: 1920, fps: 30, sample_rate: 44100, aspect_ratio: '9:16' },
      tracks: {
        video: [{ id: 'v_track_main', name: 'Main Video Track', index: 0, clips: vClips }],
        audio: [{ id: 'a_track_music', name: 'Background Music Track', index: 0, clips: [] }],
        subtitles: [{ id: 'sub_track_main', clips: subClips }],
        overlays: [{ id: 'overlay_track_main', clips: oClips }]
      }
    };
  };

  
  useEffect(() => {
    try {
      localStorage.setItem('clipai_videoPath', JSON.stringify(videoPath));
      localStorage.setItem('clipai_mediaBin', JSON.stringify(mediaBin));
      localStorage.setItem('clipai_words', JSON.stringify(words));
      localStorage.setItem('clipai_clips', JSON.stringify(clips));
      localStorage.setItem('clipai_timelineState', JSON.stringify(timelineState));
    } catch (e) { console.error('Auto-save failed:', e); }
  }, [videoPath, mediaBin, words, clips, timelineState]);

  useEffect(() => {
    axios.get(`${API_BASE}/api/settings`).then(res => setSettings(res.data)).catch((e) => console.error(e));
  }, []);

  useEffect(() => {
    if (!activeSessionId) return;
    const interval = setInterval(() => {
      axios.get(`${API_BASE}/api/status?session_id=${activeSessionId}`).then(res => {
        const data = res.data;
        setSessionProgress(data.progress * 100);
        setStatusMsg(data.status);
        if (data.status === 'Done') {
          clearInterval(interval); setLoading(false); setActiveSessionId(null);
          
          if (data.results && Array.isArray(data.results)) {
            // It's a standard download or render result
            if (typeof data.results[0] === 'string') {
              setVideoPath(data.results[0]);
              setMediaBin(prev => prev.includes(data.results[0]) ? prev : [...prev, data.results[0]]);
            }
            showToast('اكتملت العملية بنجاح!', 'error');
          } else if (data.results && typeof data.results === 'object') {
            // It's an analyze result
            if (data.results.video_path) {
              setVideoPath(data.results.video_path);
              setMediaBin(prev => prev.includes(data.results.video_path) ? prev : [...prev, data.results.video_path]);
            }
            if (data.results.words) {
              setWords(data.results.words);
              setDuration(data.results.words[data.results.words.length - 1].end);
              generatePlan(data.results.video_path || videoPath, data.results.words);
            }
          }
        } else if (data.status === 'Failed') {
          clearInterval(interval); setLoading(false); setActiveSessionId(null);
          showToast(`خطأ: ${data.errors?.join(', ', 'error')}`);
        }
      }).catch((e) => console.error(e));
    }, 1000);
    return () => clearInterval(interval);
  }, [activeSessionId, videoPath]);

  useEffect(() => {
    if (!activeDrag) return;

    const handlePointerMove = (e: PointerEvent) => {
      if (activeDrag === 'left') {
        const newWidth = Math.max(180, Math.min(500, e.clientX));
        setLeftWidth(newWidth);
      } else if (activeDrag === 'right') {
        const newWidth = Math.max(240, Math.min(640, window.innerWidth - e.clientX));
        setRightWidth(newWidth);
      } else if (activeDrag === 'bottom') {
        const newHeight = Math.max(200, Math.min(500, window.innerHeight - e.clientY));
        setBottomHeight(newHeight);
      }
    };

    const handlePointerUp = () => {
      setActiveDrag(null);
    };

    window.addEventListener('pointermove', handlePointerMove);
    window.addEventListener('pointerup', handlePointerUp);
    return () => {
      window.removeEventListener('pointermove', handlePointerMove);
      window.removeEventListener('pointerup', handlePointerUp);
    };
  }, [activeDrag]);

  // Global keyboard shortcuts
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement;
      const tag = target.tagName?.toLowerCase();
      const isInput = tag === 'input' || tag === 'textarea' || tag === 'select' || target.isContentEditable;

      if (isInput) return;

      if (e.key === ' ' || e.code === 'Space') {
        e.preventDefault();
        setPlaying(prev => !prev);
      } else if ((e.key === 'Delete' || e.key === 'Backspace') && selectedClipId) {
        e.preventDefault();
        if (window.confirm('هل أنت متأكد من حذف هذا الكليب؟ يمكنك التراجع بـ Ctrl+Z.')) {
          const nextTimeline = produce(timelineState, (draft: any) => {
            draft.tracks.video.forEach((t: any) => { t.clips = t.clips.filter((c: any) => c.id !== selectedClipId); });
            draft.tracks.audio.forEach((t: any) => { t.clips = t.clips.filter((c: any) => c.id !== selectedClipId); });
            draft.tracks.overlays.forEach((t: any) => { t.clips = t.clips.filter((c: any) => c.id !== selectedClipId); });
            draft.tracks.subtitles.forEach((t: any) => { t.clips = t.clips.filter((c: any) => c.id !== selectedClipId); });
          });
          setTimelineState(nextTimeline);
          setSelectedClipId(null);
          setSelectedClipType(null);
        }
      } else if ((e.ctrlKey || e.metaKey) && e.key === 'z' && !e.shiftKey) {
        e.preventDefault();
        undo();
      } else if (((e.ctrlKey || e.metaKey) && e.key === 'y') || ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key === 'Z')) {
        e.preventDefault();
        redo();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [selectedClipId, selectedClipType, timelineState, undo, redo]);

  // Viewport-aware responsive sizing
  const [viewportSize, setViewportSize] = useState<{ w: number; h: number }>({ w: 0, h: 0 });
  useEffect(() => {
    const update = () => setViewportSize({ w: window.innerWidth, h: window.innerHeight });
    update();
    window.addEventListener('resize', update);
    return () => window.removeEventListener('resize', update);
  }, []);

  const isNarrow = viewportSize.w > 0 && viewportSize.w < 900;
  const isShort = viewportSize.h > 0 && viewportSize.h < 700;

  // Auto-fit panel sizes based on viewport
  useEffect(() => {
    if (viewportSize.w === 0) return;
    // Auto-scale left/right panels if they exceed viewport
    const totalHorizontal = leftWidth + rightWidth;
    if (totalHorizontal > viewportSize.w - 200) {
      const scale = (viewportSize.w - 200) / totalHorizontal;
      setLeftWidth(Math.max(220, Math.floor(leftWidth * scale)));
      setRightWidth(Math.max(240, Math.floor(rightWidth * scale)));
    }
    // Auto-scale bottom timeline if window is short
    if (isShort && bottomHeight > 280) {
      setBottomHeight(260);
    }
  }, [viewportSize]);

  const handleApplyActionPlan = (actions: any[]) => {
    // Filter out destructive actions and ask for confirmation
    const safeActions: any[] = [];
    const destructiveActions: any[] = [];

    actions.forEach(action => {
      if (action.type === 'delete_clip') {
        destructiveActions.push(action);
      } else {
        safeActions.push(action);
      }
    });

    if (destructiveActions.length > 0) {
      const ids = destructiveActions.map(a => a.clip_id).join(', ');
      const ok = window.confirm(
        `الذكاء الاصطناعي يطلب حذف ${destructiveActions.length} كليب(ات):\n${ids}\n\nهل تريد الموافقة على الحذف؟ (يمكنك التراجع بـ Ctrl+Z)`
      );
      if (!ok) {
        // Only apply non-destructive actions
        actions = safeActions;
      }
    }

    let timelineChanged = false;
    const nextTimeline = produce(timelineState, (draft: any) => {
      actions.forEach(action => {
        if (action.type === 'select_clips' && Array.isArray(action.clips) && action.clips.length > 0) {
          const fresh = initTimelineState(videoPath, action.clips, words);
          draft.project_id = fresh.project_id;
          draft.project_name = fresh.project_name;
          draft.settings = fresh.settings;
          draft.tracks = fresh.tracks;
          timelineChanged = true;
        }
        else if (action.type === 'delete_clip' && action.clip_id) {
          draft.tracks.video.forEach((t: any) => { t.clips = t.clips.filter((c: any) => c.id !== action.clip_id); });
          draft.tracks.audio.forEach((t: any) => { t.clips = t.clips.filter((c: any) => c.id !== action.clip_id); });
          draft.tracks.overlays.forEach((t: any) => { t.clips = t.clips.filter((c: any) => c.id !== action.clip_id); });
          draft.tracks.subtitles.forEach((t: any) => { t.clips = t.clips.filter((c: any) => c.id !== action.clip_id); });
          timelineChanged = true;
        }
        else if (action.type === 'update_clip' && action.clip_id && action.fields) {
          const updateInList = (clips: any[]) => {
            if (!clips) return;
            clips.forEach((c: any) => {
              if (c.id === action.clip_id) {
                if (action.fields.speed !== undefined) c.speed = action.fields.speed;
                if (action.fields.volume !== undefined) c.volume = action.fields.volume;
                if (action.fields.transform) c.transform = { ...c.transform, ...action.fields.transform };
                if (action.fields.color_grading) c.color_grading = { ...c.color_grading, ...action.fields.color_grading };
                if (action.fields.ai_features) c.ai_features = { ...c.ai_features, ...action.fields.ai_features };
              }
            });
          };
          draft.tracks.video.forEach((t: any) => updateInList(t.clips));
          draft.tracks.audio.forEach((t: any) => updateInList(t.clips));
          draft.tracks.overlays.forEach((t: any) => updateInList(t.clips));
          draft.tracks.subtitles.forEach((t: any) => updateInList(t.clips));
          timelineChanged = true;
        }
        else if (action.type === 'update_subtitle_style' && action.fields) {
          draft.tracks.subtitles.forEach((t: any) => {
            t.clips.forEach((c: any) => {
              c.style = { ...c.style, ...action.fields };
            });
          });
          timelineChanged = true;
        }
        else if (action.type === 'update_settings' && action.fields) {
          draft.settings = { ...draft.settings, ...action.fields };
          timelineChanged = true;
        }
      });
    });

    if (timelineChanged) {
      setTimelineState(nextTimeline);
    }
  };

  const handleDeleteWords = (selectedIndices: number[]) => {
    if (!selectedIndices.length || !words.length) return;

    const sortedIndices = [...selectedIndices].sort((a, b) => a - b);
    const segments: { start: number; end: number }[] = [];
    
    let currentSegment: { start: number; end: number } | null = null;
    for (let i = 0; i < sortedIndices.length; i++) {
      const idx = sortedIndices[i];
      const w = words[idx];
      
      if (!currentSegment) {
        currentSegment = { start: w.start, end: w.end };
      } else {
        const gap = w.start - currentSegment.end;
        if (gap < 1.5) {
          currentSegment.end = w.end;
        } else {
          segments.push(currentSegment);
          currentSegment = { start: w.start, end: w.end };
        }
      }
    }
    if (currentSegment) {
      segments.push(currentSegment);
    }

    segments.sort((a, b) => b.start - a.start);

    const nextTimeline = produce(timelineState, (draft: any) => {
      segments.forEach(({ start, end }) => {
        const durationToDelete = end - start;

        const rippleDeleteTrackClips = (trackClips: any[]) => {
          if (!trackClips) return [];
          const result: any[] = [];
          
          trackClips.forEach((clip: any) => {
            const clipStart = clip.start_time_in_timeline;
            const clipEnd = clip.end_time_in_timeline;

            if (clipEnd <= start) {
              result.push(clip);
            }
            else if (clipStart >= end) {
              result.push({
                ...clip,
                start_time_in_timeline: clipStart - durationToDelete,
                end_time_in_timeline: clipEnd - durationToDelete
              });
            }
            else {
              const overlapStart = Math.max(clipStart, start);
              const overlapEnd = Math.min(clipEnd, end);
              const overlapDur = overlapEnd - overlapStart;

              if (clipStart >= start && clipEnd <= end) {
                return;
              }
              
              if (clipStart < start && clipEnd > end) {
                result.push({
                  ...clip,
                  id: `${clip.id}_l_${Date.now()}`,
                  end_time_in_timeline: start,
                  source_trim_end: clip.source_trim_end - (clipEnd - start)
                });
                result.push({
                  ...clip,
                  id: `${clip.id}_r_${Date.now()}`,
                  start_time_in_timeline: start,
                  end_time_in_timeline: clipEnd - durationToDelete,
                  source_trim_start: clip.source_trim_start + (end - clipStart)
                });
              }
              else if (clipStart >= start && clipStart < end) {
                result.push({
                  ...clip,
                  start_time_in_timeline: start,
                  end_time_in_timeline: clipEnd - durationToDelete,
                  source_trim_start: clip.source_trim_start + overlapDur
                });
              }
              else if (clipEnd > start && clipEnd <= end) {
                result.push({
                  ...clip,
                  end_time_in_timeline: start,
                  source_trim_end: clip.source_trim_end - overlapDur
                });
              }
            }
          });
          return result;
        };

        draft.tracks.video.forEach((t: any) => { t.clips = rippleDeleteTrackClips(t.clips); });
        draft.tracks.audio.forEach((t: any) => { t.clips = rippleDeleteTrackClips(t.clips); });
        draft.tracks.overlays.forEach((t: any) => { t.clips = rippleDeleteTrackClips(t.clips); });
        
        const rippleDeleteSubtitles = (subs: any[]) => {
          if (!subs) return [];
          const result: any[] = [];
          subs.forEach((sub: any) => {
            if (sub.end_time <= start) {
              result.push(sub);
            } else if (sub.start_time >= end) {
              result.push({
                ...sub,
                start_time: sub.start_time - durationToDelete,
                end_time: sub.end_time - durationToDelete
              });
            } else {
              if (sub.start_time >= start && sub.end_time <= end) {
                return;
              }
              const newStart = sub.start_time < start ? sub.start_time : start;
              const newEnd = sub.end_time > end ? sub.end_time - durationToDelete : start;
              if (newEnd > newStart + 0.05) {
                result.push({
                  ...sub,
                  start_time: newStart,
                  end_time: newEnd
                });
              }
            }
          });
          return result;
        };

        draft.tracks.subtitles.forEach((t: any) => { t.clips = rippleDeleteSubtitles(t.clips); });
      });
    });

    // Build set of word timestamps to delete
    const deletedWordTimes = new Set(
      sortedIndices.map(idx => words[idx].start)
    );
    let tempWords = [...words];
    let totalDeletedDuration = 0;
    segments.forEach(({ start, end }) => {
      const dur = end - start;
      totalDeletedDuration += dur;
      tempWords = tempWords.map(w => {
        if (w.start >= end) {
          return { ...w, start: w.start - dur, end: w.end - dur };
        }
        return w;
      });
    });
    const finalWords = tempWords.filter(w => !deletedWordTimes.has(w.start));

    setTimelineState(nextTimeline);
    setWords(finalWords);
    setDuration(prev => Math.max(0, prev - totalDeletedDuration));
    seekTo(Math.max(0, currentTime - totalDeletedDuration));
  };

  const triggerYoutubeDownload = async () => {
    if (!ytUrl) return showToast('برجاء إدخال رابط يوتيوب', 'error');
    setLoading(true); setStatusMsg('جاري الاتصال بيوتيوب للتحميل...');
    try { const res = await axios.post(`${API_BASE}/api/download-youtube`, { url: ytUrl }); setActiveSessionId(res.data.session_id); } catch (err: any) { setLoading(false); showToast('فشل الاتصال: ' + err.message, 'error'); }
  };

  const analyzeLocalVideo = async () => {
    if (!videoPath) return showToast('برجاء إدخال مسار ملف الفيديو المحلي', 'error');
    setLoading(true); setStatusMsg('جاري فحص الفيديو وتحليله...');
    try { const res = await axios.post(`${API_BASE}/api/analyze-video`, { video_path: videoPath, content_type: contentType }); setActiveSessionId(res.data.session_id); } catch (err: any) { setLoading(false); showToast('فشل: ' + err.message, 'error'); }
  };

  const browseLocalFile = async () => {
    const tauri = (window as any).__TAURI__;
    if (tauri && tauri.dialog) {
      try {
        const selected = await tauri.dialog.open({
          filters: [{ name: 'Video Files', extensions: ['mp4', 'mov', 'avi', 'mkv', 'webm', 'flv'] }],
          multiple: false
        });
        if (selected && typeof selected === 'string') {
          setVideoPath(selected);
        }
      } catch (err: any) {
        showToast('فشل فتح الملف عبر Tauri: ' + err.message, 'error');
      }
    } else {
      try { 
        const res = await axios.post(`${API_BASE}/api/browse-file`); 
        if (res.data.file_paths && res.data.file_paths.length > 0) { 
          setMediaBin(prev => {
            const newBin = [...prev];
            res.data.file_paths.forEach((p: string) => {
               if(!newBin.includes(p)) newBin.push(p);
            });
            return newBin;
          });
          if (!videoPath) setVideoPath(res.data.file_paths[0]); 
        } 
      } catch (err: any) { showToast('فشل: ' + err.message, 'error'); }
    }
  };

  const generatePlan = async (path: string, wordList: Word[]) => {
    setStatusMsg('جاري توليد الخطة الزمنية بالذكاء الاصطناعي...');
    try {
      const res = await axios.post(`${API_BASE}/api/generate-plan`, { video_path: path, words: wordList, content_type: contentType, n_clips: settings.n_clips, duration_sec: settings.duration });
      setClips(res.data.clips); setActiveClipIndex(0);
      setTimelineState(initTimelineState(path, res.data.clips, wordList));
      setStatusMsg('');
    } catch (err: any) { showToast('فشل توليد الخطة: ' + err.message, 'error'); }
  };

  const saveSettings = async () => {
    try { await axios.post(`${API_BASE}/api/settings`, settings); setShowSettings(false); showToast('تم حفظ الإعدادات!', 'success'); } catch (err: any) { showToast('فشل: ' + err.message, 'error'); }
  };

  const handleAutoCut = async () => {
    if (!words.length) return showToast('يرجى تحليل الفيديو أولاً للحصول على الكلمات.', 'error');
    setLoading(true); setStatusMsg('جاري عزل الصمت بالذكاء الاصطناعي...');
    try {
      const res = await axios.post(`${API_BASE}/api/project/ai/autocut`, { video_path: videoPath, words: words });
      if (res.data.timeline) setTimelineState(res.data.timeline);
      setLoading(false);
    } catch (err: any) { setLoading(false); showToast('فشل: ' + err.message, 'error'); }
  };

  const handleAutoFrame = async () => {
    if (!selectedClipId || selectedClipType !== 'video') return showToast('برجاء تحديد كليب فيديو أولاً', 'error');
    setLoading(true); setStatusMsg('جاري تتبع الوجه وتوسيط الكادر...');
    try {
      const res = await axios.post(`${API_BASE}/api/project/ai/autoframing`, { timeline: timelineState, clip_id: selectedClipId });
      if (res.data.timeline) setTimelineState(res.data.timeline);
      setLoading(false);
    } catch (err: any) { setLoading(false); showToast('فشل تتبع الوجه: ' + err.message, 'error'); }
  };

  const handleSyncBeats = async () => {
    let audioPath = '';
    // find selected audio clip or first audio clip
    if (selectedClipId && selectedClipType === 'audio') {
      timelineState.tracks.audio.forEach(t => t.clips.forEach(c => { if (c.id === selectedClipId) audioPath = c.source_path; }));
    }
    if (!audioPath) {
      if (timelineState.tracks.audio.length > 0 && timelineState.tracks.audio[0].clips.length > 0) {
        audioPath = timelineState.tracks.audio[0].clips[0].source_path;
      }
    }
    if (!audioPath) return showToast('برجاء إضافة مقطع موسيقى أولاً لمزامنته', 'error');

    setLoading(true); setStatusMsg('جاري تحليل الإيقاع الموسيقي...');
    try {
      const res = await axios.post(`${API_BASE}/api/analyze-beats`, { audio_path: audioPath });
      const beats: number[] = res.data.beats;
      if (!beats || beats.length === 0) throw new Error('لم يتم العثور على إيقاع واضح');

      // Snap b-roll clips to nearest beats
      const nextTimeline = produce(timelineState, (draft: any) => {
        if (draft.tracks.video.length > 1) { // Apply to B-rolls (track index > 0)
          for (let i = 1; i < draft.tracks.video.length; i++) {
            draft.tracks.video[i].clips.forEach((clip: any) => {
              // Find nearest beat for start time
              const startBeat = beats.reduce((prev, curr) => Math.abs(curr - clip.start_time_in_timeline) < Math.abs(prev - clip.start_time_in_timeline) ? curr : prev);
              // Find next beat for end time
              const futureBeats = beats.filter(b => b > startBeat + 0.5); // at least 0.5s duration
              const endBeat = futureBeats.length > 0 ? futureBeats[0] : startBeat + 2.0;

              const dur = endBeat - startBeat;
              clip.start_time_in_timeline = startBeat;
              clip.end_time_in_timeline = endBeat;
              clip.source_trim_end = clip.source_trim_start + dur;
            });
          }
        }
      });
      
      setTimelineState(nextTimeline);
      showToast('تمت مزامنة اللقطات مع الموسيقى بنجاح!', 'success');
      setLoading(false);
    } catch (err: any) { setLoading(false); showToast('فشل المزامنة: ' + err.message, 'error'); }
  };
  const handleSave = async () => {
    const tauri = (window as any).__TAURI__;
    let filePath = '';
    
    if (tauri && tauri.dialog) {
      try {
        const selected = await tauri.dialog.save({
          defaultPath: timelineState.project_name || 'project',
          filters: [{ name: 'ClipAI Projects', extensions: ['clipai'] }]
        });
        if (selected && typeof selected === 'string') {
          filePath = selected;
        }
      } catch (err: any) {
        showToast('فشل اختيار مسار الحفظ عبر Tauri: ' + err.message, 'error');
        return;
      }
    } else {
      try {
        const browseRes = await axios.post(`${API_BASE}/api/project/browse-save`, null, {
          params: { default_name: timelineState.project_name || 'project' }
        });
        if (browseRes.data.status === 'success' && browseRes.data.file_path) {
          filePath = browseRes.data.file_path;
        }
      } catch (err: any) {
        showToast('فشل اختيار مسار الحفظ: ' + err.message, 'error');
        return;
      }
    }

    if (filePath) {
      try {
        const saveRes = await axios.post(`${API_BASE}/api/project/save`, {
          timeline: timelineState,
          output_path: filePath
        });
        if (saveRes.data.status === 'success') {
          showToast('تم حفظ المشروع بنجاح في: ' + filePath, 'success');
        }
      } catch (err: any) {
        showToast('فشل حفظ المشروع: ' + err.message, 'error');
      }
    }
  };

  const handleLoad = async () => {
    const tauri = (window as any).__TAURI__;
    let filePath = '';

    if (tauri && tauri.dialog) {
      try {
        const selected = await tauri.dialog.open({
          filters: [{ name: 'ClipAI Projects', extensions: ['clipai'] }],
          multiple: false
        });
        if (selected && typeof selected === 'string') {
          filePath = selected;
        }
      } catch (err: any) {
        showToast('فشل اختيار ملف المشروع عبر Tauri: ' + err.message, 'error');
        return;
      }
    } else {
      try {
        const browseRes = await axios.post(`${API_BASE}/api/project/browse-open`);
        if (browseRes.data.status === 'success' && browseRes.data.file_path) {
          filePath = browseRes.data.file_path;
        }
      } catch (err: any) {
        showToast('فشل اختيار ملف المشروع: ' + err.message, 'error');
        return;
      }
    }

    if (filePath) {
      try {
        const loadRes = await axios.get(`${API_BASE}/api/project/load`, {
          params: { path: filePath }
        });
        if (loadRes.data.status === 'success' && loadRes.data.timeline) {
          setTimelineState(loadRes.data.timeline);
          const videoClips = loadRes.data.timeline.tracks?.video?.[0]?.clips || [];
          if (videoClips.length > 0 && videoClips[0].source_path) {
            setVideoPath(videoClips[0].source_path);
          }
          showToast('تم تحميل المشروع بنجاح!', 'success');
        }
      } catch (err: any) {
        showToast('فشل تحميل المشروع: ' + err.message, 'error');
      }
    }
  };

  const handleDropMedia = async (trackId: string, trackType: 'video' | 'audio' | 'overlay' | 'subtitle', dropTime: number, dropData: any) => {
    if (dropData.type === 'clip_suggestion') {
      const suggestion = dropData.clip;
      const durationSec = suggestion.end_sec - suggestion.start_sec;
      
      if (trackType === 'video') {
        const newClip = {
          id: `clip_suggestion_${Date.now()}`,
          source_path: videoPath,
          start_time_in_timeline: dropTime,
          end_time_in_timeline: dropTime + durationSec,
          source_trim_start: suggestion.start_sec,
          source_trim_end: suggestion.end_sec,
          speed: 1.0,
          volume: 1.0,
          transform: { position: { x: 0, y: 0 }, scale: { x: 100, y: 100 }, rotation: 0, keyframes: [] },
          color_grading: { brightness: 0, contrast: 1.0, saturation: 1.0, temperature: 5600, lut_path: "" },
          ai_features: { face_tracking: false, bg_removed: false, bg_remove_method: "chromakey", chromakey_color: "#00FF00" }
        };
        
        const nextTimeline = produce(timelineState, (draft: any) => {
          let track = draft.tracks.video.find((t: any) => t.id === trackId);
          if (!track && draft.tracks.video.length > 0) {
            track = draft.tracks.video[0];
          }
          if (track) {
            track.clips.push(newClip);
          }
        });
        setTimelineState(nextTimeline);
      } else if (trackType === 'overlay') {
        const newClip = {
          id: `clip_suggestion_${Date.now()}`,
          type: 'broll',
          source_path: videoPath,
          start_time_in_timeline: dropTime,
          end_time_in_timeline: dropTime + durationSec,
          source_trim_start: suggestion.start_sec,
          source_trim_end: suggestion.end_sec,
          transform: { position: { x: 0, y: 0 }, scale: { x: 100, y: 100 }, rotation: 0, keyframes: [] }
        };
        
        const nextTimeline = produce(timelineState, (draft: any) => {
          let track = draft.tracks.overlays.find((t: any) => t.id === trackId);
          if (!track && draft.tracks.overlays.length > 0) {
            track = draft.tracks.overlays[0];
          }
          if (track) {
            track.clips.push(newClip);
          }
        });
        setTimelineState(nextTimeline);
      }
    } else if (dropData.type === 'raw_video') {
      if (trackType === 'video') {
        const durationSec = dropData.duration || 15.0; // Use actual duration from payload or fallback to 15s
        const newClip = {
          id: `raw_video_${Date.now()}`,
          source_path: dropData.path,
          start_time_in_timeline: dropTime,
          end_time_in_timeline: dropTime + durationSec,
          source_trim_start: 0,
          source_trim_end: durationSec,
          speed: 1.0,
          volume: 1.0,
          transform: { position: { x: 0, y: 0 }, scale: { x: 100, y: 100 }, rotation: 0, keyframes: [] },
          color_grading: { brightness: 0, contrast: 1.0, saturation: 1.0, temperature: 5600, lut_path: "" },
          ai_features: { face_tracking: false, bg_removed: false, bg_remove_method: "chromakey", chromakey_color: "#00FF00" }
        };
        const nextTimeline = produce(timelineState, (draft: any) => {
          let track = draft.tracks.video.find((t: any) => t.id === trackId);
          if (!track && draft.tracks.video.length > 0) track = draft.tracks.video[0];
          if (track) track.clips.push(newClip);
        });
        setTimelineState(nextTimeline);
      }

    } else if (dropData.type === 'broll_item') {
      const item = dropData.item;
      setLoading(true);
      setStatusMsg('جاري تحميل لقطة B-Roll وإضافتها للتايملاين...');
      try {
        const res = await axios.post(`${API_BASE}/api/broll/download`, {
          download_url: item.download_url,
          keyword: dropData.searchQuery || 'broll'
        });
        if (res.data.status === 'success' && res.data.video_path) {
          const durationSec = item.duration || 5;
          const newClip = {
            id: `broll_downloaded_${Date.now()}`,
            type: 'broll',
            source_path: res.data.video_path,
            start_time_in_timeline: dropTime,
            end_time_in_timeline: dropTime + durationSec,
            source_trim_start: 0,
            source_trim_end: durationSec,
            transform: { position: { x: 0, y: 0 }, scale: { x: 100, y: 100 }, rotation: 0, keyframes: [] }
          };
          
          const nextTimeline = produce(timelineState, (draft: any) => {
            let track = draft.tracks.overlays.find((t: any) => t.id === trackId);
            if (!track && draft.tracks.overlays.length > 0) {
              track = draft.tracks.overlays[0];
            }
            if (track) {
              track.clips.push(newClip);
            }
          });
          setTimelineState(nextTimeline);
        }
      } catch (err: any) {
        showToast('فشل تحميل B-roll: ' + err.message, 'error');
      } finally {
        setLoading(false);
        setStatusMsg('');
      }
    }
  };

  useEffect(() => {
    const interval = setInterval(async () => {
      // Only auto-save if we have a real project loaded
      if (timelineState && timelineState.project_id && timelineState.project_id.trim() !== '') {
        try {
          await axios.post(`${API_BASE}/api/project/save`, {
            timeline: timelineState
          });
          console.log('Auto-saved project.');
        } catch (err) {
          console.error('Auto-save failed:', err);
        }
      }
    }, 5 * 60 * 1000);
    return () => clearInterval(interval);
  }, [timelineState]);

  return (
    <div className={`w-full h-screen overflow-hidden flex flex-col selection:bg-blue-600 selection:text-white ${activeDrag ? 'resize-active ' + (activeDrag === 'bottom' ? 'resize-active-row' : 'resize-active-col') + ' no-transitions' : ''}`} style={{ background: 'var(--bg-base)', color: 'var(--text-primary)' }}>
      <Header contentType={contentType} setContentType={setContentType} showSettings={showSettings} setShowSettings={setShowSettings} onExport={() => { setExportDefaultTab('video'); setShowExport(true); }} onSave={handleSave} onLoad={handleLoad} />

      <div className="flex-1 flex overflow-hidden min-h-0 relative">
        <MediaPool
          ytUrl={ytUrl} setYtUrl={setYtUrl}
          videoPath={videoPath} setVideoPath={setVideoPath}
          mediaBin={mediaBin} setMediaBin={setMediaBin}
          loading={loading} triggerYoutubeDownload={triggerYoutubeDownload}
          analyzeLocalVideo={analyzeLocalVideo} browseLocalFile={browseLocalFile}
          clips={clips} activeClipIndex={activeClipIndex}
          setActiveClipIndex={setActiveClipIndex} seekTo={seekTo}
          setClips={setClips} setMimicProfile={setMimicProfile}
          width={leftWidth}
          timelineState={timelineState}
          onChange={setTimelineState}
          currentTime={currentTime}
          settings={settings}
        />

        <div onPointerDown={() => setActiveDrag('left')} className={`splitter-col ${activeDrag === 'left' ? 'active' : ''}`} />

        <section className="flex-1 flex flex-col min-h-0 overflow-hidden" style={{ background: 'var(--bg-base)' }}>
          <div className={`flex-1 flex items-center justify-center min-h-0 relative ${isNarrow ? 'p-2' : 'p-4 lg:p-6'}`}>
            <CanvasPreview timelineState={timelineState} currentTime={currentTime} duration={duration} onTimeUpdate={setCurrentTime} onTimeSeek={setCurrentTime} playing={playing} setPlaying={setPlaying} videoPath={videoPath} />
          </div>
          <TranscriptWords words={words} currentTime={currentTime} seekTo={seekTo} onDeleteWords={handleDeleteWords} />
        </section>

        <div onPointerDown={() => setActiveDrag('right')} className={`splitter-col ${activeDrag === 'right' ? 'active' : ''}`} />

        <aside style={{ width: rightWidth }} className="border-l border-[0.5px] border-[var(--border-subtle)] bg-[var(--bg-surface-1)] flex flex-col min-h-0 flex-shrink-0">
          <div className="flex border-b border-[0.5px] border-[var(--border-subtle)] bg-[var(--bg-surface-2)] shrink-0">
            <button
              onClick={() => setRightPanelTab('copilot')}
              style={{
                borderBottom: rightPanelTab === 'copilot' ? '2px solid var(--accent)' : '2px solid transparent',
                color: rightPanelTab === 'copilot' ? 'var(--text-primary)' : 'var(--text-secondary)'
              }}
              className="flex-1 py-2.5 text-sm font-semibold text-center transition-all cursor-pointer hover:text-white"
            >
              المساعد الذكي
            </button>
            <button
              onClick={() => setRightPanelTab('inspector')}
              style={{
                borderBottom: rightPanelTab === 'inspector' ? '2px solid var(--accent)' : '2px solid transparent',
                color: rightPanelTab === 'inspector' ? 'var(--text-primary)' : 'var(--text-secondary)'
              }}
              className="flex-1 py-2.5 text-sm font-semibold text-center transition-all cursor-pointer hover:text-white"
            >
              الخصائص
            </button>
          </div>

          <div className="flex-1 overflow-y-auto min-h-0">
            {rightPanelTab === 'copilot' ? (
              <CopilotChat
                timelineState={timelineState}
                words={words}
                onApplyActionPlan={handleApplyActionPlan}
                API_BASE={API_BASE}
              />
            ) : (
              <div className="p-4 h-full flex flex-col gap-4">
                <InspectorPanel selectedClip={getSelectedClip()} clipType={selectedClipType} onUpdateClip={(updatedClip) => {
                   const nextTimeline = produce(timelineState, (draft: any) => {
                     const updateInList = (list: any[]) => {
                       if (!list) return;
                       const idx = list.findIndex((c: any) => c.id === updatedClip.id);
                       if (idx !== -1) {
                         list[idx] = updatedClip;
                       }
                     };
                     if (selectedClipType === 'video') draft.tracks.video.forEach((t: any) => updateInList(t.clips));
                     else if (selectedClipType === 'audio') draft.tracks.audio.forEach((t: any) => updateInList(t.clips));
                     else if (selectedClipType === 'overlay') draft.tracks.overlays.forEach((t: any) => updateInList(t.clips));
                     else if (selectedClipType === 'subtitle') draft.tracks.subtitles.forEach((t: any) => updateInList(t.clips));
                   });
                   setTimelineState(nextTimeline);
                 }} />
              </div>
            )}
          </div>
        </aside>
      </div>

      <div onPointerDown={() => setActiveDrag('bottom')} className={`splitter-row ${activeDrag === 'bottom' ? 'active' : ''}`} />

      <div style={{ height: bottomHeight }} className="border-t border-[0.5px] border-[var(--border-subtle)] bg-[var(--bg-base)] flex flex-col flex-shrink-0 z-30 overflow-hidden">
        <div className="flex-1 overflow-hidden min-h-0 flex flex-col">
          <Timeline
            timelineState={timelineState} onChange={setTimelineState}
            currentTime={currentTime} duration={duration} onTimeSeek={setCurrentTime}
            selectedClipId={selectedClipId}
            onSelectClip={(id, type) => { setSelectedClipId(id); setSelectedClipType(type); }}
            onAutoCut={handleAutoCut} onAutoFrame={handleAutoFrame} onSyncBeats={handleSyncBeats}
            loading={loading}
            canUndo={canUndo} canRedo={canRedo} onUndo={undo} onRedo={redo}
            clips={clips} activeClipIndex={activeClipIndex} setClips={setClips}
            onDropMedia={handleDropMedia}
          />
        </div>
      </div>

      <Footer loading={loading} statusMsg={statusMsg} sessionProgress={sessionProgress} onExportClick={(tab) => { setExportDefaultTab(tab); setShowExport(true); }} />

      {showSettings && <SettingsModal settings={settings} setSettings={setSettings} onSave={saveSettings} onClose={() => setShowSettings(false)} />}
      {showExport && <ExportModal timelineState={timelineState} settings={settings} API_BASE={API_BASE} onClose={() => setShowExport(false)} setLoading={setLoading} setStatusMsg={setStatusMsg} defaultTab={exportDefaultTab} />}
    </div>
  );
}
