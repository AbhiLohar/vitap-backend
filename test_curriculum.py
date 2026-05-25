import asyncio
from vtop_scraper import VTOPSession
from bs4 import BeautifulSoup

async def main():
    s = VTOPSession()
    await s.login('23bce9047','Tusush11$$')
    
    # Fetch Curriculum Page
    resp = await s._post_authenticated("/vtop/academics/common/StudentCurriculum", {"authorizedID": s.registration_number, "verifyMenu": "true"})
    soup = BeautifulSoup(resp.text, 'lxml')
    
    tables = soup.find_all('table')
    for i, t in enumerate(tables):
        rows = t.find_all('tr')
        if rows:
            print(f"Table {i} Headers: {[th.get_text(strip=True) for th in rows[0].find_all(['th','td'])]}")

asyncio.run(main())
