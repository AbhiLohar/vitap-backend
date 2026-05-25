import asyncio
import time
import platform

if platform.system() == "Windows":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

from fastapi import FastAPI, Form, HTTPException
from typing import Optional
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import UJSONResponse
from vtop_scraper import VTOPSession

app = FastAPI(title="VTOP API", version="3.0.0", default_response_class=UJSONResponse)

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
async def health(username: Optional[str] = None):
    # If username provided, keep session alive
    if username and username in client_store:
        client_store[username]["last_active"] = time.time()
        
    return {
        "status": "ok", 
        "active_sessions": len(client_store),
        "timestamp": time.time()
    }


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


# ─── Resend OTP ──────────────────────────────────────────
@app.post("/resend-otp")
async def resend_otp(username: str = Form(...)):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Session expired. Please login again.")

    try:
        result = await session.resend_otp()
        return {"status": result}
    except Exception as e:
        print(f"Resend OTP Error: {e}")
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
        # New parser returns dict with {cgpa, credits_registered, credits_earned, courses}
        if isinstance(data, dict):
            return {"grades": data}
        return {"grades": {"courses": data, "cgpa": "N/A", "credits_registered": "N/A", "credits_earned": "N/A"}}
    except Exception as e:
        print(f"Grades Error: {e}")
        return {"grades": {"courses": [], "cgpa": "N/A", "credits_registered": "N/A", "credits_earned": "N/A"}}


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
        # Pass None to get ALL exam types; parser extracts type from header rows
        data = await session.get_exam_schedule(semester_id=semester_id, exam_type=exam_type)
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


# ─── Mentor ──────────────────────────────────────────────
@app.get("/mentor")
async def mentor(username: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        data = await session.get_profile()
        return {"mentor": data.get("mentor", "")}
    except Exception as e:
        print(f"Mentor Error: {e}")
        return {"mentor": ""}


# ─── CGPA ────────────────────────────────────────────────
@app.get("/cgpa")
async def cgpa(username: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        data = await session.get_cgpa()
        return {"cgpa": data}
    except Exception as e:
        print(f"CGPA Error: {e}")
        return {"cgpa": {"cgpa": 0.0, "total_credits": 0.0}}


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


# ─── Faculty Search ──────────────────────────────────────
@app.get("/faculty")
async def faculty(username: str, search_term: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        data = await session.get_faculty_details(search_term)
        return {"faculty": data}
    except Exception as e:
        print(f"Faculty Error: {e}")
        return {"faculty": []}


# ─── Digital Assignments ───────────────────────────────
@app.get("/digital-assignments")
async def digital_assignments(username: str, semester_id: Optional[str] = None):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        data = await session.get_digital_assignments(semester_id=semester_id)
        return {"digital_assignments": data}
    except Exception as e:
        print(f"DA Error: {e}")
        return {"digital_assignments": []}


# ─── Outing ──────────────────────────────────────────────
@app.get("/outing")
async def outing(username: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        data = await session.get_outing_status()
        return {"outing": data}
    except Exception as e:
        print(f"Outing Error: {e}")
        return {"outing": []}


# ─── Payments ────────────────────────────────────────────
@app.get("/payments")
async def payments(username: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        data = await session.get_payment_history()
        return {"payments": data}
    except Exception as e:
        print(f"Payments Error: {e}")
        return {"payments": []}


# ─── Courses ─────────────────────────────────────────────
@app.get("/courses")
async def courses(username: str, semester_id: Optional[str] = None):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        data = await session.get_courses(semester_id=semester_id)
        return {"courses": data}
    except Exception as e:
        print(f"Courses Error: {e}")
        return {"courses": []}



# ─── New Outing Methods ──────────────────────────────────
@app.get("/outing/weekend")
async def outing_weekend(username: str):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        data = await session.get_weekend_outing_status()
        return {"outing": data}
    except Exception as e:
        print(f"Weekend Outing Error: {e}")
        return {"outing": []}

@app.post("/outing/apply/general")
async def outing_apply_general(
    username: str = Form(...),
    place: str = Form(...),
    purpose: str = Form(...),
    outDate: str = Form(...),
    outTime: str = Form(...),
    inDate: str = Form(...),
    inTime: str = Form(...)
):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        msg = await session.apply_general_outing(place, purpose, outDate, outTime, inDate, inTime)
        return {"status": "success" if "success" in msg.lower() else "failed", "message": msg}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/outing/apply/weekend")
async def outing_apply_weekend(
    username: str = Form(...),
    place: str = Form(...),
    purpose: str = Form(...),
    outDate: str = Form(...),
    outTime: str = Form(...),
    contact: str = Form(...)
):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        msg = await session.apply_weekend_outing(place, purpose, outDate, outTime, contact)
        return {"status": "success" if "success" in msg.lower() else "failed", "message": msg}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/outing/delete/general")
async def outing_delete_general(username: str = Form(...), leaveId: str = Form(...)):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        msg = await session.delete_general_outing(leaveId)
        return {"status": "success" if "success" in msg.lower() else "failed", "message": msg}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/outing/delete/weekend")
async def outing_delete_weekend(username: str = Form(...), bookingId: str = Form(...)):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        msg = await session.delete_weekend_outing(bookingId)
        return {"status": "success" if "success" in msg.lower() else "failed", "message": msg}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

from fastapi.responses import Response

@app.get("/outing/pdf/general")
async def outing_pdf_general(username: str, leaveId: str):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        pdf_bytes = await session.get_general_outing_pdf(leaveId)
        return Response(content=pdf_bytes, media_type="application/pdf")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/outing/pdf/weekend")
async def outing_pdf_weekend(username: str, bookingId: str):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        pdf_bytes = await session.get_weekend_outing_pdf(bookingId)
        return Response(content=pdf_bytes, media_type="application/pdf")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ─── Logout ──────────────────────────────────────────────
@app.post("/logout")
async def logout(username: str = Form(...)):
    await cleanup_session(username)
    return {"status": "logged_out"}