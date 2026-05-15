import asyncio
from vtop_scraper import VTOPSession

async def main():
    session = VTOPSession()
    try:
        await session.login("23BCE7356", "Quntum@2004")
        sems = await session.get_semesters()
        target_sem = sems[0]["id"]
        
        # Navigate and fetch
        await session._post_authenticated(
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
        with open("timetable_structure.html", "w", encoding="utf-8") as f:
            f.write(resp.text)
        print("Saved timetable_structure.html")

    except Exception as e:
        print("Error:", e)
    finally:
        await session.close()

asyncio.run(main())
