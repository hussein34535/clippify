# -*- coding: utf-8 -*-
import os
import datetime
import threading
import customtkinter as ctk
from tkinter import messagebox

from app_constants import BORDER_IDLE, BORDER_OK, BORDER_ERR, TEXT_DIM, ACCENT, ACCENT_HOVER
from campaign import Campaign, save_campaign, load_campaign, analyze_and_setup_campaign_from_text, generate_ai_captions, DEFAULT_CAPTIONS, GEMMA_API_KEY

class CampaignMixin:
    def _build_campaign_section(self):
        cf = self._campaign_frame
        c  = self._campaign or Campaign()

        hdr = ctk.CTkFrame(cf, fg_color="transparent")
        hdr.pack(fill="x", padx=14, pady=(12, 6))

        ctk.CTkLabel(
            hdr, text="  Campaign Mode",
            font=ctk.CTkFont(size=16, weight="bold"),
            text_color=("#5B21B6", "#C4B5FD"),
        ).pack(side="left")

        self._camp_toggle_btn = ctk.CTkButton(
            hdr,
            text="Disable" if self._campaign_active else "Enable",
            width=76, height=26, corner_radius=20,
            fg_color=("#7C3AED", "#4C1D95"),
            hover_color=("#6D28D9", "#3B0764"),
            font=ctk.CTkFont(size=13),
            command=self._toggle_campaign,
        )
        self._camp_toggle_btn.pack(side="right")

        self._camp_body = ctk.CTkFrame(cf, fg_color="transparent")
        if self._campaign_active:
            self._camp_body.pack(fill="x", padx=14, pady=(0, 10))

        body = self._camp_body

        n1 = ctk.CTkFrame(body, fg_color="transparent")
        n1.pack(fill="x", pady=(0, 6))
        ctk.CTkLabel(n1, text="Name:", font=ctk.CTkFont(size=14), width=70,
                     anchor="w").pack(side="left")
        self._camp_name_entry = ctk.CTkEntry(
            n1, height=30, corner_radius=8,
            placeholder_text="Campaign name",
            fg_color=("#FFFFFF", "#1E1E1E"),
            border_color=("#D1D1D6", "#2C2C2E"),
            text_color=("#000000", "#FFFFFF"),
            placeholder_text_color=("#8E8E93", "#AEAEB2"),
            border_width=1
        )
        self._camp_name_entry.insert(0, c.name)
        self._camp_name_entry.pack(side="left", fill="x", expand=True)

        n2 = ctk.CTkFrame(body, fg_color="transparent")
        n2.pack(fill="x", pady=(0, 6))
        ctk.CTkLabel(n2, text="Tag:", font=ctk.CTkFont(size=14), width=70,
                     anchor="w").pack(side="left")
        self._camp_handle_entry = ctk.CTkEntry(
            n2, height=30, corner_radius=8,
            placeholder_text="@handle",
            fg_color=("#FFFFFF", "#1E1E1E"),
            border_color=("#D1D1D6", "#2C2C2E"),
            text_color=("#000000", "#FFFFFF"),
            placeholder_text_color=("#8E8E93", "#AEAEB2"),
            border_width=1
        )
        self._camp_handle_entry.insert(0, c.handle)
        self._camp_handle_entry.pack(side="left", fill="x", expand=True)

        n3 = ctk.CTkFrame(body, fg_color="transparent")
        n3.pack(fill="x", pady=(0, 6))
        ctk.CTkLabel(n3, text="Type:", font=ctk.CTkFont(size=14), width=70,
                     anchor="w").pack(side="left")
        self._camp_type_var = ctk.StringVar(value=c.content_type)
        self._camp_type_seg = ctk.CTkSegmentedButton(
            n3,
            values=["YouTube", "Podcast", "Interview", "Gaming", "Custom"],
            variable=self._camp_type_var,
            font=ctk.CTkFont(size=13),
            selected_color="#7C3AED",
            selected_hover_color="#6D28D9",
            command=self._on_content_type_change,
        )
        self._camp_type_seg.pack(side="left", padx=(8, 0))

        n4 = ctk.CTkFrame(body, fg_color="transparent")
        n4.pack(fill="x", pady=(0, 8))
        ctk.CTkLabel(n4, text="Min dur:", font=ctk.CTkFont(size=14), width=70,
                     anchor="w").pack(side="left")
        self._camp_min_entry = ctk.CTkEntry(
            n4, height=30, width=60, corner_radius=8,
            fg_color=("#FFFFFF", "#1E1E1E"),
            border_color=("#D1D1D6", "#2C2C2E"),
            text_color=("#000000", "#FFFFFF"),
            placeholder_text_color=("#8E8E93", "#AEAEB2"),
            border_width=1
        )
        self._camp_min_entry.insert(0, str(c.min_duration))
        self._camp_min_entry.pack(side="left")
        ctk.CTkLabel(n4, text="seconds", font=ctk.CTkFont(size=13),
                     text_color=TEXT_DIM).pack(side="left", padx=(6, 0))

        ctk.CTkButton(
            n4, text="Save Campaign", width=110, height=28,
            corner_radius=8,
            fg_color="#7C3AED", hover_color="#6D28D9",
            font=ctk.CTkFont(size=13),
            command=self._save_campaign_from_ui,
        ).pack(side="right")

        auto_frame = ctk.CTkFrame(
            body, corner_radius=10,
            fg_color=("#FAF5FF", "#1E152A"),
            border_width=1, border_color="#A78BFA",
        )
        auto_frame.pack(fill="x", pady=(4, 6))

        auto_inner = ctk.CTkFrame(auto_frame, fg_color="transparent")
        auto_inner.pack(padx=10, pady=8, fill="x")

        ctk.CTkLabel(
            auto_inner, text="⚡  UGC Campaign AI Autopilot (الطيار الآلي للحملات)",
            font=ctk.CTkFont(size=14, weight="bold"),
            text_color="#8B5CF6",
        ).pack(anchor="w", pady=(0, 2))

        ctk.CTkLabel(
            auto_inner,
            text="Paste raw campaign requirements text (platforms, tags, rules, durations). The AI will instantly apply constraints & generate captions.",
            font=ctk.CTkFont(size=11),
            text_color=TEXT_DIM,
            justify="left",
            wraplength=480
        ).pack(anchor="w", pady=(0, 6))

        self._ai_autopilot_btn = ctk.CTkButton(
            auto_inner, text="Paste & Configure Campaign with AI 🚀", height=32, corner_radius=8,
            fg_color="#8B5CF6", hover_color="#7C3AED",
            font=ctk.CTkFont(size=13, weight="bold"),
            command=self._on_ai_campaign_paste,
        )
        self._ai_autopilot_btn.pack(fill="x")

        ai_frame = ctk.CTkFrame(
            body, corner_radius=10,
            fg_color=("#F3F4F6", "#111827"),
            border_width=1, border_color=ACCENT,
        )
        ai_frame.pack(fill="x", pady=(4, 10))

        ai_inner = ctk.CTkFrame(ai_frame, fg_color="transparent")
        ai_inner.pack(padx=10, pady=8, fill="x")

        ctk.CTkLabel(
            ai_inner, text="🤖  Gemma AI Assist (Gemma 4 31b)",
            font=ctk.CTkFont(size=14, weight="bold"),
            text_color=ACCENT,
        ).pack(anchor="w", pady=(0, 4))

        r_ai = ctk.CTkFrame(ai_inner, fg_color="transparent")
        r_ai.pack(fill="x")

        self._ai_topic_entry = ctk.CTkEntry(
            r_ai, placeholder_text="What is this video about? (e.g. real estate tips)",
            height=30, corner_radius=8,
            font=ctk.CTkFont(size=13),
            fg_color=("#FFFFFF", "#1E1E1E"),
            border_color=("#D1D1D6", "#2C2C2E"),
            text_color=("#000000", "#FFFFFF"),
            placeholder_text_color=("#8E8E93", "#AEAEB2"),
            border_width=1
        )
        self._ai_topic_entry.pack(side="left", fill="x", expand=True, padx=(0, 6))

        self._ai_generate_btn = ctk.CTkButton(
            r_ai, text="Generate Captions", width=120, height=30, corner_radius=8,
            fg_color=ACCENT, hover_color=ACCENT_HOVER,
            font=ctk.CTkFont(size=13, weight="bold"),
            command=self._on_ai_generate,
        )
        self._ai_generate_btn.pack(side="right")

        ctk.CTkLabel(
            body, text="Caption templates:",
            font=ctk.CTkFont(size=14), anchor="w",
        ).pack(fill="x", pady=(4, 2))

        self._caption_box = ctk.CTkTextbox(
            body, height=52, corner_radius=8,
            font=ctk.CTkFont(size=13, family="Segoe UI"),
            wrap="word",
        )
        self._caption_box.pack(fill="x", pady=(0, 4))
        self._refresh_caption_display()

        nav = ctk.CTkFrame(body, fg_color="transparent")
        nav.pack(fill="x")

        ctk.CTkButton(
            nav, text="←← Prev", width=60, height=26, corner_radius=8,
            fg_color=BORDER_IDLE, hover_color="#4B5563",
            font=ctk.CTkFont(size=13),
            command=self._caption_prev,
        ).pack(side="left")

        ctk.CTkButton(
            nav, text="Next →", width=60, height=26, corner_radius=8,
            fg_color=BORDER_IDLE, hover_color="#4B5563",
            font=ctk.CTkFont(size=13),
            command=self._caption_next,
        ).pack(side="left", padx=(6, 0))

        self._cap_counter_lbl = ctk.CTkLabel(
            nav, text="1 / ?", font=ctk.CTkFont(size=13), text_color=TEXT_DIM,
        )
        self._cap_counter_lbl.pack(side="left", padx=(10, 0))

        ctk.CTkButton(
            nav, text="Copy Caption", width=100, height=26, corner_radius=8,
            fg_color="#7C3AED", hover_color="#6D28D9",
            font=ctk.CTkFont(size=13),
            command=self._copy_current_caption,
        ).pack(side="right")

        self._compliance_warn_lbl = ctk.CTkLabel(
            body, text="", font=ctk.CTkFont(size=13),
            text_color="#FBBF24", wraplength=520, anchor="w",
        )
        self._compliance_warn_lbl.pack(fill="x", pady=(4, 0))

        self._setup_paste_bindings(self._camp_name_entry)
        self._setup_paste_bindings(self._camp_handle_entry)
        self._setup_paste_bindings(self._camp_min_entry)
        self._setup_paste_bindings(self._ai_topic_entry)

    def _toggle_campaign(self):
        if self._campaign_active:
            self._campaign_active = False
            self._camp_body.pack_forget()
            self._camp_toggle_btn.configure(text="Enable")
            self._campaign_frame.pack_forget()
        else:
            if not self._campaign:
                self._campaign = Campaign()
            self._campaign_active = True
            self._camp_body.pack(fill="x", padx=14, pady=(0, 10))
            self._camp_toggle_btn.configure(text="Disable")
            self._campaign_frame.pack(fill="x", padx=10, pady=(0, 12))
            self._refresh_caption_display()

    def _save_campaign_from_ui(self):
        if not self._campaign:
            self._campaign = Campaign()
        self._campaign.name     = self._camp_name_entry.get().strip() or "My Campaign"
        self._campaign.handle   = self._camp_handle_entry.get().strip() or "@handle"
        self._campaign.content_type = self._camp_type_var.get()
        try:
            self._campaign.min_duration = max(10, int(self._camp_min_entry.get()))
        except ValueError:
            self._campaign.min_duration = 10
        if not self._campaign.caption_templates:
            self._campaign.set_content_type(self._campaign.content_type)
        save_campaign(self._campaign)
        self._campaign_active = True
        self._compliance_warn_lbl.configure(text="Campaign saved!")
        self.after(2000, lambda: self._compliance_warn_lbl.configure(text=""))

    def _on_content_type_change(self, ctype: str):
        if self._campaign:
            self._campaign.set_content_type(ctype)
        self._caption_index = 0
        self._refresh_caption_display()

    def _get_captions(self) -> list:
        if self._campaign and self._campaign.caption_templates:
            return self._campaign.caption_templates
        ctype = self._camp_type_var.get() if hasattr(self, "_camp_type_var") else "YouTube"
        return DEFAULT_CAPTIONS.get(ctype, DEFAULT_CAPTIONS["Custom"])

    def _refresh_caption_display(self):
        if not hasattr(self, "_caption_box"):
            return
        caps  = self._get_captions()
        total = len(caps)
        if total == 0:
            return
        self._caption_index = max(0, min(self._caption_index, total - 1))
        text = caps[self._caption_index]
        self._caption_box.configure(state="normal")
        self._caption_box.delete("1.0", "end")
        self._caption_box.insert("1.0", f'"{text}"')
        self._caption_box.configure(state="disabled")
        if hasattr(self, "_cap_counter_lbl"):
            self._cap_counter_lbl.configure(text=f"{self._caption_index + 1} / {total}")

    def _caption_prev(self):
        caps = self._get_captions()
        self._caption_index = (self._caption_index - 1) % max(len(caps), 1)
        self._refresh_caption_display()

    def _caption_next(self):
        caps = self._get_captions()
        self._caption_index = (self._caption_index + 1) % max(len(caps), 1)
        self._refresh_caption_display()

    def _copy_current_caption(self):
        caps = self._get_captions()
        if not caps:
            return
        idx  = max(0, min(self._caption_index, len(caps) - 1))
        text = caps[idx]
        if self._campaign and self._campaign.handle:
            text = f'{text}\n{self._campaign.handle}'
        self._copy_to_clipboard(text)
        if hasattr(self, "_compliance_warn_lbl"):
            self._compliance_warn_lbl.configure(text="Caption copied to clipboard!")
            self.after(2000, lambda: self._compliance_warn_lbl.configure(text=""))

    def _on_ai_generate(self):
        topic = self._ai_topic_entry.get().strip()
        if not topic:
            messagebox.showwarning("تنبيه", "يرجى كتابة موضوع قصير أو ملخص للفيديو أولاً.")
            return

        if self._processing:
            return

        self._set_processing(True)
        self._ai_generate_btn.configure(state="disabled", text="⏳ جاري التحليل...")
        self._set_progress(0.0, "جاري الاتصال بنموذج Gemma 4 31b...")

        threading.Thread(
            target=self._run_ai_generate_thread,
            args=(topic,),
            daemon=True,
        ).start()

    def _run_ai_generate_thread(self, topic):
        try:
            from campaign import generate_ai_captions, GEMMA_API_KEY, save_campaign, Campaign
            campaign_name = self._camp_name_entry.get().strip() or "My Campaign"
            handle        = self._camp_handle_entry.get().strip() or "@handle"
            content_type  = self._camp_type_var.get()

            self._ui(self._set_progress, 0.3, "جاري قراءة تفاصيل الحملة بواسطة Gemma...")

            ai_caps = generate_ai_captions(
                video_summary=topic,
                campaign_name=campaign_name,
                handle=handle,
                content_type=content_type,
                api_key=GEMMA_API_KEY
            )

            if ai_caps:
                if not self._campaign:
                    self._campaign = Campaign()
                self._campaign.caption_templates = ai_caps
                self._campaign.name = campaign_name
                self._campaign.handle = handle
                self._campaign.content_type = content_type
                try:
                    self._campaign.min_duration = max(10, int(self._camp_min_entry.get()))
                except ValueError:
                    self._campaign.min_duration = 10

                save_campaign(self._campaign)
                self._caption_index = 0

                self._ui(self._refresh_caption_display)
                self._ui(self._set_progress, 1.0, "تم تحميل نصوص Gemma بنجاح!")
                self._ui(messagebox.showinfo, "تم بنجاح", "تمكن نموذج Gemma 4 31b بنجاح من توليد 5 كابشنز تفاعلية وفيروسية مخصصة لحملتك الإعلانية!")
            else:
                self._ui(self._set_progress, 0.0, "فشل توليد الكابشنز.")
                self._ui(messagebox.showerror, "خطأ", "أرجع نموذج Gemma استجابة فارغة.")
        except Exception as e:
            self._ui(self._set_progress, 0.0, "فشل التوليد الذكي.")
            self._ui(messagebox.showerror, "خطأ الذكاء الاصطناعي", f"خطأ في واجهة Gemma API:\n{str(e)[:150]}")
        finally:
            self._ui(self._set_processing, False)
            self._ui(self._reset_ai_btn)

    def _on_ai_campaign_paste(self):
        dialog = ctk.CTkToplevel(self)
        dialog.title("🤖 UGC Campaign AI Autopilot — One-Touch Configuration")
        dialog.geometry("680x520")
        dialog.resizable(False, False)
        dialog.transient(self)
        dialog.grab_set()
        
        self.update_idletasks()
        x = self.winfo_x() + (self.winfo_width() // 2) - 340
        y = self.winfo_y() + (self.winfo_height() // 2) - 260
        dialog.geometry(f"+{x}+{y}")

        ctk.CTkLabel(
            dialog, text="🤖 إعداد الحملة الذكي بلمسة واحدة",
            font=ctk.CTkFont(size=18, weight="bold"),
            text_color="#8B5CF6",
        ).pack(pady=(20, 4))
        
        ctk.CTkLabel(
            dialog, 
            text="ألصق شروط ومتطلبات حملة الـ UGC بالكامل أدناه (القوانين، المنصات، الهاشتاغات، الإفصاحات).\nسيقوم نموذج Gemma 2.5 Flash فوراً بتهيئة مساحة العمل وتوليد 5 كابشنز متوافقة وفيروسية!",
            font=ctk.CTkFont(size=13),
            text_color=TEXT_DIM,
            justify="center"
        ).pack(pady=(0, 14))

        text_frame = ctk.CTkFrame(dialog, fg_color="transparent")
        text_frame.pack(fill="both", expand=True, padx=24, pady=4)
        
        textbox = ctk.CTkTextbox(
            text_frame, corner_radius=10,
            font=ctk.CTkFont(size=13, family="Segoe UI"),
            wrap="word",
            fg_color=("#FFFFFF", "#1E1E1E"),
            border_color=("#D1D1D6", "#2C2C2E"),
            border_width=1
        )
        textbox.pack(fill="both", expand=True)
        textbox.focus_set()

        self._setup_paste_bindings(textbox)

        btn_frame = ctk.CTkFrame(dialog, fg_color="transparent")
        btn_frame.pack(fill="x", padx=24, pady=(16, 20))
        
        def on_apply():
            raw_text = textbox.get("1.0", "end").strip()
            if not raw_text:
                messagebox.showwarning("تنبيه", "يرجى لصق نص شروط الحملة أولاً.")
                return
            dialog.destroy()
            
            if self._processing:
                return
                
            self._set_processing(True)
            self._ai_autopilot_btn.configure(state="disabled", text="⏳ جاري استخراج الحملة...")
            self._set_progress(0.0, "جاري الاتصال بنموذج Gemma 2.5 Flash...")
            
            threading.Thread(
                target=self._run_ai_campaign_thread,
                args=(raw_text,),
                daemon=True,
            ).start()

        def on_cancel():
            dialog.destroy()

        ctk.CTkButton(
            btn_frame, text="إلغاء", width=110, height=32, corner_radius=8,
            fg_color=BORDER_IDLE, hover_color="#4B5563",
            font=ctk.CTkFont(size=13),
            command=on_cancel,
        ).pack(side="left")

        ctk.CTkButton(
            btn_frame, text="تحليل وتهيئة الحملة ⚡", width=220, height=32, corner_radius=8,
            fg_color="#8B5CF6", hover_color="#7C3AED",
            font=ctk.CTkFont(size=13, weight="bold"),
            command=on_apply,
        ).pack(side="right")

    def _run_ai_campaign_thread(self, raw_text):
        try:
            self._ui(self._set_progress, 0.4, "جاري قراءة واستخراج شروط وإرشادات الحملة بواسطة Gemma 2.5 Flash...")
            c = analyze_and_setup_campaign_from_text(raw_text)
            if c:
                self._campaign = c
                self._campaign_active = True
                self._caption_index = 0
                
                def update_gui_fields():
                    self._camp_body.pack(fill="x", padx=14, pady=(0, 10))
                    self._camp_toggle_btn.configure(text="Disable")
                    
                    self._camp_name_entry.delete(0, "end")
                    self._camp_name_entry.insert(0, c.name)
                    
                    self._camp_handle_entry.delete(0, "end")
                    self._camp_handle_entry.insert(0, c.handle)
                    
                    self._camp_min_entry.delete(0, "end")
                    self._camp_min_entry.insert(0, str(c.min_duration))
                    
                    self._camp_type_var.set(c.content_type)
                    self._refresh_caption_display()
                    
                    summary_msg = (
                        f"✨ تم ضبط وإعداد الحملة تلقائياً بنجاح باهر! ✨\n\n"
                        f"📁 اسم الحملة: {c.name}\n"
                        f"🏷️ التاج المعتمد: {c.handle}\n"
                        f"⏱️ الحد الأدنى للمدة: {c.min_duration} ثوانٍ\n"
                        f"🎧 حظر الموسيقى الخلفية: {'نعم (تم تفعيل الحظر)' if not c.allow_bg_music else 'لا (مسموح بها)'}\n"
                        f"🎬 حظر الـ B-roll الخارجي: {'نعم (تم تفعيل الحظر)' if not c.allow_broll else 'لا (مسموح به)'}\n"
                        f"⚖️ إفصاح FTC المطلوبة: {c.ftc_disclosure if c.ftc_disclosure else 'لا يوجد'}\n"
                        f"📝 تم توليد 5 كابشنز فيروسية متوافقة بالكامل مع شروط الحملة وتاغاتها!"
                    )
                    messagebox.showinfo("One-Touch AI Success", summary_msg)
                
                self._ui(update_gui_fields)
                self._ui(self._set_progress, 1.0, "تم تهيئة الحملة تلقائياً بنجاح!")
            else:
                self._ui(self._set_progress, 0.0, "فشلت التهيئة التلقائية.")
                self._ui(messagebox.showerror, "خطأ حملة الذكاء الاصطناعي", "أرجع نموذج Gemma نتائج فارغة أو غير صالحة.")
        except Exception as e:
            self._ui(self._set_progress, 0.0, "فشلت التهيئة التلقائية بالذكاء الاصطناعي.")
            self._ui(messagebox.showerror, "خطأ حملة الذكاء الاصطناعي", f"فشل استخراج متطلبات الحملة:\n{str(e)[:250]}")
        finally:
            self._ui(self._set_processing, False)
            self._ui(self._reset_ai_autopilot_btn)

    def _reset_ai_autopilot_btn(self):
        self._ai_autopilot_btn.configure(state="normal", text="Configure Campaign with AI 🚀")

    def _reset_ai_btn(self):
        self._ai_generate_btn.configure(state="normal", text="Generate Captions")
