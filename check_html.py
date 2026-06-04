import httpx
import asyncio
from bs4 import BeautifulSoup
import re

async def main():
    c = httpx.AsyncClient(verify=False, follow_redirects=True, base_url='https://vtop.vitap.ac.in',
                          headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"})
    r = await c.get('/vtop/')
    csrf = r.text.split('name="_csrf" value="')[1].split('"')[0]
    await c.post('/vtop/prelogin/setup', data={'_csrf': csrf, 'flag': 'VTOP'})
    r3 = await c.get('/vtop/login')
    
    soup = BeautifulSoup(r3.text, 'lxml')
    captcha_block = soup.find('div', id='captchaBlock')
    print("captchaBlock:", captcha_block)
    
    # Check JS snippet
    for script in soup.find_all('script'):
        if script.text and 'captchaType' in script.text:
            m = re.search(r'var\s+captchaType\s*=\s*(\d+)', script.text)
            print("captchaType:", m.group(1) if m else "Unknown")

asyncio.run(main())
