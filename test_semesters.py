"""Quick test to check what semesters the scraper finds."""
import asyncio, sys
asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

from vtop_scraper import VTOPSession

async def test():
    if len(sys.argv) < 3:
        print("Usage: python test_semesters.py <username> <password>")
        return
    
    username = sys.argv[1]
    password = sys.argv[2]
    
    session = VTOPSession()
    try:
        result = await session.login(username, password)
        print(f"Login: {result}")
        
        if result == "success":
            print("\n--- Fetching semesters ---")
            semesters = await session.get_semesters()
            print(f"\nTotal semesters found: {len(semesters)}")
            print("\nAll semesters:")
            for i, sem in enumerate(semesters):
                print(f"  {i+1}. {sem['name']} -> {sem['id']}")
        else:
            print("Login was not successful")
    except Exception as e:
        print(f"Error: {e}")
    finally:
        await session.close()

asyncio.run(test())
