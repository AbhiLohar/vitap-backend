import asyncio
import time
import platform
if platform.system() == "Windows":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

from fastapi import FastAPI, Form, HTTPException, Request
from fastapi.responses import JSONResponse, Response
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional
import uvicorn
from vtop_scraper import VTOPSession

app = FastAPI(title="VTOP Backend")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

sessions = {}

def get_session(username: str) -> Optional[VTOPSession]:
    return sessions.get(username)

def handle_exception(e: Exception):
    err_str = str(e).lower()
    if "session expired" in err_str or "not logged in" in err_str:
        raise HTTPException(status_code=401, detail=str(e))
    raise HTTPException(status_code=500, detail=str(e))


# ── Health ──────────────────────────────────────────────────────────────────
@app.get("/health")
async def health():
    return {"status": "ok"}


# ── Auth ─────────────────────────────────────────────────────────────────────
@app.post("/login")
async def login(username: str = Form(...), password: str = Form(...)):
    scraper = VTOPSession()
    try:
        status = await scraper.login(username, password)
        if status in ("success", "otp_required"):
            sessions[username] = scraper
        return {"status": status, "detail": "Login successful" if status == "success" else "OTP Required"}
    except Exception as e:
        handle_exception(e)

@app.post("/verify-otp")
async def verify_otp(username: str = Form(...), otp: str = Form(...)):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        status = await session.submit_otp(otp)
        return {"status": status}
    except Exception as e:
        handle_exception(e)

@app.post("/resend-otp")
async def resend_otp(username: str = Form(...)):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        status = await session.resend_otp()
        return {"status": status}
    except Exception as e:
        handle_exception(e)

@app.post("/logout")
async def logout(username: str = Form(...)):
    sessions.pop(username, None)
    return {"status": "success"}


# ── Session cookies (used by WebView) ────────────────────────────────────────
@app.get("/session-cookies")
async def session_cookies(username: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        cookies = [{"name": n, "value": v} for n, v in session.client.cookies.items()]
        return {"cookies": cookies}
    except Exception as e:
        handle_exception(e)

# Alias used by some older Flutter code
@app.get("/cookies")
async def cookies(username: str):
    return await session_cookies(username)


# ── Semesters ────────────────────────────────────────────────────────────────
@app.get("/semesters")
async def semesters(username: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"semesters": await session.get_semesters()}
    except Exception as e:
        handle_exception(e)


# ── Timetable ────────────────────────────────────────────────────────────────
@app.get("/timetable")
async def timetable(username: str, semester_id: Optional[str] = None):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"timetable": await session.get_timetable(semester_id)}
    except Exception as e:
        handle_exception(e)


# ── Attendance ───────────────────────────────────────────────────────────────
@app.get("/attendance")
async def attendance(username: str, semester_id: Optional[str] = None):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"attendance": await session.get_attendance(semester_id)}
    except Exception as e:
        handle_exception(e)

@app.get("/attendance/detail")
async def attendance_detail(username: str, semester_id: str, course_id: str, course_type: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"details": await session.get_attendance_detail(semester_id, course_id, course_type)}
    except Exception as e:
        handle_exception(e)


# ── Marks ────────────────────────────────────────────────────────────────────
@app.get("/marks")
async def marks(username: str, semester_id: Optional[str] = None):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"marks": await session.get_marks(semester_id)}
    except Exception as e:
        handle_exception(e)


# ── Grades ───────────────────────────────────────────────────────────────────
@app.get("/grades")
async def grades(username: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        data = await session.get_grades()
        return {"grades": {"courses": data, "cgpa": "N/A", "credits_registered": "N/A", "credits_earned": "N/A"}}
    except Exception as e:
        handle_exception(e)


# ── Exam ─────────────────────────────────────────────────────────────────────
@app.get("/exam-types")
async def exam_types(username: str, semester_id: Optional[str] = None):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"exam_types": await session.get_exam_types(semester_id)}
    except Exception as e:
        handle_exception(e)

@app.get("/exam-schedule")
async def exam_schedule(username: str, semester_id: Optional[str] = None, exam_type: Optional[str] = None):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"exam_schedule": await session.get_exam_schedule(semester_id, exam_type)}
    except Exception as e:
        handle_exception(e)


# ── Profile ──────────────────────────────────────────────────────────────────
@app.get("/profile")
async def profile(username: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"profile": await session.get_profile()}
    except Exception as e:
        handle_exception(e)

@app.get("/cgpa")
async def cgpa(username: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"cgpa": await session.get_cgpa()}
    except Exception as e:
        handle_exception(e)

