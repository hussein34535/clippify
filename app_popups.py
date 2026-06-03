# -*- coding: utf-8 -*-
"""
app_popups.py — All dialog popups, settings sheets, help tip windows, 
ConsoleRedirector, and the Video Player popup for ClipAI App.
"""

import os
import sys
import json
import datetime
import re
import cv2
from PIL import Image

import customtkinter as ctk
from tkinter import filedialog, messagebox

# Import constants and styling
from app_constants import (
    ACCENT, ACCENT_HOVER, SUCCESS, ERROR_CLR, YT_RED, YT_RED_HOVER,
    BORDER_IDLE, BORDER_OK, BORDER_ERR, TEXT_DIM, TIPS_TEXT, SECRETS_INSTRUCTIONS
)
from app_utils import open_folder, fmt_time


# ─────────────────────────────────────────────────────────────────────────────
#  Live stdout/stderr Redirector
# ─────────────────────────────────────────────────────────────────────────────
class ConsoleRedirector:
    def __init__(self, app, textbox):
        self.app = app
        self.textbox = textbox
        self.needs_timestamp = True
        
    def write(self, string):
        if not string:
            return
        try:
            if self.needs_timestamp and string not in ("\n", "\r") and not string.startswith("\r"):
                ts = datetime.datetime.now().strftime("%H:%M:%S")
                string = f"[{ts}] {string}"
            self.needs_timestamp = string.endswith("\n")
            
            self.app.after(0, lambda s=string: self._safe_write(s))
        except Exception:
            pass

    def flush(self):
        pass
            
    def _safe_write(self, string):
        try:
            if self.textbox.winfo_exists():
                self.textbox.insert("end", string)
                val = self.textbox.get("1.0", "end")
                if len(val) > 80000:
                    self.textbox.delete("1.0", "15000.0")
                self.textbox.see("end")
                
                # Dynamic Logical Progress Parsing!
                global_match = re.search(r"\[\d+/\d+\]\s+(.*?)\s+\((\d+)%\)", string)
                if global_match:
                    lbl = global_match.group(1).strip()
                    pct = int(global_match.group(2))
                    self.app._target_progress = pct / 100.0
                    self.app._last_progress_label = lbl

                whisper_match = re.search(r"\[WHISPER PROGRESS\]\s+(\d+)%", string)
                if whisper_match:
                    pct = int(whisper_match.group(1))
                    self.app._target_progress = min(0.20, pct / 100.0 * 0.20)
                    self.app._last_progress_label = f"🧠 Transcribing audio... {pct}%"
                    
                ffmpeg_match = re.search(r"\[FFMPEG PROGRESS\]\s+clip\s+(\d+):\s+(\d+)%", string)
                if ffmpeg_match:
                    clip_idx = int(ffmpeg_match.group(1))
                    pct = int(ffmpeg_match.group(2))
                    
                    try:
                        n_clips = int(int(self.app._clips_slider.get()))
                    except Exception:
                        n_clips = 1
                    per_clip = 0.50 / max(n_clips, 1)
                    
                    start_p = 0.40 + (clip_idx - 1) * per_clip
                    self.app._target_progress = min(0.99, start_p + per_clip * (pct / 100.0))
                    self.app._last_progress_label = f"🎞️⏳ Rendering clip {clip_idx}/{n_clips}... {pct}%"
        except Exception:
            pass


