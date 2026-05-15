import asyncio
from vtop_scraper import VTOPSession

async def main():
    session = VTOPSession()
    try:
        await session.login("23BCE7356", "Quntum@2004")
        with open("timetable_structure.html", "r", encoding="utf-8") as f:
            html = f.read()
        
        tt = session._parse_timetable(html)
        tue_classes = [c for c in tt if c["day"] == "Tuesday"]
        print(f"Tuesday classes count: {len(tue_classes)}")
        for c in tue_classes:
            print(f"[{c['type']}] {c['subject']} ({c['time']})")

    except Exception as e:
        print("Error:", e)
    finally:
        await session.close()

asyncio.run(main())
