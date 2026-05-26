import os
import asyncio
import httpx
from vtop_scraper import VTOPSession

async def run():
    s = VTOPSession()
    try:
        res = await s.login(os.environ.get("VTOP_USERNAME"), os.environ.get("VTOP_PASSWORD"))
        print("Login Result:", res)
    except Exception as e:
        print("Exception:", e)

if __name__ == "__main__":
    asyncio.run(run())
