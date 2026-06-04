import asyncio
from vtop_scraper import VTOPSession

async def main():
    session = VTOPSession()
    status = await session.login("23BCE7438", "Sanjivi@123")
    print(f"Login status: {status}")
    
    if status == 'otp_required':
        # Can't bypass OTP here. But wait! I can just use my credentials if I have a session.
        # Is there any other way?
        pass

if __name__ == '__main__':
    asyncio.run(main())
