import os
import json

def login_and_save_cookies(cookies_path: str):
    """
    Launches a visible Chromium browser for the user to log into YouTube.
    Saves cookies to cookies_path in Netscape format.
    """
    from playwright.sync_api import sync_playwright

    with sync_playwright() as p:
        # Launch persistent context to keep it logged in across runs if needed
        app_dir = os.path.dirname(os.path.abspath(__file__))
        user_data_dir = os.path.join(app_dir, "yt_login_profile")
        
        browser = p.chromium.launch_persistent_context(
            user_data_dir=user_data_dir,
            headless=False,
            viewport={'width': 1000, 'height': 800},
            channel="chrome", # use existing chrome if chromium isn't there
            args=["--disable-blink-features=AutomationControlled"],
            ignore_default_args=["--enable-automation"]
        )
        
        page = browser.pages[0] if browser.pages else browser.new_page()
        
        # Hide webdriver signature to bypass Google login block
        page.add_init_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")
        
        page.goto("https://www.youtube.com")
        
        print("Please log into YouTube in the browser window.")
        print("Waiting for login to complete (or you can close the window when done)...")
        
        cookies = []
        try:
            # Continuously fetch cookies until the user logs in or closes the browser
            while True:
                if len(browser.pages) == 0:
                    break
                
                current_cookies = browser.cookies()
                # YouTube/Google sets __Secure-1PSID or SAPISID when logged in
                is_logged_in = any(c['name'] in ['SAPISID', '__Secure-1PSID', '__Secure-3PSID'] for c in current_cookies)
                
                if is_logged_in:
                    print("Login detected via cookies! Auto-closing browser.")
                    # wait 2 seconds just to ensure all cookies are fully saved
                    browser.pages[0].wait_for_timeout(2000)
                    cookies = browser.cookies()
                    break
                
                # wait a little bit before checking again
                browser.pages[0].wait_for_timeout(1000)
        except Exception:
            # User closed the browser manually
            cookies = browser.cookies() if 'browser' in locals() and len(browser.pages) > 0 else cookies
            
        if not cookies:
            print("No cookies found. Did you close the browser too quickly?")
            return False
        
        # Convert playwright cookies to Netscape format
        with open(cookies_path, "w") as f:
            f.write("# Netscape HTTP Cookie File\n")
            f.write("# http://curl.haxx.se/rfc/cookie_spec.html\n")
            f.write("# This is a generated file!  Do not edit.\n\n")
            
            for cookie in cookies:
                domain = cookie['domain']
                # Netscape format starts with a dot if it's a generic domain cookie
                if not domain.startswith('.'):
                    domain = '.' + domain
                
                include_subdomains = "TRUE" if domain.startswith('.') else "FALSE"
                path = cookie['path']
                secure = "TRUE" if cookie['secure'] else "FALSE"
                expires = str(int(cookie.get('expires', 0)))
                name = cookie['name']
                value = cookie['value']
                
                f.write(f"{domain}\t{include_subdomains}\t{path}\t{secure}\t{expires}\t{name}\t{value}\n")
                
        browser.close()
        return True

if __name__ == "__main__":
    login_and_save_cookies("cookies.txt")
