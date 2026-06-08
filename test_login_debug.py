import asyncio
from vtop_scraper import VTOPSession

async def run():
    s = VTOPSession()
    try:
        res = await s.login('PLALITKR2526', 'password123')
        print("Final:", res)
    except Exception as e:
        print("Exception:", e)

asyncio.run(run())
