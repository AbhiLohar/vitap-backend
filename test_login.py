import asyncio
from vtop_scraper import VTOPSession

async def main():
    session = VTOPSession()
    try:
        res = await session.login("23BCE7356", "Quntum@2004")
        print("Success:", res)
    except Exception as e:
        print("Error:", repr(e))

asyncio.run(main())
