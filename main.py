import asyncio
import time
import platform

if platform.system() == "Windows":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

from fastapi import FastAPI, Form, HTTPException
from typing import Optional
from fastapi.middleware.cors import CORSMiddleware
from vtop_scraper import VTOPSession

app = FastAPI(title="VTOP API", version="3.0.0")

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Active sessions per user
client_store: dict[str, dict] = {}
SESSION_TIMEOUT = 1800  # 30 minutes


def get_session(username: str) -> VTOPSession | None:
    entry = client_store.get(username)
    if not entry:
        return None
    if time.time() - entry["last_active"] > SESSION_TIMEOUT:
        asyncio.create_task(cleanup_session(username))
        return None
    entry["last_active"] = time.time()
    return entry["session"]


async def cleanup_session(username: str):
    entry = client_store.pop(username, None)
    if entry:
        try:
            await entry["session"].close()
        except Exception:
            pass


# ─── Health ───────────────────────────────────────────────
@app.get("/health")
async def health():
    return {"status": "ok", "active_sessions": len(client_store)}


# ─── Login (auto-solves captcha) ──────────────────────────
@app.post("/login")
async def login(username: str = Form(...), password: str = Form(...)):
    # Cleanup old session
    if username in client_store:
        old = client_store.pop(username)
        asyncio.create_task(old["session"].close())

    try:
        session = VTOPSession()
        result = await session.login(username, password)

        client_store[username] = {
            "session": session,
            "last_active": time.time(),
        }

        return {"status": result}

    except Exception as e:
        print(f"Login Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ─── Verify OTP ──────────────────────────────────────────
@app.post("/verify-otp")
async def verify_otp(username: str = Form(...), otp: str = Form(...)):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Session expired")

    try:
        result = await session.submit_otp(otp)
        return {"status": result}
    except Exception as e:
        print(f"OTP Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ─── Semesters ───────────────────────────────────────────
@app.get("/semesters")
async def semesters(username: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        data = await session.get_semesters()
        return {"semesters": data}
    except Exception as e:
        print(f"Semesters Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ─── Attendance ──────────────────────────────────────────
@app.get("/attendance")
async def attendance(username: str, semester_id: Optional[str] = None):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        data = await session.get_attendance(semester_id=semester_id)
        return {"attendance": data}
    except Exception as e:
        print(f"Attendance Error: {e}")
        return {"attendance": []}


# ─── Timetable ───────────────────────────────────────────
@app.get("/timetable")
async def timetable(username: str, semester_id: Optional[str] = None):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        data = await session.get_timetable(semester_id=semester_id)
        return {"timetable": data}
    except Exception as e:
        print(f"Timetable Error: {e}")
        return {"timetable": []}


# ─── Marks ───────────────────────────────────────────────
@app.get("/marks")
async def marks(username: str, semester_id: Optional[str] = None):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        data = await session.get_marks(semester_id=semester_id)
        return {"marks": data}
    except Exception as e:
        print(f"Marks Error: {e}")
        return {"marks": []}


# ─── Grades ──────────────────────────────────────────────
@app.get("/grades")
async def grades(username: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        data = await session.get_grades()
        return {"grades": data}
    except Exception as e:
        print(f"Grades Error: {e}")
        return {"grades": []}


# ─── Exam Types ──────────────────────────────────────────
@app.get("/exam-types")
async def exam_types(username: str, semester_id: Optional[str] = None):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        data = await session.get_exam_types(semester_id=semester_id)
        return {"exam_types": data}
    except Exception as e:
        print(f"Exam Types Error: {e}")
        return {"exam_types": []}


# ─── Exam Schedule ───────────────────────────────────────
@app.get("/exam-schedule")
async def exam_schedule(username: str, semester_id: Optional[str] = None, exam_type: Optional[str] = None):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        # If exam_type is not provided, we could fetch it first or use a default
        e_type = exam_type or "FAT" 
        data = await session.get_exam_schedule(semester_id=semester_id, exam_type=e_type)
        return {"exam_schedule": data}
    except Exception as e:
        print(f"Exam Schedule Error: {e}")
        return {"exam_schedule": []}


# ─── Profile ────────────────────────────────────────────
@app.get("/profile")
async def profile(username: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        data = await session.get_profile()
        return {"profile": data}
    except Exception as e:
        print(f"Profile Error: {e}")
        return {"profile": {}}


# ─── Session Cookies ─────────────────────────────────────
@app.get("/session-cookies")
async def session_cookies(username: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        # Expose all cookies attached to the httpx client
        cookies = dict(session.client.cookies)
        return {"cookies": cookies}
    except Exception as e:
        print(f"Session Cookies Error: {e}")
        return {"cookies": {}}


# ─── Curriculum ──────────────────────────────────────────
@app.get("/curriculum")
async def curriculum(username: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        data = await session.get_curriculum()
        return {"curriculum": data}
    except Exception as e:
        print(f"Curriculum Error: {e}")
        return {
            "curriculum": {
                "summary": {"earned": "0", "total": "0", "left": "0"},
                "distribution": []
            }
        }


# ─── Logout ──────────────────────────────────────────────
@app.post("/logout")
async def logout(username: str = Form(...)):
    await cleanup_session(username)
    return {"status": "logged_out"}