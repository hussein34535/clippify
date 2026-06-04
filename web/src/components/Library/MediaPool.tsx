import { useState, useEffect } from 'react';
import { produce } from 'immer';
import { Upload, Video, Download, FolderOpen, Sparkles, Film, Layers, Wand2, Search, Plus, Music } from 'lucide-react';
import StyleMimicWorkspace from '../StyleMimicWorkspace';
import type { Clip } from '../../types';
import axios from 'axios';
import { API_BASE, streamUrl } from '../../api';
import { useStore } from '../../store';

const YoutubeIcon = () => (
  <svg className="w-3.5 h-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 fill-current" style={{ color: 'var(--accent-red)' }} viewBox="0 0 24 24">
    <path d="M23.498 6.163a3.003 3.003 0 0 0-2.11-2.11C19.518 3.5 12 3.5 12 3.5s-7.518 0-9.388.503a3.003 3.003 0 0 0-2.11 2.11C0 8.033 0 12 0 12s0 3.967.502 5.837a3.003 3.003 0 0 0 2.11 2.11c1.87.503 9.388.503 9.388.503s7.518 0 9.388-.503a3.003 3.003 0 0 0 2.11-2.11c.502-1.87.502-5.837.502-5.837s0-3.967-.502-5.837zM9.545 15.568V8.432L15.818 12l-6.273 3.568z"/>
  </svg>
);

interface MediaPoolProps {
  ytUrl: string;
  setYtUrl: (url: string) => void;
  setVideoPath: (path: string) => void;
  mediaBin?: string[];
  setMediaBin?: (bin: string[]) => void;
  loading: boolean;
  triggerYoutubeDownload: () => void;
  analyzeLocalVideo: () => void;
  browseLocalFile: () => void;
  clips: Clip[];
  activeClipIndex: number;
  setActiveClipIndex: (idx: number) => void;
  setClips: (clips: Clip[]) => void;
  setMimicProfile: (profile: any) => void;
  width?: number;
  timelineState: any;
  onChange: (newState: any) => void;
  settings?: any;
}

type Section = 'import' | 'clips' | 'broll' | 'mimic' | 'music';