@app.get("/mentor")
async def mentor(username: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        profile_data = await session.get_profile()
        mentor_val = profile_data.get("mentor", "") if isinstance(profile_data, dict) else ""
        return {"mentor": mentor_val}
    except Exception as e:
        handle_exception(e)


# ── Curriculum ───────────────────────────────────────────────────────────────
@app.get("/curriculum")
async def curriculum(username: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"curriculum": await session.get_curriculum()}
    except Exception as e:
        handle_exception(e)


# ── Faculty ──────────────────────────────────────────────────────────────────
@app.get("/faculty")
async def faculty(username: str, search_term: Optional[str] = None):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"faculty": await session.get_faculty_details(search_term or "")}
    except Exception as e:
        handle_exception(e)

@app.get("/faculty/details")
async def faculty_details(username: str, emp_id: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"details": await session.get_faculty_data(emp_id)}
    except Exception as e:
        handle_exception(e)


# ── Digital Assignments ──────────────────────────────────────────────────────
@app.get("/digital-assignments")
async def digital_assignments(username: str, semester_id: Optional[str] = None):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"digital_assignments": await session.get_digital_assignments(semester_id)}
    except Exception as e:
        handle_exception(e)


# ── Outing ───────────────────────────────────────────────────────────────────
@app.get("/outing")
async def outing(username: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"outing": await session.get_outing_status()}
    except Exception as e:
        handle_exception(e)

@app.get("/outing/weekend")
async def outing_weekend(username: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"outing": await session.get_weekend_outing_status()}
    except Exception as e:
        handle_exception(e)

@app.post("/outing/apply/general")
async def outing_apply_general(
    username: str = Form(...), place: str = Form(...), purpose: str = Form(...),
    outDate: str = Form(...), outTime: str = Form(...),
    inDate: str = Form(...), inTime: str = Form(...)
):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        msg = await session.apply_general_outing(place, purpose, outDate, outTime, inDate, inTime)
        status = "failed" if (msg or "").lower().startswith("error") else "success"
        return {"status": status, "message": msg}
    except Exception as e:
        handle_exception(e)

@app.post("/outing/apply/weekend")
async def outing_apply_weekend(
    username: str = Form(...), place: str = Form(...), purpose: str = Form(...),
    outDate: str = Form(...), outTime: str = Form(...), contact: str = Form(...)
):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        msg = await session.apply_weekend_outing(place, purpose, outDate, outTime, contact)
        status = "failed" if (msg or "").lower().startswith("error") else "success"
        return {"status": status, "message": msg}
    except Exception as e:
        handle_exception(e)

@app.post("/outing/delete/general")
async def outing_delete_general(username: str = Form(...), leaveId: str = Form(...)):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        msg = await session.delete_general_outing(leaveId)
        status = "failed" if (msg or "").lower().startswith("error") else "success"
        return {"status": status, "message": msg}
    except Exception as e:
        handle_exception(e)

@app.post("/outing/delete/weekend")
async def outing_delete_weekend(username: str = Form(...), bookingId: str = Form(...)):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        msg = await session.delete_weekend_outing(bookingId)
        status = "failed" if (msg or "").lower().startswith("error") else "success"
        return {"status": status, "message": msg}
    except Exception as e:
        handle_exception(e)


# ── Outing PDFs ──────────────────────────────────────────────────────────────
@app.get("/outing/pdf/general")
async def outing_pdf_general(username: str, leave_id: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        pdf_bytes = await session.get_general_outing_pdf(leave_id)
        return Response(content=pdf_bytes, media_type="application/pdf")
    except Exception as e:
        handle_exception(e)

@app.get("/outing/pdf/weekend")
async def outing_pdf_weekend(username: str, booking_id: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        pdf_bytes = await session.get_weekend_outing_pdf(booking_id)
        return Response(content=pdf_bytes, media_type="application/pdf")
    except Exception as e:
        handle_exception(e)


# ── Payments ─────────────────────────────────────────────────────────────────
@app.get("/payments")
async def payments(username: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"payments": await session.get_payment_history()}
    except Exception as e:
        handle_exception(e)

@app.get("/payments/receipt")
async def payment_receipt(username: str, receipt_id: str):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        data = await session.get_payment_receipt_details(receipt_id)
        if isinstance(data, dict) and "error" in data:
            handle_exception(Exception(data["error"]))
        return data
    except Exception as e:
        handle_exception(e)


# ── Courses ──────────────────────────────────────────────────────────────────
@app.get("/courses")
async def courses(username: str, semester_id: Optional[str] = None):
    session = get_session(username)
    if not session:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"courses": await session.get_courses(semester_id)}
    except Exception as e:
        handle_exception(e)


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)