import httpx
import asyncio
from bs4 import BeautifulSoup

async def main():
    c = httpx.AsyncClient(verify=False, follow_redirects=True, base_url='https://vtop.vitap.ac.in',
                          headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"})
    r = await c.get('/vtop/')
    csrf = r.text.split('name="_csrf" value="')[1].split('"')[0]
    r2 = await c.post('/vtop/prelogin/setup', data={'_csrf': csrf, 'flag': 'VTOP'})
    r3 = await c.get('/vtop/login')
    
    soup = BeautifulSoup(r3.text, 'lxml')
    print("ALL INPUTS:")
    for inp in soup.find_all('input'):
        print(inp)
    
    print("\nALL SCRIPTS:")
    for script in soup.find_all('script'):
        if script.get('src'):
            print(script['src'])
        elif script.text:
            print("Inline script snippet:", script.text[:100].strip().replace('\n', ' '))

asyncio.run(main())
