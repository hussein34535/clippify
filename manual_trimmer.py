import os
import cv2
import customtkinter as ctk
from PIL import Image, ImageTk

class ManualTrimmerWindow(ctk.CTkToplevel):
    def __init__(self, master, video_path: str, **kwargs):
        super().__init__(master, **kwargs)
        self.title("Manual Video Trimmer ✂️")
        
        # Center the window
        window_width = 800
        window_height = 600
        screen_width = self.winfo_screenwidth()
        screen_height = self.winfo_screenheight()
        x = int((screen_width / 2) - (window_width / 2))
        y = int((screen_height / 2) - (window_height / 2))
        self.geometry(f"{window_width}x{window_height}+{x}+{y}")
        self.minsize(800, 600)
        self.configure(fg_color="#0F172A") # Deep elegant dark blue
        
        # Make it modal
        self.transient(master)
        self.grab_set()

        self.video_path = video_path
        self.result = None # Tuple (start, end)
        self.start_sec = 0.0
        self.end_sec = 10.0 # Default 10s clip
        
        # Load Video
        self.cap = cv2.VideoCapture(self.video_path)
        self.fps = self.cap.get(cv2.CAP_PROP_FPS) or 30.0
        self.total_frames = int(self.cap.get(cv2.CAP_PROP_FRAME_COUNT))
        self.total_duration = self.total_frames / self.fps if self.fps > 0 else 0.0
        self.end_sec = min(15.0, self.total_duration)
        
        # UI Layout
        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(0, weight=1)
        
        # ── Header ──
        header_frame = ctk.CTkFrame(self, fg_color="transparent")
        header_frame.grid(row=0, column=0, sticky="new", padx=20, pady=10)
        ctk.CTkLabel(header_frame, text="حدد نقطة البداية والنهاية للمقطع", font=("Inter", 20, "bold"), text_color="#F8FAFC").pack()
        
        # ── Video Preview Frame ──
        self.preview_frame = ctk.CTkFrame(self, fg_color="#1E293B", corner_radius=15)
        self.preview_frame.grid(row=1, column=0, sticky="nsew", padx=20, pady=10)
        self.grid_rowconfigure(1, weight=1)
        
        self.video_label = ctk.CTkLabel(self.preview_frame, text="", fg_color="transparent")
        self.video_label.pack(expand=True, fill="both", padx=10, pady=10)
        
        # ── Scrubbing Slider ──
        slider_frame = ctk.CTkFrame(self, fg_color="transparent")
        slider_frame.grid(row=2, column=0, sticky="ew", padx=20, pady=(0, 10))
        slider_frame.grid_columnconfigure(1, weight=1)
        
        self.time_lbl = ctk.CTkLabel(slider_frame, text="00:00", font=("Inter", 14), text_color="#94A3B8")
        self.time_lbl.grid(row=0, column=0, padx=(0, 10))
        
        self.scrub_slider = ctk.CTkSlider(slider_frame, from_=0, to=self.total_duration,
                                          progress_color="#3B82F6", button_color="#2563EB", button_hover_color="#1D4ED8")
        self.scrub_slider.set(0)
        self.scrub_slider.grid(row=0, column=1, sticky="ew")
        self.scrub_slider.bind("<B1-Motion>", self._on_scrub)
        self.scrub_slider.bind("<ButtonRelease-1>", self._on_scrub)
        
        self.total_lbl = ctk.CTkLabel(slider_frame, text=self._fmt_time(self.total_duration), font=("Inter", 14), text_color="#94A3B8")
        self.total_lbl.grid(row=0, column=2, padx=(10, 0))
        
        # ── Controls Frame ──
        controls_frame = ctk.CTkFrame(self, fg_color="transparent")
        controls_frame.grid(row=3, column=0, sticky="ew", padx=20, pady=(0, 20))
        controls_frame.grid_columnconfigure((0,1,2,3), weight=1)
        
        self.start_btn = ctk.CTkButton(controls_frame, text="تعيين البداية [ [", font=("Inter", 14, "bold"), fg_color="#334155", hover_color="#475569", command=self._mark_start)
        self.start_btn.grid(row=0, column=0, padx=5)
        
        self.start_lbl = ctk.CTkLabel(controls_frame, text=f"البداية: {self._fmt_time(self.start_sec)}", text_color="#10B981", font=("Inter", 14, "bold"))
        self.start_lbl.grid(row=0, column=1, padx=5)
        
        self.end_lbl = ctk.CTkLabel(controls_frame, text=f"النهاية: {self._fmt_time(self.end_sec)}", text_color="#EF4444", font=("Inter", 14, "bold"))
        self.end_lbl.grid(row=0, column=2, padx=5)
        
        self.end_btn = ctk.CTkButton(controls_frame, text="] ] تعيين النهاية", font=("Inter", 14, "bold"), fg_color="#334155", hover_color="#475569", command=self._mark_end)
        self.end_btn.grid(row=0, column=3, padx=5)
        
        # ── Footer ──
        footer = ctk.CTkFrame(self, fg_color="transparent")
        footer.grid(row=4, column=0, sticky="ew", padx=20, pady=(0, 20))
        footer.grid_columnconfigure(0, weight=1)
        
        confirm_btn = ctk.CTkButton(footer, text="✅ تأكيد المقطع", font=("Inter", 16, "bold"), fg_color="#3B82F6", hover_color="#2563EB", height=45, command=self._confirm)
        confirm_btn.grid(row=0, column=0, sticky="ew")

        # Initial render
        self._update_frame(0.0)
        
        # Handle close
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    def _fmt_time(self, sec: float) -> str:
        m = int(sec // 60)
        s = int(sec % 60)
        return f"{m:02d}:{s:02d}"

    def _on_scrub(self, event=None):
        t = self.scrub_slider.get()
        self.time_lbl.configure(text=self._fmt_time(t))
        self._update_frame(t)

    def _update_frame(self, t_sec: float):
        if not self.cap.isOpened():
            return
        # Set video position
        self.cap.set(cv2.CAP_PROP_POS_MSEC, t_sec * 1000.0)
        ret, frame = self.cap.read()
        if ret:
            # Resize frame to fit preview area while maintaining aspect ratio
            h, w = frame.shape[:2]
            max_w, max_h = 740, 400
            scale = min(max_w/w, max_h/h)
            new_w, new_h = int(w * scale), int(h * scale)
            
            frame = cv2.resize(frame, (new_w, new_h))
            frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            img = Image.fromarray(frame)
            ctk_img = ctk.CTkImage(light_image=img, dark_image=img, size=(new_w, new_h))
            self.video_label.configure(image=ctk_img)
            self.video_label.image = ctk_img

    def _mark_start(self):
        t = self.scrub_slider.get()
        if t >= self.end_sec:
            self.end_sec = min(self.total_duration, t + 10.0)
            self.end_lbl.configure(text=f"النهاية: {self._fmt_time(self.end_sec)}")
        self.start_sec = t
        self.start_lbl.configure(text=f"البداية: {self._fmt_time(self.start_sec)}")

    def _mark_end(self):
        t = self.scrub_slider.get()
        if t <= self.start_sec:
            self.start_sec = max(0.0, t - 10.0)
            self.start_lbl.configure(text=f"البداية: {self._fmt_time(self.start_sec)}")
        self.end_sec = t
        self.end_lbl.configure(text=f"النهاية: {self._fmt_time(self.end_sec)}")

    def _confirm(self):
        self.result = (self.start_sec, self.end_sec)
        self._on_close()

    def _on_close(self):
        if self.cap.isOpened():
            self.cap.release()
        self.destroy()

def open_manual_trimmer(master, video_path: str):
    """Opens the trimmer dialog and returns (start_sec, end_sec) or None if cancelled."""
    dialog = ManualTrimmerWindow(master, video_path)
    master.wait_window(dialog)
    return dialog.result
