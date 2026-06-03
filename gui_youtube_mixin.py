# -*- coding: utf-8 -*-
import os
import datetime
import threading
import customtkinter as ctk
from tkinter import messagebox

from app_constants import TEXT_DIM, YT_RED, YT_RED_HOVER, SUCCESS, ERROR_CLR, BORDER_IDLE
from app_utils import open_folder
from downloader import download_youtube_video

try:
    import pyperclip
    PYPERCLIP_OK = True
except Exception:
    PYPERCLIP_OK = False

class YouTubeMixin:
    def _build_youtube_section(self):
        yt = self._yt_frame

        hdr = ctk.CTkFrame(yt, fg_color="transparent")
        hdr.pack(fill="x", padx=16, pady=(14, 6))

        ctk.CTkLabel(
            hdr, text="  يوتيوب | YouTube",
            font=ctk.CTkFont(size=17, weight="bold"),
            text_color=("#DC2626", "#FF6B6B"),
        ).pack(side="left")

        ctk.CTkLabel(
            hdr, text="رفع تلقائي بعد التوليد مباشراً",
            font=ctk.CTkFont(size=13), text_color=TEXT_DIM,
        ).pack(side="left", padx=(8, 0))

        priv_row = ctk.CTkFrame(yt, fg_color="transparent")
        priv_row.pack(fill="x", padx=16, pady=(0, 10))

        ctk.CTkLabel(
            priv_row, text="الخصوصية:", font=ctk.CTkFont(size=15), width=70, anchor="w",
        ).pack(side="left")

        self._privacy_var = ctk.StringVar(value="Private")
        self._privacy_seg = ctk.CTkSegmentedButton(
            priv_row,
            values=["Private", "Unlisted", "Public"],
            variable=self._privacy_var,
            font=ctk.CTkFont(size=14),
            selected_color=YT_RED,
            selected_hover_color=YT_RED_HOVER,
        )
        self._privacy_seg.pack(side="left", padx=(8, 0))

        self._upload_btn = ctk.CTkButton(
            yt, text="   رفع جميع المقاطع المميزة إلى يوتيوب",
            height=44, corner_radius=12,
            font=ctk.CTkFont(size=16, weight="bold"),
            fg_color=YT_RED, hover_color=YT_RED_HOVER,
            command=self._on_upload_all,
        )
        self._upload_btn.pack(padx=16, fill="x", pady=(0, 10))

        self._yt_rows_frame = ctk.CTkScrollableFrame(
            yt, corner_radius=10,
            fg_color=("#D1D5DB", "#111827"),
            label_text="", height=130,
        )
        self._yt_rows_frame.pack(padx=12, fill="x", pady=(0, 12))

        self._yt_placeholder = ctk.CTkLabel(
            self._yt_rows_frame,
            text="ستظهر تفاصيل وحالة الرفع إلى قناتك هنا",
            font=ctk.CTkFont(size=13), text_color=TEXT_DIM,
        )
        self._yt_placeholder.pack(pady=20)

    def _update_login_btn_state(self):
        app_dir = os.path.dirname(os.path.abspath(__file__))
        cookies_path = os.path.join(app_dir, "cookies.txt")
        if os.path.exists(cookies_path):
            self._yt_login_btn.configure(text="✅ متصل", fg_color="#10B981", hover_color="#059669")
        else:
            self._yt_login_btn.configure(text="🔑 دخول", fg_color="#D97706", hover_color="#B45309")

    def _on_youtube_login(self):
        if self._processing:
            return
        
        self._set_processing(True)
        self._set_progress(0, "Opening browser for login...")
        
        def login_thread():
            try:
                from youtube_login import login_and_save_cookies
                app_dir = os.path.dirname(os.path.abspath(__file__))
                cookies_path = os.path.join(app_dir, "cookies.txt")
                
                success = login_and_save_cookies(cookies_path)
                if success:
                    self._ui(self._set_progress, 1.0, "تم تسجيل الدخول إلى يوتيوب بنجاح!")
                    self._ui(self._update_login_btn_state)
                    self._ui(messagebox.showinfo, "تم بنجاح", "تم تسجيل الدخول إلى يوتيوب بنجاح تام!\nيمكنك الآن تحميل الفيديوهات المقيدة بالفئة العمرية أو الفيديوهات الخاصة.")
                else:
                    self._ui(self._set_progress, 0.0, "تم إلغاء تسجيل الدخول أو فشله.")
                    self._ui(messagebox.showwarning, "فشل تسجيل الدخول", "لم يتم العثور على ملفات تعريف الارتباط (Cookies). هل قمت بإغلاق المتصفح بسرعة كبيرة؟")
            except Exception as e:
                self._ui(self._add_error, f"Login failed: {e}")
                self._ui(messagebox.showerror, "خطأ في تسجيل الدخول", f"فشل تسجيل الدخول:\n{str(e)[:120]}")
            finally:
                self._ui(self._set_processing, False)
                self._ui(self.after, 3000, lambda: self._set_progress(0, ""))
                
        threading.Thread(target=login_thread, daemon=True).start()

    def _on_youtube_download(self):
        url = self._yt_url_entry.get().strip()
        if not url:
            messagebox.showwarning("تنبيه", "يرجى لصق رابط فيديو يوتيوب أولاً.")
            return

        if self._processing:
            return

        self._set_processing(True)
        self._yt_download_btn.configure(state="disabled", text="⏳ جاري التحميل...")
        self._set_progress(0.0, "جاري الاتصال بيوتيوب...")

        threading.Thread(
            target=self._run_youtube_download_thread,
            args=(url,),
            daemon=True,
        ).start()

    def _run_youtube_download_thread(self, url):
        try:
            out_dir = self._output_dir or "./output"
            dl_dir  = os.path.join(out_dir, "downloads")
            os.makedirs(dl_dir, exist_ok=True)

            def prog_cb(pct, status):
                self._ui(self._set_progress, pct / 100.0, f"YouTube: {status}")

            local_path = download_youtube_video(url, dl_dir, progress_callback=prog_cb)

            if local_path and os.path.exists(local_path):
                self._ui(self._set_video, local_path)
                self._ui(self._set_progress, 1.0, "تم تحميل فيديو يوتيوب بنجاح!")
                self._ui(messagebox.showinfo, "تم بنجاح", f"تم تحميل الفيديو بنجاح واحترافية:\n{os.path.basename(local_path)}")
            else:
                self._ui(self._set_progress, 0.0, "فشل التحميل.")
                self._ui(messagebox.showerror, "خطأ", "فشل تحميل الفيديو من يوتيوب. يرجى التحقق من صحة الرابط.")
        except Exception as e:
            self._ui(self._set_progress, 0.0, f"خطأ تحميل: {str(e)[:40]}")
            self._ui(messagebox.showerror, "خطأ في التحميل", f"حدث خطأ غير متوقع أثناء التحميل:\n{str(e)[:120]}")
        finally:
            self._ui(self._set_processing, False)
            self._ui(self._reset_download_btn)

    def _reset_download_btn(self):
        self._yt_download_btn.configure(state="normal", text="تحميل الفيديو")

    def _on_upload_all(self):
        if self._uploading:
            return

        try:
            import google.oauth2.credentials
            import googleapiclient.discovery
        except ImportError:
            messagebox.showerror(
                "حزم برمجية مفقودة",
                "حزم Google API غير مثبتة على جهازك.\n\n"
                "يرجى تشغيل الأمر التالي في سطر الأوامر لتثبيتها:\n  pip install google-auth-oauthlib google-api-python-client google-auth-httplib2",
            )
            return

        app_dir      = os.path.dirname(os.path.abspath(__file__))
        secrets_file = os.path.join(app_dir, "client_secrets.json")
        if not os.path.exists(secrets_file):
            from app_popups import show_secrets_popup
            show_secrets_popup(self, app_dir)
            return

        clips_to_upload = [p for p in self._generated_clips if p and os.path.isfile(p)]
        if not clips_to_upload:
            messagebox.showinfo("لا توجد مقاطع", "برجاء توليد المقاطع المميزة أولاً قبل محاولة الرفع.")
            return

        privacy = self._privacy_var.get()

        for w in self._yt_rows_frame.winfo_children():
            w.destroy()
        self._upload_rows = {}

        self._set_uploading(True)

        threading.Thread(
            target=self._run_upload_thread,
            args=(clips_to_upload, privacy),
            daemon=True,
        ).start()

    def _run_upload_thread(self, clips_paths: list, privacy: str):
        try:
            from uploader import upload_video
        except ImportError as e:
            self._ui(self._add_yt_error, "uploader.py not found or broken: " + str(e))
            self._ui(self._set_uploading, False)
            return

        total = len(clips_paths)

        for i, path in enumerate(clips_paths, 1):
            clip_name = os.path.basename(path)
            self._ui(self._add_yt_row_processing, i, clip_name)
            self._ui(self._update_upload_btn_text, f"Uploading... ({i}/{total})")

            base  = os.path.splitext(clip_name)[0]
            today = datetime.date.today().strftime("%Y-%m-%d")
            if self._campaign_active and self._campaign:
                title = f"{self._campaign.name} — {base} — {today}"
            else:
                title = f"{base} — {today}"

            try:
                url = upload_video(
                    file_path=path,
                    title=title,
                    privacy=privacy.lower(),
                    progress_cb=lambda pct, idx=i: self._ui(
                        self._update_yt_row_progress, idx, pct
                    ),
                )
                self._uploaded_urls[i] = url
                self._ui(self._mark_yt_row_done, i, clip_name, url)

            except FileNotFoundError as e:
                self._ui(self._mark_yt_row_error, i, clip_name, str(e))
            except ConnectionError as e:
                self._ui(self._mark_yt_row_error, i, clip_name,
                         "No internet / network error")
            except Exception as e:
                self._ui(self._mark_yt_row_error, i, clip_name, str(e)[:80])

        self._ui(self._set_uploading, False)
        self._ui(self._update_upload_btn_text, "  Upload All Clips to YouTube")

    def _set_uploading(self, state: bool):
        self._uploading = state
        if state:
            self._upload_btn.configure(state="disabled", fg_color="#991B1B")
        else:
            self._upload_btn.configure(state="normal", fg_color=YT_RED)

    def _update_upload_btn_text(self, text: str):
        self._upload_btn.configure(text=text)

    def _add_yt_row_processing(self, index: int, clip_name: str):
        if hasattr(self, "_yt_placeholder") and self._yt_placeholder.winfo_exists():
            self._yt_placeholder.destroy()

        row = ctk.CTkFrame(self._yt_rows_frame, corner_radius=8,
                           fg_color=("#D1D5DB", "#1F2937"), height=52)
        row.pack(fill="x", pady=(0, 4), padx=4)
        row.pack_propagate(False)

        inner = ctk.CTkFrame(row, fg_color="transparent")
        inner.pack(fill="x", padx=10, pady=6)

        top_row = ctk.CTkFrame(inner, fg_color="transparent")
        top_row.pack(fill="x")

        icon = ctk.CTkLabel(top_row, text="⏳", font=ctk.CTkFont(size=16), width=22)
        icon.pack(side="left")

        status = ctk.CTkLabel(
            top_row, text=f"{clip_name}  —  uploading...",
            font=ctk.CTkFont(size=13), text_color=TEXT_DIM,
        )
        status.pack(side="left", padx=(4, 0))

        prog_lbl = ctk.CTkLabel(
            inner, text="0%", font=ctk.CTkFont(size=12), text_color=TEXT_DIM,
        )
        prog_lbl.pack(anchor="w", padx=(26, 0))

        self._upload_rows[index] = {
            "row": row, "icon": icon, "status": status, "prog": prog_lbl,
        }

    def _update_yt_row_progress(self, index: int, pct: int):
        if index not in self._upload_rows:
            return
        self._upload_rows[index]["prog"].configure(text=f"{pct}%")
        self._upload_rows[index]["status"].configure(
            text=f"clip_{index}.mp4  —  uploading...  {pct}%")

    def _mark_yt_row_done(self, index: int, clip_name: str, url: str):
        if index not in self._upload_rows:
            return
        w = self._upload_rows[index]
        w["row"].configure(fg_color=("#FEF9C3", "#1C1917"))
        w["icon"].configure(text="✅")
        w["status"].configure(
            text=f"{clip_name}  →  {url}",
            text_color=("#065F46", "#A7F3D0"),
        )
        w["prog"].configure(text="")

        copy_btn = ctk.CTkButton(
            w["row"], text="Copy Link", width=80, height=22,
            corner_radius=6, font=ctk.CTkFont(size=12),
            fg_color=("#D1FAE5", "#064E3B"),
            text_color=("#065F46", "#A7F3D0"),
            hover_color=("#A7F3D0", "#047857"),
            command=lambda u=url: self._copy_to_clipboard(u),
        )
        copy_btn.place(relx=1.0, rely=0.5, anchor="e", x=-8)

    def _mark_yt_row_error(self, index: int, clip_name: str, msg: str):
        if index not in self._upload_rows:
            return
        w = self._upload_rows[index]
        w["row"].configure(fg_color=("#FEE2E2", "#450A0A"))
        w["icon"].configure(text="❌")
        w["status"].configure(
            text=f"{clip_name}  —  {msg[:60]}",
            text_color=ERROR_CLR,
        )
        w["prog"].configure(text="")

    def _add_yt_error(self, msg: str):
        row = ctk.CTkFrame(self._yt_rows_frame, corner_radius=8,
                           fg_color=("#FEE2E2", "#450A0A"), height=40)
        row.pack(fill="x", pady=(0, 4), padx=4)
        row.pack_propagate(False)
        ctk.CTkLabel(row, text=f"❌  {msg}", font=ctk.CTkFont(size=13),
                     text_color=ERROR_CLR).place(relx=0.02, rely=0.5, anchor="w")

    def _copy_to_clipboard(self, text: str):
        if PYPERCLIP_OK:
            try:
                pyperclip.copy(text)
                return
            except Exception:
                pass
        try:
            self.clipboard_clear()
            self.clipboard_append(text)
        except Exception:
            pass
