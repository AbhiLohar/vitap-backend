import httpx
import asyncio
from bs4 import BeautifulSoup
import re

VTOP_BASE = "https://vtop.vitap.ac.in"

async def main():
    c = httpx.AsyncClient(
        verify=False, follow_redirects=True, base_url=VTOP_BASE,
        headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
            "Origin": "https://vtop.vitap.ac.in",
            "Referer": "https://vtop.vitap.ac.in/vtop/login",
        },
        timeout=30.0,
    )
    
    while True:
        r1 = await c.get("/vtop/open/page")
        soup1 = BeautifulSoup(r1.text, 'lxml')
        csrf1 = soup1.find('input', {'name': '_csrf'})['value']
        
        await c.post("/vtop/prelogin/setup", data={"_csrf": csrf1, "flag": "VTOP"})
        
        r2 = await c.get("/vtop/login")
        m = re.search(r'var\s+captchaType\s*=\s*(\d+)', r2.text)
        c_type = m.group(1) if m else "unknown"
        if c_type != "1":
            print(f"Got captchaType={c_type}, retrying...")
            await asyncio.sleep(1)
            continue
            
        print("Got captchaType=1!")
        soup2 = BeautifulSoup(r2.text, 'lxml')
        
        from vtop_captcha import solve_vtop_captcha
        r_captcha = await c.get("/vtop/get/new/captcha")
        soup_c = BeautifulSoup(r_captcha.text, 'lxml')
        img_b64 = soup_c.find('img')['src']
        
        solved = solve_vtop_captcha(img_b64)
        print(f"Solved: {solved}")
        
        # Save image for verification
        import base64
        with open("last_test_captcha.png", "wb") as f:
            f.write(base64.b64decode(img_b64.split(",")[1]))
        
        csrf2 = soup2.find('input', {'name': '_csrf'})['value']
        
        login_data = {
            "_csrf": csrf2,
            "username": "23BCE7356",
            "password": "NovaPrime@2004", 
            "captchaStr": solved,
            "gResponse": "",
        }
        
        r3 = await c.post("/vtop/login", data=login_data)
        print("Status:", r3.status_code)
        print("Final URL:", r3.url)
        
        soup3 = BeautifulSoup(r3.text, 'lxml')
        error_div = soup3.find('div', class_='alert')
        if error_div:
            print("ERROR MESSAGE ON PAGE:", error_div.text.strip())
        else:
            print("No alert div found.")
            if "/vtop/content" in str(r3.url):
                print("SUCCESSFULLY LOGGED IN!")
            else:
                print(r3.text[:1000])
        break

asyncio.run(main())
