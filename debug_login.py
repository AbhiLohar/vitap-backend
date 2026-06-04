"""
Run multiple captcha attempts and check if uppercasing helps.
Also try pytesseract as an alternative OCR.
"""
import httpx
import asyncio
import base64
from bs4 import BeautifulSoup
from PIL import Image, ImageEnhance
import io
import ddddocr
import re

VTOP_BASE = "https://vtop.vitap.ac.in"

def find_csrf(html):
    soup = BeautifulSoup(html, "lxml")
    inp = soup.find("input", attrs={"name": "_csrf"})
    if inp and inp.get("value"):
        return inp["value"]
    return ""

def find_captcha(html):
    soup = BeautifulSoup(html, "lxml")
    for img in soup.find_all("img"):
        src = img.get("src", "")
        if src.startswith("data:image"):
            return src
    return ""

def solve_captcha(b64_data):
    if "," in b64_data:
        b64_data = b64_data.split(",")[1]
    img_bytes = base64.b64decode(b64_data)
    
    pil_img = Image.open(io.BytesIO(img_bytes)).convert('L')
    enhanced = ImageEnhance.Contrast(pil_img).enhance(1.5)
    buf = io.BytesIO()
    enhanced.save(buf, format='PNG')
    
    ocr = ddddocr.DdddOcr(show_ad=False)
    text = ocr.classification(buf.getvalue())
    text = re.sub(r'[^A-Za-z0-9]', '', text)
    return text.upper()  # VTOP converts to uppercase

async def main():
    c = httpx.AsyncClient(
        verify=False, follow_redirects=True, base_url=VTOP_BASE,
        headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            "Origin": "https://vtop.vitap.ac.in",
            "Referer": "https://vtop.vitap.ac.in/vtop/login",
        },
        timeout=30.0,
    )
    
    # Setup
    r1 = await c.get("/vtop/open/page")
    csrf = find_csrf(r1.text)
    await c.post("/vtop/prelogin/setup", data={"_csrf": csrf, "flag": "VTOP"})
    
    for attempt in range(30):
        # Get login page
        r = await c.get("/vtop/login")
        csrf = find_csrf(r.text)
        captcha_b64 = find_captcha(r.text)
        
        if not captcha_b64:
            print(f"Attempt {attempt+1}: No captcha found, refreshing...")
            await c.get("/vtop/open/page")
            csrf = find_csrf(r.text)
            await c.post("/vtop/prelogin/setup", data={"_csrf": csrf, "flag": "VTOP"})
            continue
        
        solved = solve_captcha(captcha_b64)
        if len(solved) != 6:
            print(f"Attempt {attempt+1}: Bad length '{solved}' ({len(solved)}), skipping")
            continue
        
        login_data = {
            "_csrf": csrf,
            "username": "23BCE7356",
            "password": "NovaPrime@2004",
            "captchaStr": solved,
            "gResponse": "",
        }
        
        resp = await c.post("/vtop/login", data=login_data)
        final_url = str(resp.url)
        
        if "/vtop/content" in final_url:
            print(f"Attempt {attempt+1}: SUCCESS! Captcha='{solved}' -> Logged in!")
            return
        elif "/vtop/login/error" in final_url:
            print(f"Attempt {attempt+1}: Invalid captcha '{solved}'")
            csrf = find_csrf(resp.text)
        elif "otp" in final_url.lower() or "securityOtpPending" in resp.text:
            print(f"Attempt {attempt+1}: OTP REQUIRED! Captcha='{solved}' was correct!")
            return
        elif "HTTP Status 404" in resp.text or "Apache Tomcat" in resp.text:
            print(f"Attempt {attempt+1}: 404 error, re-initializing...")
            r1 = await c.get("/vtop/open/page")
            csrf = find_csrf(r1.text)
            await c.post("/vtop/prelogin/setup", data={"_csrf": csrf, "flag": "VTOP"})
        else:
            print(f"Attempt {attempt+1}: Unknown response at {final_url}")
            # Check for securityOtpPending in JS
            if "securityOtpPending" in resp.text:
                import re as re2
                m = re2.search(r'var\s+securityOtpPending\s*=\s*(\w+)', resp.text)
                if m:
                    print(f"  securityOtpPending = {m.group(1)}")
        
        await asyncio.sleep(0.3)
    
    print("FAILED: All 30 attempts exhausted")

asyncio.run(main())
