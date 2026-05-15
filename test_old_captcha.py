import asyncio
from vtop_scraper import VTOPSession, _find_captcha_b64
from bs4 import BeautifulSoup

async def main():
    session = VTOPSession()
    resp = await session.client.get("/vtop/open/page")
    csrf = session.csrf_token = __import__("vtop_scraper")._find_csrf(resp.text)
    pre_data = {"_csrf": csrf, "flag": "VTOP"}
    await session.client.post("/vtop/prelogin/setup", data=pre_data)
    
    resp = await session.client.get("/vtop/get/new/captcha")
    print("Captcha status:", resp.status_code)
    
    b64 = _find_captcha_b64(resp.text)
    print("Found b64:", bool(b64))
    
asyncio.run(main())
