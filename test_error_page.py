import asyncio
from vtop_scraper import VTOPSession

async def run():
    s = VTOPSession()
    try:
        # Do prelogin
        resp = await s.client.get("/vtop/open/page")
        from vtop_scraper import _find_csrf, _solve_captcha_image, _find_captcha_b64
        csrf = _find_csrf(resp.text)
        await s.client.post("/vtop/prelogin/setup", data={"_csrf": csrf, "flag": "VTOP"})
        
        # Get login page
        resp = await s.client.get("/vtop/login")
        csrf = _find_csrf(resp.text)
        
        # Get captcha
        captcha_resp = await s.client.get("/vtop/get/new/captcha")
        b64 = _find_captcha_b64(captcha_resp.text)
        
        # Solve
        solved = _solve_captcha_image(b64)
        print("Captcha:", solved)
        
        # Post
        login_data = {
            "_csrf": csrf,
            "username": "PLALITKR2526",
            "password": "password123",
            "captchaStr": solved,
            "gResponse": "",
        }
        res = await s.client.post("/vtop/login", data=login_data)
        with open("error_page.html", "w", encoding="utf-8") as f:
            f.write(res.text)
        print("Saved real error page, url:", res.url)
    except Exception as e:
        print("Exception:", e)

asyncio.run(run())
