' ============================================================
'  Clippify Studio — silent launcher (بدون نافذة سوداء إضافية)
'
'  الدبل-كليك على run.bat هو الطريقة الأسهل والأوضح (تشاهد كل
'  الحالات بالعربي). هذا السكربت لتشغيل أنيق بدون كونسول:
'  يفوض كل شيء إلى run_clippify.py ويكتب السجل في clippify_run.log
'  بجذر المشروع — راجعه لو لم يفتح التطبيق.
'
'  يدعم تمرير وسائط run_clippify.py، مثلاً من الطرفية:
'    wscript start_clippify.vbs --dry-run
' ============================================================
Option Explicit

Dim shell, fso, scriptDir, logPath, cmd, args, i
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
logPath = fso.BuildPath(scriptDir, "clippify_run.log")

args = ""
For i = 0 To WScript.Arguments.Count - 1
    args = args & " """ & WScript.Arguments(i) & """"
Next

' python أو py -3 — أي منهما متاح؛ run_clippify.py يكتشف بايثون المشروع بنفسه
cmd = "cmd /c cd /d """ & scriptDir & """ && (python run_clippify.py" & args & _
      " || py -3 run_clippify.py" & args & ") > """ & logPath & """ 2>&1"

' windowStyle = 0 (مخفي) — ولا ينتظر حتى ينتهي
shell.Run cmd, 0, False
