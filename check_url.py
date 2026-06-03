import httpx
import asyncio
from bs4 import BeautifulSoup

async def main():
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
        "Origin": "https://vtop.vitap.ac.in",
        "Referer": "https://vtop.vitap.ac.in/vtop/login"
    }
    c = httpx.AsyncClient(verify=False, follow_redirects=True, base_url='https://vtop.vitap.ac.in', headers=headers)
    
    r = await c.get('/vtop/')
    print("GET /vtop/:", r.status_code)
    csrf = r.text.split('name="_csrf" value="')[1].split('"')[0]
    
    r2 = await c.post('/vtop/prelogin/setup', data={'_csrf': csrf, 'flag': 'VTOP'})
    print("POST /prelogin/setup:", r2.status_code)
    
    # GET /vtop/login
    r_login_get = await c.get('/vtop/login')
    print("GET /vtop/login:", r_login_get.status_code)
    
    soup = BeautifulSoup(r_login_get.text, 'lxml')
    form = soup.find('form', id='vtopLoginForm')
    if form:
        csrf2 = form.find('input', {'name': '_csrf'}).get('value')
    else:
        csrf2 = r_login_get.text.split('name="_csrf" value="')[1].split('"')[0]
        
    print("csrf2", csrf2)
    
    data = {
        '_csrf': csrf2,
        'username': '23BCE7356',
        'password': 'NovaPrime@2004',
        'captchaStr': 'test12',
        'gResponse': ''
    }
    
    r3 = await c.post('/vtop/login', data=data)
    print("R3 STATUS:", r3.status_code)
    print("R3 URL:", r3.url)
    print("R3 HTML:", r3.text[:1000])

asyncio.run(main())