export default function MediaPool({
  ytUrl, setYtUrl, setVideoPath, loading,
  mediaBin = [], setMediaBin: _setMediaBin,
  triggerYoutubeDownload, analyzeLocalVideo, browseLocalFile,
  clips = [], activeClipIndex = 0, setActiveClipIndex, setClips, setMimicProfile,
  width, timelineState, onChange, settings,
}: MediaPoolProps) {
  const [section, setSection] = useState<Section>('import');
  const videoPath = useStore((s) => s.videoPath);
  const currentTime = useStore((s) => s.currentTime);
  const seek = useStore((s) => s.seek);

  // B-Roll search states
  const [searchQuery, setSearchQuery] = useState('');
  const [searching, setSearching] = useState(false);
  const [searchEngine, setSearchEngine] = useState<'both' | 'pexels' | 'pixabay'>('both');
  const [brollResults, setBrollResults] = useState<any[]>([]);
  const [downloadingBrollId, setDownloadingBrollId] = useState<number | null>(null);
  const [rawVideoDurations, setRawVideoDurations] = useState<Record<string, number>>({});

  // Music library state
  const [musicLibrary, setMusicLibrary] = useState<string[]>(() => {
    try {
      const saved = localStorage.getItem('clipai_musicLibrary');
      return saved ? JSON.parse(saved) : [];
    } catch { return []; }
  });
  const [localMusicPath, setLocalMusicPath] = useState('');

  // Persist music library
  useEffect(() => {
    try { localStorage.setItem('clipai_musicLibrary', JSON.stringify(musicLibrary)); } catch {}
  }, [musicLibrary]);

  const addMusicToTimeline = (overridePath?: string) => {
    const path = overridePath || localMusicPath;
    if (!path) return;
    // Add to library if not already there
    if (!musicLibrary.includes(path)) {
      setMusicLibrary(prev => [...prev, path]);
    }
    // Create audio clip at current playhead
    const newClip = {
      id: `audio_${Date.now()}`,
      source_path: path,
      start_time_in_timeline: currentTime,
      end_time_in_timeline: currentTime + 30, // default 30s
      source_trim_start: 0,
      source_trim_end: 30,
      volume: 1.0,
    };
    const nextTimeline = produce(timelineState, (draft: any) => {
      if (!draft.tracks.audio || draft.tracks.audio.length === 0) {
        draft.tracks.audio = [{ id: 'a_track_music', name: 'Background Music Track', index: 0, clips: [] }];
      }
      // Find or create audio track
      let track = draft.tracks.audio[0];
      if (!track) {
        draft.tracks.audio.push({ id: 'a_track_music', name: 'Background Music Track', index: 0, clips: [] });
        track = draft.tracks.audio[0];
      }
      track.clips.push(newClip);
    });
    onChange(nextTimeline);
    if (!overridePath) setLocalMusicPath('');
  };

  const handleSearchBroll = async () => {
    if (!searchQuery.trim()) return;
    setSearching(true);
    try {
      const res = await axios.post(`${API_BASE}/api/broll/search`, {
        query: searchQuery,
        pexels_api_key: settings?.pexels_api_key || '',
        pixabay_api_key: settings?.pixabay_api_key || '',
        engine: searchEngine
      });
      if (res.data.status === 'success' && res.data.results) {
        setBrollResults(res.data.results);
      }
    } catch (err: any) {
      alert('فشل البحث عن B-roll: ' + err.message);
    } finally {
      setSearching(false);
    }
  };

  const handleAddBroll = async (item: any) => {
    setDownloadingBrollId(item.id);
    try {
      const res = await axios.post(`${API_BASE}/api/broll/download`, {
        download_url: item.download_url,
        keyword: searchQuery || 'broll'
      });
      if (res.data.status === 'success' && res.data.video_path) {
        const localPath = res.data.video_path;
        const durationSec = item.duration || 5;

        // Insert new overlay clip
        const newClip = {
          id: `broll_downloaded_${Date.now()}`,
          type: 'broll',
          source_path: localPath,
          start_time_in_timeline: currentTime,
          end_time_in_timeline: currentTime + durationSec,
          source_trim_start: 0,
          source_trim_end: durationSec,
          transform: {
            position: { x: 0, y: 0 },
            scale: { x: 100, y: 100 },
            rotation: 0,
            keyframes: []
          }
        };

        const nextTimeline = produce(timelineState, (draft: any) => {
          if (!draft.tracks.overlays) {
            draft.tracks.overlays = [];
          }
          if (draft.tracks.overlays.length === 0) {
            draft.tracks.overlays.push({ id: 'overlay_track_main', name: 'Overlay Track 1', index: 0, clips: [] });
          }
          draft.tracks.overlays[0].clips.push(newClip);
        });
        onChange(nextTimeline);

        alert('تم تحميل لقطة B-Roll وإضافتها إلى تراكب التايملاين بنجاح!');
      }
    } catch (err: any) {
      alert('فشل تحميل B-roll: ' + err.message);
    } finally {
      setDownloadingBrollId(null);
    }
  };

  const navBtn = (id: Section, label: string, Icon: any) => {
    const isActive = section === id;
    return (
      <button
        onClick={() => setSection(id)}
        className="flex-1 flex items-center justify-center gap-1.5 py-2 text-[11px] font-semibold transition-all rounded-[7px] cursor-pointer"
        style={{
          background: isActive ? 'var(--accent-bg)' : 'transparent',
          color: isActive ? 'var(--accent)' : 'var(--text-secondary)',
          border: isActive ? '0.5px solid rgba(10, 132, 255, 0.15)' : '0.5px solid transparent',
        }}
        onMouseEnter={(e) => {
          if (!isActive) {
            e.currentTarget.style.background = 'var(--bg-surface-3)';
            e.currentTarget.style.color = 'var(--text-primary)';
          }
        }}
        onMouseLeave={(e) => {
          if (!isActive) {
            e.currentTarget.style.background = 'transparent';
            e.currentTarget.style.color = 'var(--text-secondary)';
          }
        }}
      >
        <Icon className="w-3.5 h-3.5" /> {label}
      </button>
    );
  };

  return (
    <aside className="border-r flex flex-col min-h-0 flex-shrink-0" style={{ width: width, background: 'var(--bg-surface-1)', borderColor: 'var(--border-subtle)' }}>
      {/* Nav */}
      <div className="flex gap-1.5 p-2.5 border-b flex-shrink-0" style={{ background: 'var(--bg-surface-1)', borderColor: 'var(--border-subtle)' }}>
        {navBtn('import', 'استيراد', Upload)}
        {navBtn('clips', `كليبات (${clips.length})`, Layers)}
        {navBtn('broll', 'بحث B-Roll', Film)}
        {navBtn('music', 'موسيقى', Music)}
        {navBtn('mimic', 'محاكاة', Wand2)}
      </div>

      <div className="flex-1 overflow-y-auto p-4 flex flex-col gap-3.5 min-h-0">

        {/* ─── IMPORT SECTION ─── */}
        {section === 'import' && (
          <div className="apple-card p-4 flex flex-col gap-3.5">
            <h3 className="text-sm font-semibold tracking-wider flex items-center gap-2 justify-end" style={{ color: 'var(--text-primary)' }}>
              <Upload className="w-4 h-4" style={{ color: 'var(--accent)' }} /> استيراد الفيديو
            </h3>

            <div className="flex flex-col gap-1.5 text-right">
              <label className="apple-label">رابط يوتيوب:</label>
              <div className="flex gap-2">
                <div className="relative flex-1">
                  <YoutubeIcon />
                  <input
                    type="text" value={ytUrl} onChange={(e) => setYtUrl(e.target.value)}
                    placeholder="https://youtube.com/..."
                    className="apple-input w-full pl-9 pr-3 py-2.5 text-sm"
                  />
                </div>
                <button
                  onClick={triggerYoutubeDownload}
                  disabled={loading}
                  style={{ background: 'var(--accent-red)' }}
                  className="hover:opacity-85 disabled:bg-gray-800 disabled:text-gray-500 text-white px-3 py-2 rounded-[7px] text-sm flex items-center justify-center cursor-pointer transition-all border-none"
                >
                  <Download className="w-4 h-4" />
                </button>
              </div>
            </div>

            <div className="flex items-center my-0.5">
              <div className="flex-1 apple-separator" />
              <span className="text-[10px] uppercase px-2 font-semibold" style={{ color: 'var(--text-tertiary)' }}>أو</span>
              <div className="flex-1 apple-separator" />
            </div>

            <div className="flex flex-col gap-1.5 text-right">
              <label className="apple-label">ملف محلي:</label>
              <div className="flex gap-2">
                <div className="relative flex-1">
                  <Video className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2" style={{ color: 'var(--accent)' }} />
                  <input
                    type="text" value={videoPath} onChange={(e) => setVideoPath(e.target.value)}
                    placeholder="C:\video.mp4"
                    className="apple-input w-full pl-9 pr-3 py-2.5 text-sm"
                  />
                </div>
                <button
                  onClick={browseLocalFile}
                  disabled={loading}
                  className="apple-btn-secondary py-2 px-2.5 flex items-center justify-center"
                >
                  <FolderOpen className="w-4 h-4" />
                </button>
                <button
                  onClick={analyzeLocalVideo}
                  disabled={loading || !videoPath}
                  className="apple-btn-primary py-2 px-3 flex items-center justify-center"
                >
                  <Sparkles className="w-4 h-4" />
                </button>
              </div>
            </div>

            {mediaBin && mediaBin.length > 0 && (
              <div className="mt-2 flex flex-col gap-2.5">
                <label className="apple-label">مكتبة الوسائط:</label>
                <div className="grid grid-cols-2 gap-2.5">
                  {mediaBin.map((binPath) => (
                    <div
                      key={binPath}
                      draggable
                      onDragStart={(e) => {
                        e.dataTransfer.setData('text/plain', JSON.stringify({
                          type: 'raw_video',
                          path: binPath,
                          duration: rawVideoDurations[binPath] || 15.0
                        }));
                      }}
                      className={`p-2 rounded-lg text-right border cursor-move transition-all group hover:scale-[1.02] ${videoPath === binPath ? 'border-[var(--accent)] bg-[var(--accent-bg)] shadow-[0_0_8px_rgba(10,132,255,0.2)]' : 'border-[var(--border-default)] bg-[var(--bg-surface-3)]'}`}
                    >
                      <div className="relative w-full h-20 mb-2 bg-black rounded overflow-hidden">
                        <video
                          src={streamUrl(binPath)}
                          className="w-full h-full object-cover"
                          crossOrigin="anonymous"
                          muted
                          onLoadedData={(e) => {
                            e.currentTarget.currentTime = 1;
                            const dur = e.currentTarget.duration;
                            if (dur && !isNaN(dur)) {
                              setRawVideoDurations(prev => ({...prev, [binPath]: dur}));
                            }
                          }}
                        />
                        <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center gap-2">
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              setVideoPath(binPath);
                              analyzeLocalVideo();
                            }}
                            title="تحليل وتقطيع بالذكاء الاصطناعي"
                            className="p-2 rounded-full bg-[var(--accent)] text-white hover:scale-110 transition-transform shadow-lg"
                          >
                            <Sparkles className="w-4 h-4" />
                          </button>
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              const durationSec = rawVideoDurations[binPath] || 15.0;
                              const newClip = {
                                id: `raw_video_${Date.now()}`,
                                source_path: binPath,
                                start_time_in_timeline: 0,
                                end_time_in_timeline: durationSec,
                                source_trim_start: 0,
                                source_trim_end: durationSec,
                                speed: 1.0,
                                volume: 1.0,
                                transform: { position: { x: 0, y: 0 }, scale: { x: 100, y: 100 }, rotation: 0, keyframes: [] },
                                color_grading: { brightness: 0, contrast: 1.0, saturation: 1.0, temperature: 5600, lut_path: "" },
                                ai_features: { face_tracking: false, bg_removed: false, bg_remove_method: "chromakey", chromakey_color: "#00FF00" }
                              };
                              const next = produce(timelineState, (draft: any) => {
                                const track = draft.tracks.video[0];
                                if (track) track.clips.push(newClip);
                              });
                              onChange(next);
                            }}
                            title="أضف للتايم لاين مباشرة"
                            className="p-2 rounded-full bg-[#30D158] text-white hover:scale-110 transition-transform shadow-lg"
                          >
                            <Plus className="w-4 h-4" />
                          </button>
                        </div>
                      </div>
                      <p
                        className="text-[10px] font-medium truncate w-full"
                        style={{ color: 'var(--text-primary)' }}
                        title={binPath.split('\\').pop() || binPath.split('/').pop() || ''}
                      >
                        {binPath.split('\\').pop() || binPath.split('/').pop()}
                      </p>
                      {rawVideoDurations[binPath] && (
                        <p className="text-[9px] mt-0.5" style={{ color: 'var(--text-tertiary)' }}>
                          {Math.round(rawVideoDurations[binPath])} ثانية
                        </p>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}

        {/* ─── CLIPS LIST SECTION ─── */}
        {section === 'clips' && (
          <div className="flex flex-col gap-2.5 flex-1">
            <h3 className="text-sm font-semibold tracking-wider flex items-center gap-2 justify-end flex-shrink-0" style={{ color: 'var(--text-primary)' }}>
              <Layers className="w-4 h-4" style={{ color: 'var(--accent)' }} /> المقاطع المقترحة ({clips.length})
            </h3>

            {clips.length === 0 ? (
              <div className="flex-1 flex flex-col items-center justify-center text-center p-6 border border-dashed rounded-xl" style={{ borderColor: 'var(--border-default)', color: 'var(--text-tertiary)' }}>
                <Film className="w-10 h-10 mb-3 animate-pulse" style={{ color: 'var(--border-strong)' }} />
                <p className="text-sm font-medium" style={{ color: 'var(--text-secondary)' }}>لا يوجد خطة زمنية نشطة</p>
                <p className="text-[11px] max-w-[200px] mt-1" style={{ color: 'var(--text-tertiary)' }}>قم بإدخال فيديو وتحليله لتوليد المقاطع تلقائياً</p>
              </div>
            ) : (
              <div className="flex flex-col gap-2.5">
                {clips.map((clip, idx) => {
                  const isActive = activeClipIndex === idx;
                  return (
                    <div
                      key={clip.index}
                      onClick={() => { setActiveClipIndex(idx); seek(clip.start_sec); }}
                      draggable={true}
                      onDragStart={(e) => {
                        e.dataTransfer.setData('text/plain', JSON.stringify({
                          type: 'clip_suggestion',
                          clip: clip
                        }));
                      }}
                      className="p-3.5 rounded-lg border text-right transition-all duration-150 cursor-pointer cursor-grab active:cursor-grabbing"
                      style={{
                        background: isActive ? 'var(--accent-bg)' : 'var(--bg-surface-2)',
                        borderColor: isActive ? 'var(--accent)' : 'var(--border-default)',
                        boxShadow: isActive ? '0 2px 6px rgba(10,132,255,0.1)' : 'none',
                      }}
                      onMouseEnter={(e) => {
                        if (!isActive) e.currentTarget.style.borderColor = 'var(--border-strong)';
                      }}
                      onMouseLeave={(e) => {
                        if (!isActive) e.currentTarget.style.borderColor = 'var(--border-default)';
                      }}
                    >
                      <div className="flex items-center justify-between mb-2">
                        <span
                          className="text-[10px] px-2 py-0.5 rounded font-semibold border"
                          style={{
                            background: 'var(--bg-surface-3)',
                            borderColor: 'var(--border-default)',
                            color: 'var(--accent)'
                          }}
                        >
                          {Math.round(clip.end_sec - clip.start_sec)}ث
                        </span>
                        <span className="font-semibold text-sm" style={{ color: 'var(--text-primary)' }}>مقطع {clip.index}</span>
                      </div>
                      <p className="text-xs leading-relaxed line-clamp-2 mb-2.5" style={{ color: 'var(--text-secondary)' }}>
                        💡 {clip.reason}
                      </p>
                      <div className="flex flex-wrap gap-1 justify-end">
                        <span className="text-[9px] px-1.5 py-0.5 rounded border font-medium" style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-subtle)', color: 'var(--text-secondary)' }}>{clip.caption_theme}</span>
                        <span className="text-[9px] px-1.5 py-0.5 rounded border font-medium" style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-subtle)', color: 'var(--text-secondary)' }}>{clip.zoom_style}</span>
                        <span className="text-[9px] px-1.5 py-0.5 rounded border font-medium" style={{ background: 'var(--bg-surface-3)', borderColor: 'var(--border-subtle)', color: 'var(--text-secondary)' }}>{clip.color_grade}</span>
                      </div>

                      {/* Hook options inline */}
                      {isActive && clip.hook_options && clip.hook_options.length > 1 && (
                        <div className="mt-2 pt-2 flex flex-col gap-1 border-t" style={{ borderColor: 'var(--border-subtle)' }}>
                          <span className="text-[9px] font-semibold" style={{ color: 'var(--accent)' }}>خيارات الهوك:</span>
                          {clip.hook_options.map((opt, i) => {
                            const isHookActive = clip.hook === opt;
                            return (
                              <button
                                key={i}
                                onClick={(e) => { e.stopPropagation(); const updated = [...clips]; updated[idx].hook = opt; setClips(updated); }}
                                className="text-[10px] text-right p-1.5 rounded border transition-all cursor-pointer"
                                style={{
                                  background: isHookActive ? 'var(--accent-bg)' : 'var(--bg-surface-3)',
                                  borderColor: isHookActive ? 'var(--accent)' : 'var(--border-default)',
                                  color: isHookActive ? 'var(--text-primary)' : 'var(--text-secondary)',
                                  fontWeight: isHookActive ? 600 : 400
                                }}
                              >
                                {opt}
                              </button>
                            );
                          })}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        )}

        {/* ─── B-ROLL SECTION ─── */}
        {section === 'broll' && (
          <div className="flex flex-col gap-3.5 flex-1 text-right">
            <h3 className="text-sm font-semibold tracking-wider flex items-center gap-2 justify-end" style={{ color: 'var(--text-primary)' }}>
              <Film className="w-4 h-4" style={{ color: 'var(--accent)' }} /> مكتبة B-Roll الذكية
            </h3>

            {/* Search Engine Selector */}
            <div className="flex gap-1.5 justify-end">
              <button
                onClick={() => setSearchEngine('both')}
                className={`px-3 py-1 text-[10px] rounded-full border transition-all cursor-pointer ${searchEngine === 'both' ? 'bg-[var(--accent-bg)] border-[var(--accent)] text-[var(--accent)]' : 'bg-[var(--bg-surface-3)] border-[var(--border-subtle)] text-[var(--text-secondary)]'}`}
              >
                كلاهما
              </button>
              <button
                onClick={() => setSearchEngine('pixabay')}
                className={`px-3 py-1 text-[10px] rounded-full border transition-all cursor-pointer ${searchEngine === 'pixabay' ? 'bg-[var(--accent-bg)] border-[var(--accent)] text-[var(--accent)]' : 'bg-[var(--bg-surface-3)] border-[var(--border-subtle)] text-[var(--text-secondary)]'}`}
              >
                Pixabay
              </button>
              <button
                onClick={() => setSearchEngine('pexels')}
                className={`px-3 py-1 text-[10px] rounded-full border transition-all cursor-pointer ${searchEngine === 'pexels' ? 'bg-[var(--accent-bg)] border-[var(--accent)] text-[var(--accent)]' : 'bg-[var(--bg-surface-3)] border-[var(--border-subtle)] text-[var(--text-secondary)]'}`}
              >
                Pexels
              </button>
              <span className="text-[10px] text-[var(--text-tertiary)] self-center ml-2">المصدر:</span>
            </div>

            {/* Search Input */}
            <div className="flex gap-2">
              <button
                onClick={handleSearchBroll}
                disabled={searching || !searchQuery}
                style={{ background: 'var(--accent)' }}
                className="hover:opacity-90 disabled:bg-gray-800 disabled:text-gray-500 text-white px-4 py-2.5 rounded-[7px] text-sm flex items-center justify-center cursor-pointer transition-all border-none font-semibold"
              >
                {searching ? 'جاري...' : <Search className="w-4 h-4" />}
              </button>
              <div className="relative flex-1">
                <input
                  type="text"
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && handleSearchBroll()}
                  placeholder="ابحث عن فيديوهات B-Roll..."
                  className="apple-input w-full pr-3 py-2.5 text-sm text-right"
                  style={{ direction: 'rtl' }}
                />
              </div>
            </div>

            {/* Search Results */}
            <div className="flex-grow overflow-y-auto mt-2 min-h-0">
              {searching ? (
                <div className="text-center py-8 text-sm text-[var(--text-secondary)]">جاري جلب الفيديوهات...</div>
              ) : brollResults.length === 0 ? (
                <div className="text-center py-8 text-sm text-[var(--text-tertiary)]">ابحث للحصول على لقطات B-Roll المجانية</div>
              ) : (
                <div className="grid grid-cols-2 gap-2.5">
                  {brollResults.map((item: any) => {
                    const isDownloading = downloadingBrollId === item.id;
                    return (
                      <div
                        key={item.id}
                        draggable={true}
                        onDragStart={(e) => {
                          e.dataTransfer.setData('text/plain', JSON.stringify({
                            type: 'broll_item',
                            item: item,
                            searchQuery: searchQuery
                          }));
                        }}
                        className="rounded-lg border overflow-hidden relative group flex flex-col justify-between cursor-grab active:cursor-grabbing hover:border-[var(--accent)] transition-all"
                        style={{ background: 'var(--bg-surface-2)', borderColor: 'var(--border-default)' }}
                      >
                        {/* Video Thumbnail */}
                        <div className="aspect-[9/16] bg-black relative flex items-center justify-center overflow-hidden">
                          {item.image ? (
                            <img
                              src={item.image}
                              alt="broll thumbnail"
                              className="w-full h-full object-cover"
                            />
                          ) : (
                            <div className="w-full h-full flex items-center justify-center text-[10px] text-[var(--text-tertiary)] bg-gray-900">
                              لا توجد معاينة
                            </div>
                          )}
                          <div className="absolute bottom-1.5 right-1.5 px-2 py-0.5 bg-black/60 rounded text-[10px] font-mono text-white">
                            {item.duration}ث
                          </div>
                          <span className="absolute top-1.5 left-1.5 px-1.5 py-0.5 bg-black/50 rounded text-[8px] text-[var(--text-secondary)] uppercase">
                            {item.source || 'broll'}
                          </span>
                        </div>

                        {/* Add Button */}
                        <button
                          onClick={() => handleAddBroll(item)}
                          disabled={isDownloading}
                          className="w-full py-1.5 text-[11px] font-semibold border-t flex items-center justify-center gap-1 transition-all cursor-pointer hover:bg-[var(--accent-bg)]"
                          style={{
                            background: 'var(--bg-surface-3)',
                            borderColor: 'var(--border-default)',
                            color: isDownloading ? 'var(--text-tertiary)' : 'var(--text-primary)'
                          }}
                        >
                          <Plus className="w-3.5 h-3.5" />
                          {isDownloading ? 'جاري...' : 'أضف للتايملاين'}
                        </button>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          </div>
        )}

        {/* ─── MUSIC SECTION ─── */}
        {section === 'music' && (
          <div className="flex flex-col gap-3.5 flex-1 text-right">
            <h3 className="text-sm font-semibold tracking-wider flex items-center gap-2 justify-end" style={{ color: 'var(--text-primary)' }}>
              <Music className="w-4 h-4" style={{ color: '#34c759' }} /> الموسيقى والمؤثرات
            </h3>

            {/* Import Local Audio */}
            <div className="apple-card p-4 flex flex-col gap-2.5">
              <label className="apple-label">استيراد ملف موسيقى محلي:</label>
              <div className="flex gap-2">
                <div className="relative flex-1">
                  <Music className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2" style={{ color: '#34c759' }} />
                  <input
                    type="text"
                    value={localMusicPath}
                    onChange={(e) => setLocalMusicPath(e.target.value)}
                    placeholder="C:\music.mp3"
                    className="apple-input w-full pl-9 pr-3 py-2.5 text-sm"
                  />
                </div>
                <button
                  onClick={async () => {
                    const tauri = (window as any).__TAURI__;
                    if (tauri && tauri.dialog) {
                      try {
                        const selected = await tauri.dialog.open({
                          filters: [{ name: 'Audio Files', extensions: ['mp3', 'wav', 'aac', 'ogg', 'm4a', 'flac'] }],
                          multiple: false
                        });
                        if (selected && typeof selected === 'string') {
                          setLocalMusicPath(selected);
                        }
                      } catch (err: any) {
                        alert('فشل: ' + err.message);
                      }
                    } else {
                      alert('File browser not available. Type the path manually.');
                    }
                  }}
                  className="apple-btn-secondary py-2 px-2.5 flex items-center justify-center"
                >
                  <FolderOpen className="w-4 h-4" />
                </button>
                <button
                  onClick={() => addMusicToTimeline()}
                  disabled={!localMusicPath}
                  className="apple-btn-primary py-2 px-3 flex items-center gap-1.5"
                  style={{ background: '#34c759' }}
                >
                  <Plus className="w-4 h-4" /> أضف
                </button>
              </div>
              <p className="text-[10px]" style={{ color: 'var(--text-tertiary)' }}>
                MP3, WAV, AAC, OGG, M4A, FLAC
              </p>
            </div>

            {/* Music Library */}
            <div className="flex flex-col gap-2 flex-1 min-h-0">
              <div className="flex items-center justify-between">
                <span className="text-[10px] uppercase tracking-wider font-semibold" style={{ color: 'var(--text-tertiary)' }}>
                  {musicLibrary.length} مقطع
                </span>
                <span className="text-[10px] font-semibold" style={{ color: 'var(--text-secondary)' }}>المكتبة:</span>
              </div>
              {musicLibrary.length === 0 ? (
                <div className="flex-1 flex flex-col items-center justify-center text-center p-6 border border-dashed rounded-xl" style={{ borderColor: 'var(--border-default)', color: 'var(--text-tertiary)' }}>
                  <Music className="w-10 h-10 mb-2 animate-pulse" style={{ color: 'var(--border-strong)' }} />
                  <p className="text-sm font-medium" style={{ color: 'var(--text-secondary)' }}>لا يوجد موسيقى</p>
                  <p className="text-[11px] max-w-[200px] mt-1" style={{ color: 'var(--text-tertiary)' }}>استورد ملف صوتي أو اسحب ملف من File Explorer</p>
                </div>
              ) : (
                <div className="flex flex-col gap-2 overflow-y-auto flex-1 min-h-0 pr-1">
                  {musicLibrary.map((track, idx) => (
                    <div
                      key={idx}
                      className="p-3 rounded-lg border flex items-center gap-2"
                      style={{ background: 'var(--bg-surface-2)', borderColor: 'var(--border-default)' }}
                    >
                      <Music className="w-4 h-4 flex-shrink-0" style={{ color: '#34c759' }} />
                      <div className="flex-1 min-w-0">
                        <p className="text-xs font-semibold truncate" style={{ color: 'var(--text-primary)' }} title={track}>
                          {track.split('\\').pop() || track.split('/').pop()}
                        </p>
                      </div>
                      <button
                        onClick={() => addMusicToTimeline(track)}
                        className="px-2 py-1 rounded text-[10px] font-semibold flex items-center gap-1 transition-all cursor-pointer"
                        style={{ background: 'var(--accent-bg)', color: 'var(--accent)' }}
                        title="أضف للتايملاين"
                      >
                        <Plus className="w-3 h-3" /> أضف
                      </button>
                      <button
                        onClick={() => setMusicLibrary(prev => prev.filter((_, i) => i !== idx))}
                        className="px-2 py-1 rounded text-[10px] font-semibold flex items-center transition-all cursor-pointer"
                        style={{ background: 'transparent', color: 'var(--text-tertiary)' }}
                        title="حذف من المكتبة"
                      >
                        ✕
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        )}

        {/* ─── MIMIC SECTION ─── */}
        {section === 'mimic' && (
          <StyleMimicWorkspace
            onTargetVideoSelected={(path) => setVideoPath(path)}
            onAnalysisComplete={(profile: any) => setMimicProfile(profile)}
          />
        )}
      </div>
    </aside>
  );
}