# ─────────────────────────────────────────────────────────────────────────────
#  Video Player Popup (Portrait phone-mockup player)
# ─────────────────────────────────────────────────────────────────────────────
class CTkVideoPlayer(ctk.CTkToplevel):
    def __init__(self, parent, video_path):
        super().__init__(parent)
        self.title("معاينة الفيديو | ClipAI Player")
        self.geometry("400x780")
        self.resizable(False, False)
        self.configure(fg_color=("#F2F2F7", "#121212"))
        
        self.transient(parent)
        self.grab_set()
        
        self.video_path = video_path
        
        self.cap = cv2.VideoCapture(video_path)
        self.fps = self.cap.get(cv2.CAP_PROP_FPS) or 30.0
        self.total_frames = int(self.cap.get(cv2.CAP_PROP_FRAME_COUNT)) or 100
        self.delay = int(1000 / self.fps)
        self.playing = True
        
        # Phone screen card
        self.screen_card = ctk.CTkFrame(self, corner_radius=16, fg_color="#000000", border_width=1, border_color="#2C2C2E")
        self.screen_card.pack(fill="both", expand=True, padx=15, pady=(15, 10))
        
        # Video frame label
        self.video_label = ctk.CTkLabel(self.screen_card, text="", width=360, height=640)
        self.video_label.pack(fill="both", expand=True)
        
        # Controls Frame
        self.controls = ctk.CTkFrame(self, fg_color="transparent")
        self.controls.pack(fill="x", padx=15, pady=(0, 15))
        
        # Play/Pause
        self.play_btn = ctk.CTkButton(
            self.controls, text="إيقاف مؤقت", width=90, height=30, corner_radius=8,
            font=ctk.CTkFont(size=12, weight="bold"), fg_color=ACCENT, text_color="#FFFFFF",
            hover_color=ACCENT_HOVER, command=self.toggle_play
        )
        self.play_btn.pack(side="left", padx=(0, 10))
        
        # Open in system player (with sound)
        self.sys_btn = ctk.CTkButton(
            self.controls, text="تشغيل بالصوت", width=140, height=30, corner_radius=8,
            font=ctk.CTkFont(size=12, weight="bold"), fg_color=SUCCESS, text_color="#FFFFFF",
            hover_color=("#28A745", "#218838"), command=self.play_in_system
        )
        self.sys_btn.pack(side="left")
        
        # Close button
        self.close_btn = ctk.CTkButton(
            self.controls, text="إغلاق", width=80, height=30, corner_radius=8,
            font=ctk.CTkFont(size=12, weight="bold"), fg_color=("#E5E5EA", "#2C2C2E"),
            text_color=("#000000", "#FFFFFF"), hover_color=("#D1D1D6", "#3A3A3C"),
            command=self.destroy
        )
        self.close_btn.pack(side="right")
        
        self.protocol("WM_DELETE_WINDOW", self.on_close)
        
        self.update_frame()
        
    def toggle_play(self):
        self.playing = not self.playing
        if self.playing:
            self.play_btn.configure(text="إيقاف مؤقت")
            self.update_frame()
        else:
            self.play_btn.configure(text="تشغيل")
            
    def play_in_system(self):
        open_folder(self.video_path)
            
    def update_frame(self):
        if not self.playing or not self.cap.isOpened():
            return
            
        ret, frame = self.cap.read()
        if not ret:
            # Loop video
            self.cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
            ret, frame = self.cap.read()
            
        if ret:
            # Convert BGR to RGB
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            img = Image.fromarray(rgb_frame)
            img = img.resize((360, 640), Image.Resampling.LANCZOS)
            
            ctk_img = ctk.CTkImage(light_image=img, dark_image=img, size=(360, 640))
            self.video_label.configure(image=ctk_img)
            self.video_label.image = ctk_img
            
        self.after(self.delay, self.update_frame)
        
    def on_close(self):
        self.playing = False
        if self.cap.isOpened():
            self.cap.release()
        self.destroy()


# ─────────────────────────────────────────────────────────────────────────────
#  Tips popup
# ─────────────────────────────────────────────────────────────────────────────
def show_tips_popup(parent=None):
    """Open a modal window with per-video-type settings guide."""
    win = ctk.CTkToplevel(parent)
    win.title("دليل إعدادات ClipAI")
    win.geometry("520x580")
    win.resizable(False, False)
    
    if parent:
        win.transient(parent)
        
    win.after(300, win.grab_set)
    win.after(300, win.focus_force)

    def on_close():
        try:
            win.grab_release()
        except Exception:
            pass
        win.destroy()
        if parent:
            try:
                parent.attributes("-alpha", 1.0)
                parent.focus_force()
                parent.deiconify()
            except Exception:
                pass

    win.protocol("WM_DELETE_WINDOW", on_close)

    ctk.CTkLabel(
        win,
        text="🎯 الإعدادات المثالية لكل نوع فيديو",
        font=ctk.CTkFont(size=18, weight="bold"),
    ).pack(pady=(18, 4))

    ctk.CTkLabel(
        win,
        text="يكتشف ClipAI قمم طاقة الصوت — ولكل نوع محتوى نمط ومميزات مختلفة لرفع جودة الفيديو",
        font=ctk.CTkFont(size=13),
        text_color=TEXT_DIM,
        wraplength=460,
    ).pack(pady=(0, 10))

    txt = ctk.CTkTextbox(
        win, width=470, height=440, corner_radius=10,
        font=ctk.CTkFont(size=14, family="Courier New"),
        wrap="word",
    )
    txt.insert("1.0", TIPS_TEXT)
    txt.configure(state="disabled")
    txt.pack(padx=20)

    ctk.CTkButton(
        win, text="حسناً، فهمت!", width=120, height=34,
        corner_radius=10, fg_color=ACCENT, hover_color=ACCENT_HOVER,
        command=on_close,
    ).pack(pady=12)


