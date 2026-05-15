import asyncio
from vtop_scraper import VTOPSession, _find_login_error
from bs4 import BeautifulSoup

async def main():
    session = VTOPSession()
    resp = await session.client.get("/vtop/open/page")
    csrf = session.csrf_token = __import__("vtop_scraper")._find_csrf(resp.text)
    pre_data = {"_csrf": csrf, "flag": "VTOP"}
    await session.client.post("/vtop/prelogin/setup", data=pre_data)
    
    login_data = {
        "_csrf": csrf,
        "username": "23BCE7356",
        "password": "Quntum@2004",
        "captchaStr": "",
        "gResponse": ""
    }
    resp = await session.client.post("/vtop/login", data=login_data)
    print("Error:", _find_login_error(resp.text))
    
asyncio.run(main())
