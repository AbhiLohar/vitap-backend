import httpx
import asyncio
from bs4 import BeautifulSoup

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
    
    r1 = await c.get("/vtop/open/page")
    soup1 = BeautifulSoup(r1.text, 'lxml')
    csrf1 = soup1.find('input', {'name': '_csrf'})['value']
    
    await c.post("/vtop/prelogin/setup", data={"_csrf": csrf1, "flag": "VTOP"})
    
    r2 = await c.get("/vtop/login")
    soup2 = BeautifulSoup(r2.text, 'lxml')
    csrf2 = soup2.find('input', {'name': '_csrf'})['value']
    
    login_data = {
        "_csrf": csrf2,
        "username": "23BCE7356",
        "password": "NovaPrime@2004",
        "captchaStr": "DAYE5C",
        "gResponse": "",
    }
    
    r3 = await c.post("/vtop/login", data=login_data)
    print("Status:", r3.status_code)
    print("Final URL:", r3.url)
    print("Body preview:", r3.text[:1000])

asyncio.run(main())
