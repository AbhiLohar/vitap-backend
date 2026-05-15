import asyncio
import httpx
from bs4 import BeautifulSoup
import re
import base64

# Copy necessary pieces of VTOPSession to print the raw error text
from vtop_scraper import VTOPSession

async def run():
    s = VTOPSession()
    # Mock _find_login_error to print the HTML
    original_find = s.__class__.__module__ # just intercept the print
    try:
        await s.login('23BCE7356', 'dummy_pass')
    except Exception as e:
        pass

if __name__ == "__main__":
    asyncio.run(run())