# ─────────────────────────────────────────────────────────────────────────────
#  Secrets Popup
# ─────────────────────────────────────────────────────────────────────────────
def show_secrets_popup(parent, app_dir: str):
    """Open a modal window with setup instructions."""
    win = ctk.CTkToplevel(parent)
    win.title("مطلوب إعداد يوتيوب")
    win.geometry("540x460")
    win.resizable(False, False)
    
    if parent:
        win.transient(parent)
        
    win.after(300, win.grab_set)
    win.after(300, win.focus_force)

    def on_close():
        try:
            win.grab_release()
        except Exception:
            pass
        win.destroy()
        if parent:
            try:
                parent.attributes("-alpha", 1.0)
                parent.focus_force()
                parent.deiconify()
            except Exception:
                pass

    win.protocol("WM_DELETE_WINDOW", on_close)

    ctk.CTkLabel(
        win,
        text="📋 إعداد واجهة يوتيوب (YouTube API)",
        font=ctk.CTkFont(size=20, weight="bold"),
    ).pack(pady=(20, 4))

    ctk.CTkLabel(
        win,
        text="ملف client_secrets.json غير موجود",
        font=ctk.CTkFont(size=14),
        text_color=ERROR_CLR,
    ).pack(pady=(0, 12))

    txt = ctk.CTkTextbox(win, width=490, height=240, corner_radius=10,
                         font=ctk.CTkFont(size=14, family="Courier New"))
    txt.insert("1.0", SECRETS_INSTRUCTIONS)
    txt.insert("end", f"\n         {app_dir}")
    txt.configure(state="disabled")
    txt.pack(padx=20)

    ctk.CTkLabel(
        win,
        text=" 8. أعد فتح ClipAI ← اضغط رفع ← سيفتح المتصفح لتسجيل الدخول بجوجل",
        font=ctk.CTkFont(size=14),
        wraplength=490,
        justify="right",
    ).pack(padx=20, pady=(8, 0), anchor="e")

    def open_console():
        import webbrowser
        webbrowser.open("https://console.cloud.google.com")

    row = ctk.CTkFrame(win, fg_color="transparent")
    row.pack(pady=16, fill="x", padx=20)

    ctk.CTkButton(
        row, text="فتح لوحة تحكم جوجل", width=200,
        fg_color=ACCENT, hover_color=ACCENT_HOVER,
        command=open_console,
    ).pack(side="right")

    ctk.CTkButton(
        row, text="إغلاق", width=100,
        fg_color=BORDER_IDLE, hover_color="#4B5563",
        command=on_close,
    ).pack(side="left")


