import asyncio
from vtop_scraper import VTOPSession

async def main():
    session = VTOPSession()
    status = await session.login("23BCE7438", "Sanjivi@123")
    print(f"Login status: {status}")
    if status == 'success':
        # Fetch payment history
        resp = await session.client.post("https://vtop.vitap.ac.in/vtop/finance/Payments", data={"verifyMenu": "true", "authorizedID": "23BCE7438", "_csrf": session.csrf_token}, headers={"User-Agent": "Mozilla/5.0"})
        # Now find the getReceiptsApplno table to get the javascript
        data = {"verifyMenu": "true", "authorizedID": "23BCE7438", "_csrf": session.csrf_token}
        resp2 = await session.client.post("https://vtop.vitap.ac.in/vtop/p2p/getReceiptsApplno", data=data)
        html = resp2.text
        
        # Let's extract the <script> tags to find doDuplicateReceipt
        from bs4 import BeautifulSoup
        soup = BeautifulSoup(html, 'lxml')
        for script in soup.find_all('script'):
            if script.string and 'doDuplicateReceipt' in script.string:
                print(script.string)

if __name__ == '__main__':
    asyncio.run(main())
