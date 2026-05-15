"""Test fetching timetable to ensure _post_menu works correctly."""
import asyncio, sys
asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

from vtop_scraper import VTOPSession

async def test():
    if len(sys.argv) < 3:
        print("Usage: python test_tt_fetch.py <username> <password> [semester_id]")
        return
    
    username = sys.argv[1]
    password = sys.argv[2]
    semester = sys.argv[3] if len(sys.argv) > 3 else "AP2025265" # Test with Summer Sem - 1 by default
    
    session = VTOPSession()
    try:
        result = await session.login(username, password)
        print(f"Login: {result}")
        
        if result == "success":
            print(f"\n--- Fetching Timetable for {semester} ---")
            tt = await session.get_timetable(semester_id=semester)
            print(f"Timetable records found: {len(tt)}")
            if tt:
                for item in tt[:3]:
                    print(f"  {item}")
            else:
                print("No timetable found or parse failed. Trying to fetch raw HTML to debug...")
                # Let's do the raw fetch and save HTML to debug
                await session._post_menu("/vtop/academics/common/StudentTimeTable")
                resp = await session._post_authenticated(
                    "/vtop/processViewTimeTable",
                    {
                        "semesterSubId": semester,
                        "authorizedID": session.registration_number,
                    }
                )
                with open("debug_tt.html", "w", encoding="utf-8") as f:
                    f.write(resp.text)
                print("Saved to debug_tt.html")
                
    except Exception as e:
        print(f"Error: {e}")
    finally:
        await session.close()

asyncio.run(test())