# ─────────────────────────────────────────────────────────────────────────────
#  Settings Popup (tabbed general control panel)
# ─────────────────────────────────────────────────────────────────────────────
def show_settings_popup(parent):
    """Open a gorgeous tabbed modal window with settings for EVERYTHING."""
    win = ctk.CTkToplevel(parent)
    win.title("⚙️ إعدادات ClipAI")
    win.geometry("560x580")
    win.resizable(False, False)
    
    if parent:
        win.transient(parent)
        
    win.after(300, win.grab_set)
    win.after(300, win.focus_force)

    def on_close():
        try:
            win.grab_release()
        except Exception:
            pass
        win.destroy()
        if parent:
            try:
                parent.attributes("-alpha", 1.0)
                parent.focus_force()
            except Exception:
                pass

    win.protocol("WM_DELETE_WINDOW", on_close)

    # Tabview for layout
    tabview = ctk.CTkTabview(win, width=520, height=485, corner_radius=12)
    tabview.pack(padx=20, pady=(10, 10), fill="both", expand=True)
    
    tabview.add("⚙️ عام")
    tabview.add("🔥 تأثيرات الانتشار")
    tabview.add("💻 النظام")

    # ── TAB 1: General Settings ──────────────────────────────────────
    t1 = tabview.tab("⚙️ عام")
    
    r1 = ctk.CTkFrame(t1, fg_color="transparent")
    r1.pack(fill="x", pady=10, padx=10)
    lbl_r1 = ctk.CTkFrame(r1, fg_color="transparent")
    lbl_r1.pack(fill="x")
    ctk.CTkLabel(lbl_r1, text="عدد المقاطع:", font=ctk.CTkFont(size=12, weight="bold")).pack(side="right")
    clips_val_lbl = ctk.CTkLabel(lbl_r1, text=str(parent._n_clips), font=ctk.CTkFont(size=12, weight="bold"), text_color=ACCENT)
    clips_val_lbl.pack(side="left")
    
    def on_clips_slider(v):
        clips_val_lbl.configure(text=str(int(v)))
    clips_slider = ctk.CTkSlider(r1, from_=1, to=10, number_of_steps=9, command=on_clips_slider, height=12)
    clips_slider.set(parent._n_clips)
    clips_slider.pack(fill="x", pady=(4, 0))

    r2 = ctk.CTkFrame(t1, fg_color="transparent")
    r2.pack(fill="x", pady=10, padx=10)
    lbl_r2 = ctk.CTkFrame(r2, fg_color="transparent")
    lbl_r2.pack(fill="x")
    ctk.CTkLabel(lbl_r2, text="مدة المقطع المستهدفة (ثانية):", font=ctk.CTkFont(size=12, weight="bold")).pack(side="right")
    dur_val_lbl = ctk.CTkLabel(lbl_r2, text=f"{parent._duration}s", font=ctk.CTkFont(size=12, weight="bold"), text_color=ACCENT)
    dur_val_lbl.pack(side="left")
    
    def on_dur_slider(v):
        dur_val_lbl.configure(text=f"{int(v)}s")
    dur_slider = ctk.CTkSlider(r2, from_=15, to=120, number_of_steps=21, command=on_dur_slider, height=12)
    dur_slider.set(parent._duration)
    dur_slider.pack(fill="x", pady=(4, 0))

    # Output dir row
    out_row = ctk.CTkFrame(t1, fg_color="transparent")
    out_row.pack(fill="x", pady=12, padx=10)
    ctk.CTkLabel(out_row, text="مجلد حفظ النتائج:", font=ctk.CTkFont(size=12, weight="bold")).pack(anchor="e")
    
    out_inner = ctk.CTkFrame(out_row, fg_color="transparent")
    out_inner.pack(fill="x", pady=4)
    out_entry_var = ctk.StringVar(value=parent._output_dir)
    out_entry = ctk.CTkEntry(out_inner, textvariable=out_entry_var, height=30, corner_radius=8, fg_color=("#F2F2F7", "#121212"), border_width=0)
    out_entry.pack(side="left", fill="x", expand=True, padx=(0, 6))
    
    def browse_out():
        path = filedialog.askdirectory(title="اختر مجلد الحفظ")
        if path:
            out_entry_var.set(path)
    ctk.CTkButton(out_inner, text="استعراض", width=70, height=30, corner_radius=8, command=browse_out).pack(side="right")

    # ── TAB 2: Viral FX Settings ─────────────────────────────────────
    t2 = tabview.tab("🔥 تأثيرات الانتشار")
    
    # Simple checkbox grid
    fx_grid = ctk.CTkFrame(t2, fg_color="transparent")
    fx_grid.pack(fill="x", pady=10, padx=10)
    for c in range(2):
        fx_grid.grid_columnconfigure(c, weight=1)

    chk_vars = {}
    
    def add_chk(label, key, val, row, col):
        var = ctk.BooleanVar(value=val)
        chk = ctk.CTkCheckBox(
            fx_grid, text=label, variable=var, font=ctk.CTkFont(size=12),
            fg_color=ACCENT, hover_color=ACCENT_HOVER, border_width=1, border_color=BORDER_IDLE
        )
        chk.grid(row=row, column=col, padx=5, pady=8, sticky="w")
        chk_vars[key] = var

    add_chk("المخرج الآلي الذكي", "auto_director", parent._auto_director, 0, 0)
    add_chk("قص الفترات الصامتة تلقائياً", "trim_silence", parent._trim_silence, 0, 1)
    add_chk("التركيز التلقائي والزوم الذكي", "scale_punches", parent._scale_punches, 1, 0)
    add_chk("صناعة مقطع تشويقي جذاب (Hook)", "hook_mode", parent._hook_mode, 1, 1)
    add_chk("تجميع اللقطات المميزة في فيديو واحد", "compile_clips", parent._compile_clips, 2, 0)
    add_chk("ترجمة الكلمات والنصوص للعربية", "translate_to_arabic", parent._translate_to_arabic, 2, 1)
    
    # ── TAB 3: System Settings ───────────────────────────────────────
    t3 = tabview.tab("💻 النظام")
    
    # Model option
    model_row = ctk.CTkFrame(t3, fg_color="transparent")
    model_row.pack(fill="x", pady=10, padx=10)
    ctk.CTkLabel(model_row, text="نموذج الذكاء الاصطناعي:", font=ctk.CTkFont(size=12, weight="bold")).pack(side="right")
    model_var = ctk.StringVar(value=parent._ai_engine_model)
    model_menu = ctk.CTkOptionMenu(model_row, values=["Gemma 4 31b (بدون إنترنت)", "Gemma 3.5 Flash (عبر الإنترنت)"], variable=model_var, height=28, font=ctk.CTkFont(size=12))
    model_menu.pack(side="left")

    # API Keys (Pexels, Freesound)
    pex_row = ctk.CTkFrame(t3, fg_color="transparent")
    pex_row.pack(fill="x", pady=10, padx=10)
    ctk.CTkLabel(pex_row, text="مفتاح Pexels للفيديوهات التعبيرية:", font=ctk.CTkFont(size=12, weight="bold")).pack(anchor="e")
    pex_entry_var = ctk.StringVar(value=parent._pexels_api_key)
    pex_entry = ctk.CTkEntry(pex_row, textvariable=pex_entry_var, placeholder_text="أدخل المفتاح المجاني الخاص بك هنا...", height=30, show="*", fg_color=("#F2F2F7", "#121212"), border_width=0)
    pex_entry.pack(fill="x", pady=4)

    fs_row = ctk.CTkFrame(t3, fg_color="transparent")
    fs_row.pack(fill="x", pady=10, padx=10)
    ctk.CTkLabel(fs_row, text="مفتاح Freesound.org للمؤثرات الصوتية:", font=ctk.CTkFont(size=12, weight="bold")).pack(anchor="e")
    
    try:
        from freesound_client import get_api_key as _get_fs_key
        current_fs_key = _get_fs_key() or ""
    except Exception:
        current_fs_key = ""
        
    fs_entry_var = ctk.StringVar(value=current_fs_key)
    fs_entry = ctk.CTkEntry(fs_row, textvariable=fs_entry_var, placeholder_text="أدخل المفتاح الخاص بك هنا...", height=30, show="*", fg_color=("#F2F2F7", "#121212"), border_width=0)
    fs_entry.pack(fill="x", pady=4)

    # Save Settings action
    def save_settings():
        parent._n_clips = int(clips_slider.get())
        parent._duration = int(dur_slider.get())
        parent._output_dir = out_entry_var.get().strip()
        parent._ai_engine_model = model_var.get()
        parent._pexels_api_key = pex_entry_var.get().strip()
        
        # Save Pexels Key to file
        pex_key_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pexels_key.txt")
        try:
            with open(pex_key_path, "w") as f:
                f.write(parent._pexels_api_key)
        except Exception:
            pass

        # Save Freesound Key to file
        fs_key = fs_entry_var.get().strip()
        if fs_key:
            fs_key_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "freesound_key.txt")
            try:
                with open(fs_key_path, "w") as f:
                    f.write(fs_key)
                import freesound_client
                freesound_client.set_api_key(fs_key)
            except Exception as e:
                print(f"[Settings] Failed to save Freesound key: {e}")

        # Sync checkboxes values
        parent._auto_director = chk_vars["auto_director"].get()
        parent._trim_silence = chk_vars["trim_silence"].get()
        parent._scale_punches = chk_vars["scale_punches"].get()
        parent._hook_mode = chk_vars["hook_mode"].get()
        parent._compile_clips = chk_vars["compile_clips"].get()
        parent._translate_to_arabic = chk_vars["translate_to_arabic"].get()

        # Update variable state and GUI elements
        try:
            parent._auto_director_var.set(parent._auto_director)
            parent._trim_silence_var.set(parent._trim_silence)
            parent._scale_punches_var.set(parent._scale_punches)
            parent._hook_mode_var.set(parent._hook_mode)
            parent._compile_clips_var.set(parent._compile_clips)
            parent._translate_to_arabic_var.set(parent._translate_to_arabic)
            
            parent._clips_slider.set(parent._n_clips)
            parent._clips_val.configure(text=str(parent._n_clips))
            parent._dur_slider.set(parent._duration)
            parent._dur_val.configure(text=f"{parent._duration}s")
        except Exception:
            pass
            
        on_close()

    ctk.CTkButton(
        win, text="حفظ وتطبيق الإعدادات", width=220, height=40,
        corner_radius=12, fg_color=ACCENT, hover_color=ACCENT_HOVER,
        font=ctk.CTkFont(size=13, weight="bold"),
        command=save_settings,
    ).pack(pady=(0, 15))
