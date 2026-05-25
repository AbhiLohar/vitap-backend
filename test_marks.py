import asyncio
from vtop_scraper import VTOPSession

async def main():
    s = VTOPSession()
    await s.login('23bce9047','Tusush11$$')
    m = await s.get_marks()
    print(f"Num courses: {len(m)}")
    if m:
        print(m[0])

asyncio.run(main())
