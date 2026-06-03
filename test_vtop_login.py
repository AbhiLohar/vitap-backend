import asyncio
from vtop_scraper import VTOPSession

async def main():
    s = VTOPSession()
    res = await s.login('23BCE7356', 'NovaPrime@2004')
    print("Result:", res)

asyncio.run(main())
