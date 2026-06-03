"""
gui_main.py — ClipAI Desktop Application GUI Entry Point
Beautiful UI built with CustomTkinter, inheriting modular features.
"""

import os
import sys
import warnings
import threading
import subprocess
import datetime
import customtkinter as ctk
from tkinter import filedialog, messagebox

warnings.filterwarnings("ignore", category=RuntimeWarning, module="pydub")
warnings.filterwarnings("ignore", category=UserWarning, module="requests")

# DPI Awareness
if sys.platform == "win32":
    try:
        import ctypes
        ctypes.windll.shcore.SetProcessDpiAwareness(1)
    except Exception:
        try:
            ctypes.windll.user32.SetProcessDPIAware()
        except Exception:
            pass

# Drag and Drop support
try:
    from tkinterdnd2 import DND_FILES, TkinterDnD
    DND_AVAILABLE = True
except Exception:
    DND_AVAILABLE = False

# pyperclip support
try:
    import pyperclip
    PYPERCLIP_OK = True
except Exception:
    PYPERCLIP_OK = False

# Import modular components
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from app_constants import (
    ACCENT, ACCENT_HOVER, SUCCESS, ERROR_CLR, YT_RED, YT_RED_HOVER,
    BORDER_IDLE, BORDER_OK, BORDER_ERR, TEXT_DIM
)
from app_utils import open_folder, fmt_time
from app_popups import ConsoleRedirector, CTkVideoPlayer, show_tips_popup, show_settings_popup
from icons import get_copy_icon
from campaign import load_campaign
from gui_state import load_ui_prefs, save_ui_prefs

# Mixins
from gui_campaign_mixin import CampaignMixin
from gui_youtube_mixin import YouTubeMixin
from gui_pipeline_mixin import PipelineMixin

ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("blue")

