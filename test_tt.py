import os
import asyncio
from vtop_scraper import VTOPSession

async def main():
    session = VTOPSession()
    try:
        # Login
        await session.login(os.environ.get("VTOP_USERNAME"), os.environ.get("VTOP_PASSWORD"))
        
        # Get semesters
        sems = await session.get_semesters()
        print("Semesters:", sems)
        
        # Get timetable for the newest one
        target_sem = sems[0]["id"] if sems else "AP2024254"
        print(f"Fetching timetable for {target_sem}...")
        
        tt = await session.get_timetable(target_sem)
        print("Timetable count:", len(tt))
        if tt:
            print("First entry:", tt[0])
        else:
            # Let's save the HTML to see why it's empty
            resp = await session._post_authenticated(
                "https://vtop.vitap.ac.in/vtop/academics/common/StudentTimeTable",
                {"_csrf": session.post_login_csrf}
            )
            resp = await session._post_authenticated(
                "https://vtop.vitap.ac.in/vtop/processViewTimeTable",
                {
                    "semesterSubId": target_sem,
                    "authorizedID": session.registration_number,
                }
            )
            with open("timetable_debug.html", "w", encoding="utf-8") as f:
                f.write(resp.text)
            print("Saved timetable_debug.html")

    except Exception as e:
        print("Error:", e)
    finally:
        await session.close()

asyncio.run(main())
