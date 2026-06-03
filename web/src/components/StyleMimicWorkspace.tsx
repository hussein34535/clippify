import { useState, useEffect } from "react";
import axios from "axios";
import { Upload, Sparkles, Sliders, Video, Layers } from "lucide-react";

const API_BASE = "http://localhost:8000";

interface StyleProfile {
  name: string;
  meta: {
    reference_video_name: string;
    duration_sec: number;
    detected_fps: number;
    resolution: { width: number; height: number };
  };
  pacing: {
    bpm: number;
    average_shot_duration_sec: number;
    total_cuts: number;
  };
  typography: {
    subtitles: {
      fill_color: string;
      font_size_ratio: number;
      position_y_ratio: number;
    };
  };
}

interface StyleMimicWorkspaceProps {
  onAnalysisComplete?: (profile: any) => void;
  onTargetVideoSelected?: (path: string) => void;
}

export default function StyleMimicWorkspace({ onAnalysisComplete, onTargetVideoSelected }: StyleMimicWorkspaceProps) {
  const [refVideoPath, setRefVideoPath] = useState("");
  const [targetVideoPath, setTargetVideoPath] = useState("");
  const [profileName, setProfileName] = useState("vlog_reference_style");
  const [isAnalyzing, setIsAnalyzing] = useState(false);
  const [isRendering, setIsRendering] = useState(false);
  const [analysisProgress, setAnalysisProgress] = useState(0);
  const [activeProfile, setActiveProfile] = useState<StyleProfile | null>(null);
  const [profilesList, setProfilesList] = useState<StyleProfile[]>([]);
  
  // Custom mimicry intensity sliders
  const [pacingIntensity, setPacingIntensity] = useState(80);
  const [subtitleOverride, setSubtitleOverride] = useState(false);
  const [zoomIntensity, setZoomIntensity] = useState(100);

  const fetchProfiles = async () => {
    try {
      const res = await axios.get(`${API_BASE}/api/style/profiles`);
      setProfilesList(res.data);
    } catch (err) {
      console.error("Failed to load style profiles:", err);
    }
  };

  useEffect(() => {
    fetchProfiles();
  }, []);

  const handleBrowseReference = async () => {
    try {
      const res = await axios.post(`${API_BASE}/api/browse-file`);
      if (res.data.status === "success" && res.data.file_path) {
        setRefVideoPath(res.data.file_path);
      }
    } catch (err) {
      console.error("Browse failed:", err);
    }
  };

  const handleBrowseTarget = async () => {
    try {
      const res = await axios.post(`${API_BASE}/api/browse-file`);
      if (res.data.status === "success" && res.data.file_path) {
        setTargetVideoPath(res.data.file_path);
        if (onTargetVideoSelected) {
          onTargetVideoSelected(res.data.file_path);
        }
      }
    } catch (err) {
      console.error("Browse failed:", err);
    }
  };

  const runReferenceAnalysis = async () => {
    if (!refVideoPath) return;
    setIsAnalyzing(true);
    setAnalysisProgress(20);
    
    try {
      const res = await axios.post(`${API_BASE}/api/style/analyze-reference`, {
        reference_path: refVideoPath,
        profile_name: profileName
      });
      
      setAnalysisProgress(80);
      if (res.data.status === "success") {
        setActiveProfile(res.data.profile);
        setAnalysisProgress(100);
        alert("تم تحليل الفيديو المرجعي وحفظ النمط بنجاح!");
        if (onAnalysisComplete) {
          onAnalysisComplete(res.data.profile);
        }
        fetchProfiles();
      }
    } catch (err: any) {
      console.error("Analysis failed:", err);
      alert("فشل تحليل الفيديو المرجعي: " + err.message);
    } finally {
      setTimeout(() => {
        setIsAnalyzing(false);
        setAnalysisProgress(0);
      }, 500);
    }
  };

  const runStyleImitation = async () => {
    if (!targetVideoPath || !activeProfile) return alert("يرجى تحديد الفيديو الجديد وتحديد نمط مرجعي نشط");
    setIsRendering(true);
    
    try {
      // 1. Transcribe the target raw video
      alert("بدء فحص وتفريغ الفيديو المستهدف (قد يستغرق بضع ثوانٍ)...");
      const transcriptRes = await axios.post(`${API_BASE}/api/analyze-video`, {
        video_path: targetVideoPath
      });
      
      const session_id = transcriptRes.data.session_id;
      
      // Poll transcription status
      const pollInterval = setInterval(async () => {
        try {
          const statusRes = await axios.get(`${API_BASE}/api/status?session_id=${session_id}`);
          if (statusRes.data.status === 'Done') {
            clearInterval(pollInterval);
            
            const words = statusRes.data.results?.words || [];
            
            // 2. Trigger Style Imitator Render
            const imitateRes = await axios.post(`${API_BASE}/api/style/imitate`, {
              target_path: targetVideoPath,
              profile_path: `./profiles/${activeProfile.name || profileName}.json`,
              output_name: `${activeProfile.name || profileName}_output`,
              words: words
            });
            
            if (imitateRes.data.status === "success") {
              alert("تم إرسال مهمة رندر محاكاة المونتاج بنجاح! راقب مجلد التصدير.");
            }
            setIsRendering(false);
          } else if (statusRes.data.status === 'Failed') {
            clearInterval(pollInterval);
            setIsRendering(false);
            alert("فشلت عملية تفريغ الفيديو المستهدف.");
          }
        } catch (pollErr) {
          clearInterval(pollInterval);
          setIsRendering(false);
          console.error("Poll error:", pollErr);
        }
      }, 1500);
      
    } catch (err: any) {
      console.error("Imitation render failed:", err);
      setIsRendering(false);
      alert("فشلت عملية المحاكاة: " + err.message);
    }
  };

  return (
    <div className="w-full p-5 bg-[#110d1c] border border-[#221a30] rounded-2xl shadow-xl flex flex-col gap-5 text-right">
      <div className="flex justify-between items-center pb-3 border-b border-[#221a30]">
        <span className="px-2.5 py-0.5 bg-purple-950 border border-purple-800 text-purple-300 rounded-full text-[10px] font-semibold">
          تحليل محلي بالكامل (DSP & CV)
        </span>
        <h2 className="text-sm font-bold text-white flex items-center gap-2">
          محاكاة فيديو مرجعي <Sparkles className="w-4 h-4 text-purple-500" />
        </h2>
      </div>

      <div className="flex flex-col gap-4">
        {/* Upload Slot 1: Reference Video */}
        <div className="p-4 bg-[#171226]/50 border border-[#2c1e4a] rounded-xl flex flex-col gap-3">
          <h3 className="text-xs font-bold text-gray-300 flex items-center gap-2 justify-end">
            <Upload className="w-3.5 h-3.5 text-purple-400" /> 1. الفيديو المرجعي (المطلوب تقليده)
          </h3>
          
          <div className="flex gap-2">
            <input
              type="text"
              readOnly
              value={refVideoPath}
              placeholder="اختر ملف الفيديو المرجعي..."
              className="flex-1 px-3 py-1.5 bg-black/40 border border-[#2e234a] rounded-lg text-[11px] font-mono text-left text-gray-400 focus:outline-none"
            />
            <button
              onClick={handleBrowseReference}
              className="px-3 py-1.5 bg-[#1f1733] border border-[#372a5a] text-purple-300 hover:bg-[#2b1f47] rounded-lg text-xs font-bold transition cursor-pointer"
            >
              استعراض
            </button>
          </div>
          
          <div className="flex gap-2 items-center">
            <input
              type="text"
              value={profileName}
              onChange={(e) => setProfileName(e.target.value)}
              placeholder="اسم بصمة النمط..."
              className="w-1/2 px-3 py-1.5 bg-black/40 border border-[#2e234a] rounded-lg text-xs text-right text-gray-300 focus:outline-none"
            />
            <button
              disabled={!refVideoPath || isAnalyzing}
              onClick={runReferenceAnalysis}
              className={`flex-1 py-1.5 px-3 rounded-lg text-xs font-bold transition-all cursor-pointer ${
                !refVideoPath || isAnalyzing 
                  ? "bg-gray-800 text-gray-500 cursor-not-allowed" 
                  : "bg-purple-600 hover:bg-purple-700 text-white shadow-lg shadow-purple-500/10"
              }`}
            >
              {isAnalyzing ? `جاري التحليل... ${analysisProgress}%` : "⚡ تحليل البصمة"}
            </button>
          </div>
        </div>

        {/* Upload Slot 2: Target Video */}
        <div className="p-4 bg-[#171226]/50 border border-[#2c1e4a] rounded-xl flex flex-col gap-3">
          <h3 className="text-xs font-bold text-gray-300 flex items-center gap-2 justify-end">
            <Video className="w-3.5 h-3.5 text-purple-400" /> 2. الفيديو الجديد (المستهدف)
          </h3>
          
          <div className="flex gap-2">
            <input
              type="text"
              readOnly
              value={targetVideoPath}
              placeholder="اختر ملف الفيديو الخام..."
              className="flex-1 px-3 py-1.5 bg-black/40 border border-[#2e234a] rounded-lg text-[11px] font-mono text-left text-gray-400 focus:outline-none"
            />
            <button
              onClick={handleBrowseTarget}
              className="px-3 py-1.5 bg-[#1f1733] border border-[#372a5a] text-purple-300 hover:bg-[#2b1f47] rounded-lg text-xs font-bold transition cursor-pointer"
            >
              استعراض
            </button>
          </div>

          <button
            disabled={!targetVideoPath || !activeProfile || isRendering}
            onClick={runStyleImitation}
            className={`w-full py-2 rounded-lg text-xs font-bold transition-all cursor-pointer ${
              !targetVideoPath || !activeProfile || isRendering
                ? "bg-gray-800 text-gray-500 cursor-not-allowed"
                : "bg-gradient-to-r from-purple-600 to-pink-500 hover:from-purple-700 hover:to-pink-600 text-white shadow-lg shadow-purple-500/20"
            }`}
          >
            {isRendering ? "جاري المعالجة..." : "🎬 مطابقة ومحاكاة المونتاج"}
          </button>
        </div>
      </div>

      {/* Database & Tuning stacked vertically */}
      <div className="flex flex-col gap-4">
        {/* Style Parameters Tuning */}
        <div className="p-4 bg-[#171226]/30 border border-[#2c1e4a] rounded-xl flex flex-col gap-3">
          <h3 className="text-xs font-bold text-purple-300 flex items-center gap-1.5 justify-end">
            <Sliders className="w-3.5 h-3.5" /> ضبط شدة المحاكاة
          </h3>
          
          <div className="space-y-3">
            <div>
              <div className="flex justify-between text-[10px] text-gray-400 mb-1">
                <span>{pacingIntensity}%</span>
                <span>إيقاع المونتاج والقص (Pacing)</span>
              </div>
              <input
                type="range"
                min="20"
                max="100"
                value={pacingIntensity}
                onChange={(e) => setPacingIntensity(Number(e.target.value))}
                className="w-full accent-purple-600 bg-black/40 h-1 rounded"
              />
            </div>

            <div>
              <div className="flex justify-between text-[10px] text-gray-400 mb-1">
                <span>{zoomIntensity}%</span>
                <span>تأثيرات الزوم والتقريب (Zoom)</span>
              </div>
              <input
                type="range"
                min="0"
                max="120"
                value={zoomIntensity}
                onChange={(e) => setZoomIntensity(Number(e.target.value))}
                className="w-full accent-purple-600 bg-black/40 h-1 rounded"
              />
            </div>

            <div className="flex items-center justify-between pt-2 border-t border-[#2c1e4a]">
              <input
                type="checkbox"
                id="subOverride"
                checked={subtitleOverride}
                onChange={(e) => setSubtitleOverride(e.target.checked)}
                className="w-4 h-4 rounded accent-purple-600 bg-black/40 cursor-pointer"
              />
              <label htmlFor="subOverride" className="text-xs text-gray-300 cursor-pointer">
                استخدام خطوط وترجمات تلقائية
              </label>
            </div>
          </div>
        </div>

        {/* Selected style details */}
        <div className="flex flex-col gap-3">
          <h3 className="text-xs font-bold text-gray-400 justify-end flex items-center gap-2">
            <Layers className="w-3.5 h-3.5 text-purple-400" /> الأنماط المرجعية المحفوظة
          </h3>

          {profilesList.length === 0 ? (
            <div className="p-6 text-center text-gray-500 border border-dashed border-[#2c1e4a] rounded-xl text-xs">
              لا توجد أنماط محفوظة حالياً.
            </div>
          ) : (
            <div className="flex flex-col gap-2.5 max-h-[220px] overflow-y-auto pr-1">
              {profilesList.map((prof) => (
                <div
                  key={prof.name}
                  onClick={() => {
                    setActiveProfile(prof);
                    if (onAnalysisComplete) {
                      onAnalysisComplete(prof);
                    }
                  }}
                  className={`p-3 rounded-xl border text-right transition cursor-pointer flex flex-col gap-2 ${
                    activeProfile?.name === prof.name
                      ? 'bg-purple-950/30 border-purple-500 shadow-md'
                      : 'bg-[#151122] border-[#221a30] hover:border-[#3c2f5d]'
                  }`}
                >
                  <div className="flex justify-between items-center">
                    <span className="text-[9px] px-1.5 py-0.5 rounded bg-gray-900 border border-gray-800 text-gray-300 font-bold">
                      {Math.round(prof.meta.duration_sec)}s
                    </span>
                    <span className="font-bold text-xs text-white">{prof.name}</span>
                  </div>
                  
                  <div className="grid grid-cols-3 gap-1 text-[8px] text-gray-400 pt-1.5 border-t border-[#261f36] text-center">
                    <div>
                      <span className="text-purple-400 font-bold block">{prof.pacing.bpm}</span>
                      <span>إيقاع BPM</span>
                    </div>
                    <div>
                      <span className="text-purple-400 font-bold block">{prof.pacing.average_shot_duration_sec}s</span>
                      <span>معدل القص</span>
                    </div>
                    <div>
                      <span className="text-purple-400 font-bold block">{prof.pacing.total_cuts}</span>
                      <span>القصات</span>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
