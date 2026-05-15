import asyncio
from vtop_scraper import VTOPSession
from bs4 import BeautifulSoup

async def main():
    session = VTOPSession()
    resp = await session.client.get("/vtop/open/page")
    csrf = session.csrf_token = __import__("vtop_scraper")._find_csrf(resp.text)
    pre_data = {"_csrf": csrf, "flag": "VTOP"}
    await session.client.post("/vtop/prelogin/setup", data=pre_data)
    resp = await session.client.get("/vtop/login")
    with open("login_page.html", "w", encoding="utf-8") as f:
        f.write(resp.text)
    
    captcha = __import__("vtop_scraper")._find_captcha_b64(resp.text)
    print("Captcha found:", bool(captcha))

asyncio.run(main())
