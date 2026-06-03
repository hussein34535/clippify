"""
app.py — ClipAI Main Launcher

Run desktop GUI:
    python app.py

Run local web server (FastAPI):
    python app.py --web
"""

import sys
import os

if __name__ == "__main__":
    # Check if user wants to run the web server
    if "--web" in sys.argv or "--api" in sys.argv:
        print("Starting ClipAI Web Backend Server...")
        import uvicorn
        # Import and run the app
        uvicorn.run("api:app", host="127.0.0.1", port=8000, reload=True)
    else:
        print("Starting ClipAI Desktop Application...")
        # Add current directory to path
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        
        # Import the GUI app from gui_main
        from gui_main import ClipAIApp
        
        app = ClipAIApp()
        app.mainloop()
