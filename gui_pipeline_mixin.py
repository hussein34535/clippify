# -*- coding: utf-8 -*-
import os
import urllib.request
import threading
import customtkinter as ctk
from tkinter import messagebox

from app_constants import BORDER_IDLE, SUCCESS, ERROR_CLR, ACCENT, ACCENT_HOVER, TEXT_DIM
from models import EditingPlan, ClipSpec
from orchestrator import run_editing_plan, _find_hook_sentence
from campaign import generate_caption_file
from audio import get_words_in_range

class PipelineMixin:
    def _prepare_default_music(self) -> str:
        app_dir = os.path.dirname(os.path.abspath(__file__))
        music_dir = os.path.join(app_dir, "music")
        os.makedirs(music_dir, exist_ok=True)
        default_file = os.path.join(music_dir, "default_lofi.mp3")
        
        if os.path.exists(default_file) and os.path.getsize(default_file) > 100000:
            return default_file
            
        url = "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3"
        try:
            print(f"Downloading default background music from SoundHelix...")
            urllib.request.urlretrieve(url, default_file)
            print("Download complete!")
            return default_file
        except Exception as e:
            print(f"Could not download default music: {e}")
            return None

    def _get_custom_instructions(self) -> str:
        try:
            text = self._custom_instr_entry.get("1.0", "end").strip()
            if text.startswith("حط لي مثلا"):
                return ""
            return text
        except Exception:
            return ""

    def _run_ai_pipeline(self, video_path, n_clips, duration, out_dir,
                          music_path="", ending_cta="", theme="TikTok", manual_bounds=None):
        try:
            os.makedirs(out_dir, exist_ok=True)

            if not music_path or not os.path.exists(music_path):
                self._ui(self._set_progress, 0.02, "Preparing default music...")
                music_path = self._prepare_default_music()

            def status_update(msg):
                if self._cancel_flag:
                    raise Exception("Cancelled by user")
                import re
                m = re.search(r'\((\d+)%\)', msg)
                pct = int(m.group(1)) / 100.0 if m else 0.5
                self._ui(self._set_progress, pct, msg)

            gui_hook = self._hook_mode_var.get()
            gui_compile = self._compile_clips_var.get()
            gui_framing = self._framing_strategy_var.get()
            
            framing_map = {
                "Split Screen": "split_screen",
                "Active Speaker": "speaker_tracking",
                "No Crop": "no_crop"
            }
            framing_strategy = framing_map.get(gui_framing, "split_screen")
            font_name = self._font_name_var.get()
            export_quality = self._export_quality_var.get()
            logo_path = self._logo_path_var.get().strip()
            translate_to_arabic = self._translate_to_arabic_var.get()

            _sfx_map = {
                "Auto/Normal (تلقائي)": "normal",
                "Hook Only (الهوك فقط)": "hook_only",
                "Sparse (بسيط)": "sparse",
                "None (بدون مؤثرات)": "none",
            }
            sfx_mode_val = _sfx_map.get(self._sfx_mode_option_var.get(), "normal")

            self._gemma_multimodal = self._gemma_multimodal_var.get()
            self._auto_broll = self._auto_broll_var.get()
            self._use_scene_captioning = self._use_scene_captioning_var.get()
            self._use_local_captioning = self._use_local_captioning_var.get()
            self._pexels_api_key = self._pex_entry_var.get().strip()
            self._ai_engine_model = self._model_var.get()
            self._temp_folder = self._temp_entry_var.get().strip() or "./temp"
            
            if self._pexels_api_key:
                try:
                    pex_key_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pexels_key.txt")
                    with open(pex_key_path, "w") as f:
                        f.write(self._pexels_api_key)
                    os.environ["PEXELS_API_KEY"] = self._pexels_api_key
                except Exception:
                    pass
            
            fs_key = self._fs_entry_var.get().strip()
            if fs_key:
                try:
                    from freesound_client import save_api_key as _save_fs_key
                    _save_fs_key(fs_key)
                except Exception:
                    pass

            export_mode_val = "davinci" if "DaVinci" in self._export_mode_var.get() else "ffmpeg"

            plan = EditingPlan(
                video_path=video_path,
                n_clips=n_clips,
                duration_sec=duration,
                music_path=music_path,
                compile_clips=gui_compile,
                global_music=bool(music_path),
                global_ending_cta=ending_cta,
                content_type=self._content_type,
                custom_instructions=self._get_custom_instructions(),
                hook_mode=gui_hook,
                outro_enabled=True,
                framing_strategy=framing_strategy,
                font_name=font_name,
                export_quality=export_quality,
                logo_path=logo_path,
                translate_to_arabic=translate_to_arabic,
                caption_animation_mode=getattr(self, "_caption_animation_mode", "auto"),
                gemma_multimodal=self._gemma_multimodal,
                auto_broll=self._auto_broll,
                pexels_api_key=self._pexels_api_key,
                api_key=os.environ.get("GEMMA_API_KEY", ""),
                sfx_mode=sfx_mode_val,
                use_scene_captioning=self._use_scene_captioning,
                use_local_captioning=self._use_local_captioning,
                export_mode=export_mode_val,
                plan_review_callback=self._on_plan_review,
            )
            
            if manual_bounds:
                plan.manual_clip_bounds = manual_bounds

            sound_fx_on = self._sound_fx_var.get()
            clip_paths = run_editing_plan(plan, status_callback=status_update, sound_fx=sound_fx_on)

            if self._cancel_flag:
                return

            import shutil
            self._generated_clips = []
            for i, cp in enumerate(clip_paths):
                dest = os.path.join(out_dir, os.path.basename(cp))
                shutil.copy2(cp, dest)
                self._generated_clips.append(dest)

            self._ui(self._set_progress, 1.0, f"Done! {len(clip_paths)} files ready.")
            self._ui(self._show_post_generation_ui)
            
            self._ui(lambda: messagebox.showinfo("ClipAI - تم الانتهاء! 🎉", f"عاش يا بطل! 🚀\n\nتم الانتهاء من تجهيز الفيديوهات بنجاح ({len(clip_paths)} مقاطع).\nتقدر تشوفهم دلوقتي في مسار الحفظ اللي حددته."))

        except Exception as e:
            if "Cancelled" in str(e):
                self._ui(self._set_progress, 0, "Cancelled")
            else:
                self._ui(self._add_error, f"Orchestrator error: {e}")
        finally:
            self._ui(self._set_processing, False)

    def _on_plan_review(self, clips, words):
        event = threading.Event()
        selection = {"status": "pending"}
        self._ui(self._show_scenario_selector, clips, words, event, selection)
        event.wait()
        if selection["status"] != "approved":
            raise Exception("Cancelled by user")

    def _show_scenario_selector(self, clips, words, event, selection):
        win = ctk.CTkToplevel(self)
        win.title("💡 اختيار سيناريو وعنوان المقاطع بالذكاء الاصطناعي")
        win.geometry("740x580")
        win.resizable(False, False)
        win.transient(self)
        
        win.after(300, win.grab_set)
        win.after(300, win.focus_force)

        def on_close():
            selection["status"] = "cancelled"
            win.grab_release()
            win.destroy()
            event.set()

        win.protocol("WM_DELETE_WINDOW", on_close)

        ctk.CTkLabel(
            win,
            text="🧠  اختر عنوان وسيناريو المقاطع بالذكاء الاصطناعي",
            font=ctk.CTkFont(family="SF Pro Display", size=18, weight="bold"),
        ).pack(pady=(16, 4))

        ctk.CTkLabel(
            win,
            text="اختر لكل كليب أحد العناوين المقترحة أو اضغط 'شوف غيرهم' لتوليد بدائل جديدة ديناميكياً!",
            font=ctk.CTkFont(family="SF Pro Text", size=13),
            text_color=TEXT_DIM,
            wraplength=660,
        ).pack(pady=(0, 12))

        scroll = ctk.CTkScrollableFrame(win, width=680, height=380, corner_radius=12)
        scroll.pack(padx=20, pady=5, fill="both", expand=True)

        comboboxes = {}
        timing_vars = {}

        for clip in clips:
            card = ctk.CTkFrame(scroll, corner_radius=10, border_width=1, border_color=BORDER_IDLE)
            card.pack(fill="x", padx=10, pady=8)

            details_frame = ctk.CTkFrame(card, fg_color="transparent")
            details_frame.pack(fill="x", padx=12, pady=(8, 4))

            clip_lbl = ctk.CTkLabel(
                details_frame,
                text=f"موقع {clip.index:02d}  ·  التوقيت:",
                font=ctk.CTkFont(family="SF Pro Display", size=14, weight="bold"),
                text_color=ACCENT
            )
            clip_lbl.pack(side="left", padx=(0, 10))

            start_var = ctk.StringVar(value=f"{clip.start_sec:.1f}")
            end_var = ctk.StringVar(value=f"{clip.end_sec:.1f}")
            timing_vars[clip.index] = (start_var, end_var)

            start_entry = ctk.CTkEntry(
                details_frame, textvariable=start_var, width=50, height=28,
                justify="center", font=ctk.CTkFont(size=12)
            )
            start_entry.pack(side="left")

            ctk.CTkLabel(details_frame, text="s  -  ").pack(side="left")

            end_entry = ctk.CTkEntry(
                details_frame, textvariable=end_var, width=50, height=28,
                justify="center", font=ctk.CTkFont(size=12)
            )
            end_entry.pack(side="left")

            ctk.CTkLabel(details_frame, text="s").pack(side="left")

            plan_text = f"💡 الفكرة: {clip.reason}"
            viral_score = getattr(clip, "viral_score", 0.0)
            if viral_score and float(viral_score) > 0:
                plan_text += f"  |  🔥 نسبة الانتشار: {viral_score}"
            
            narrative_acts = getattr(clip, "narrative_acts", [])
            if narrative_acts:
                acts_str = " ➔ ".join([f"{act.get('name', 'Act')}" for act in narrative_acts])
                plan_text += f"\n📖 الحبكة الدرامية: {acts_str}"
                
            brolls = getattr(clip, "brolls", [])
            if brolls:
                plan_text += f"\n🎬 لقطات مساعدة (B-roll): {len(brolls)} لقطة"

            reason_lbl = ctk.CTkLabel(
                card,
                text=plan_text,
                font=ctk.CTkFont(family="SF Pro Text", size=12),
                text_color=TEXT_DIM,
                wraplength=620,
                justify="left"
            )
            reason_lbl.pack(fill="x", padx=12, pady=(0, 6), anchor="w")

            action_row = ctk.CTkFrame(card, fg_color="transparent")
            action_row.pack(fill="x", padx=12, pady=(0, 10))

            opt_var = ctk.StringVar(value=clip.hook_options[0] if clip.hook_options else "")
            
            options_frame = ctk.CTkFrame(action_row, fg_color="transparent")
            options_frame.pack(side="left", fill="x", expand=True, padx=(0, 8))

            if clip.hook_options:
                for opt in clip.hook_options:
                    rb = ctk.CTkRadioButton(
                        options_frame,
                        text=opt,
                        variable=opt_var,
                        value=opt,
                        font=ctk.CTkFont(size=13),
                        text_color="#FFFFFF"
                    )
                    rb.pack(anchor="w", pady=4, fill="x")

            comboboxes[clip.index] = opt_var

            def make_regenerate_callback(c_spec, o_frame, o_var):
                def regenerate_thread():
                    try:
                        self._ui(lambda: c_btn.configure(state="disabled", text="⏳ جاري التوليد..."))
                        c_words = [w["text"] for w in words if c_spec.start_sec <= w["start"] <= c_spec.end_sec]
                        c_text = " ".join(c_words)
                        if not c_text:
                            c_text = c_spec.reason or "Short clip"
                        
                        from orchestrator import generate_hook_alternatives
                        api_key = os.environ.get("GEMMA_API_KEY", "")
                        new_hooks = generate_hook_alternatives(c_text, self._content_type, api_key=api_key)
                        if new_hooks and len(new_hooks) >= 3:
                            c_spec.hook_options = new_hooks
                            
                            def update_ui():
                                for child in o_frame.winfo_children():
                                    child.destroy()
                                for opt in new_hooks:
                                    rb = ctk.CTkRadioButton(
                                        o_frame, text=opt, variable=o_var, value=opt,
                                        font=ctk.CTkFont(size=13), text_color="#FFFFFF"
                                    )
                                    rb.pack(anchor="w", pady=4, fill="x")
                                o_var.set(new_hooks[0])
                            
                            self._ui(update_ui)
                    except Exception as ex:
                        print(f"Error regenerating: {ex}")
                    finally:
                        self._ui(lambda: c_btn.configure(state="normal", text="شوف غيرهم"))
                
                return lambda: threading.Thread(target=regenerate_thread, daemon=True).start()

            c_btn = ctk.CTkButton(
                action_row,
                text="شوف غيرهم",
                width=110,
                height=32,
                corner_radius=8,
                fg_color=("#E5E5EA", "#2C2C2E"),
                hover_color=("#D1D1D6", "#3A3A3C"),
                text_color=("#000000", "#FFFFFF"),
            )
            c_btn.configure(command=make_regenerate_callback(clip, options_frame, opt_var))
            c_btn.pack(side="right")

        bottom_frame = ctk.CTkFrame(win, fg_color="transparent")
        bottom_frame.pack(fill="x", padx=20, pady=16, side="bottom")

        def on_approve():
            for clip in clips:
                chosen_opt = comboboxes[clip.index].get().strip()
                if chosen_opt:
                    clip.hook = chosen_opt
                    if clip.index == 1:
                        clip.hook_sentence = chosen_opt
                        import re
                        def norm_t(t): return re.sub(r"[.,!?;:()\"'«»\-أإآايىةه]", "", t.lower()).strip()
                        c_words = [w for w in words if clip.start_sec <= w["start"] <= clip.end_sec]
                        chosen_tokens = chosen_opt.split()
                        if chosen_tokens and c_words:
                            f_word = norm_t(chosen_tokens[0])
                            l_word = norm_t(chosen_tokens[-1])
                            new_start = clip.hook_sentence_start
                            new_end = clip.hook_sentence_end
                            found_start = False
                            for i, w in enumerate(c_words):
                                w_text = norm_t(w["text"])
                                if not found_start and len(f_word) > 1 and f_word in w_text:
                                    new_start = max(0.0, w["start"] - clip.start_sec)
                                    found_start = True
                                    for j in range(i, min(len(c_words), i + 20)):
                                        jw_text = norm_t(c_words[j]["text"])
                                        if len(l_word) > 1 and l_word in jw_text:
                                            new_end = max(new_start + 1.5, c_words[j]["end"] - clip.start_sec + 0.4)
                                            break
                                    break
                            
                            if found_start:
                                clip.hook_sentence_start = new_start
                                clip.hook_sentence_end = new_end
                
                start_str, end_str = timing_vars[clip.index]
                try:
                    new_start = float(start_str.get().strip())
                    new_end = float(end_str.get().strip())
                    if 0 <= new_start < new_end:
                        clip.start_sec = new_start
                        clip.end_sec = new_end
                except ValueError:
                    pass

            selection["status"] = "approved"
            win.grab_release()
            win.destroy()
            event.set()

        start_btn = ctk.CTkButton(
            bottom_frame,
            text="ابدأ المونتاج 🎬",
            height=38,
            corner_radius=10,
            fg_color=SUCCESS,
            hover_color=("#28A745", "#28A745"),
            font=ctk.CTkFont(family="SF Pro Display", size=14, weight="bold"),
            command=on_approve
        )
        start_btn.pack(side="left", fill="x", expand=True, padx=(0, 6))

        cancel_btn = ctk.CTkButton(
            bottom_frame,
            text="إلغاء ✕",
            height=38,
            corner_radius=10,
            fg_color=ERROR_CLR,
            hover_color=("#CC2D24", "#CC2D24"),
            font=ctk.CTkFont(family="SF Pro Display", size=14, weight="bold"),
            command=on_close
        )
        cancel_btn.pack(side="right", fill="x", expand=True, padx=(6, 0))

    def _run_pipeline(self, video_path, n_clips, duration, out_dir, trim_silence=False, scale_punches=False, music_path=None, ending_cta=None, theme="TikTok", auto_director=False):
        try:
            os.makedirs(out_dir, exist_ok=True)

            if not music_path or not os.path.exists(music_path):
                self._ui(self._set_progress, 0.05, "Preparing default lo-fi music...")
                music_path = self._prepare_default_music()

            self._ui(self._set_progress, 0.05, "Extracting audio & analyzing...")
            import ai_engine
            
            self._ui(self._set_progress, 0.15, "AI is transcribing the full video...")
            words = ai_engine.generate_subtitles(video_path)
            
            self._ui(self._set_progress, 0.50, "AI is selecting best clip moments...")
            
            vid_dur = None
            try:
                from moviepy import VideoFileClip as _VFC
                _t = _VFC(video_path); vid_dur = _t.duration; _t.close()
            except Exception:
                pass

            if vid_dur and vid_dur <= duration:
                clips = [{"start_sec": 0.0, "end_sec": vid_dur, "score": 1.0}]
            else:
                clips = ai_engine.find_semantic_clips(words, n_clips, duration)

            if not clips:
                self._ui(self._add_error, "No clip moments detected in this video.")
                self._ui(self._set_processing, False)
                return

            self._ui(self._set_progress, 0.60, f"{len(clips)} AI clip(s) selected")

            font_name = self._font_name_var.get()
            export_quality = self._export_quality_var.get()
            logo_path = self._logo_path_var.get().strip() or None
            translate_to_arabic = self._translate_to_arabic_var.get()

            _sfx_map = {
                "Auto/Normal (تلقائي)": "normal",
                "Hook Only (الهوك فقط)": "hook_only",
                "Sparse (بسيط)": "sparse",
                "None (بدون مؤثرات)": "none",
            }
            sfx_mode_val = _sfx_map.get(self._sfx_mode_option_var.get(), "normal")

            import concurrent.futures
            from concurrent.futures import ThreadPoolExecutor

            def render_fallback_task(i, clip):
                self._ui(self._add_result_processing, i,
                         clip["start_sec"], clip["end_sec"])

                out_path = os.path.join(out_dir, f"clip_{i}.mp4")
                try:
                    ass_path = os.path.join(out_dir, f"clip_{i}_subs.ass")
                    import ai_engine
                    from editor import export as export_clip
                    ai_engine.generate_ass_for_clip(
                        words,
                        clip["start_sec"],
                        clip["end_sec"],
                        ass_path,
                        theme=theme,
                        font_name=font_name,
                        translate_to_arabic=translate_to_arabic,
                        animation_mode=getattr(self, "_caption_animation_mode", "auto"),
                        content_type=self._content_type
                    )
                    
                    emphasis_timestamps = None
                    if auto_director:
                        emphasis_timestamps = ai_engine.get_emphasis_timestamps(words, clip["start_sec"], clip["end_sec"])
                    
                    export_clip(video_path=video_path,
                                start_sec=clip["start_sec"], end_sec=clip["end_sec"],
                                output_path=out_path, clip_index=i, ass_path=ass_path,
                                words=words, trim_silence=trim_silence,
                                scale_punches=scale_punches, music_path=music_path,
                                ending_cta=ending_cta,
                                theme=theme, auto_director=auto_director,
                                emphasis_timestamps=emphasis_timestamps,
                                sound_fx=self._sound_fx_var.get(),
                                sfx_mode=sfx_mode_val,
                                content_type=self._content_type,
                                export_quality=export_quality,
                                logo_path=logo_path)
                                
                    self._ui(self._mark_result_done, i,
                             clip["start_sec"], clip["end_sec"], out_path)
                    if self._campaign_active and self._campaign:
                        try:
                            dur_sec = clip["end_sec"] - clip["start_sec"]
                            generate_caption_file(
                                self._campaign, i, out_path, dur_sec
                            )
                        except Exception:
                            pass
                    self._clips_done += 1
                    if self._clips_done == 1:
                        self._ui(self._show_post_generation_ui)
                except Exception as e:
                    self._ui(self._mark_result_error, i, str(e))

            max_threads = min(os.cpu_count() or 4, len(clips), 3)
            per_clip = 0.40 / max(len(clips), 1)
            self._ui(self._set_progress, 0.65, f"Rendering {len(clips)} clips in parallel (10x speedup)...")
            
            with ThreadPoolExecutor(max_workers=max_threads) as executor:
                futures = [executor.submit(render_fallback_task, i, clip) for i, clip in enumerate(clips, 1)]
                concurrent.futures.wait(futures)

            final = min(0.60 + len(clips) * per_clip, 1.0)
            self._ui(self._set_progress, final,
                     f"Done! {self._clips_done}/{len(clips)} clips saved.")

        except Exception as e:
            self._ui(self._add_error, f"Pipeline error: {e}")
        finally:
            self._ui(self._set_processing, False)