class ClipAIApp(ctk.CTk, CampaignMixin, YouTubeMixin, PipelineMixin):

    def __init__(self):
        super().__init__()
        
        if DND_AVAILABLE:
            try:
                self.TkdndVersion = self.tk.call('package', 'require', 'dnd')
            except Exception:
                try:
                    self.TkdndVersion = TkinterDnD._to_absolute_path(self, 'dnd')
                except Exception:
                    pass
            ctk.set_appearance_mode("dark")

        # ── State ────────────────────────────────────────────────────────────
        self._video_path      = None
        self._processing      = False
        self._cancel_flag     = False
        self._uploading       = False
        self._clips_done      = 0
        self._result_rows     = {}       # {idx: {row, icon, info, path}}
        self._generated_clips = []       # ordered list of exported file paths
        self._uploaded_urls   = {}       # {idx: youtube_url}
        self._upload_rows     = {}       # {idx: {row, status_lbl, prog_lbl}}

        # Load Preferences from state module
        p = load_ui_prefs()
        self._n_clips                = p.get("n_clips", 5)
        self._duration               = p.get("duration", 60)
        self._ai_mode                = p.get("ai_mode", True)
        self._auto_director          = p.get("auto_director", True)
        self._trim_silence           = p.get("trim_silence", True)
        self._scale_punches          = p.get("scale_punches", True)
        self._hook_mode              = p.get("hook_mode", True)
        self._compile_clips          = p.get("compile_clips", True)
        self._translate_to_arabic    = p.get("translate_to_arabic", False)
        self._gemma_multimodal      = p.get("gemma_multimodal", False)
        self._auto_broll             = p.get("auto_broll", False)
        self._use_scene_captioning   = p.get("use_scene_captioning", False)
        self._use_local_captioning   = p.get("use_local_captioning", True)
        self._subtitle_style         = p.get("subtitle_style", "TikTok Yellow")
        self._font_name              = p.get("font_name", "Impact")
        self._export_quality         = p.get("export_quality", "High")
        self._sfx_mode               = p.get("sfx_mode", "normal")
        self._caption_animation_mode = p.get("caption_animation_mode", "auto")
        self._framing_strategy       = p.get("framing_strategy", "speaker_tracking")
        self._output_dir             = p.get("output_dir", "./output")
        self._temp_folder            = p.get("temp_folder", "./temp")
        self._ending_cta             = ""
        self._logo_path              = ""
        self._content_type           = "podcast"
        self._manual_bounds          = None

        # Campaign
        self._campaign        = load_campaign()
        self._campaign_active = self._campaign is not None
        self._caption_index   = 0

        # API Keys
        self._pexels_api_key = os.environ.get("PEXELS_API_KEY", "")
        if not self._pexels_api_key:
            pex_key_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pexels_key.txt")
            if os.path.exists(pex_key_path):
                try:
                    with open(pex_key_path, "r") as f:
                        self._pexels_api_key = f.read().strip()
                except Exception:
                    pass

        self._setup_window()
        self._build_ui()
        self._load_prefs_into_ui()
        
        # Redirect output
        sys.stdout = ConsoleRedirector(self, self._console_box)
        sys.stderr = ConsoleRedirector(self, self._console_box)
        
        self._current_progress = 0.0
        self._target_progress  = 0.0
        self._last_progress_label = ""
        self._start_progress_loop()

    def _save_ui_prefs(self):
        """Build and save current state to state module."""
        try:
            p = {
                "n_clips":               int(self._clips_slider.get()),
                "duration":              int(self._dur_slider.get()),
                "ai_mode":               self._ai_mode_var.get(),
                "auto_director":         self._auto_director_var.get(),
                "trim_silence":          self._trim_silence_var.get(),
                "scale_punches":         self._scale_punches_var.get(),
                "hook_mode":             self._hook_mode_var.get(),
                "compile_clips":         self._compile_clips_var.get(),
                "translate_to_arabic":   self._translate_to_arabic_var.get(),
                "gemma_multimodal":     self._gemma_multimodal_var.get(),
                "auto_broll":            self._auto_broll_var.get(),
                "use_scene_captioning":  self._use_scene_captioning_var.get(),
                "use_local_captioning":  self._use_local_captioning_var.get(),
                "subtitle_style":        self._theme_option_var.get(),
                "font_name":             self._font_name_var.get(),
                "export_quality":        self._export_quality_var.get(),
                "sfx_mode":              self._sfx_mode_option_var.get(),
                "caption_animation_mode":self._caption_animation_mode,
                "framing_strategy":      self._framing_strategy_var.get(),
                "output_dir":            self._output_dir,
                "temp_folder":           self._temp_folder
            }
            save_ui_prefs(p)
        except Exception as e:
            print(f"[Prefs] Failed to save ui_prefs: {e}")

    def _load_prefs_into_ui(self):
        try:
            self._clips_slider.set(self._n_clips)
            self._dur_slider.set(self._duration)
            self._ai_mode_var.set(self._ai_mode)
            self._auto_director_var.set(self._auto_director)
            self._trim_silence_var.set(self._trim_silence)
            self._scale_punches_var.set(self._scale_punches)
            self._hook_mode_var.set(self._hook_mode)
            self._compile_clips_var.set(self._compile_clips)
            self._translate_to_arabic_var.set(self._translate_to_arabic)
            self._gemma_multimodal_var.set(self._gemma_multimodal)
            self._auto_broll_var.set(self._auto_broll)
            self._use_scene_captioning_var.set(self._use_scene_captioning)
            self._use_local_captioning_var.set(self._use_local_captioning)
            self._theme_option_var.set(self._subtitle_style)
            self._font_name_var.set(self._font_name)
            self._export_quality_var.set(self._export_quality)
            self._sfx_mode_option_var.set(self._sfx_mode)
            framing_display = {"no_crop": "No Crop", "speaker_tracking": "Active Speaker", "split_screen": "Split Screen"}.get(self._framing_strategy, "Active Speaker")
            self._framing_strategy_var.set(framing_display)
        except Exception as e:
            print(f"[Prefs] Could not restore some UI widgets: {e}")

    def destroy(self):
        try:
            self._save_ui_prefs()
        except Exception as e:
            print(f"[Prefs] Failed to save prefs on destroy: {e}")
        super().destroy()

    def _setup_window(self):
        self.title("ClipAI")
        self.geometry("1020x660")
        self.minsize(1000, 650)
        self.resizable(True, True)
        
        try:
            self.update_idletasks()
            sw = self.winfo_screenwidth()
            sh = self.winfo_screenheight()
            if sw >= 2560 or sh >= 1400:
                ctk.set_widget_scaling(1.35)
                ctk.set_window_scaling(1.35)
            elif sw >= 1920:
                ctk.set_widget_scaling(1.20)
                ctk.set_window_scaling(1.20)
        except Exception:
            pass
        try:
            self.configure(fg_color=("#F2F2F7", "#121212"))
        except Exception:
            self.configure(bg="#121212")
        self.update_idletasks()
        sw = self.winfo_screenwidth()
        sh = self.winfo_screenheight()
        x  = (sw - 1020) // 2
        y  = max(0, (sh - 660) // 2)
        self.geometry(f"1020x660+{x}+{y}")
        try:
            self.state("zoomed")
        except Exception:
            pass

    def _build_ui(self):
        main_container = ctk.CTkFrame(self, fg_color="transparent")
        main_container.pack(fill="both", expand=True, padx=16, pady=12)

        left_column = ctk.CTkFrame(main_container, fg_color="transparent", width=480)
        left_column.pack(side="left", fill="both", expand=False, padx=(0, 12))
        left_column.pack_propagate(False)

        right_column = ctk.CTkFrame(main_container, fg_color="transparent")
        right_column.pack(side="right", fill="both", expand=True, padx=(12, 0))

        logo_frame = ctk.CTkFrame(left_column, fg_color="transparent")
        logo_frame.pack(fill="x", pady=(0, 6))
        
        ctk.CTkLabel(
            logo_frame, text="🎬  ClipAI | كليب آي",
            font=ctk.CTkFont(family="SF Pro Display", size=24, weight="bold"),
        ).pack(anchor="w")
        
        ctk.CTkLabel(
            logo_frame, text="حول الفيديوهات الطويلة إلى مقاطع فيروسية قصيرة جذابة — 100% بدون إنترنت",
            font=ctk.CTkFont(family="SF Pro Text", size=12), text_color=TEXT_DIM,
        ).pack(anchor="w", pady=(1, 0))

        self._sidebar_body = ctk.CTkScrollableFrame(left_column, fg_color="transparent", label_text="", border_width=0)
        self._sidebar_body.pack(fill="both", expand=True, pady=(0, 4))

        # CARD 1: Video Input
        card1 = ctk.CTkFrame(self._sidebar_body, corner_radius=12, fg_color=("#FFFFFF", "#1C1C1E"), border_width=0)
        card1.pack(fill="x", pady=(0, 14), padx=2)

        self._drop_frame = ctk.CTkFrame(card1, height=90, corner_radius=10, fg_color=("#F2F2F7", "#121212"), border_width=0)
        self._drop_frame.pack(fill="x", padx=12, pady=12)
        self._drop_frame.pack_propagate(False)

        drop_inner = ctk.CTkFrame(self._drop_frame, fg_color="transparent")
        drop_inner.place(relx=0.5, rely=0.5, anchor="center")

        self._drop_icon  = ctk.CTkLabel(drop_inner, text="📂", font=ctk.CTkFont(size=20))
        self._drop_icon.pack()
        self._drop_label = ctk.CTkLabel(
            drop_inner, text="اسحب الفيديو وأسقطه هنا أو اضغط للاستعراض",
            font=ctk.CTkFont(family="SF Pro Text", size=13, weight="bold"),
        )
        self._drop_label.pack(pady=(1, 0))
        self._drop_hint = ctk.CTkLabel(
            drop_inner, text="صيغ المدعومة: MP4 · MOV · AVI · MKV",
            font=ctk.CTkFont(family="SF Pro Text", size=11), text_color=TEXT_DIM,
        )
        self._drop_hint.pack()

        for w in [self._drop_frame, drop_inner, self._drop_icon, self._drop_label, self._drop_hint]:
            w.bind("<Button-1>", self._browse_video)

        if DND_AVAILABLE:
            try:
                self._drop_frame.drop_target_register(DND_FILES)
                self._drop_frame.dnd_bind("<<Drop>>", self._on_drop)
            except Exception:
                pass

        yt_section = ctk.CTkFrame(card1, fg_color="transparent")
        yt_section.pack(fill="x", padx=12, pady=(0, 14))

        ctk.CTkLabel(
            yt_section, text="🔗 YouTube URL (رابط يوتيوب):",
            font=ctk.CTkFont(family="SF Pro Text", size=13, weight="bold"),
        ).pack(anchor="w", pady=(0, 3))

        self._yt_url_entry = ctk.CTkEntry(
            yt_section, placeholder_text="https://www.youtube.com/watch?v=...",
            height=30, corner_radius=8,
            fg_color=("#F2F2F7", "#121212"),
            border_width=0,
            text_color=("#000000", "#FFFFFF"),
            placeholder_text_color=("#8E8E93", "#AEAEB2"),
        )
        self._yt_url_entry.pack(fill="x", pady=(0, 10))

        yt_btns = ctk.CTkFrame(yt_section, fg_color="transparent")
        yt_btns.pack(fill="x")

        self._yt_login_btn = ctk.CTkButton(
            yt_btns, text="🔑 دخول", width=74, height=30, corner_radius=8,
            fg_color="#D97706", hover_color="#B45309",
            font=ctk.CTkFont(family="SF Pro Text", size=12, weight="bold"),
            command=self._on_youtube_login,
        )
        self._yt_login_btn.pack(side="left")

        self._yt_download_btn = ctk.CTkButton(
            yt_btns, text="تحميل الفيديو", height=30, corner_radius=8,
            fg_color=ACCENT, hover_color=ACCENT_HOVER,
            font=ctk.CTkFont(family="SF Pro Text", size=12, weight="bold"),
            command=self._on_youtube_download,
        )
        self._yt_download_btn.pack(side="right", fill="x", expand=True, padx=(6, 0))
        self._update_login_btn_state()

        # Campaign Frame
        self._campaign_frame = ctk.CTkFrame(self._sidebar_body, corner_radius=12, fg_color=("#F5F3FF", "#1E1B4B"), border_width=0)
        self._build_campaign_section()
        if self._campaign_active:
            self._campaign_frame.pack(fill="x", padx=1, pady=(0, 8))

        # CARD 2: Settings
        card2 = ctk.CTkFrame(self._sidebar_body, corner_radius=12, fg_color=("#FFFFFF", "#1C1C1E"), border_width=0)
        card2.pack(fill="x", pady=(0, 14), padx=2)

        ctk.CTkLabel(
            card2, text="إعدادات المقاطع المطلوبة",
            font=ctk.CTkFont(family="SF Pro Display", size=15, weight="bold"),
        ).pack(anchor="w", padx=12, pady=(14, 10))

        # Clips slider
        r1 = ctk.CTkFrame(card2, fg_color="transparent")
        r1.pack(fill="x", padx=12, pady=(0, 10))
        lbl_r1 = ctk.CTkFrame(r1, fg_color="transparent")
        lbl_r1.pack(fill="x")
        ctk.CTkLabel(lbl_r1, text="عدد المقاطع المطلوب استخراجها", font=ctk.CTkFont(size=13, weight="bold"), anchor="w").pack(side="left")
        self._clips_val = ctk.CTkLabel(lbl_r1, text="5", font=ctk.CTkFont(size=13, weight="bold"), text_color=ACCENT)
        self._clips_val.pack(side="right")
        self._clips_slider = ctk.CTkSlider(r1, from_=1, to=10, number_of_steps=9, command=self._on_clips_change, height=12)
        self._clips_slider.pack(fill="x")

        # Duration slider
        r2 = ctk.CTkFrame(card2, fg_color="transparent")
        r2.pack(fill="x", padx=12, pady=(0, 10))
        lbl_r2 = ctk.CTkFrame(r2, fg_color="transparent")
        lbl_r2.pack(fill="x")
        ctk.CTkLabel(lbl_r2, text="مدة كل مقطع مستهدفة (ثانية)", font=ctk.CTkFont(size=13, weight="bold"), anchor="w").pack(side="left")
        self._dur_val = ctk.CTkLabel(lbl_r2, text="60s", font=ctk.CTkFont(size=13, weight="bold"), text_color=ACCENT)
        self._dur_val.pack(side="right")
        self._dur_slider = ctk.CTkSlider(r2, from_=15, to=120, number_of_steps=21, command=self._on_dur_change, height=12)
        self._dur_slider.pack(fill="x")

        ai_badge = ctk.CTkFrame(card2, fg_color=("#EEF2FF", "#1E1B4B"), corner_radius=8)
        ai_badge.pack(fill="x", padx=12, pady=(0, 14))
        ctk.CTkLabel(
            ai_badge,
            text="🤖  AI يتحكم في كل شيء تلقائياً\nالـ Framing · الـ Effects · الـ Hook · الـ B-Roll",
            font=ctk.CTkFont(size=12), text_color=("#6366F1", "#A5B4FC"), justify="center",
        ).pack(padx=10, pady=8)

        style_row = ctk.CTkFrame(card2, fg_color="transparent")
        style_row.pack(fill="x", padx=12, pady=(0, 14))
        ctk.CTkLabel(style_row, text="🎨  ستايل النص (Subtitle Style):", font=ctk.CTkFont(size=13, weight="bold")).pack(anchor="w", pady=(0, 4))
        self._theme_option_var = ctk.StringVar(value=self._subtitle_style)
        self._theme_option_menu = ctk.CTkOptionMenu(style_row, values=["TikTok Yellow", "Cyberpunk Neon", "Minimalist Clean"], variable=self._theme_option_var, height=32)
        self._theme_option_menu.pack(fill="x")

        export_row = ctk.CTkFrame(card2, fg_color="transparent")
        export_row.pack(fill="x", padx=12, pady=(0, 10))
        ctk.CTkLabel(export_row, text="نظام التصدير", font=ctk.CTkFont(size=13, weight="bold")).pack(anchor="w", pady=(0, 4))
        self._export_mode_var = ctk.StringVar(value="FFmpeg (فيديو نهائي)")
        self._export_mode_menu = ctk.CTkOptionMenu(export_row, values=["FFmpeg (فيديو نهائي)", "DaVinci Resolve (ملف XML)"], variable=self._export_mode_var, height=32)
        self._export_mode_menu.pack(fill="x")

        # Hidden variables
        self._ai_mode_var              = ctk.BooleanVar(value=True)
        self._auto_director_var        = ctk.BooleanVar(value=True)
        self._trim_silence_var         = ctk.BooleanVar(value=True)
        self._scale_punches_var        = ctk.BooleanVar(value=True)
        self._sound_fx_var             = ctk.BooleanVar(value=True)
        self._hook_mode_var            = ctk.BooleanVar(value=True)
        self._compile_clips_var        = ctk.BooleanVar(value=True)
        self._translate_to_arabic_var  = ctk.BooleanVar(value=False)
        self._gemma_multimodal_var    = ctk.BooleanVar(value=True)
        self._auto_broll_var           = ctk.BooleanVar(value=False)
        self._use_scene_captioning_var = ctk.BooleanVar(value=False)
        self._use_local_captioning_var = ctk.BooleanVar(value=False)
        self._framing_strategy_var     = ctk.StringVar(value="speaker_tracking")
        self._export_quality_var       = ctk.StringVar(value="High")
        self._sfx_mode_option_var      = ctk.StringVar(value="Auto/Normal (تلقائي)")
        self._font_name_var            = ctk.StringVar(value=self._font_name)
        self._logo_path_var            = ctk.StringVar(value=self._logo_path)

        instr_card = ctk.CTkFrame(card2, fg_color=("F2F2F7", "#1C1C1E"), corner_radius=8)
        instr_card.pack(fill="x", padx=12, pady=(0, 14))
        ctk.CTkLabel(instr_card, text="✍️  تعليقات خاصة للـ AI (Custom Instructions):", font=ctk.CTkFont(size=13, weight="bold")).pack(anchor="w", padx=10, pady=(8, 4))
        
        self._custom_instr_entry = ctk.CTkTextbox(instr_card, height=56, corner_radius=8, fg_color=("F2F2F7", "#121212"), text_color=("000000", "#FFFFFF"), wrap="word")
        self._custom_instr_entry.pack(fill="x", padx=10, pady=(0, 10))
        self._custom_instr_entry.insert("1.0", "حط لي مثلاً: 'اشتركوا' في الثلث الأوسط بخط كبير")
        self._custom_instr_entry.configure(text_color=("8E8E93", "#AEAEB2"))

        def _on_instr_focus(e):
            curr = self._custom_instr_entry.get("1.0", "end").strip()
            if curr.startswith("حط لي مثلاً"):
                self._custom_instr_entry.delete("1.0", "end")
                self._custom_instr_entry.configure(text_color=("000000", "#FFFFFF"))
        self._custom_instr_entry.bind("<FocusIn>", _on_instr_focus)

        self._model_var = ctk.StringVar(value="Gemma 4 31b (Offline)")
        self._pex_entry_var = ctk.StringVar(value=self._pexels_api_key)
        self._temp_entry_var = ctk.StringVar(value=self._temp_folder)
        self._fs_entry_var = ctk.StringVar(value="")

        class DummyWidget:
            def __init__(self, val_var): self.val_var = val_var
            def get(self): return self.val_var.get()
        self._pex_entry = DummyWidget(self._pex_entry_var)
        self._fs_entry = DummyWidget(self._fs_entry_var)
        self._temp_entry = DummyWidget(self._temp_entry_var)

        fixed_bottom = ctk.CTkFrame(left_column, fg_color="transparent")
        fixed_bottom.pack(fill="x", side="bottom", pady=(12, 6))

        self._generate_btn = ctk.CTkButton(
            fixed_bottom, text="⚡ استخراج المقاطع الفيروسية", height=42, corner_radius=10,
            font=ctk.CTkFont(family="SF Pro Display", size=16, weight="bold"),
            fg_color=ACCENT, hover_color=ACCENT_HOVER,
            command=self._on_generate,
        )
        self._generate_btn.pack(side="left", fill="x", expand=True)

        self._manual_trim_btn = ctk.CTkButton(
            fixed_bottom, text="✂️ قص يدوي", height=42, width=90, corner_radius=10,
            font=ctk.CTkFont(family="SF Pro Display", size=14, weight="bold"),
            fg_color="#0EA5E9", hover_color="#0284C7",
            command=self._on_manual_trim,
        )
        self._manual_trim_btn.pack(side="left", padx=(6, 0))

        self._cancel_btn = ctk.CTkButton(
            fixed_bottom, text="✕", width=40, height=42, corner_radius=10,
            font=ctk.CTkFont(family="SF Pro Display", size=16, weight="bold"),
            fg_color=("#E5E5EA", "#2C2C2E"), hover_color=("#D1D1D6", "#3A3A3C"),
            text_color=("#000000", "#FFFFFF"),
            command=self._on_cancel,
        )
        self._cancel_btn.pack(side="right", padx=(6, 0))

        # Right Column
        top_bar = ctk.CTkFrame(right_column, fg_color="transparent")
        top_bar.pack(fill="x", pady=(0, 8))

        self._theme_btn = ctk.CTkButton(
            top_bar, text="☀️ مضيء", width=86, height=30, corner_radius=15,
            fg_color=("#FFFFFF", "#1C1C1E"), hover_color=ACCENT_HOVER,
            text_color=("#000000", "#FFFFFF"),
            font=ctk.CTkFont(size=13, weight="bold"), command=self._toggle_theme,
        )
        self._theme_btn.pack(side="right")

        self._settings_btn = ctk.CTkButton(
            top_bar, text="⚙️ الإعدادات", width=96, height=30, corner_radius=15,
            fg_color=("#FFFFFF", "#1C1C1E"), hover_color=ACCENT_HOVER,
            text_color=("#000000", "#FFFFFF"),
            font=ctk.CTkFont(size=13, weight="bold"),
            command=lambda: show_settings_popup(self),
        )
        self._settings_btn.pack(side="right", padx=(0, 8))

        ctk.CTkButton(
            top_bar, text="💡 دليل الإعدادات", width=120, height=30, corner_radius=15,
            fg_color=("#FFFFFF", "#1C1C1E"), hover_color=ACCENT_HOVER,
            text_color=("#000000", "#FFFFFF"),
            font=ctk.CTkFont(size=13, weight="bold"),
            command=lambda: show_tips_popup(self),
        ).pack(side="right", padx=(0, 8))

        # Progress dashboard
        prog_card = ctk.CTkFrame(right_column, corner_radius=14, fg_color=("#FFFFFF", "#1C1C1E"), border_width=0)
        prog_card.pack(fill="x", pady=(0, 10))

        self._progress_bar = ctk.CTkProgressBar(prog_card, height=4, corner_radius=2, progress_color=ACCENT, fg_color=("#F2F2F7", "#121212"))
        self._progress_bar.set(0)
        self._progress_bar.pack(fill="x", padx=16, pady=(12, 4))

        self._progress_label = ctk.CTkTextbox(prog_card, height=32, font=ctk.CTkFont(family="SF Pro Text", size=14), text_color=TEXT_DIM, fg_color="transparent", wrap="word")
        self._progress_label.bind("<Key>", lambda e: "break")
        self._progress_label.pack(fill="x", padx=12, pady=(0, 2))

        self._steps_frame = ctk.CTkFrame(prog_card, fg_color="transparent")
        self._steps_frame.pack(fill="x", padx=12, pady=(0, 12))
        self._steps_frame.grid_columnconfigure(0, weight=1)
        self._steps_frame.grid_columnconfigure(1, weight=1)
        
        self._step_widgets = {}
        steps_data = [
            (1, "🧠 Transcribe", "النسخ", 0, 0),
            (2, "🎯 AI Select", "التحديد", 0, 1),
            (3, "🎬 Viral FX", "المؤثرات", 1, 0),
            (4, "🎞️ Render", "المونتاج", 1, 1)
        ]
        
        for num, eng, arb, row, col in steps_data:
            step_card = ctk.CTkFrame(self._steps_frame, height=44, corner_radius=8, fg_color=("#F2F2F7", "#121212"), border_width=0)
            step_card.grid(row=row, column=col, padx=4, pady=4, sticky="nsew")
            step_card.pack_propagate(False)
            
            inner_card = ctk.CTkFrame(step_card, fg_color="transparent")
            inner_card.place(relx=0.5, rely=0.5, anchor="center")
            
            ind = ctk.CTkLabel(inner_card, text="○", font=ctk.CTkFont(size=15, weight="bold"), text_color=BORDER_IDLE)
            ind.pack(side="left", padx=(0, 6))
            
            lbl = ctk.CTkLabel(inner_card, text=f"{eng} ({arb})", font=ctk.CTkFont(family="SF Pro Text", size=14, weight="bold"), text_color=TEXT_DIM)
            lbl.pack(side="left")
            
            self._step_widgets[num] = (step_card, lbl, ind)

        results_wrapper = ctk.CTkFrame(right_column, fg_color="transparent", height=260)
        results_wrapper.pack(fill="both", expand=True, pady=(0, 10))
        results_wrapper.pack_propagate(False)

        results_header = ctk.CTkFrame(results_wrapper, fg_color="transparent")
        results_header.pack(fill="x")
        ctk.CTkLabel(results_header, text="المقاطع والنتائج المستخرجة", font=ctk.CTkFont(family="SF Pro Display", size=14, weight="bold"), text_color=ACCENT, anchor="w").pack(side="left")

        self._results_frame = ctk.CTkScrollableFrame(results_wrapper, corner_radius=14, fg_color=("#FFFFFF", "#1C1C1E"), border_width=0)
        self._results_frame.pack(fill="both", expand=True, pady=(0, 0))

        self._no_results_lbl = ctk.CTkLabel(self._results_frame, text="ستظهر المقاطع والنتائج هنا فور انتهاء معالجة الفيديو المميز", font=ctk.CTkFont(family="SF Pro Text", size=14), text_color=TEXT_DIM)
        self._no_results_lbl.pack(pady=34)

        ctk.CTkButton(
            results_wrapper, text="", width=28, height=24,
            image=get_copy_icon((14, 14), (142, 142, 147)),
            corner_radius=6,
            fg_color=("#E8E8ED", "#252527"), hover_color=("#DCDCE0", "#303032"),
            border_width=0, command=self._copy_results_output
        ).place(relx=0.96, rely=0.95, anchor="se")

        self._open_folder_btn = ctk.CTkButton(right_column, text="📁  فتح مجلد حفظ المقاطع", height=38, corner_radius=8, font=ctk.CTkFont(family="SF Pro Text", size=15, weight="bold"), fg_color=("#FFFFFF", "#1C1C1E"), text_color=("#000000", "#FFFFFF"), hover_color=("#F2F2F7", "#2C2C2E"), command=self._open_output_folder)
        self._open_folder_btn.pack_forget()

        self._yt_frame = ctk.CTkFrame(right_column, corner_radius=14, fg_color=("#FFFFFF", "#1C1C1E"), border_width=0)
        self._build_youtube_section()

        console_header = ctk.CTkFrame(right_column, fg_color="transparent")
        console_header.pack(fill="x", pady=(1, 1))
        
        ctk.CTkLabel(console_header, text="💻  Live Terminal Console (مخرجات النظام الحية)", font=ctk.CTkFont(family="SF Pro Display", size=14, weight="bold"), text_color=ACCENT, anchor="w").pack(side="left")
        
        self._console_box = ctk.CTkTextbox(right_column, height=90, corner_radius=10, font=ctk.CTkFont(family="Consolas", size=12), fg_color=("#FFFFFF", "#0A0A0C"), text_color=("#000000", "#30D158"), wrap="word", state="normal", border_width=0)
        self._console_box.bind("<Key>", lambda e: "break")
        self._console_box.pack(fill="x", pady=(0, 2))
        self._console_box.insert("1.0", "ClipAI Live Terminal initialized successfully. Ready to process...\n")

        ctk.CTkButton(
            self._console_box, text="", width=28, height=24,
            image=get_copy_icon((14, 14), (142, 142, 147)),
            corner_radius=6,
            fg_color=("#E8E8ED", "#1C1C1E"), hover_color=("#DCDCE0", "#28282A"),
            border_width=0, command=self._copy_console_output
        ).place(relx=0.96, rely=0.84, anchor="se")

        self._setup_paste_bindings(self._yt_url_entry)

    def _ui(self, func, *args):
        self.after(0, lambda: func(*args))

    def _set_processing(self, state: bool):
        self._processing = state
        if state:
            self._generate_btn.configure(state="disabled", text="⏳  Processing...", fg_color="#374151")
        else:
            self._generate_btn.configure(state="normal", text="⚡  Generate Clips", fg_color=ACCENT)

    def _set_progress(self, value: float, label: str = ""):
        self._target_progress = value
        self._last_progress_label = label
        
        lbl_lower = label.lower()
        if "transcribing" in lbl_lower or "whisper" in lbl_lower:
            self._update_pipeline_steps(active_step=1, success_steps=[])
        elif "selecting" in lbl_lower or "moment" in lbl_lower:
            self._update_pipeline_steps(active_step=2, success_steps=[1])
        elif "captions" in lbl_lower or "subtitle" in lbl_lower:
            self._update_pipeline_steps(active_step=3, success_steps=[1, 2])
        elif "rendering" in lbl_lower or "ffmpeg" in lbl_lower:
            self._update_pipeline_steps(active_step=4, success_steps=[1, 2, 3])
        elif "done!" in lbl_lower or value >= 0.99:
            self._update_pipeline_steps(active_step=0, success_steps=[1, 2, 3, 4])
        elif not self._processing and value == 0.0:
            self._update_pipeline_steps(active_step=0, success_steps=[])

        if not self._processing and value == 0.0:
            self._current_progress = 0.0
            self._progress_bar.set(0)
            self._progress_label.delete("1.0", "end")
            self._progress_label.insert("end", "0%")

    def _update_pipeline_steps(self, active_step: int, success_steps: list = None):
        if not hasattr(self, "_step_widgets") or not self._step_widgets:
            return
        if success_steps is None: success_steps = []
        for i in range(1, 5):
            widget, label, indicator = self._step_widgets[i]
            if i in success_steps:
                widget.configure(fg_color=("#E8F8F0", "#1C3D27"), border_color=("#30D158", "#30D158"))
                label.configure(text_color=("#065F46", "#30D158"))
                indicator.configure(text="●⏳", text_color=("#30D158", "#30D158"))
            elif i == active_step:
                widget.configure(fg_color=("#E3F2FD", "#0A2540"), border_color=("#0A84FF", "#0A84FF"))
                label.configure(text_color=("#0A84FF", "#0A84FF"))
                indicator.configure(text="○", text_color=("#0A84FF", "#0A84FF"))
            else:
                widget.configure(fg_color=("#F2F2F7", "#121212"), border_color=BORDER_IDLE)
                label.configure(text_color=TEXT_DIM)
                indicator.configure(text="○", text_color=BORDER_IDLE)

    def _start_progress_loop(self):
        def loop():
            if self._processing:
                diff = self._target_progress - self._current_progress
                if diff > 0.001:
                    step = max(0.001, diff * 0.08)
                    self._current_progress = min(self._target_progress, self._current_progress + step)
                else:
                    crawl_step = 0.00015 * (1.0 - self._current_progress)
                    self._current_progress = min(0.99, self._current_progress + crawl_step)
                
                self._progress_bar.set(self._current_progress)
                pct = int(self._current_progress * 100)
                text = f"{self._last_progress_label}  ({pct}%)" if self._last_progress_label else f"{pct}%"
                self._progress_label.delete("1.0", "end")
                self._progress_label.insert("end", text)
            else:
                if self._current_progress < self._target_progress:
                    diff = self._target_progress - self._current_progress
                    step = max(0.01, diff * 0.1)
                    self._current_progress = min(self._target_progress, self._current_progress + step)
                    self._progress_bar.set(self._current_progress)
                    pct = int(self._current_progress * 100)
                    text = f"{self._last_progress_label}  ({pct}%)" if self._last_progress_label else f"{pct}%"
                    self._progress_label.delete("1.0", "end")
                    self._progress_label.insert("end", text)
            self.after(50, loop)
        loop()

    def _toggle_theme(self):
        mode = ctk.get_appearance_mode()
        if mode == "Dark":
            ctk.set_appearance_mode("light")
            self._theme_btn.configure(text="🌙  مظلم")
        else:
            ctk.set_appearance_mode("dark")
            self._theme_btn.configure(text="☀️  مضيء")

    def _on_clips_change(self, v): self._clips_val.configure(text=str(int(v)))
    def _on_dur_change(self, v): self._dur_val.configure(text=f"{int(v)}s")

    def _browse_video(self, event=None):
        path = filedialog.askopenfilename(title="Select a video file", filetypes=[("Video files", "*.mp4 *.mov *.avi *.mkv *.webm *.flv"), ("All files", "*.*")])
        if path: self._set_video(path)

    def _on_drop(self, event):
        raw = event.data.strip()
        if raw.startswith("{") and raw.endswith("}"): raw = raw[1:-1]
        if os.path.isfile(raw): self._set_video(raw)

    def _set_video(self, path: str):
        self._video_path = path
        name = os.path.basename(path)
        self._drop_label.configure(text=f"📹  {name}", text_color=SUCCESS)
        self._drop_hint.configure(text="Click to choose a different file", text_color=TEXT_DIM)
        self._drop_icon.configure(text="✅")
        self._drop_frame.configure(border_color=BORDER_OK)

    def _flash_drop_error(self):
        self._drop_frame.configure(border_color=BORDER_ERR)
        self._drop_label.configure(text_color=ERROR_CLR, text="⚠️  Please select a video first")
        self.after(1000, self._reset_drop_error)

    def _reset_drop_error(self):
        self._drop_frame.configure(border_color=BORDER_IDLE)
        self._drop_label.configure(text_color=("black", "white"), text="Drop video here  or  click to Browse")

    def _open_output_folder(self):
        folder = self._output_dir or "./output"
        os.makedirs(folder, exist_ok=True)
        open_folder(folder)

    def _copy_console_output(self):
        try:
            self._copy_to_clipboard(self._console_box.get("1.0", "end-1c"))
        except Exception: pass

    def _copy_results_output(self):
        try:
            lines = []
            for child in self._results_frame.winfo_children():
                if isinstance(child, ctk.CTkLabel):
                    lines.append(child.cget("text"))
                elif hasattr(child, "winfo_children"):
                    for sub in child.winfo_children():
                        if isinstance(sub, ctk.CTkLabel):
                            lines.append(sub.cget("text"))
            self._copy_to_clipboard("\n".join(lines))
        except Exception: pass

    def _play_preview(self, path: str):
        if path and os.path.exists(path):
            try:
                CTkVideoPlayer(self, path)
            except Exception as e:
                abs_path = os.path.abspath(path)
                try:
                    if sys.platform == "win32": os.startfile(abs_path)
                    elif sys.platform == "darwin": subprocess.run(["open", abs_path], check=False)
                    else: subprocess.run(["xdg-open", abs_path], check=False)
                except Exception as ex:
                    messagebox.showerror("خطأ", f"تعذر تشغيل المعاينة المباشرة:\n{e}\nخطأ احتياطي: {ex}")
        else:
            messagebox.showwarning("الملف مفقود", "تعذر العثور على ملف المقطع الذي تم توليده.")

    def _on_manual_trim(self):
        if not self._video_path:
            self._flash_drop_error()
            return
        from manual_trimmer import open_manual_trimmer
        try:
            bounds = open_manual_trimmer(self, self._video_path)
            if bounds:
                self._manual_bounds = bounds
                start_str = fmt_time(bounds[0])
                end_str = fmt_time(bounds[1])
                messagebox.showinfo("تم التحديد", f"تم تحديد المقطع بنجاح!\nمن {start_str} إلى {end_str}\n\nاضغط على 'استخراج المقاطع' لإنشاء المقطع وتطبيق الذكاء الاصطناعي عليه.")
                self._clips_slider.set(1)
            else:
                self._manual_bounds = None
        except Exception as e:
            messagebox.showerror("خطأ", f"حدث خطأ أثناء فتح أداة القص: {e}")

    def _on_generate(self):
        if self._processing: return
        if not self._video_path:
            self._flash_drop_error()
            return

        self._save_ui_prefs()

        n_clips  = int(self._clips_slider.get())
        duration = int(self._dur_slider.get())
        out_dir  = self._output_dir
        
        theme_raw = self._theme_option_var.get()
        theme = "Cyberpunk" if "Cyberpunk" in theme_raw else "Minimalist" if "Minimalist" in theme_raw else "TikTok"

        self._cancel_flag = False
        self._clips_done      = 0
        self._generated_clips = []
        self._uploaded_urls   = {}
        self._upload_rows     = {}
        self._clear_results()
        self._set_progress(0, "Starting...")
        self._set_processing(True)

        threading.Thread(
            target=self._run_ai_pipeline,
            args=(self._video_path, n_clips, duration, out_dir, "", "", theme, self._manual_bounds),
            daemon=True,
        ).start()

    def _on_cancel(self):
        self._cancel_flag = True
        self._ui(self._set_progress, 0, "Cancelled")
        self._ui(self._set_processing, False)

    def _clear_results(self):
        for w in self._results_frame.winfo_children(): w.destroy()
        self._no_results_lbl = ctk.CTkLabel(self._results_frame, text="Processing...", font=ctk.CTkFont(size=14), text_color=TEXT_DIM)
        self._no_results_lbl.pack(pady=20)
        self._result_rows = {}
        self._open_folder_btn.pack_forget()
        self._yt_frame.pack_forget()
        for w in self._yt_rows_frame.winfo_children(): w.destroy()
        self._yt_placeholder = ctk.CTkLabel(self._yt_rows_frame, text="Upload status will appear here", font=ctk.CTkFont(size=13), text_color=TEXT_DIM)
        self._yt_placeholder.pack(pady=20)
        self._upload_rows = {}

    def _add_result_processing(self, index: int, start: float, end: float):
        if hasattr(self, "_no_results_lbl") and self._no_results_lbl.winfo_exists(): self._no_results_lbl.destroy()
        row = ctk.CTkFrame(self._results_frame, corner_radius=8, fg_color=("#F2F2F7", "#2C2C2E"), height=44)
        row.pack(fill="x", pady=(0, 5), padx=5)
        row.pack_propagate(False)
        inner = ctk.CTkFrame(row, fg_color="transparent")
        inner.place(relx=0.0, rely=0.5, anchor="w", x=10)
        icon = ctk.CTkLabel(inner, text="⏳", font=ctk.CTkFont(family="SF Pro Text", size=16), width=26)
        icon.pack(side="left")
        info = ctk.CTkLabel(inner, text=f"clip_{index}.mp4   {fmt_time(start)} → {fmt_time(end)}   processing...", font=ctk.CTkFont(family="SF Pro Text", size=13), text_color=TEXT_DIM)
        info.pack(side="left", padx=(5, 0))
        self._result_rows[index] = {"row": row, "icon": icon, "info": info, "path": None}

    def _mark_result_done(self, index: int, start: float, end: float, out_path: str):
        if index not in self._result_rows: return
        w = self._result_rows[index]
        w["row"].configure(fg_color=("#E8F8F0", "#1C3D27"))
        w["icon"].configure(text="✅")
        w["info"].configure(text=f"clip_{index}.mp4   {fmt_time(start)} → {fmt_time(end)}", text_color=SUCCESS)
        w["path"] = out_path
        self._generated_clips.append(out_path)

        preview_btn = ctk.CTkButton(w["row"], text="▶ Play Preview", width=95, height=24, corner_radius=6, font=ctk.CTkFont(family="SF Pro Text", size=12, weight="bold"), fg_color=ACCENT, text_color="#FFFFFF", hover_color=ACCENT_HOVER, command=lambda p=out_path: self._play_preview(p))
        preview_btn.place(relx=1.0, rely=0.5, anchor="e", x=-8)

    def _mark_result_error(self, index: int, msg: str):
        if index not in self._result_rows: return
        w = self._result_rows[index]
        w["row"].configure(fg_color=("#FEE2E2", "#450A0A"))
        w["icon"].configure(text="❌")
        w["info"].configure(text=f"clip_{index}.mp4  failed — {msg[:55]}", text_color=ERROR_CLR)

    def _add_error(self, msg: str):
        row = ctk.CTkFrame(self._results_frame, corner_radius=10, fg_color=("#FEE2E2", "#450A0A"), height=42)
        row.pack(fill="x", pady=(0, 5), padx=5)
        row.pack_propagate(False)
        ctk.CTkLabel(row, text=f"❌  {msg}", font=ctk.CTkFont(size=13), text_color=ERROR_CLR).place(relx=0.02, rely=0.5, anchor="w")

    def _show_post_generation_ui(self):
        self._open_folder_btn.pack(fill="x", padx=10, pady=(0, 8))
        self._yt_frame.pack(fill="x", padx=10, pady=(0, 12))

if __name__ == "__main__":
    app = ClipAIApp()
    app.mainloop()
