import asyncio
import time
import platform
if platform.system() == "Windows":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

from fastapi import FastAPI, Form, HTTPException, Request, Response
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional
import uvicorn
from vtop_scraper import VtopScraper

app = FastAPI(title="VTOP Backend")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

sessions = {}

def get_session(username: str) -> Optional[VtopScraper]:
    return sessions.get(username)

def handle_exception(e: Exception):
    err_str = str(e).lower()
    if "session expired" in err_str or "not logged in" in err_str:
        raise HTTPException(status_code=401, detail=str(e))
    raise HTTPException(status_code=500, detail=str(e))

@app.post("/login")
async def login(username: str = Form(...), password: str = Form(...)):
    scraper = VtopScraper()
    try:
        status = await scraper.login(username, password)
        if status == "success" or status == "otp_required":
            sessions[username] = scraper
        return {"status": status, "detail": "Login successful" if status == "success" else "OTP Required"}
    except Exception as e:
        handle_exception(e)

@app.post("/verify-otp")
async def verify_otp(username: str = Form(...), otp: str = Form(...)):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        status = await session.submit_otp(otp)
        return {"status": status}
    except Exception as e:
        handle_exception(e)

@app.post("/resend-otp")
async def resend_otp(username: str = Form(...)):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        status = await session.resend_otp()
        return {"status": status}
    except Exception as e:
        handle_exception(e)

@app.get("/timetable")
async def timetable(username: str, semester_id: Optional[str] = None):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"timetable": await session.get_timetable(semester_id)}
    except Exception as e:
        handle_exception(e)

@app.get("/attendance")
async def attendance(username: str, semester_id: Optional[str] = None):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"attendance": await session.get_attendance(semester_id)}
    except Exception as e:
        handle_exception(e)

@app.get("/attendance/detail")
async def attendance_detail(username: str, semester_id: str, course_id: str, course_type: str):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"details": await session.get_attendance_detail(semester_id, course_id, course_type)}
    except Exception as e:
        handle_exception(e)

@app.get("/marks")
async def marks(username: str, semester_id: Optional[str] = None):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"marks": await session.get_marks(semester_id)}
    except Exception as e:
        handle_exception(e)

@app.get("/grades")
async def grades(username: str):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        # Compatibility with frontend
        return {"grades": {"courses": await session.get_grades(), "cgpa": "N/A", "credits_registered": "N/A", "credits_earned": "N/A"}}
    except Exception as e:
        handle_exception(e)

@app.get("/exam-types")
async def exam_types(username: str, semester_id: Optional[str] = None):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"exam_types": await session.get_exam_types(semester_id)}
    except Exception as e:
        handle_exception(e)

@app.get("/exam-schedule")
async def exam_schedule(username: str, semester_id: Optional[str] = None, exam_type: Optional[str] = None):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"exam_schedule": await session.get_exam_schedule(semester_id, exam_type)}
    except Exception as e:
        handle_exception(e)

@app.get("/profile")
async def profile(username: str):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"profile": await session.get_profile()}
    except Exception as e:
        handle_exception(e)

@app.get("/cgpa")
async def cgpa(username: str):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"cgpa": await session.get_cgpa()}
    except Exception as e:
        handle_exception(e)

@app.get("/mentor")
async def mentor(username: str):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        profile_data = await session.get_profile()
        return {"mentor": profile_data.get("mentor", "")}
    except Exception as e:
        handle_exception(e)

@app.get("/cookies")
async def get_cookies(username: str):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        cookies = []
        for name, value in session.client.cookies.items():
            cookies.append({"name": name, "value": value})
        return {"cookies": cookies}
    except Exception as e:
        handle_exception(e)

@app.get("/curriculum")
async def curriculum(username: str):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"curriculum": await session.get_curriculum()}
    except Exception as e:
        handle_exception(e)

@app.get("/faculty")
async def faculty(username: str):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"faculty": await session.get_faculty_details("")}
    except Exception as e:
        handle_exception(e)

@app.get("/faculty/details")
async def faculty_details(username: str, emp_id: str):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"details": await session.get_faculty_data(emp_id)}
    except Exception as e:
        handle_exception(e)

@app.get("/digital-assignments")
async def digital_assignments(username: str, semester_id: Optional[str] = None):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"digital_assignments": await session.get_digital_assignments(semester_id)}
    except Exception as e:
        handle_exception(e)

@app.get("/outing")
async def outing(username: str):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"outing": await session.get_outing_status()}
    except Exception as e:
        handle_exception(e)

@app.get("/outing/weekend")
async def outing_weekend(username: str):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
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
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        msg = await session.apply_general_outing(place, purpose, outDate, outTime, inDate, inTime)
        status = "failed" if msg.lower().startswith("error") else "success"
        return {"status": status, "message": msg}
    except Exception as e:
        handle_exception(e)

@app.post("/outing/apply/weekend")
async def outing_apply_weekend(
    username: str = Form(...), place: str = Form(...), purpose: str = Form(...),
    outDate: str = Form(...), outTime: str = Form(...), contact: str = Form(...)
):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        msg = await session.apply_weekend_outing(place, purpose, outDate, outTime, contact)
        status = "failed" if msg.lower().startswith("error") else "success"
        return {"status": status, "message": msg}
    except Exception as e:
        handle_exception(e)

@app.post("/outing/delete/general")
async def outing_delete_general(username: str = Form(...), leaveId: str = Form(...)):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        msg = await session.delete_general_outing(leaveId)
        status = "failed" if msg.lower().startswith("error") else "success"
        return {"status": status, "message": msg}
    except Exception as e:
        handle_exception(e)

@app.post("/outing/delete/weekend")
async def outing_delete_weekend(username: str = Form(...), bookingId: str = Form(...)):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        msg = await session.delete_weekend_outing(bookingId)
        status = "failed" if msg.lower().startswith("error") else "success"
        return {"status": status, "message": msg}
    except Exception as e:
        handle_exception(e)

@app.get("/payments")
async def payments(username: str):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"payments": await session.get_payment_history()}
    except Exception as e:
        handle_exception(e)

@app.get("/payments/receipt")
async def payment_receipt(username: str, receipt_id: str):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        data = await session.get_payment_receipt_details(receipt_id)
        if "error" in data:
            handle_exception(Exception(data["error"]))
        return data
    except Exception as e:
        handle_exception(e)

@app.get("/courses")
async def courses(username: str, semester_id: Optional[str] = None):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"courses": await session.get_courses(semester_id)}
    except Exception as e:
        handle_exception(e)

@app.get("/semesters")
async def semesters(username: str):
    session = get_session(username)
    if not session: raise HTTPException(status_code=401, detail="Not logged in")
    try:
        return {"semesters": await session.get_semesters()}
    except Exception as e:
        handle_exception(e)

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)