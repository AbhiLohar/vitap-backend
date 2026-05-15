import asyncio
from vtop_scraper import VTOPSession

async def main():
    session = VTOPSession()
    try:
        await session.login("23BCE7356", "Quntum@2004")
        data = await session.get_attendance("AP2025264")
        print("Attendance data sample:")
        if data:
            for item in data[:3]:
                print(f"Subject: {item['subject']}, Type: {item['type']}")
        else:
            print("No attendance data found!")

    except Exception as e:
        print("Error:", e)
    finally:
        await session.close()

asyncio.run(main())
