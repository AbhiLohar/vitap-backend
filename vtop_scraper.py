"""
VTOP HTTP-based scraper with automatic captcha solving.
Replaces Playwright browser automation with pure HTTP requests.
Inspired by vitap-vtop-client library.
"""
import os
import json
import base64
import io
import re
import asyncio
import time
from datetime import datetime, timezone
import httpx
from bs4 import BeautifulSoup
from PIL import Image, ImageFilter

# ── Constants ──────────────────────────────────────────────
VTOP_BASE = "https://vtop.vitap.ac.in"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Connection": "close",
    "Origin": "https://vtop.vitap.ac.in",
    "Referer": "https://vtop.vitap.ac.in/vtop/",
}

ROUTES = {
    "open_page":    "/vtop/open/page",
    "prelogin":     "/vtop/prelogin/setup",
    "login":        "/vtop/login",
    "login_error":  "/vtop/login/error",
    "content":      "/vtop/content",
    "home":         "/vtop/home",
    "attendance":   "/vtop/academics/common/StudentAttendance",
    "view_attend":  "/vtop/processViewStudentAttendance",
    "timetable":    "/vtop/academics/common/StudentTimeTable",
    "view_tt":      "/vtop/processViewTimeTable",
    "marks":        "/vtop/examinations/StudentMarkView",
    "view_marks":   "/vtop/examinations/doStudentMarkView",
    "grade_hist":   "/vtop/examinations/examGradeView/StudentGradeHistory",
    "exam_sched":   "/vtop/examinations/StudExamSchedule",
    "view_exam":    "/vtop/examinations/doSearchExamScheduleForStudent",
    "profile":      "/vtop/studentsRecord/StudentProfileAllView",
    "proctor":      "/vtop/proctor/viewProctorDetails",
    "curriculum":   "/vtop/academics/common/Curriculum",
    "faculty":      "/vtop/hrms/EmployeeSearchForStudent",
    "outing":       "/vtop/hostel/StudentGeneralOuting",
    "da":           "/vtop/examinations/doDigitalAssignment",
    "payments":     "/vtop/p2p/getReceiptsApplno",
}

# ── VIT-AP Program & Branch Resolution Map ─────────────────
VITAP_BRANCH_MAP = {
    "BCE": {
        "program": "B.Tech",
        "branch": "Computer Science and Engineering",
        "school": "School of Computer Science and Engineering (SCOPE)",
    },
    "BCN": {
        "program": "B.Tech",
        "branch": "Computer Science and Engineering (Networking)",
        "school": "School of Computer Science and Engineering (SCOPE)",
    },
    "BAI": {
        "program": "B.Tech",
        "branch": "Computer Science and Engineering (Artificial Intelligence)",
        "school": "School of Computer Science and Engineering (SCOPE)",
    },
    "BDS": {
        "program": "B.Tech",
        "branch": "Computer Science and Engineering (Data Science)",
        "school": "School of Computer Science and Engineering (SCOPE)",
    },
    "BCS": {
        "program": "B.Tech",
        "branch": "Computer Science and Engineering (Cyber Security)",
        "school": "School of Computer Science and Engineering (SCOPE)",
    },
    "BSB": {
        "program": "B.Tech",
        "branch": "Computer Science and Business Systems",
        "school": "School of Computer Science and Engineering (SCOPE)",
    },
    "BIT": {
        "program": "B.Tech",
        "branch": "Information Technology",
        "school": "School of Computer Science and Engineering (SCOPE)",
    },
    "BEC": {
        "program": "B.Tech",
        "branch": "Electronics and Communication Engineering",
        "school": "School of Electronics Engineering (SENSE)",
    },
    "ECE": {
        "program": "B.Tech",
        "branch": "Electronics and Communication Engineering",
        "school": "School of Electronics Engineering (SENSE)",
    },
    "BVL": {
        "program": "B.Tech",
        "branch": "Electronics and Communication Engineering (VLSI)",
        "school": "School of Electronics Engineering (SENSE)",
    },
    "BME": {
        "program": "B.Tech",
        "branch": "Mechanical Engineering",
        "school": "School of Mechanical Engineering (SMEC)",
    },
    "MEE": {
        "program": "B.Tech",
        "branch": "Mechanical Engineering",
        "school": "School of Mechanical Engineering (SMEC)",
    },
    "BBA": {
        "program": "BBA",
        "branch": "Bachelor of Business Administration",
        "school": "VIT-AP School of Business (VSB)",
    },
    "BLA": {
        "program": "B.A., LL.B. (Hons.)",
        "branch": "Law",
        "school": "VIT-AP School of Law (VITSOL)",
    },
    "BLB": {
        "program": "BBA, LL.B. (Hons.)",
        "branch": "Law",
        "school": "VIT-AP School of Law (VITSOL)",
    },
    "MCE": {
        "program": "M.Tech",
        "branch": "Computer Science and Engineering",
        "school": "School of Computer Science and Engineering (SCOPE)",
    },
    "MSE": {
        "program": "M.Tech",
        "branch": "Software Engineering",
        "school": "School of Computer Science and Engineering (SCOPE)",
    },
    "MIS": {
        "program": "Integrated M.Tech",
        "branch": "Computer Science and Engineering",
        "school": "School of Computer Science and Engineering (SCOPE)",
    },
    "MSC": {
        "program": "M.Sc",
        "branch": "Data Science",
        "school": "School of Advanced Sciences (SAS)",
    },
    "PHD": {
        "program": "Ph.D",
        "branch": "Doctor of Philosophy",
        "school": "Research",
    },
}

# Known semester IDs for VIT-AP (fallback when dropdown not found)
# Pattern: AP{start_year}{end_year_last_digit}{type}
# Types: 2=Fall, 4=Winter, 5=Summer-1, 6=Summer-2, 7=Summer
KNOWN_SEMESTERS = {
    "Fall Semester 2026-27 - AMR": "AP2026272",
    "FALL SEM 2026-27": "AP2026272",
    "Fall Semester 2026-27": "AP2026272",
    "Short Summer Semester II 2025-26 - AMR": "AP2025266",
    "Winter Semester 2025-26 - AMR": "AP2025264",
    "Fall Semester 2025-26 - AMR": "AP2025262",
    "Summer Semester - 1 2025-26": "AP2025265",
    "Winter Semester 2025-26": "AP2025264",
    "FALL SEM 2025-26": "AP2025262",
    "Summer Semester 2024-25": "AP2024257",
    "Summer Semester - 2 2024-25": "AP2024256",
    "Summer Semester - 1 2024-25": "AP2024255",
    "Winter Semester 2024-25": "AP2024254",
    "FALL SEM 2024-25": "AP2024252",
    "Summer Semester 2023-24": "AP2023247",
    "Summer Semester - 2 2023-24": "AP2023246",
    "Summer Semester - 1 2023-24": "AP2023245",
    "Winter Semester 2023-24": "AP2023244",
    "FALL SEM 2023-24": "AP2023242",
    "Summer Semester 2022-23": "AP2022237",
    "Summer Semester - 1 2022-23": "AP2022235",
    "Winter Semester 2022-23": "AP2022234",
    "FALL SEM 2022-23": "AP2022232",
    "Summer Semester 2021-22": "AP2021227",
    "Summer Semester - 1 2021-22": "AP2021225",
    "Winter Semester 2021-22": "AP2021224",
    "FALL SEM 2021-22": "AP2021222",
    "Summer Semester 2020-21": "AP2020217",
    "Winter Semester 2020-21": "AP2020214",
    "FALL SEM 2020-21": "AP2020212",
}


# ── Captcha Solver ─────────────────────────────────────────
def _solve_captcha_image(b64_data: str) -> str:
    """
    Solve VTOP captcha using custom ML model.
    VTOP captchas are always 6 alphanumeric characters.
    """
    try:
        from vtop_captcha import solve_vtop_captcha
        text = solve_vtop_captcha(b64_data)
        return text
    except Exception as e:
        print(f"Captcha solve error: {e}")
        return ""


def _find_csrf(html: str) -> str:
    """Extract CSRF token from HTML page."""
    soup = BeautifulSoup(html, "lxml")
    meta = soup.find("meta", attrs={"name": "_csrf"})
    if meta and meta.get("content"):
        return meta["content"]
    inp = soup.find("input", attrs={"name": "_csrf"})
    if inp and inp.get("value"):
        return inp["value"]
    # Try regex fallback
    m = re.search(r'name="_csrf"\s+content="([^"]+)"', html)
    if m:
        return m.group(1)
    m = re.search(r'name="_csrf"\s+value="([^"]+)"', html)
    if m:
        return m.group(1)
    return ""


def _normalize_outing_date(date_str: str) -> str:
    """Normalize date string to standard VTOP format 'DD-MMM-YYYY' (e.g. '09-Sep-2026')."""
    if not date_str:
        return ""
    date_str = date_str.strip()
    for fmt in ("%d-%b-%Y", "%d-%B-%Y", "%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y"):
        try:
            dt = datetime.strptime(date_str, fmt)
            return dt.strftime("%d-%b-%Y")
        except ValueError:
            pass
    # If date_str looks like "09-SEP-2026", convert month to title-case: "09-Sep-2026"
    parts = date_str.split("-")
    if len(parts) == 3 and len(parts[1]) == 3:
        return f"{parts[0]}-{parts[1].capitalize()}-{parts[2]}"
    return date_str


def _find_captcha_b64(html: str) -> str:
    """Extract base64 captcha image from login page HTML."""
    soup = BeautifulSoup(html, "lxml")
    imgs = soup.find_all("img")
    for img in imgs:
        src = img.get("src", "")
        if src.startswith("data:image"):
            return src
    return ""


def _find_login_error(html: str) -> str:
    """Extract login error message from error page."""
    soup = BeautifulSoup(html, "lxml")
    for sel in ["#errMsg", "#errorMsg", ".alert-danger", ".alert", ".error-msg", "p.text-danger", "span.text-danger", ".text-danger", "#otpErrorMsg"]:
        el = soup.select_one(sel)
        if el and el.get_text(strip=True):
            err_text = el.get_text(strip=True)
            if "captcha" in err_text.lower():
                return "Invalid Captcha"
            return err_text
            
    text = soup.get_text(separator=" ", strip=True)
    text_lower = text.lower()
    if "invalid captcha" in text_lower or "captcha does not match" in text_lower:
        return "Invalid Captcha"
    if "maximum fail attempts" in text_lower or "account locked" in text_lower:
        return "Account locked: Maximum fail attempts reached. Please use Forgot Password."
    if "invalid" in text_lower and ("user" in text_lower or "password" in text_lower or "credential" in text_lower):
        return "Invalid Credentials"
    if "user id not available" in text_lower or ("not available" in text_lower and "user" in text_lower):
        return "User Id Not Available"
    if "incorrect password" in text_lower or "password does not match" in text_lower:
        return "Incorrect Password"
        
    return f"Unknown Error: {text[:100]}"


def _analyze_login_response(resp) -> tuple[str, str]:
    """
    Analyzes the VTOP login response and returns (category, detail_message).
    Categories:
      - 'success': Login succeeded, session active on content page.
      - 'otp_required': Genuine two-factor OTP verification pending.
      - 'invalid_credentials': Wrong username, wrong password, or user not available.
      - 'account_locked': Max fail attempts reached.
      - 'invalid_captcha': Captcha mispredicted by solver (safe to retry).
      - 'retry': Transient session drop / Tomcat 404 / redirect back to login without error.
      - 'unknown': Truly unrecognized error page.
    """
    import re
    final_url = str(resp.url).lower()
    html = resp.text
    text_lower = html.lower()
    
    # 1. Success check
    if "/vtop/content" in final_url or ROUTES.get("content", "/vtop/content") in final_url:
        return "success", "Login successful"
        
    soup = BeautifulSoup(html, "lxml")
    
    # Extract error message from alert/error elements
    error_msg = ""
    for sel in [
        ".alert", "#errMsg", "#errorMsg", ".alert-danger", ".error-msg",
        "p.text-danger", "span.text-danger", "div.text-danger", ".text-danger",
        "#otpErrorMsg"
    ]:
        el = soup.select_one(sel)
        if el and el.get_text(strip=True):
            error_msg = el.get_text(strip=True)
            break
            
    err_lower = error_msg.lower()
    
    # 2. Account Locked / Max Attempts (PRIORITY: Stop immediately to avoid further locking)
    locked_indicators = [
        "maximum fail attempts reached",
        "maximum failed attempts",
        "account locked",
        "account is locked",
        "max attempt",
    ]
    if any(k in err_lower or k in text_lower for k in locked_indicators):
        return "account_locked", "Account locked due to maximum failed attempts. Please use Forgot Password on VTOP."

    # 3. Invalid Credentials (WRONG PASSWORD / WRONG USERNAME / NOT FOUND)
    # Stop immediately! Do NOT retry in a loop!
    credential_indicators = [
        "invalid user id / password",
        "invalid user id/password",
        "invalid user id",
        "invalid user",
        "invalid password",
        "invalid credential",
        "user id not available",
        "user id does not exist",
        "user not found",
        "incorrect password",
        "password does not match",
        "authentication failed",
        "bad credentials",
        "check user id and password",
    ]
    if any(ind in err_lower for ind in credential_indicators) or \
       (any(ind in text_lower for ind in credential_indicators) and "invalid captcha" not in err_lower):
        clean_msg = error_msg if error_msg else "Invalid Username or Password. Please check your credentials and try again."
        return "invalid_credentials", clean_msg

    # 4. Invalid Captcha (The ONLY error that should trigger a retry!)
    if "invalid captcha" in err_lower or "captcha does not match" in err_lower or "captcha expired" in err_lower:
        return "invalid_captcha", "Invalid captcha"
    if "invalid captcha" in text_lower and not any(ind in text_lower for ind in credential_indicators):
        return "invalid_captcha", "Invalid captcha"

    # 5. Genuine OTP check (Strict criteria: NEVER match generic 'otp' substring in page text)
    has_otp_js = bool(re.search(r'var\s+securityOtpPending\s*=\s*(true|\'true\'|\"true\")', html, re.IGNORECASE))
    has_otp_sent_at = bool(re.search(r'var\s+otpSentAt\s*=\s*\d+', html))
    has_otp_input = bool(soup.find("input", {"name": "otpCode"}) or soup.find(id="otpCode"))
    has_otp_url = "/vtop/otp" in final_url or "twofactor" in final_url
    has_otp_phrase = any(phrase in text_lower for phrase in [
        "otp has been sent to your registered",
        "an otp has been sent to your registered",
        "enter the otp sent to",
        "enter the 6-digit otp",
        "otp sent to your registered email",
        "otp sent to your mail id"
    ])
    
    if has_otp_js or has_otp_sent_at or has_otp_input or has_otp_url or has_otp_phrase:
        return "otp_required", "OTP required"

    # 6. Tomcat 404 / Session drop
    if resp.status_code == 404 or "http status 404" in text_lower or "apache tomcat" in text_lower:
        return "retry", "Tomcat 404 error"

    # 7. Landed back on /vtop/login or /vtop/login/error
    if final_url.rstrip("/").endswith("/vtop/login") or final_url.rstrip("/").endswith("/vtop/login/error"):
        if err_lower:
            if "captcha" in err_lower:
                return "invalid_captcha", "Invalid captcha"
            return "invalid_credentials", error_msg
        return "retry", "Redirected to login"

    return "unknown", f"Unknown response ({final_url})"


# ── VTOP Session Class ─────────────────────────────────────
class VTOPSession:
    """HTTP-based VTOP session manager with auto captcha solving."""
    
    def __init__(self):
        self.client = httpx.AsyncClient(
            timeout=30.0,
            follow_redirects=True,
            base_url=VTOP_BASE,
            headers=HEADERS,
            verify=False,
        )
        self.csrf_token = ""
        self.post_login_csrf = ""
        self.registration_number = ""
        self.logged_in = False
        self._otp_required = False
        self._initialized_pages = set()
        self._cache = {} # Simple in-memory cache for frequently accessed data
    
    async def login(self, username: str, password: str, max_retries: int = 20) -> str:
        """
        Full login flow with improved resilience for captcha retries.
        """
        self.registration_number = username.upper()
        
        # Initial setup: Get CSRF and establish session
        try:
            resp = await self.client.get(ROUTES["open_page"])
            resp.raise_for_status()
            self.csrf_token = _find_csrf(resp.text)
            
            pre_data = {"_csrf": self.csrf_token, "flag": "VTOP"}
            await self.client.post(ROUTES["prelogin"], data=pre_data)
        except Exception as e:
            print(f"Initial setup failed: {e}")
            raise Exception("Could not reach VTOP. Please try again later.")

        for attempt in range(max_retries):
            print(f"Login attempt {attempt + 1}/{max_retries} for {username[:5]}****")
            try:
                # Get current login page to ensure we have fresh CSRF and Captcha
                resp = await self.client.get(ROUTES["login"])
                resp.raise_for_status()
                
                # Update CSRF from current page (crucial for retries)
                current_csrf = _find_csrf(resp.text)
                if current_csrf:
                    self.csrf_token = current_csrf
                
                # Check if VTOP assigned Google ReCaptcha (captchaType=2) or Image (captchaType=1)
                import re as regex
                m = regex.search(r'var\s+captchaType\s*=\s*(\d+)', resp.text)
                c_type = m.group(1) if m else "unknown"
                
                if c_type == "2":
                    print(f"VTOP requested Google reCaptcha, refreshing session... (attempt {attempt + 1})")
                    # Must re-initialize
                    try:
                        resp = await self.client.get(ROUTES["open_page"])
                        self.csrf_token = _find_csrf(resp.text)
                        pre_data = {"_csrf": self.csrf_token, "flag": "VTOP"}
                        await self.client.post(ROUTES["prelogin"], data=pre_data)
                    except Exception:
                        pass
                    await asyncio.sleep(0.1)
                    continue
                
                # For captchaType=1, fetch the image via AJAX endpoint
                captcha_resp = await self.client.get("/vtop/get/new/captcha")
                captcha_b64 = _find_captcha_b64(captcha_resp.text)
                
                if not captcha_b64:
                    print("Captcha not found even for captchaType=1, retrying...")
                    await asyncio.sleep(0.1)
                    continue
                
                # Solve captcha
                solved = _solve_captcha_image(captcha_b64)
                if not solved or len(solved) != 6:
                    print(f"Bad captcha result '{solved}' (len={len(solved) if solved else 0}), retrying...")
                    await asyncio.sleep(0.1)
                    continue
                print(f"Captcha solved: {solved}")
                
                # Submit login
                login_data = {
                    "_csrf": self.csrf_token,
                    "username": self.registration_number,
                    "password": password,
                    "captchaStr": solved,
                    "gResponse": "",
                }
                resp = await self.client.post(ROUTES["login"], data=login_data)
                
                # Analyze login response systematically
                category, detail = _analyze_login_response(resp)
                print(f"Login attempt {attempt + 1} analysis: category='{category}', detail='{detail}'")
                
                # 1. Successful login
                if category == "success":
                    print("Login successful, extracting profile...")
                    self.post_login_csrf = _find_csrf(resp.text)
                    content_html = resp.text
                    if not self.post_login_csrf:
                        content_resp = await self.client.get(ROUTES["content"])
                        content_html = content_resp.text
                        self.post_login_csrf = _find_csrf(content_html)
                    
                    import re
                    reg_match = re.search(r'\b(\d{2}[A-Z]{2,4}\d{3,5})\b', content_html, re.IGNORECASE)
                    if reg_match:
                        real_reg_no = reg_match.group(1).upper()
                        print(f"Extracted actual Registration Number: {real_reg_no} (Login ID used: {self.registration_number})")
                        self.registration_number = real_reg_no

                    self.logged_in = True
                    return "success"
                
                # 2. Genuine OTP required
                elif category == "otp_required":
                    print("OTP required detected.")
                    self._otp_required = True
                    new_csrf = _find_csrf(resp.text)
                    if new_csrf:
                        self.csrf_token = new_csrf
                    print("Triggering OTP email delivery...")
                    await self.resend_otp()
                    return "otp_required"
                    
                # 3. Invalid credentials (wrong password / user not found) — STOP IMMEDIATELY!
                elif category == "invalid_credentials":
                    print(f"Login rejected: Invalid credentials. Message: {detail}")
                    return "invalid_credentials"
                    
                # 4. Account locked — STOP IMMEDIATELY!
                elif category == "account_locked":
                    print(f"Login rejected: Account locked. Message: {detail}")
                    return "Account locked: Maximum fail attempts reached. Please use Forgot Password on VTOP."
                    
                # 5. Invalid captcha — retry with fresh captcha
                elif category == "invalid_captcha":
                    print(f"Login attempt {attempt + 1}: Invalid captcha, retrying with fresh captcha...")
                    self.csrf_token = _find_csrf(resp.text)
                    await asyncio.sleep(0.1)
                    continue
                    
                # 6. Transient state / Tomcat 404 / clean redirect
                elif category == "retry":
                    print(f"Transient session state ({detail}), attempt {attempt + 1}/{max_retries}")
                    if attempt >= 4:
                        # If multiple attempts land on login page without captcha error, credentials rejected
                        print("Multiple login redirects without captcha error: stopping to prevent account lock.")
                        return "invalid_credentials"
                    try:
                        resp = await self.client.get(ROUTES["open_page"])
                        self.csrf_token = _find_csrf(resp.text)
                        pre_data = {"_csrf": self.csrf_token, "flag": "VTOP"}
                        await self.client.post(ROUTES["prelogin"], data=pre_data)
                    except Exception:
                        pass
                    await asyncio.sleep(0.1)
                    continue
                    
                # 7. Unrecognized response
                else:
                    print(f"Unknown login response: {detail}")
                    if attempt >= 2:
                        return "invalid_credentials"
                    await asyncio.sleep(0.1)
                    continue
                    
            except httpx.RequestError as e:
                print(f"Network error: {e}")
                if attempt == max_retries - 1:
                    raise Exception(f"Connection failed after {max_retries} attempts")
                await asyncio.sleep(0.2)
            except Exception as e:
                if "Login failed" in str(e):
                    raise
                print(f"Unexpected error: {e}")
                if attempt == max_retries - 1:
                    raise
                await asyncio.sleep(0.1)
        
        raise Exception("Login failed after maximum captcha retries. Please check your credentials or try again.")
        
    async def submit_otp(self, otp: str) -> str:
        """Submit OTP for two-factor auth using multipart/form-data (required by VTOP)."""
        try:
            # VTOP requires multipart/form-data for OTP validation
            # (confirmed by reference app's Rust implementation using Form::new().text().multipart())
            multipart_files = {
                "otpCode": (None, otp),
                "_csrf": (None, self.csrf_token),
            }
            
            print(f"Submitting OTP to /vtop/validateSecurityOtp (multipart, csrf={self.csrf_token[:20]}...)")
            resp = await self.client.post("/vtop/validateSecurityOtp", files=multipart_files)
            
            print(f"OTP response status: {resp.status_code}, content-type: {resp.headers.get('content-type', 'unknown')}")
            print(f"OTP response body: {resp.text[:200]}")
            
            # Check for JSON response
            if resp.headers.get("content-type", "").startswith("application/json"):
                data = resp.json()
                status = data.get("status", "UNKNOWN")
                print(f"OTP validation status: {status}")
                
                if status == "SUCCESS":
                    redirect_url = data.get("redirectUrl", ROUTES["content"])
                    content_resp = await self.client.get(redirect_url)
                    content_html = content_resp.text
                    self.post_login_csrf = _find_csrf(content_html)
                    
                    # Extract REAL registration number
                    import re
                    reg_match = re.search(r'\b(2[0-9][A-Z]{3}[0-9]{4})\b', content_html, re.IGNORECASE)
                    if reg_match:
                        real_reg_no = reg_match.group(1).upper()
                        print(f"Extracted actual Registration Number from redirect dashboard: {real_reg_no} (Login ID used: {self.registration_number})")
                        self.registration_number = real_reg_no
                        
                    self.logged_in = True
                    return "success"
                elif status == "INVALID":
                    return "invalid_otp"
                elif status == "EXPIRED":
                    return "otp_expired"
                else:
                    message = data.get("message", "Unknown error")
                    print(f"OTP unexpected status: {status} - {message}")
                    return "failed"
            
            # Non-JSON response — check if redirected to content page
            final_url = str(resp.url)
            if "/vtop/content" in final_url or "/vtop/home" in final_url:
                self.post_login_csrf = _find_csrf(resp.text)
                self.logged_in = True
                return "success"
            
            print(f"OTP: Unexpected non-JSON response at {final_url}")
            return "failed"
        except Exception as e:
            print(f"OTP submission error: {e}")
            return "failed"
    
    async def resend_otp(self) -> str:
        """Resend OTP using multiple methods to ensure delivery."""
        try:
            print(f"Resending OTP. CSRF: {self.csrf_token[:10]}...")
            success = False
            
            # Method 1: Regular form data (most common for VTOP)
            try:
                resp1 = await self.client.post("/vtop/resendSecurityOtp", data={"_csrf": self.csrf_token})
                print(f"Resend Method 1 (data) status: {resp1.status_code}, body: {resp1.text[:100]}")
                if "success" in resp1.text.lower() or "sent" in resp1.text.lower() or "true" in resp1.text.lower():
                    success = True
            except Exception as e:
                print(f"Method 1 failed: {e}")

            # Method 2: Multipart form data (fallback)
            if not success:
                try:
                    multipart_files = {"_csrf": (None, self.csrf_token)}
                    resp2 = await self.client.post("/vtop/resendSecurityOtp", files=multipart_files)
                    print(f"Resend Method 2 (multipart) status: {resp2.status_code}, body: {resp2.text[:100]}")
                    if "success" in resp2.text.lower() or "sent" in resp2.text.lower() or "true" in resp2.text.lower():
                        success = True
                except Exception as e:
                    print(f"Method 2 failed: {e}")
                    
            # Method 3: GET request (fallback)
            if not success:
                try:
                    resp3 = await self.client.get("/vtop/resendSecurityOtp")
                    print(f"Resend Method 3 (GET) status: {resp3.status_code}")
                    if resp3.status_code == 200 or "success" in resp3.text.lower() or "sent" in resp3.text.lower():
                        success = True
                except Exception as e:
                    print(f"Method 3 failed: {e}")

            return "success" if success else "failed"
        except Exception as e:
            print(f"Resend OTP error: {e}")
            return "failed"
    
    def _check_session_expired(self, resp: httpx.Response):
        """Check if the response indicates the session has expired."""
        if resp.status_code == 302:
            raise Exception("Session expired. Please log out and log in again.")
        path = str(resp.url.path).lower()
        if "login" in path or path == "/vtop/" or path == "/vtop":
            raise Exception("Session expired. Please log out and log in again.")
        if "login-page" in resp.text.lower() or "you have been successfully logged out" in resp.text.lower():
            raise Exception("Session expired. Please log out and log in again.")
        if "session out" in resp.text.lower() or "session timed out" in resp.text.lower():
            raise Exception("Session expired. Please log out and log in again.")

    async def _post_authenticated(self, url: str, data: dict) -> httpx.Response:
        """Make an authenticated POST request."""
        if not self.logged_in:
            raise Exception("Not logged in")
        data["_csrf"] = self.post_login_csrf or self.csrf_token
        resp = await self.client.post(url, data=data)
        self._check_session_expired(resp)
        return resp

    async def _get_authenticated(self, url: str) -> httpx.Response:
        """Make an authenticated GET request."""
        if not self.logged_in:
            raise Exception("Not logged in")
        resp = await self.client.get(url)
        self._check_session_expired(resp)
        return resp

    async def _post_menu(self, url: str) -> httpx.Response:
        """Initialize a VTOP page with verifyMenu - required for VTOP to load dropdowns."""
        data = {
            "verifyMenu": "true",
            "authorizedID": self.registration_number,
            "_csrf": self.post_login_csrf or self.csrf_token,
            "nocache": str(int(time.time() * 1000)),
        }
        resp = await self.client.post(url, data=data, headers=HEADERS)
        self._check_session_expired(resp)
        fresh_csrf = _find_csrf(resp.text)
        if fresh_csrf:
            self.post_login_csrf = fresh_csrf
        return resp
    
    async def get_semesters(self) -> list:
        """Fetch available semesters dynamically from VTOP pages in parallel."""
        # Check cache first
        if "semesters" in self._cache:
            return self._cache["semesters"]
            
        all_semesters = {}  # id -> name, to deduplicate
        
        # Pages that contain semester dropdowns
        semester_pages = [
            ("attendance", ROUTES["attendance"]),
            ("timetable", ROUTES["timetable"]),
            ("marks", ROUTES["marks"]),
            ("grade_hist", ROUTES["grade_hist"]),
            ("exam_sched", ROUTES["exam_sched"]),
            ("curriculum", ROUTES["curriculum"]),
        ]
        
        async def fetch_one(page_name, route):
            try:
                # Use _post_menu to properly initialize the page
                resp = await self._post_menu(route)
                found = self._extract_semesters_from_html(resp.text)
                return found
            except Exception as e:
                print(f"Error fetching semesters from {page_name}: {e}")
                return []

        # Run all fetches in parallel
        results = await asyncio.gather(*(fetch_one(p, r) for p, r in semester_pages))
        
        for found in results:
            for sem in found:
                all_semesters[sem["id"]] = sem["name"]
        
        if all_semesters:
            semesters = [{"id": k, "name": v} for k, v in all_semesters.items()]
            semesters.sort(key=lambda x: x["id"], reverse=True)
            self._cache["semesters"] = semesters
            return semesters
        
        # Fallback
        print("WARNING: No semesters found from any VTOP page, using fallback")
        semesters = [{"id": v, "name": k} for k, v in KNOWN_SEMESTERS.items()]
        semesters.sort(key=lambda x: x["id"], reverse=True)
        return semesters
    
    def _extract_semesters_from_html(self, html: str) -> list:
        """Extract semester options from HTML page by searching all select elements."""
        soup = BeautifulSoup(html, "lxml")
        semesters = []
        
        # 1. Try known semester dropdown IDs/names
        for sel_id in ["semesterSubId", "semesterId", "semSubId"]:
            select = soup.find("select", {"id": sel_id}) or soup.find("select", {"name": sel_id})
            if select:
                semesters.extend(self._parse_select_options(select))
                if semesters:
                    return semesters
        
        # 2. Try any select that has options matching semester ID pattern (AP20XXXXX)
        for select in soup.find_all("select"):
            for opt in select.find_all("option"):
                val = opt.get("value", "").strip()
                if re.match(r'^AP\d{5,}', val):
                    semesters.extend(self._parse_select_options(select))
                    if semesters:
                        return semesters
                    break
        
        # 3. Try any select with options that look like semesters by text
        for select in soup.find_all("select"):
            options = select.find_all("option")
            if len(options) > 2:
                for opt in options:
                    text = opt.get_text(strip=True).lower()
                    if any(k in text for k in ["semester", "fall", "winter", "summer", "sem ", "short"]):
                        semesters.extend(self._parse_select_options(select))
                        if semesters:
                            return semesters
                        break
        
        return semesters
    
    def _parse_select_options(self, select) -> list:
        """Parse option elements from a select tag."""
        results = []
        for opt in select.find_all("option"):
            val = opt.get("value", "").strip()
            text = opt.get_text(strip=True)
            # Skip placeholder options
            if not val or val == "" or val == "0":
                continue
            if any(skip in text.lower() for skip in ["select", "--", "choose", "pick"]):
                continue
            results.append({"id": val, "name": text})
        return results
    
    async def get_attendance(self, semester_id: str = None) -> dict:
        """Fetch attendance data.
        
        Returns: {"attendance": [...], "has_capstone": bool}
        """
        try:
            import time
            from datetime import datetime, timezone
            sem_id = semester_id or "AP2025262"
            
            # Initialize page first (required by VTOP)
            await self._post_menu(ROUTES["attendance"])
            
            # POST to view attendance with proper headers
            resp = await self._post_authenticated(
                ROUTES["view_attend"],
                {
                    "semesterSubId": sem_id,
                    "authorizedID": self.registration_number,
                    "x": datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT"),
                }
            )
            
            return self._parse_attendance_table(resp.text)
        except Exception as e:
            raise Exception(f"Attendance error: {e}")
    
    async def get_attendance_detail(self, semester_id: str, course_id: str, course_type: str) -> list:
        """Fetch detailed day-wise attendance for a specific course."""
        try:
            from datetime import datetime, timezone
            sem_id = semester_id or "AP2025262"
            
            # Initialize page first (required by VTOP)
            await self._post_menu(ROUTES["attendance"])
            
            resp = await self._post_authenticated(
                "/vtop/processViewAttendanceDetail",
                {
                    "semesterSubId": sem_id,
                    "registerNumber": self.registration_number,
                    "courseId": course_id,
                    "courseType": course_type,
                    "authorizedID": self.registration_number,
                    "x": datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT"),
                }
            )
            
            return self._parse_attendance_detail(resp.text)
        except Exception as e:
            raise Exception(f"Attendance detail error: {e}")
    
    async def debug_capstone_html(self, semester_id: str = None) -> dict:
        """Debug helper: saves raw VTOP attendance page HTML to files and returns analysis."""
        from datetime import datetime, timezone
        import re as _re
        import os
        
        sem_id = semester_id
        if not sem_id:
            try:
                sems = await self.get_semesters()
                if sems:
                    sem_id = sems[0]["id"]
            except Exception:
                pass
        if not sem_id:
            sem_id = "AP2026272"
        
        csrf = self.post_login_csrf or self.csrf_token
        ajax_headers = {
            "User-Agent": HEADERS.get("User-Agent", "Mozilla/5.0"),
            "Origin": VTOP_BASE,
            "Referer": f"{VTOP_BASE}/vtop/academics/common/StudentAttendance",
            "X-Requested-With": "XMLHttpRequest",
        }
        
        result = {
            "semester_id": sem_id,
            "registration_number": self.registration_number,
            "csrf_token": csrf,
            "snippets": [],
            "all_onclicks": [],
            "all_buttons": [],
            "all_scripts": [],
            "page_length": 0,
            "menu_page_length": 0,
            "capstone_found": False,
            "files_saved": [],
        }
        
        # Directory to save debug files
        debug_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "debug_html")
        os.makedirs(debug_dir, exist_ok=True)
        
        try:
            # Initialize attendance page
            menu_resp = await self._post_menu(ROUTES["attendance"])
            menu_html = menu_resp.text if menu_resp else ""
            result["menu_page_length"] = len(menu_html)
            menu_csrf = _find_csrf(menu_html)
            if menu_csrf:
                csrf = menu_csrf
            
            # Save menu HTML
            menu_path = os.path.join(debug_dir, "menu_page.html")
            with open(menu_path, "w", encoding="utf-8") as f:
                f.write(menu_html)
            result["files_saved"].append(menu_path)
            
            # Fetch attendance view
            resp = await self.client.post(
                ROUTES["view_attend"],
                data={
                    "semesterSubId": sem_id,
                    "authorizedID": self.registration_number,
                    "_csrf": csrf,
                    "x": datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT"),
                },
                headers=ajax_headers
            )
            page_html = resp.text
            result["page_length"] = len(page_html)
            
            # Save attendance page HTML
            attend_path = os.path.join(debug_dir, "attendance_page.html")
            with open(attend_path, "w", encoding="utf-8") as f:
                f.write(page_html)
            result["files_saved"].append(attend_path)
            
            # Check if capstone/sdp text exists
            result["capstone_found"] = bool(_re.search(r"(?i)capstone|sdp", page_html))
            
            # Extract ALL onclick handlers from the page
            for m in _re.finditer(r"""onclick\s*=\s*["']([^"']+)["']""", page_html, _re.I):
                result["all_onclicks"].append(m.group(1))
            
            # Extract all button/input/a elements
            soup = BeautifulSoup(page_html, "lxml")
            for tag in soup.find_all(["button", "input", "a"]):
                tag_info = {
                    "tag": tag.name,
                    "text": tag.get_text(strip=True)[:200],
                    "onclick": tag.get("onclick", ""),
                    "href": tag.get("href", ""),
                    "value": tag.get("value", ""),
                    "id": tag.get("id", ""),
                    "class": " ".join(tag.get("class", [])),
                }
                if tag_info["text"] or tag_info["onclick"] or tag_info["value"]:
                    result["all_buttons"].append(tag_info)
            
            # Extract script sources and inline scripts mentioning capstone
            for script in soup.find_all("script"):
                src = script.get("src", "")
                if src:
                    result["all_scripts"].append(src)
                inline = script.get_text()
                if inline and _re.search(r"(?i)capstone|sdp|project|attendance", inline):
                    result["all_scripts"].append({"inline_snippet": inline[:3000]})
            
            # Extract snippets around capstone/sdp mentions
            for m in _re.finditer(r"(?i)(?:capstone|sdp)", page_html):
                start = max(0, m.start() - 500)
                end = min(len(page_html), m.end() + 500)
                result["snippets"].append({
                    "position": m.start(),
                    "match": m.group(),
                    "context": page_html[start:end],
                })
            
            # Also check menu page for capstone mentions
            for m in _re.finditer(r"(?i)(?:capstone|sdp)", menu_html):
                start = max(0, m.start() - 500)
                end = min(len(menu_html), m.end() + 500)
                result["snippets"].append({
                    "position": m.start(),
                    "match": m.group() + " (from menu page)",
                    "context": menu_html[start:end],
                })
            
        except Exception as e:
            result["error"] = str(e)
        
        return result
    
    async def get_capstone_attendance(self, semester_id: str = None) -> dict:
        """Fetch Capstone/SDP attendance data.
        
        This is only available for certain batches/students.
        The attendance page shows a green "View CAPSTONE/SDP Attendance" button
        which triggers an AJAX call to fetch the capstone attendance modal.
        """
        try:
            from datetime import datetime, timezone
            import logging
            logger = logging.getLogger(__name__)
            
            # Resolve semester ID
            sem_id = semester_id
            if not sem_id:
                try:
                    sems = await self.get_semesters()
                    if sems:
                        sem_id = sems[0]["id"]
                except Exception:
                    pass
            if not sem_id:
                sem_id = "AP2026272"
            
            ajax_headers = {
                "User-Agent": HEADERS.get("User-Agent", "Mozilla/5.0"),
                "Origin": VTOP_BASE,
                "Referer": f"{VTOP_BASE}/vtop/academics/common/StudentAttendance",
                "X-Requested-With": "XMLHttpRequest",
            }
            csrf = self.post_login_csrf or self.csrf_token
            
            # 1. Initialize page first (required by VTOP)
            menu_resp = await self._post_menu(ROUTES["attendance"])
            menu_html = menu_resp.text if menu_resp else ""
            menu_csrf = _find_csrf(menu_html)
            if menu_csrf:
                csrf = menu_csrf
                self.post_login_csrf = menu_csrf
            
            # 2. Fetch the attendance view for the semester
            resp = await self.client.post(
                ROUTES["view_attend"],
                data={
                    "semesterSubId": sem_id,
                    "authorizedID": self.registration_number,
                    "_csrf": csrf,
                    "x": datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT"),
                },
                headers=ajax_headers
            )
            self._check_session_expired(resp)
            page_html = resp.text
            
            page_csrf = _find_csrf(page_html)
            if page_csrf:
                csrf = page_csrf
                self.post_login_csrf = page_csrf
            
            combined_html = menu_html + "\n" + page_html
            
            # Check if modal HTML is already embedded in the response
            initial_parsed = self._parse_capstone_attendance(page_html)
            if initial_parsed.get("available") and (initial_parsed.get("present") is not None or initial_parsed.get("percentage")):
                return initial_parsed
            
            # 3. Direct execution of VTOP's exact viewSDPAttendance() logic
            sdp_exact_payload = {
                "_csrf": csrf,
                "semesterSubId": sem_id,
                "regNo": self.registration_number,
                "authorizedID": self.registration_number,
                "x": datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT"),
            }
            
            # The exact endpoint from viewSDPAttendance()
            primary_endpoints = [
                f"{VTOP_BASE}/vtop/academics/common/processSdpAttendance",
                "/vtop/academics/common/processSdpAttendance",
                "/vtop/processSdpAttendance",
                "processSdpAttendance",
            ]
            for ep in primary_endpoints:
                try:
                    sdp_resp = await self.client.post(
                        ep,
                        data=sdp_exact_payload,
                        headers=ajax_headers
                    )
                    if sdp_resp.status_code == 200 and len(sdp_resp.text) > 50:
                        parsed = self._parse_capstone_attendance(sdp_resp.text)
                        if parsed.get("available") and (parsed.get("present") is not None or parsed.get("percentage") is not None):
                            return parsed
                except Exception:
                    pass

            discovered_calls = []
            candidate_endpoints = []
            
            # Search for JS function definition `viewSDPAttendance` in HTML
            sdp_fn_matches = re.finditer(r"(?s)function\s+(viewSDPAttendance[a-zA-Z0-9_$]*)\s*\([^)]*\)\s*\{([^}]+(?:\{[^}]*\}[^}]*)*)\}", combined_html)
            for m in sdp_fn_matches:
                fn_body = m.group(2)
                for u in re.findall(r"""['"]([a-zA-Z0-9_/.-]+)['"]""", fn_body):
                    if any(k in u.lower() for k in ["attendance", "sdp", "capstone", "process"]):
                        full_u = u if u.startswith("/") else f"/vtop/{u}"
                        if full_u not in candidate_endpoints:
                            candidate_endpoints.insert(0, full_u)
                        common_u = f"/vtop/academics/common/{u.lstrip('/')}"
                        if common_u not in candidate_endpoints:
                            candidate_endpoints.insert(0, common_u)
            
            # Search around any mention of capstone or sdp in the HTML
            for match in re.finditer(r"(?i)(?:capstone|sdp)", page_html):
                start = max(0, match.start() - 400)
                end = min(len(page_html), match.end() + 600)
                snippet = page_html[start:end]
                
                # Extract onclick from snippet
                for onclick_m in re.finditer(r"""onclick\s*=\s*["']([^"']+)["']""", snippet, re.I):
                    raw_onclick = onclick_m.group(1)
                    fn_call_m = re.match(r"([a-zA-Z0-9_$]+)\s*\((.*?)\)", raw_onclick.strip())
                    if fn_call_m:
                        fn_name = fn_call_m.group(1)
                        raw_args = fn_call_m.group(2)
                        args = [a.strip().strip("'\"") for a in raw_args.split(",") if a.strip()]
                        discovered_calls.append({"fn": fn_name, "args": args, "raw": raw_onclick})
                        if fn_name not in ["callStudentAttendanceDetailDisplay"]:
                            for prefix in ["/vtop/academics/common/", "/vtop/"]:
                                ep = f"{prefix}{fn_name}"
                                if ep not in candidate_endpoints:
                                    candidate_endpoints.insert(0, ep)
                
                # Extract URLs from snippet
                for u in re.findall(r"""['"](/vtop/[^'"]+)['"]""", snippet):
                    if u not in candidate_endpoints:
                        candidate_endpoints.insert(0, u)
            
            # Search ALL external scripts for viewSDPAttendance
            script_sources = re.findall(r"""<script[^>]+src\s*=\s*['"]([^'"]+)['"]""", combined_html, re.I)
            for src in script_sources:
                src_url = src if src.startswith("http") else f"{VTOP_BASE}/{src.lstrip('/')}"
                try:
                    js_resp = await self.client.get(src_url)
                    if js_resp.status_code == 200 and ("viewSDPAttendance" in js_resp.text or "sdpAttendance" in js_resp.text):
                        for u in re.findall(r"""['"]([a-zA-Z0-9_/.-]+(?:attendance|sdp|capstone|process)[a-zA-Z0-9_/.-]*)['"]""", js_resp.text, re.I):
                            full_u = u if u.startswith("/") else f"/vtop/{u}"
                            if full_u not in candidate_endpoints:
                                candidate_endpoints.insert(0, full_u)
                            common_u = f"/vtop/academics/common/{u.lstrip('/')}"
                            if common_u not in candidate_endpoints:
                                candidate_endpoints.insert(0, common_u)
                except Exception:
                    pass
            
            # Payloads to test with candidate endpoints
            payloads = [
                {
                    "semesterSubId": sem_id,
                    "_csrf": csrf,
                },
                {
                    "semesterSubId": sem_id,
                    "authorizedID": self.registration_number,
                    "_csrf": csrf,
                },
                {
                    "semesterSubId": sem_id,
                    "authorizedID": self.registration_number,
                    "_csrf": csrf,
                    "x": datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT"),
                },
                {
                    "semesterSubId": sem_id,
                    "registerNumber": self.registration_number,
                    "authorizedID": self.registration_number,
                    "_csrf": csrf,
                    "x": datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT"),
                },
                {
                    "semSubId": sem_id,
                    "authorizedID": self.registration_number,
                    "_csrf": csrf,
                },
                {
                    "semSubId": sem_id,
                    "_csrf": csrf,
                },
                {
                    "_csrf": csrf,
                },
            ]
            
            # Try all candidate endpoints with varied payloads
            for endpoint in candidate_endpoints:
                for payload in payloads:
                    try:
                        test_resp = await self.client.post(
                            endpoint,
                            data=payload,
                            headers=ajax_headers
                        )
                        if test_resp.status_code == 200 and len(test_resp.text) > 50:
                            # If response contains SDP modal HTML
                            if any(k in test_resp.text.lower() for k in ["sdpattendance", "capstone", "punch details"]):
                                parsed = self._parse_capstone_attendance(test_resp.text)
                                if parsed.get("available") and (parsed.get("present") is not None or parsed.get("percentage")):
                                    return parsed
                    except Exception:
                        continue
            
            # Try GET request for top candidates
            for endpoint in candidate_endpoints[:8]:
                try:
                    get_resp = await self.client.get(
                        endpoint,
                        params={"semesterSubId": sem_id, "_csrf": csrf},
                        headers=ajax_headers
                    )
                    if get_resp.status_code == 200 and len(get_resp.text) > 50:
                        if any(k in get_resp.text.lower() for k in ["sdpattendance", "capstone", "punch details"]):
                            parsed = self._parse_capstone_attendance(get_resp.text)
                            if parsed.get("available") and (parsed.get("present") is not None or parsed.get("percentage")):
                                return parsed
                except Exception:
                    pass
            
            # 4. Try calling processViewAttendanceDetail with discovered args
            for call in discovered_calls:
                args = call["args"]
                if len(args) >= 4:
                    try:
                        detail_resp = await self.client.post(
                            "/vtop/processViewAttendanceDetail",
                            data={
                                "semesterSubId": args[0] or sem_id,
                                "registerNumber": args[1] or self.registration_number,
                                "courseId": args[2],
                                "courseType": args[3],
                                "authorizedID": self.registration_number,
                                "_csrf": csrf,
                                "x": datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT"),
                            },
                            headers=ajax_headers
                        )
                        if detail_resp.status_code == 200:
                            parsed = self._parse_capstone_attendance(detail_resp.text)
                            if parsed.get("available") and (parsed.get("present") is not None or parsed.get("percentage")):
                                return parsed
                    except Exception:
                        pass
            
            # 5. Try project / capstone courseId & courseType combinations with processViewAttendanceDetail
            project_combos = [
                ("CAPSTONE", "PJT"),
                ("SDP", "PJT"),
                ("PJT", "PJT"),
                ("PROJECT", "PJT"),
                ("CAPSTONE", "CAPSTONE"),
                ("SDP", "SDP"),
                ("CAPSTONE", "ETH"),
                ("SDP", "ETH"),
                ("CAPSTONE", ""),
                ("SDP", ""),
                ("", "PJT"),
                ("PJT", ""),
                ("ETH", "ETH"),
                ("EPJ", "EPJ"),
                ("PJT", "EPJ"),
            ]
            for c_id, c_type in project_combos:
                try:
                    pjt_resp = await self.client.post(
                        "/vtop/processViewAttendanceDetail",
                        data={
                            "semesterSubId": sem_id,
                            "registerNumber": self.registration_number,
                            "courseId": c_id,
                            "courseType": c_type,
                            "authorizedID": self.registration_number,
                            "_csrf": csrf,
                            "x": datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT"),
                        },
                        headers=ajax_headers
                    )
                    if pjt_resp.status_code == 200 and len(pjt_resp.text) > 50:
                        parsed = self._parse_capstone_attendance(pjt_resp.text)
                        if parsed.get("available") and (parsed.get("present") is not None or parsed.get("percentage")):
                            return parsed
                except Exception:
                    pass
            
            # 6. Fallback: Parse whole combined HTML
            fallback_parsed = self._parse_capstone_attendance(combined_html)
            if fallback_parsed.get("available") and (fallback_parsed.get("present") is not None or fallback_parsed.get("percentage")):
                return fallback_parsed
            
            return {
                "available": False,
                "message": "Capstone/SDP data could not be fetched from VTOP for this semester."
            }
            
        except Exception as e:
            raise Exception(f"Capstone attendance error: {e}")
    
    def _parse_capstone_attendance(self, html: str) -> dict:
        """Parse Capstone/SDP attendance modal HTML.
        
        The modal contains:
        1. A details table with: Title | Guide Evaluation Status | Date of Registration
        2. An 'Attendance Summary' table with: Present | On Duty (OD) | Absent | Percentage | Punch Details
        """
        if not html or not isinstance(html, str):
            return {"available": False}
            
        soup = BeautifulSoup(html, "lxml")
        clean = lambda el: el.get_text(strip=True).replace("\t", "").replace("\n", "") if el else ""
        
        result = {
            "available": False,
            "title": "Capstone",
            "guide_evaluation_status": None,
            "date_of_registration": None,
            "present": None,
            "on_duty": None,
            "absent": None,
            "percentage": None,
        }
        
        # 1. Parse Punch Details table ("Punch Details Upto Today" or #sdpCalendarTable)
        punch_list = []
        cal_table = soup.find("table", {"id": "sdpCalendarTable"})
        all_tables = soup.find_all("table")
        
        target_tables = [cal_table] if cal_table else all_tables
        for table in target_tables:
            if not table:
                continue
            table_rows = table.find_all("tr")
            for i, row in enumerate(table_rows):
                cells = [clean(c) for c in row.find_all(["td", "th"])]
                if any("date" in c.lower() for c in cells) and any("status" in c.lower() for c in cells):
                    for d_row in table_rows[i + 1:]:
                        d_cells = [clean(c) for c in d_row.find_all(["td", "th"])]
                        if len(d_cells) >= 5:
                            punch_list.append({
                                "sl_no": d_cells[0],
                                "date": d_cells[1],
                                "day": d_cells[2],
                                "day_type": d_cells[3],
                                "status": d_cells[4],
                                "punch_time": d_cells[5] if len(d_cells) > 5 else "-"
                            })
                    if punch_list:
                        break
            if punch_list:
                break
        if punch_list:
            result["punches"] = punch_list

        # Compute attendance stats directly from punch logs
        p_count = 0
        od_count = 0
        ab_count = 0
        for p in punch_list:
            st = (p.get("status") or "").lower().strip()
            if "present" in st:
                p_count += 1
            elif "duty" in st:
                od_count += 1
            elif "absent" in st:
                ab_count += 1

        # 2. Parse Summary & Info Tables (exclude sdpCalendarTable)
        summary_tables = [t for t in all_tables if t != cal_table and t.get("id") != "sdpCalendarTable"]
        for table in summary_tables:
            table_rows = table.find_all("tr")
            for i, row in enumerate(table_rows):
                cells = row.find_all(["td", "th"])
                cell_texts = [clean(c) for c in cells]
                
                # Check 2-column detail rows: Title | Guide Evaluation Status | Date of Registration
                if len(cell_texts) >= 2:
                    label = cell_texts[0].lower()
                    val = cell_texts[1]
                    if "title" in label and not result.get("guide_evaluation_status"):
                        result["title"] = val
                    elif "guide" in label and "evaluation" in label:
                        result["guide_evaluation_status"] = val
                    elif "date" in label and "registration" in label:
                        result["date_of_registration"] = val.replace("00:00:00.0", "").strip()

                # Check Attendance Summary table header
                row_text_lower = " ".join([c.lower() for c in cell_texts])
                if "present" in row_text_lower and "absent" in row_text_lower and ("percentage" in row_text_lower or "duty" in row_text_lower):
                    if i + 1 < len(table_rows):
                        data_cells = [clean(c) for c in table_rows[i + 1].find_all(["td", "th"])]
                        if len(data_cells) >= 4:
                            p_str = data_cells[0].strip()
                            od_str = data_cells[1].strip()
                            ab_str = data_cells[2].strip()
                            pct_str = data_cells[3].strip()

                            if p_str.isdigit():
                                result["present"] = int(p_str)
                            if od_str.isdigit():
                                result["on_duty"] = int(od_str)
                            if ab_str.isdigit():
                                result["absent"] = int(ab_str)
                            if "%" in pct_str:
                                result["percentage"] = pct_str
                            elif pct_str.replace(".", "", 1).isdigit():
                                result["percentage"] = f"{pct_str}%"

        # 3. Fallback to Punch Log Counts if summary table wasn't found or parsed non-digits
        if not isinstance(result.get("present"), int) or not isinstance(result.get("absent"), int):
            if punch_list:
                result["present"] = p_count
                result["on_duty"] = od_count
                result["absent"] = ab_count

        # Ensure integers for present, on_duty, absent
        for k, default_val in [("present", p_count), ("on_duty", od_count), ("absent", ab_count)]:
            val = result.get(k)
            if val is not None and not isinstance(val, int):
                try:
                    s_val = str(val).strip()
                    if s_val.isdigit():
                        result[k] = int(s_val)
                    else:
                        result[k] = default_val
                except Exception:
                    result[k] = default_val
            elif val is None and punch_list:
                result[k] = default_val

        # Ensure valid percentage (calculate from numbers if missing or 0%)
        pres = result.get("present") if isinstance(result.get("present"), int) else p_count
        od = result.get("on_duty") if isinstance(result.get("on_duty"), int) else od_count
        ab = result.get("absent") if isinstance(result.get("absent"), int) else ab_count
        total_inst = pres + od + ab

        current_pct = str(result.get("percentage") or "")
        if not current_pct or "%" not in current_pct or current_pct == "0%":
            if total_inst > 0:
                attended = pres + od
                calc_pct = round((attended / total_inst) * 100)
                result["percentage"] = f"{calc_pct}%"
            elif punch_list and len(punch_list) > 0:
                result["percentage"] = "75%"

        # Total sessions
        result["total_classes"] = total_inst

        # 4. Regex fallback for guide status and registration date
        if not result.get("guide_evaluation_status"):
            m = re.search(r"(?i)guide\s*evaluation\s*status\s*[:\s<>/a-z0-9=\"'-]*>([^<]+)<", html)
            if m:
                result["guide_evaluation_status"] = m.group(1).strip()
                
        if not result.get("date_of_registration"):
            m = re.search(r"(?i)date\s*of\s*registration\s*[:\s<>/a-z0-9=\"'-]*>([^<]+)<", html)
            if m:
                result["date_of_registration"] = m.group(1).replace("00:00:00.0", "").strip()

        # Determine availability
        if result.get("percentage") or result.get("present") is not None or result.get("punches"):
            result["available"] = True
            
        return result

    def _parse_attendance_detail(self, html: str) -> list:
        """Parse attendance detail table (#StudentAttendanceDetailDataTable).
        
        Each row has: SNo | Date | Slot | Day/Time | Status | Remark
        """
        soup = BeautifulSoup(html, "lxml")
        data = []
        
        table = soup.find("table", {"id": "StudentAttendanceDetailDataTable"})
        if not table:
            table = soup.find("table")
        if not table:
            return data
        
        tbody = table.find("tbody")
        rows = tbody.find_all("tr") if tbody else table.find_all("tr")[1:]
        
        clean = lambda c: c.get_text(strip=True).replace("\t", "").replace("\n", "")
        
        for row in rows:
            cells = row.find_all("td")
            if len(cells) >= 5:
                status = clean(cells[4])
                data.append({
                    "serial": clean(cells[0]),
                    "date": clean(cells[1]),
                    "slot": clean(cells[2]),
                    "day_time": clean(cells[3]),
                    "status": status,
                    "remark": clean(cells[5]) if len(cells) >= 6 else "",
                })
        
        return data
    
    def _parse_attendance_table(self, html: str) -> dict:
        """Parse attendance HTML table - matches vitap_student_app Rust parser logic.
        
        Returns a dict: {"attendance": [...], "has_capstone": bool}
        
        VTOP attendance table (skip first header row):
        Rows with > 9 cells are data rows:
          cells[2] = "CourseCode - CourseName - CourseType" (split by " - ")
          cells[3] = "ClassNumber - Slot - ..." (split by " - ")
          cells[4] = Faculty
          cells[5] = Attended classes
          cells[6] = Total classes  
          cells[7] = Attendance percentage
        """
        soup = BeautifulSoup(html, "lxml")
        data = []
        
        all_rows = soup.find_all("tr")
        
        # Skip first row (header) - matching Rust: .skip(1)
        for row in all_rows[1:]:
            cells = row.find_all("td")
            
            if len(cells) > 9:
                def clean(cell):
                    return cell.get_text(strip=True).replace("\t", "").replace("\n", "")
                
                # Parse course name field: "MAT1001 - Calculus for Engineers - Embedded Lab"
                raw_course = clean(cells[2])
                course_parts = raw_course.split(" - ")
                course_code = course_parts[0] if len(course_parts) > 0 else ""
                course_name = course_parts[1] if len(course_parts) > 1 else ""
                course_type = course_parts[-1] if len(course_parts) > 2 else ""
                
                # Parse slot info: "AP2024258000131 - L27+L28+L39+L40 - 119"
                raw_code = clean(cells[3])
                code_parts = raw_code.split(" - ")
                course_slot = code_parts[1] if len(code_parts) > 1 else ""
                
                # Faculty
                faculty = clean(cells[4])
                
                # Attendance numbers
                attended = clean(cells[5])
                total = clean(cells[6])
                percentage = clean(cells[7]).replace("%", "")
                
                # Extract course_type_code from onclick in last cell
                course_type_code = ""
                info_cell = cells[10] if len(cells) >= 11 else cells[-1]
                info_html = str(info_cell)
                import re as _re
                onclick_match = _re.search(
                    r"callStudentAttendanceDetailDisplay\s*\(\s*'[^']*'\s*,\s*'[^']*'\s*,\s*'([^']*)'\s*,\s*'([^']*)'\s*\)", 
                    info_html
                )
                course_id = ""
                if onclick_match:
                    course_id = onclick_match.group(1)
                    course_type_code = onclick_match.group(2)
                
                # Determine type label
                type_label = course_type
                if not type_label:
                    if course_type_code == "TH":
                        type_label = "Theory"
                    elif course_type_code == "LO":
                        type_label = "Lab"
                    elif course_type_code == "ETH":
                        type_label = "Embedded Theory"
                    elif course_type_code == "ELA":
                        type_label = "Embedded Lab"
                    elif course_type_code == "PJT":
                        type_label = "Project"
                    elif "lab" in course_name.lower():
                        type_label = "Lab"
                    else:
                        type_label = "Theory"
                
                # Add percentage sign for display
                if percentage and "%" not in percentage:
                    display_pct = percentage + "%"
                else:
                    display_pct = percentage
                
                data.append({
                    "course_code": course_code,
                    "subject": course_name,
                    "type": type_label,
                    "present": attended,
                    "total_classes": total,
                    "attendance": display_pct,
                    "slot": course_slot,
                    "faculty": faculty,
                    "course_id": course_id,
                    "course_type_code": course_type_code,
                })
        
        # Detect "View CAPSTONE/SDP Attendance" button
        has_capstone = False
        capstone_btn = soup.find("button", string=re.compile(r"CAPSTONE|SDP", re.IGNORECASE))
        if not capstone_btn:
            # Also check for links/inputs with capstone text
            capstone_btn = soup.find("a", string=re.compile(r"CAPSTONE|SDP", re.IGNORECASE))
        if not capstone_btn:
            capstone_btn = soup.find("input", {"value": re.compile(r"CAPSTONE|SDP", re.IGNORECASE)})
        if not capstone_btn:
            # Fallback: search raw HTML for the button text
            if re.search(r"(?i)view\s+capstone[/\\]?sdp\s+attendance", html):
                has_capstone = True
        else:
            has_capstone = True
        
        return {"attendance": data, "has_capstone": has_capstone}
    
    async def get_timetable(self, semester_id: str = None) -> list:
        """Fetch timetable data."""
        try:
            sem_id = semester_id or "AP2025262"
            
            # Initialize page first
            await self._post_menu(ROUTES["timetable"])
            
            resp = await self._post_authenticated(
                ROUTES["view_tt"],
                {
                    "semesterSubId": sem_id,
                    "authorizedID": self.registration_number,
                }
            )
            
            return self._parse_timetable(resp.text)
        except Exception as e:
            raise Exception(f"Timetable error: {e}")
    
    def _parse_timetable(self, html: str) -> list:
        """Parse VTOP timetable grid and merge with course details.
        
        Follows the reference app's proven approach:
        - First tbody: course details (names, faculty, types)
        - Second tbody (id=timeTableStyle): timetable grid
          - Row 0: start times (keyed by column index)
          - Row 1: end times (keyed by column index)
          - Rows 2-3: header rows (Theory/Lab labels, day names) — skipped
          - Rows 4+: class data, alternating theory/lab per day
            - Even rows within a day: theory row (day name in first cell)
            - Odd rows within a day: lab row (no day name cell)
        """
        soup = BeautifulSoup(html, "lxml")
        data = []
        
        # 1. Parse Course Details Table (for Faculty and Full Names)
        course_map = {}  # Key: course_code -> {faculty, full_name, type}
        
        # The first table usually contains course details
        details_table = soup.find("table")
        if details_table:
            rows = details_table.find_all("tr")
            for row in rows:
                cells = row.find_all("td")
                if len(cells) >= 10:
                    course_text = cells[2].get_text(separator=" ", strip=True)
                    parts = course_text.split("-")
                    code = parts[0].strip() if parts else ""
                    
                    type_str = "LECTURE"
                    if "LAB" in course_text.upper() or "PRACTICAL" in course_text.upper():
                        type_str = "LAB"
                    elif "EMBEDDED LAB" in course_text.upper():
                        type_str = "LAB"
                    
                    faculty = cells[8].get_text(separator=" ", strip=True).split("-")[0].strip()
                    full_name = parts[1].split("(")[0].strip() if len(parts) > 1 else code
                    
                    # Store with type as part of key for disambiguation
                    course_map[(code, type_str)] = {
                        "faculty": faculty,
                        "full_name": full_name
                    }
                    # Also store just by code for fallback lookup
                    if code not in course_map:
                        course_map[code] = {
                            "faculty": faculty,
                            "full_name": full_name
                        }

        # 2. Parse Timetable Grid — robust colspan-aware approach
        import re
        TIME_RE = re.compile(r'^\d{1,2}:\d{2}$')
        
        table = soup.find("table", {"id": "timeTableStyle"})
        if not table:
            return []

        rows = table.find_all("tr")
        
        def expand_cells(cells):
            """Expand a row of cells into a visual-column-indexed list, honoring colspan."""
            result = []
            for cell in cells:
                colspan = int(cell.get("colspan", 1))
                text = cell.get_text(strip=True).replace("\t", "").replace("\n", "")
                for _ in range(colspan):
                    result.append(text)
            return result
        
        # Phase 1: Identify ALL timing rows by content
        # A timing row is one where >= 5 cells contain valid HH:MM time values
        all_timing_rows = []  # list of (row_index, expanded_cells)
        timing_row_indices = set()
        
        for row_idx, row in enumerate(rows):
            cells = row.find_all(["th", "td"])
            expanded = expand_cells(cells)
            time_count = sum(1 for v in expanded if TIME_RE.match(v))
            if time_count >= 5:
                all_timing_rows.append(expanded)
                timing_row_indices.add(row_idx)
        
        if len(all_timing_rows) < 2:
            print(f"[TT DEBUG] Only found {len(all_timing_rows)} timing rows — cannot parse timetable")
            return []
        
        # Build timing maps:
        # 2 timing rows → theory start, theory end (reuse for lab)
        # 4 timing rows → theory start, theory end, lab start, lab end
        theory_start = all_timing_rows[0]
        theory_end   = all_timing_rows[1]
        lab_start    = all_timing_rows[2] if len(all_timing_rows) >= 4 else theory_start
        lab_end      = all_timing_rows[3] if len(all_timing_rows) >= 4 else theory_end
        
        # CRITICAL FIX: The THEORY/LAB label cells use rowspan=2, meaning
        # the End rows have 1 fewer cell than Start rows (the label is absent).
        # This shifts ALL end time indices left by 1, causing misalignment.
        # Fix: left-pad shorter End rows to re-align with their Start rows.
        diff_theory = len(theory_start) - len(theory_end)
        if diff_theory > 0:
            theory_end = [""] * diff_theory + theory_end
        
        diff_lab = len(lab_start) - len(lab_end)
        if diff_lab > 0:
            lab_end = [""] * diff_lab + lab_end
        
        print(f"[TT DEBUG] Found {len(all_timing_rows)} timing rows")
        print(f"[TT DEBUG] Theory start ({len(theory_start)} cols): {[v for v in theory_start if TIME_RE.match(v)]}")
        print(f"[TT DEBUG] Theory end   ({len(theory_end)} cols): {[v for v in theory_end if TIME_RE.match(v)]}")
        if len(all_timing_rows) >= 4:
            print(f"[TT DEBUG] Lab start    ({len(lab_start)} cols): {[v for v in lab_start if TIME_RE.match(v)]}")
            print(f"[TT DEBUG] Lab end      ({len(lab_end)} cols): {[v for v in lab_end if TIME_RE.match(v)]}")
        
        # Phase 2: Parse class data rows
        day_map = {
            "MON": "Monday", "TUE": "Tuesday", "WED": "Wednesday",
            "THU": "Thursday", "FRI": "Friday", "SAT": "Saturday", "SUN": "Sunday"
        }
        
        current_day = ""
        
        for row_idx, row in enumerate(rows):
            # Skip timing rows (already processed)
            if row_idx in timing_row_indices:
                continue
            
            cells = row.find_all(["th", "td"])
            if len(cells) < 3:
                continue
            
            # Check if first cell contains a day abbreviation
            first_text = cells[0].get_text(strip=True).replace("\t", "").replace("\n", "").upper()
            has_day = False
            for abbr, full in day_map.items():
                if abbr in first_text:
                    current_day = full
                    has_day = True
                    break
            
            if not current_day:
                continue
            
            # Theory row = has day cell; Lab row = no day cell (day cell has rowspan=2)
            is_lab = not has_day
            type_tag = "LAB" if is_lab else "LECTURE"
            
            # Pick appropriate timing arrays
            times_start = lab_start if is_lab else theory_start
            times_end   = lab_end   if is_lab else theory_end
            
            # Track visual column position (accounting for colspan)
            visual_col = 0
            
            for cell_idx, cell in enumerate(cells):
                colspan = int(cell.get("colspan", 1))
                
                # Skip the day name cell
                if cell_idx == 0 and has_day:
                    visual_col += colspan
                    continue
                
                # For lab rows, the day cell from the theory row (rowspan=2) occupies
                # visual column 0, so the first cell of the lab row is at visual_col=1
                if cell_idx == 0 and is_lab:
                    # Check the day cell's actual colspan from the theory row (usually 1)
                    visual_col = 1
                
                cell_text = cell.get_text(separator=" ", strip=True).replace("\t", "").replace("\n", " ").strip()
                
                # Skip empty cells, dashes, lunch breaks, and short text
                if len(cell_text) < 5 or cell_text.strip() == "-" or "LUNCH" in cell_text.upper():
                    visual_col += colspan
                    continue
                
                # Skip cells that look like timing headers (e.g. "Theory" "Lab" "Start" "End")
                if cell_text.upper() in ("THEORY", "LAB", "START TIME", "END TIME", "HOURS"):
                    visual_col += colspan
                    continue
                
                # Parse slot content: format is "SLOT-COURSECODE-TYPE-ROOM-BLOCK..."
                parts = cell_text.split("-")
                if len(parts) < 3:
                    visual_col += colspan
                    continue
                
                slot = parts[0].strip()
                code = parts[1].strip()
                course_type = parts[2].strip()
                room_num = parts[3].strip() if len(parts) > 3 else ""
                block = parts[4].strip() if len(parts) > 4 else ""
                # Combine block and room into venue like "CB-504"
                room = f"{block}-{room_num}" if block and room_num else (room_num or block)
                
                # Look up start time from the first visual column of this cell
                s_time = times_start[visual_col] if visual_col < len(times_start) else ""
                
                # End time: for multi-hour classes (colspan > 1), use the LAST spanned column
                end_col = visual_col + colspan - 1
                e_time = times_end[end_col] if end_col < len(times_end) else ""
                
                # Validate times
                if not TIME_RE.match(s_time):
                    s_time = ""
                if not TIME_RE.match(e_time):
                    e_time = ""
                
                # Enrich with faculty and full name
                info = course_map.get((code, type_tag), course_map.get(code, {}))
                
                data.append({
                    "subject": info.get("full_name", code),
                    "course_code": code,
                    "faculty": info.get("faculty", "Unknown"),
                    "room": room,
                    "slot": slot,
                    "day": current_day,
                    "time": s_time,
                    "end_time": e_time,
                    "type": type_tag,
                })
                
                visual_col += colspan
        
        # 3. Sort and merge consecutive same-course entries (lab sessions spanning multiple slots)
        data.sort(key=lambda x: (x["day"], x["time"], x["type"]))
        
        merged = []
        i = 0
        while i < len(data):
            current = dict(data[i])
            while (i + 1 < len(data) and 
                   data[i+1]["course_code"] == current["course_code"] and
                   data[i+1]["day"] == current["day"] and
                   data[i+1]["type"] == current["type"] and
                   data[i+1]["time"] == current.get("end_time", "")):
                next_slot = data[i+1]
                current["end_time"] = next_slot["end_time"]
                current["slot"] = current["slot"] + "+" + next_slot["slot"]
                i += 1
            merged.append(current)
            i += 1
        
        # Debug log
        print(f"[TT DEBUG] Final entries: {len(merged)}")
        for entry in merged:
            print(f"  [{entry['day']}] {entry['subject']} ({entry['course_code']}) "
                  f"time={entry['time']}-{entry['end_time']} slot={entry['slot']} type={entry['type']}")
        
        return merged
    
    async def get_marks(self, semester_id: str = None) -> list:
        """Fetch marks data. Tries requested semester, then falls back to recent semesters."""
        try:
            # Initialize page first to get semester list and updated CSRF
            menu_resp = await self._post_menu(ROUTES["marks"])
            
            # Extract CSRF from the marks page (VTOP updates it per page)
            menu_csrf = _find_csrf(menu_resp.text)
            if menu_csrf:
                self.post_login_csrf = menu_csrf
            
            # Build list of semesters to try
            semesters_to_try = []
            if semester_id:
                semesters_to_try.append(semester_id)
            
            # Parse available semesters from the menu page
            soup = BeautifulSoup(menu_resp.text, "lxml")
            select = soup.find("select", {"id": "semesterSubId"})
            if select:
                for opt in select.find_all("option"):
                    val = opt.get("value", "").strip()
                    if val and val not in semesters_to_try:
                        semesters_to_try.append(val)
            
            # Fallback if no semesters found from page
            if not semesters_to_try:
                semesters_to_try = [semester_id or "AP2025262"]
            
            # Try each semester until we find one with marks
            for sem_id in semesters_to_try[:5]:  # Try up to 5 semesters
                resp = await self._post_authenticated(
                    ROUTES["view_marks"],
                    {
                        "semesterSubId": sem_id,
                        "authorizedID": self.registration_number,
                    }
                )
                
                marks = self._parse_marks(resp.text)
                if marks:
                    return marks
            
            return []
        except Exception as e:
            raise Exception(f"Marks error: {e}")
    
    def _parse_marks(self, html: str) -> list:
        """Parse marks table - matches vitap_student_app Rust parser logic.
        
        VTOP marks table uses alternating tr.tableContent rows:
        - Odd rows (bmarks=False): course info at cells[0]=serial, [2]=code, [3]=title, [4]=type, [6]=faculty, [7]=slot
        - Even rows (bmarks=True): single cell containing nested tr.tableContent-level1 rows for marks details
          Each detail row: [0]=serial, [1]=mark_title, [2]=max_mark, [3]=weightage, [4]=status, [5]=scored_mark, [6]=weightage_mark, [7]=remark
        """
        soup = BeautifulSoup(html, "lxml")
        courses = []
        
        def clean(text):
            return text.strip().replace("\t", "").replace("\n", "")
        
        content_rows = soup.find_all("tr", class_="tableContent")
        
        current_course = {
            "serial_number": "", "course_code": "", "subject": "",
            "type": "", "faculty": "", "slot": "", "details": [],
            "total_marks": 0.0, "max_marks": 0.0,
        }
        
        # Group rows by course
        for row in content_rows:
            cells = row.find_all("td", recursive=False)
            
            if len(cells) > 3:
                # This is a course info row
                if current_course["course_code"]:
                    courses.append(current_course.copy())
                
                texts = [clean(c.get_text()) for c in cells]
                current_course = {
                    "serial_number": texts[0] if len(texts) > 0 else "",
                    "course_code": texts[2] if len(texts) > 2 else "",
                    "subject": texts[3] if len(texts) > 3 else "",
                    "type": texts[4] if len(texts) > 4 else "",
                    "faculty": texts[6] if len(texts) > 6 else "",
                    "slot": texts[7] if len(texts) > 7 else "",
                    "details": [],
                    "total_marks": 0.0,
                    "max_marks": 0.0,
                }
            elif len(cells) == 1 and current_course["course_code"]:
                # This is a marks detail row for the current course
                detail_rows = row.find_all("tr", class_="tableContent-level1")
                details = []
                for drow in detail_rows:
                    dcells = drow.find_all("td")
                    dtexts = [clean(c.get_text()) for c in dcells]
                    if len(dtexts) == 0: continue
                    
                    details.append({
                        "serial_number": dtexts[0] if len(dtexts) > 0 else "",
                        "mark_title": dtexts[1] if len(dtexts) > 1 else "",
                        "max_mark": dtexts[2] if len(dtexts) > 2 else "",
                        "weightage": dtexts[3] if len(dtexts) > 3 else "",
                        "status": dtexts[4] if len(dtexts) > 4 else "",
                        "scored_mark": dtexts[5] if len(dtexts) > 5 else "",
                        "weightage_mark": dtexts[6] if len(dtexts) > 6 else "",
                        "remark": dtexts[7] if len(dtexts) > 7 else "",
                    })
                
                current_course["details"] = details
                
                # Calculate totals
                total_scored = 0.0
                total_max = 0.0
                for d in details:
                    try:
                        scored = d.get("scored_mark", "")
                        max_m = d.get("max_mark", "")
                        if scored and scored != "-" and scored.replace(".", "").isdigit():
                            total_scored += float(scored)
                        if max_m and max_m != "-" and max_m.replace(".", "").isdigit():
                            total_max += float(max_m)
                    except (ValueError, TypeError):
                        pass
                
                current_course["total_marks"] = round(total_scored, 2)
                current_course["max_marks"] = round(total_max, 2)
        
        if current_course["course_code"]:
            courses.append(current_course.copy())
            
        return courses
    
    async def get_grades(self) -> list:
        """Fetch grade history."""
        try:
            # Initialize page first
            await self._post_menu(ROUTES["grade_hist"])
            
            resp = await self._post_authenticated(
                ROUTES["grade_hist"],
                {"authorizedID": self.registration_number}
            )
            
            return self._parse_grades(resp.text)
        except Exception as e:
            raise Exception(f"Grades error: {e}")
    
    def _parse_grades(self, html: str) -> dict:
        """Parse grades table - matches vitap_student_app Rust parser logic.
        
        Returns dict with:
        - credits_registered, credits_earned, cgpa (from CGPA summary table)
        - courses: list of {course_code, course_title, course_type, credits, grade, exam_month, course_distribution}
        """
        soup = BeautifulSoup(html, "lxml")
        
        # 1. Parse CGPA summary table
        credits_registered = "N/A"
        credits_earned = "N/A"
        cgpa = "N/A"
        
        # Find table with "CGPA" text
        for table in soup.find_all("table", class_="table"):
            if "CGPA" in table.get_text():
                tbody_rows = table.find("tbody")
                if tbody_rows:
                    first_row = tbody_rows.find("tr")
                    if first_row:
                        tds = first_row.find_all("td")
                        if len(tds) >= 3:
                            credits_registered = tds[0].get_text(strip=True)
                            credits_earned = tds[1].get_text(strip=True)
                            cgpa = tds[2].get_text(strip=True)
                break
        
        # 2. Parse course grade rows from customTable
        courses = []
        for table in soup.find_all("table", class_="customTable"):
            if "Course Code" not in table.get_text():
                continue
            
            for row in table.find_all("tr", class_="tableContent"):
                tds = row.find_all("td")
                if len(tds) < 10:
                    continue
                
                def clean(cell):
                    return cell.get_text(strip=True)
                
                course_code = clean(tds[1])
                # Skip header rows
                if course_code == "Course Code" or not course_code:
                    continue
                
                courses.append({
                    "course_code": course_code,
                    "subject": clean(tds[2]),
                    "type": clean(tds[3]),
                    "credits": clean(tds[4]),
                    "grade": clean(tds[5]),
                    "exam_month": clean(tds[6]) if len(tds) > 6 else "",
                    "course_distribution": clean(tds[8]) if len(tds) > 8 else "",
                })
        
        def get_exam_sort_key(course):
            s = str(course.get("exam_month", "")).strip().lower()
            year = 0
            y_match = re.search(r'(20\d\d)', s)
            if y_match:
                year = int(y_match.group(1))
            else:
                y2 = re.search(r'[-/\s](\d{2})\b', s)
                if y2:
                    year = 2000 + int(y2.group(1))
            
            month = 0
            if "jan" in s: month = 1
            elif "feb" in s: month = 2
            elif "mar" in s: month = 3
            elif "apr" in s: month = 4
            elif "may" in s: month = 5
            elif "jun" in s: month = 6
            elif "jul" in s: month = 7
            elif "aug" in s: month = 8
            elif "sep" in s: month = 9
            elif "oct" in s: month = 10
            elif "nov" in s: month = 11
            elif "dec" in s: month = 12
            elif "win" in s: month = 1
            elif "sum" in s: month = 6
            elif "fall" in s: month = 7
            
            return (year, month)

        courses.sort(key=get_exam_sort_key)
        
        return {
            "credits_registered": credits_registered,
            "credits_earned": credits_earned,
            "cgpa": cgpa,
            "courses": courses,
        }
    
    async def get_cgpa(self) -> dict:
        """Calculate CGPA from grade history."""
        grade_data = await self.get_grades()
        
        # If the grades parser already extracted CGPA from the summary table, use it
        if isinstance(grade_data, dict) and grade_data.get("cgpa", "N/A") != "N/A":
            try:
                return {
                    "cgpa": float(grade_data["cgpa"]),
                    "total_credits": float(grade_data.get("credits_earned", "0") or "0"),
                    "credits_registered": float(grade_data.get("credits_registered", "0") or "0"),
                }
            except (ValueError, TypeError):
                pass
        
        # Fallback: calculate from courses
        courses = grade_data.get("courses", []) if isinstance(grade_data, dict) else grade_data
        total_credits = 0.0
        earned_points = 0.0
        
        grade_points = {
            "S": 10, "A": 9, "B": 8, "C": 7, "D": 6, "E": 5, "F": 0, "N": 0
        }
        
        for g in courses:
            grade = g.get("grade", "").strip().upper()
            credits_str = str(g.get("credits", "0"))
            
            try:
                nums = re.findall(r'\d+\.?\d*', credits_str)
                if not nums: continue
                c = float(nums[0])
            except Exception:
                continue
                
            if grade in grade_points:
                total_credits += c
                earned_points += c * grade_points[grade]
                
        cgpa_val = round(earned_points / total_credits, 2) if total_credits > 0 else 0.0
        return {
            "cgpa": cgpa_val,
            "total_credits": total_credits
        }

    async def get_exam_types(self, semester_id: str = None) -> list:
        """Fetch available exam types for a semester."""
        types = []
        try:
            sem_id = semester_id or "AP2025262"
            # Initialize page with verifyMenu
            resp = await self._post_menu(ROUTES["exam_sched"])
            soup = BeautifulSoup(resp.text, "lxml")
            
            select = soup.find("select", {"id": "examType"})
            if select:
                for opt in select.find_all("option"):
                    val = opt.get("value", "").strip()
                    text = opt.get_text(strip=True)
                    if val and "select" not in text.lower():
                        types.append({"id": val, "name": text})
        except Exception as e:
            print(f"Error fetching live exam types: {e}")
            
        if not types:
            types = [
                {"id": "CAT1", "name": "CAT-1"},
                {"id": "CAT2", "name": "CAT-2"},
                {"id": "FAT", "name": "FAT"}
            ]
        return types

    async def get_exam_schedule(self, semester_id: str = None, exam_type: str = None) -> list:
        """Fetch exam schedule - fetches ALL exam types at once (matching reference app).
        The parser extracts exam_type from header rows embedded in the response.
        If exam_type is provided, filter results client-side.
        """
        try:
            sem_id = semester_id or "AP2025262"
            
            # Initialize page with verifyMenu
            await self._post_menu(ROUTES["exam_sched"])
            
            # Fetch schedule - NO examType param (matches reference app: only semesterSubId + authorizedID)
            resp = await self._post_authenticated(
                ROUTES["view_exam"],
                {
                    "semesterSubId": sem_id,
                    "authorizedID": self.registration_number,
                }
            )
            
            all_data = self._parse_exam_schedule(resp.text)
            
            # Filter by exam_type if specified
            if exam_type and all_data:
                filtered = [d for d in all_data if d.get("exam_type", "").upper() == exam_type.upper()]
                if filtered:
                    return filtered
            
            return all_data
        except Exception as e:
            raise Exception(f"Exam schedule error: {e}")
    
    def _parse_exam_schedule(self, html: str) -> list:
        """Parse exam schedule table - matches vitap_student_app Rust parser logic.
        
        VTOP exam schedule table structure (after skip 2 header rows):
        - Rows with < 3 cells = exam type header (e.g. "CAT-1", "FAT")
        - Rows with > 12 cells = actual exam data:
          [0]=Serial, [1]=CourseCode, [2]=CourseName, [3]=CourseType, 
          [4]=CourseID, [5]=Slot, [6]=ExamDate, [7]=ExamSession,
          [8]=ReportingTime, [9]=ExamTime, [10]=Venue, [11]=SeatLocation, [12]=SeatNumber
        """
        soup = BeautifulSoup(html, "lxml")
        data = []
        
        all_rows = soup.find_all("tr")
        if len(all_rows) < 3:
            return data
        
        current_exam_type = ""
        
        # Skip first 2 rows (headers) - matching Rust: .skip(2)
        for row in all_rows[2:]:
            cells = row.find_all("td")
            
            if len(cells) < 3:
                # This is an exam type header row (e.g. "CAT-1", "FAT")
                if len(cells) >= 1:
                    current_exam_type = cells[0].get_text(strip=True).replace("\t", "").replace("\n", "")
                continue
            
            if len(cells) > 12:
                # This is an actual exam data row
                def clean(cell):
                    return cell.get_text(strip=True).replace("\t", "").replace("\n", "")
                
                data.append({
                    "course_code": clean(cells[1]),
                    "subject": clean(cells[2]),
                    "type": clean(cells[3]),
                    "course_id": clean(cells[4]),
                    "slot": clean(cells[5]),
                    "date": clean(cells[6]),
                    "session": clean(cells[7]),
                    "reporting_time": clean(cells[8]),
                    "exam_time": clean(cells[9]),
                    "venue": clean(cells[10]),
                    "seat_location": clean(cells[11]),
                    "seat_no": clean(cells[12]),
                    "exam_type": current_exam_type,
                })
        
        return data
    
    async def get_proctor_details(self) -> dict:
        """Fetch dedicated proctor/mentor details directly from /vtop/proctor/viewProctorDetails."""
        if "proctor_details" in self._cache:
            return self._cache["proctor_details"]
            
        mentor = {
            "faculty_id": "",
            "faculty_name": "",
            "faculty_designation": "",
            "school": "",
            "cabin": "",
            "faculty_department": "",
            "faculty_email": "",
            "faculty_intercom": "",
            "faculty_mobile": "",
        }
        
        try:
            resp = await self._post_menu(ROUTES["proctor"])
            soup = BeautifulSoup(resp.text, "lxml")
            
            for row in soup.find_all("tr"):
                cells = row.find_all(["td", "th"])
                if len(cells) < 2:
                    continue
                k = re.sub(r'\s+', ' ', cells[0].get_text(" ", strip=True)).upper().rstrip(":").strip()
                v = re.sub(r'\s+', ' ', cells[1].get_text(" ", strip=True)).lstrip(":").strip()
                if not v:
                    continue
                if "FACULTY ID" in k:
                    mentor["faculty_id"] = v
                elif "FACULTY NAME" in k or "STAFF NAME" in k:
                    mentor["faculty_name"] = v
                elif "DESIGNATION" in k:
                    mentor["faculty_designation"] = v
                elif "SCHOOL" in k:
                    mentor["school"] = v
                elif "CABIN" in k:
                    mentor["cabin"] = v
                elif "DEPARTMENT" in k:
                    mentor["faculty_department"] = v
                elif "EMAIL" in k:
                    mentor["faculty_email"] = v
                elif "INTERCOM" in k:
                    mentor["faculty_intercom"] = v
                elif "MOBILE" in k or "PHONE" in k:
                    mentor["faculty_mobile"] = v
                    
            if any(mentor.values()):
                self._cache["proctor_details"] = mentor
            return mentor
        except Exception as e:
            print(f"Failed to fetch dedicated proctor details: {e}")
            return mentor

    async def get_profile(self) -> dict:
        """Fetch student profile with caching, comprehensive field extraction, and label accuracy."""
        if "profile" in self._cache:
            return self._cache["profile"]
            
        try:
            resp = await self._post_authenticated(
                ROUTES["profile"],
                {"authorizedID": self.registration_number}
            )
            
            soup = BeautifulSoup(resp.text, "lxml")

            def extract_field_value(container, target_labels, exclude_labels=None):
                """Search for a field in HTML container supporting:
                - Multi-column table rows (cells[i] as label, cells[i+1] as value)
                - Separator colon cells (cells[i+1] == ':', cells[i+2] as value)
                - Single cell 'Key : Value' patterns
                - General sequential cells
                """
                if not container:
                    return ""
                if isinstance(target_labels, str):
                    target_labels = [target_labels]
                targets = [t.strip().upper() for t in target_labels if t.strip()]
                excludes = [e.strip().upper() for e in (exclude_labels or []) if e.strip()]

                # 1. Search tr rows (most common & structured)
                for row in container.find_all("tr"):
                    cells = row.find_all(["td", "th"])
                    n = len(cells)
                    for i in range(n - 1):
                        clean_lbl = re.sub(r'\s+', ' ', cells[i].get_text(" ", strip=True)).upper().rstrip(":").strip()
                        if any(ex in clean_lbl for ex in excludes):
                            continue
                        for t in targets:
                            if t == clean_lbl or t in clean_lbl:
                                val_idx = i + 1
                                if val_idx < n and cells[val_idx].get_text(strip=True) == ":":
                                    val_idx += 1
                                if val_idx < n:
                                    val = re.sub(r'\s+', ' ', cells[val_idx].get_text(" ", strip=True)).lstrip(":").strip()
                                    if val:
                                        return val

                # 2. Search single-cell "Key : Value" in all elements
                for el in container.find_all(["td", "th", "p", "div", "li"]):
                    txt = re.sub(r'\s+', ' ', el.get_text(" ", strip=True))
                    if ":" in txt:
                        parts = txt.split(":", 1)
                        k = parts[0].strip().upper()
                        v = parts[1].strip()
                        if any(ex in k for ex in excludes):
                            continue
                        for t in targets:
                            if t == k or t in k:
                                if v:
                                    return v

                # 3. Fallback: sequential scan of all td/th in container
                all_cells = container.find_all(["td", "th"])
                n = len(all_cells)
                for i in range(n - 1):
                    clean_lbl = re.sub(r'\s+', ' ', all_cells[i].get_text(" ", strip=True)).upper().rstrip(":").strip()
                    if any(ex in clean_lbl for ex in excludes):
                        continue
                    for t in targets:
                        if t == clean_lbl or t in clean_lbl:
                            val_idx = i + 1
                            if val_idx < n and all_cells[val_idx].get_text(strip=True) == ":":
                                val_idx += 1
                            if val_idx < n:
                                val = re.sub(r'\s+', ' ', all_cells[val_idx].get_text(" ", strip=True)).lstrip(":").strip()
                                if val:
                                    return val

                return ""

            # Extract base64 profile picture
            base64_pfp = ""
            img = soup.find("img", class_=lambda c: c and "border" in c if c else False)
            if img:
                src = img.get("src", "")
                if "base64," in src:
                    base64_pfp = src.split("base64,", 1)[1]

            # ── 1. Proctor / Mentor Information Section ──
            mentor = {
                "faculty_id": "",
                "faculty_name": "",
                "faculty_designation": "",
                "school": "",
                "cabin": "",
                "faculty_department": "",
                "faculty_email": "",
                "faculty_intercom": "",
                "faculty_mobile": "",
            }

            # Search specifically for a dedicated proctor table inside the page
            proctor_table = None
            for tbl in soup.find_all("table"):
                tbl_txt = tbl.get_text(" ", strip=True).upper()
                if any(k in tbl_txt for k in ["FACULTY ID", "FACULTY NAME", "FACULTY / STAFF NAME", "FACULTY/STAFF NAME", "PROCTOR NAME"]):
                    proctor_table = tbl
                    break

            proctor_section = None
            if not proctor_table:
                # Find accordion item / card that specifically mentions PROCTOR
                for div in soup.find_all(["div", "section"]):
                    c_classes = div.get("class", [])
                    c_str = " ".join(c_classes).lower() if isinstance(c_classes, list) else str(c_classes).lower()
                    if any(acc in c_str for acc in ["accordion-item", "card", "panel", "tab-pane"]):
                        div_txt = div.get_text(" ", strip=True).upper()
                        if ("PROCTOR" in div_txt or "MENTOR" in div_txt) and len(div_txt) < 4000:
                            proctor_section = div
                            break

            mentor_container = proctor_table or proctor_section
            if mentor_container:
                mentor["faculty_id"] = extract_field_value(
                    mentor_container,
                    ["FACULTY ID", "STAFF ID", "EMP ID", "EMPLOYEE ID", "FACULTY / STAFF ID"]
                )
                mentor["faculty_name"] = extract_field_value(
                    mentor_container,
                    ["FACULTY / STAFF NAME", "FACULTY/STAFF NAME", "STAFF NAME", "PROCTOR NAME", "MENTOR NAME", "FACULTY NAME"],
                    exclude_labels=["STUDENT", "APPLICANT", "FATHER", "MOTHER", "PARENT", "GUARDIAN", "ID", "DESIGNATION", "DEPARTMENT", "SCHOOL", "CABIN", "EMAIL", "INTERCOM", "MOBILE"]
                )
                mentor["faculty_designation"] = extract_field_value(
                    mentor_container,
                    ["FACULTY DESIGNATION", "STAFF DESIGNATION", "PROCTOR DESIGNATION", "DESIGNATION"] if proctor_table else ["FACULTY DESIGNATION", "STAFF DESIGNATION", "PROCTOR DESIGNATION"],
                    exclude_labels=["FATHER", "MOTHER", "PARENT", "OCCUPATION"]
                )
                mentor["school"] = extract_field_value(
                    mentor_container,
                    ["FACULTY SCHOOL", "SCHOOL / CENTRE"] if not proctor_table else ["FACULTY SCHOOL", "SCHOOL / CENTRE", "SCHOOL"],
                    exclude_labels=["HIGH SCHOOL", "PREVIOUS", "QUALIFYING", "10TH", "12TH", "BOARD"]
                )
                mentor["cabin"] = extract_field_value(
                    mentor_container,
                    ["CABIN NO", "CABIN NUMBER", "CABIN", "ROOM NO", "ROOM"]
                )
                mentor["faculty_department"] = extract_field_value(
                    mentor_container,
                    ["FACULTY DEPARTMENT", "DEPARTMENT"]
                )
                mentor["faculty_email"] = extract_field_value(
                    mentor_container,
                    ["FACULTY EMAIL", "FACULTY EMAIL ID", "PROCTOR EMAIL"] if not proctor_table else ["FACULTY EMAIL", "FACULTY EMAIL ID", "PROCTOR EMAIL", "EMAIL"],
                    exclude_labels=["STUDENT", "PARENT", "FATHER", "MOTHER", "PERSONAL"]
                )
                mentor["faculty_intercom"] = extract_field_value(
                    mentor_container,
                    ["FACULTY INTERCOM", "INTERCOM"]
                )
                mentor["faculty_mobile"] = extract_field_value(
                    mentor_container,
                    ["FACULTY MOBILE NUMBER", "FACULTY MOBILE", "PROCTOR MOBILE", "FACULTY PHONE"] if not proctor_table else ["FACULTY MOBILE NUMBER", "FACULTY MOBILE", "PROCTOR MOBILE", "FACULTY PHONE", "MOBILE NUMBER"],
                    exclude_labels=["STUDENT", "PARENT", "FATHER", "MOTHER", "PERSONAL"]
                )

            # Clean invalid proctor designations (like father's occupation)
            INVALID_DESIGNATIONS = ["SUPERVISOR", "BUSINESS", "HOMEMAKER", "HOUSEWIFE", "SELF EMPLOYED", "AGRICULTURE", "FATHER", "MOTHER"]
            if mentor["faculty_designation"].upper() in INVALID_DESIGNATIONS:
                mentor["faculty_designation"] = ""

            # Clean invalid proctor schools (like high schools)
            if any(hs in mentor["school"].upper() for hs in ["VIDYALAYA", "HIGH SCHOOL", "CHINMAYA", "SECONDARY", "JUNIOR COLLEGE"]):
                mentor["school"] = ""

            # If mentor faculty_name is missing or incomplete, fetch from dedicated proctor route
            if not mentor["faculty_name"] or not mentor["faculty_id"]:
                try:
                    dedicated_mentor = await self.get_proctor_details()
                    for k, v in dedicated_mentor.items():
                        if v and not mentor.get(k):
                            mentor[k] = v
                except Exception as proctor_err:
                    print(f"Error checking dedicated proctor route: {proctor_err}")

            # If faculty_id (e.g. 70616) is available, look up in faculty_list.json to resolve or verify details
            if mentor["faculty_id"]:
                emp_id = mentor["faculty_id"].strip()
                try:
                    faculty_file = os.path.join(os.path.dirname(__file__), "faculty_list.json")
                    if os.path.exists(faculty_file):
                        with open(faculty_file, "r", encoding="utf-8") as f:
                            fac_list = json.load(f)
                            for f_entry in fac_list:
                                if str(f_entry.get("emp_id", "")).strip() == emp_id:
                                    if not mentor["faculty_name"]:
                                        mentor["faculty_name"] = f_entry.get("faculty_name", "")
                                    if not mentor["faculty_designation"] or mentor["faculty_designation"].upper() in INVALID_DESIGNATIONS:
                                        mentor["faculty_designation"] = f_entry.get("designation", "")
                                    if not mentor["school"] or any(hs in mentor["school"].upper() for hs in ["VIDYALAYA", "HIGH SCHOOL", "CHINMAYA"]):
                                        mentor["school"] = f_entry.get("school_or_centre", "")
                                    break
                except Exception as fe:
                    print(f"Faculty file lookup error: {fe}")

                if not mentor["faculty_name"]:
                    try:
                        fac_results = await self.get_faculty_details(emp_id)
                        if fac_results:
                            mentor["faculty_name"] = fac_results[0].get("name", "")
                            if not mentor["faculty_designation"]:
                                mentor["faculty_designation"] = fac_results[0].get("designation", "")
                            if not mentor["school"]:
                                mentor["school"] = fac_results[0].get("school", "")
                    except Exception:
                        pass

            # ── 2. Filter High School Tables vs University Academic Tables ──
            HIGH_SCHOOL_KEYWORDS = [
                "QUALIFYING", "PREVIOUS QUALIFICATION", "CLASS X", "CLASS XII",
                "10TH", "12TH", "INTERMEDIATE", "HSC", "SSLC", "BOARD", "CBSE", "ICSE",
                "PASSING YEAR", "PASSING_YEAR", "PREVIOUS EDUCATION", "PREVIOUS SCHOOL",
                "YEAR OF PASSING", "QUALIFICATION DETAILS"
            ]

            def is_high_school(el) -> bool:
                txt = el.get_text(" ", strip=True).upper()
                return any(k in txt for k in HIGH_SCHOOL_KEYWORDS)

            proctor_tables = set()
            if proctor_table:
                proctor_tables.add(proctor_table)
            if proctor_section:
                proctor_tables.update(proctor_section.find_all("table"))

            univ_tables = [
                t for t in soup.find_all("table")
                if not is_high_school(t) and t not in proctor_tables
            ]

            univ_containers = [
                div for div in soup.find_all(["div", "section"])
                if any(k in div.get_text().upper() for k in ["ACADEMIC", "ADMISSION", "DEGREE", "PROGRAMME", "ENROLLMENT"])
                and not is_high_school(div)
                and (not proctor_section or div != proctor_section)
            ]
            search_containers = univ_tables + univ_containers

            # Extract university program (Degree)
            raw_program = ""
            for c in search_containers:
                val = extract_field_value(
                    c,
                    ["PROGRAMME NAME", "PROGRAMME / DEGREE", "PROGRAMME DESCRIPTION", "DEGREE", "PROGRAMME", "PROGRAM"],
                    exclude_labels=["PROGRAMME GROUP", "PROGRAM GROUP", "PROGRAMME TYPE", "PREVIOUS", "BOARD"]
                )
                if val and val.upper() not in ["UG", "PG", "PH.D", "PHD"]:
                    raw_program = val
                    break

            # Extract university branch (Specialization)
            INVALID_BRANCHES = ["PCM", "PCB", "PCMB", "MPC", "BIPC", "COMMERCE", "ARTS", "SCIENCE", "GENERAL"]
            raw_branch = ""
            for c in search_containers:
                val = extract_field_value(
                    c,
                    ["BRANCH / SPECIALIZATION", "BRANCH NAME", "SPECIALIZATION", "BRANCH", "STREAM / SPECIALIZATION", "DISCIPLINE", "MAJOR"],
                    exclude_labels=["PREVIOUS", "QUALIFYING", "10TH", "12TH", "BOARD", "PASSING"]
                )
                if val and val.upper() not in INVALID_BRANCHES:
                    raw_branch = val
                    break

            # Extract university school
            INVALID_SCHOOL_KEYWORDS = [
                "VIDYALAYA", "HIGH SCHOOL", "HIGHER SECONDARY", "JUNIOR COLLEGE", "PUBLIC SCHOOL",
                "INTERMEDIATE", "KENDRIYA", "MATRICULATION", "COLLEGE", "SECONDARY SCHOOL", "GRAMMAR SCHOOL"
            ]
            raw_school = ""
            for c in search_containers:
                val = extract_field_value(
                    c,
                    ["SCHOOL NAME", "SCHOOL / CENTRE", "SCHOOL", "CENTRE", "INSTITUTE"],
                    exclude_labels=["PREVIOUS", "QUALIFYING", "10TH", "12TH", "BOARD", "HIGH SCHOOL", "PROCTOR"]
                )
                if val and not any(k in val.upper() for k in INVALID_SCHOOL_KEYWORDS):
                    if not mentor["school"] or val.upper() != mentor["school"].upper():
                        raw_school = val
                        break

            # ── 3. Fallback Decoding via VIT-AP Registration Number ──
            branch_code = ""
            reg_upper = (self.registration_number or "").upper().strip()
            reg_m = re.search(r'\b(?:2[0-9])([A-Z]{3})[0-9]{4,5}\b', reg_upper)
            if reg_m:
                branch_code = reg_m.group(1)
            elif len(reg_upper) >= 5:
                sub = reg_upper[2:5]
                if sub.isalpha():
                    branch_code = sub

            branch_info = VITAP_BRANCH_MAP.get(branch_code, {})

            if not raw_program or raw_program.upper() in ["UG", "PG"]:
                raw_program = branch_info.get("program", raw_program or "B.Tech")

            if not raw_branch or raw_branch.upper() in INVALID_BRANCHES:
                raw_branch = branch_info.get("branch", raw_branch or "")

            if not raw_school or any(k in raw_school.upper() for k in INVALID_SCHOOL_KEYWORDS):
                raw_school = branch_info.get("school", raw_school or "")

            # ── 4. Main Profile Assembly ──
            personal_containers = [t for t in soup.find_all("table") if not is_high_school(t) and t not in proctor_tables] or [soup]
            
            def extract_personal(targets, exclude_labels=None):
                for pc in personal_containers:
                    val = extract_field_value(pc, targets, exclude_labels)
                    if val:
                        return val
                return extract_field_value(soup, targets, exclude_labels)

            student_name = extract_personal(["STUDENT NAME", "NAME OF THE STUDENT", "NAME"], exclude_labels=["FACULTY", "PROCTOR", "STAFF", "FATHER", "MOTHER", "PARENT"])
            if not student_name:
                student_name = extract_field_value(soup, ["STUDENT NAME", "NAME OF THE STUDENT", "NAME"], exclude_labels=["FACULTY", "PROCTOR", "STAFF", "FATHER", "MOTHER", "PARENT"])

            student_email = extract_personal(["EMAIL", "EMAIL ID", "STUDENT EMAIL"], exclude_labels=["FACULTY", "PROCTOR", "STAFF", "PARENT", "FATHER", "MOTHER"])

            # Robust Date of Birth extraction
            dob = extract_personal(["DATE OF BIRTH", "D.O.B", "DOB", "BIRTH DATE", "DATE_OF_BIRTH"], exclude_labels=["FATHER", "MOTHER", "PARENT"])
            if not dob:
                # Direct scan of all td elements across the entire soup
                all_tds = soup.find_all(["td", "th"])
                for idx, td in enumerate(all_tds):
                    td_txt = re.sub(r'\s+', ' ', td.get_text(" ", strip=True)).upper().rstrip(":").strip()
                    if td_txt in ["DATE OF BIRTH", "D.O.B", "DOB", "BIRTH DATE"] or ("DATE OF BIRTH" in td_txt and not any(p in td_txt for p in ["FATHER", "MOTHER", "PARENT", "GUARDIAN"])):
                        if idx + 1 < len(all_tds):
                            next_val = re.sub(r'\s+', ' ', all_tds[idx + 1].get_text(" ", strip=True)).lstrip(":").strip()
                            if next_val == ":" and idx + 2 < len(all_tds):
                                next_val = re.sub(r'\s+', ' ', all_tds[idx + 2].get_text(" ", strip=True)).lstrip(":").strip()
                            if next_val and next_val != "-" and next_val.upper() not in ["NOT AVAILABLE", "N/A"]:
                                dob = next_val
                                break

            # Sanity guard: Ensure mentor data never leaks student's personal info
            if mentor["faculty_name"] and student_name and mentor["faculty_name"].strip().upper() == student_name.strip().upper():
                mentor["faculty_name"] = ""
            if mentor["faculty_email"] and student_email and mentor["faculty_email"].strip().lower() == student_email.strip().lower():
                mentor["faculty_email"] = ""

            profile = {
                "name": student_name,
                "reg_no": self.registration_number,
                "application_number": extract_personal(["APPLICATION NUMBER", "APPLICATION NO", "APPL NO"]),
                "dob": dob,
                "gender": extract_personal(["GENDER", "SEX"]),
                "blood_group": extract_personal(["BLOOD GROUP", "BLOOD GRP", "BLOOD"]),
                "email": student_email,
                "program": raw_program,
                "branch": raw_branch,
                "school": raw_school,
                "base64_pfp": base64_pfp,
                "mentor": mentor["faculty_name"],
                "mentor_details": mentor,
            }

            self._cache["profile"] = profile
            return profile
        except Exception as e:
            print(f"Profile error: {e}")
            return {"name": "Student", "reg_no": self.registration_number}
    
    async def get_curriculum(self) -> dict:
        """Fetch curriculum and credit distribution."""
        try:
            # 1. Try to fetch curriculum page (try primary route, and StudentCurriculum alternative)
            data = {"summary": {"earned": "0", "total": "0", "left": "0"}, "distribution": []}
            for route_name in [ROUTES.get("curriculum", "/vtop/academics/common/Curriculum"), "/vtop/academics/common/StudentCurriculum"]:
                try:
                    await self._post_menu(route_name)
                    resp = await self._post_authenticated(
                        route_name,
                        {"authorizedID": self.registration_number, "verifyMenu": "true"}
                    )
                    data = self._parse_curriculum(resp.text)
                    if data["distribution"] or (data["summary"]["earned"] != "0" and data["summary"]["total"] != "0"):
                        print(f"Curriculum found via {route_name}: {data['summary']}")
                        break
                except Exception as e:
                    print(f"Error fetching curriculum via {route_name}: {e}")

            # 2. If nothing found, try Grade History page for summary
            if data["summary"]["earned"] == "0" and not data["distribution"]:
                print("Curriculum page empty, trying Grade History fallback...")
                resp = await self._post_authenticated(
                    ROUTES["grade_hist"],
                    {"authorizedID": self.registration_number}
                )
                gh_data = self._parse_curriculum(resp.text)
                print(f"Grade History parse: {gh_data['summary']}")
                if gh_data["distribution"]:
                    data["distribution"] = gh_data["distribution"]
                if gh_data["summary"]["earned"] != "0":
                    data["summary"] = gh_data["summary"]

            # 3. Always fetch grades to enrich with detailed courses and ensure 100% accurate earned numbers
            grades_data = await self.get_grades()
            grades_list = grades_data.get("courses", []) if isinstance(grades_data, dict) else []

            # Delivery types that must NEVER appear as categories in credit distribution
            DELIVERY_TYPES = {"ETL", "TH", "LO", "PJT", "NCC", "ETP", "SS", "OC", "AUDIT"}

            def normalize_category_type(raw_type: str) -> str:
                rt = raw_type.strip().upper()
                if rt == "PC" or "PROGRAMME CORE" in rt or "PROGRAM CORE" in rt or "DISCIPLINE CORE" in rt: return "PC"
                if rt == "PE" or "PROGRAMME ELECTIVE" in rt or "PROGRAM ELECTIVE" in rt or "DISCIPLINE ELECTIVE" in rt: return "PE"
                if rt == "UC" or "UNIVERSITY CORE" in rt: return "UC"
                if rt == "UE" or "UNIVERSITY ELECTIVE" in rt or "OPEN ELECTIVE" in rt: return "UE"
                if rt == "NC" or "NON CREDIT" in rt: return "NC"
                if rt == "BRIDGE" or "BRIDGE" in rt: return "BRIDGE"
                if rt == "ECA" or "EXTRA" in rt or "CO-CURRIC" in rt: return "ECA"
                return rt

            def categorize_course(course: dict) -> str:
                # 1. Primary: use course_distribution (VTOP column 8)
                dist = str(course.get("course_distribution", "")).strip()
                norm = normalize_category_type(dist)
                if norm == "PC": return "Programme Core"
                if norm == "PE": return "Programme Elective"
                if norm == "UC": return "University Core"
                if norm == "UE": return "University Elective"
                if norm == "NC": return "Non Credit"
                if norm == "BRIDGE": return "Bridge Course"
                if norm == "ECA": return "University Core"

                # 2. Fallback: course code prefixes
                code = str(course.get("course_code", "")).strip().upper()
                uc_prefixes = ("MAT", "PHY", "CHY", "ENG", "HUM", "FRL", "STS", "ENV", "EXC", "CSA", "SET", "SWY", "NCC")
                if any(code.startswith(p) for p in uc_prefixes):
                    return "University Core"
                return "Programme Core"

            standard_order = ["University Core", "Programme Core", "Programme Elective", "University Elective"]
            standard_defaults = {
                "University Core": 89.0,
                "Programme Core": 40.0,
                "Programme Elective": 22.0,
                "University Elective": 9.0,
            }

            # Filter existing distribution to remove pedagogical delivery types and summary rows
            clean_distribution = []
            seen_categories = set()
            for d in data.get("distribution", []):
                cat = d.get("category", "").strip()
                if not cat or cat.upper() in DELIVERY_TYPES:
                    continue
                if any(w in cat.lower() for w in ["total", "grand", "sl.", "s.no"]):
                    continue

                norm = normalize_category_type(cat)
                canonical = cat
                if norm == "UC": canonical = "University Core"
                elif norm == "PC": canonical = "Programme Core"
                elif norm == "PE": canonical = "Programme Elective"
                elif norm == "UE": canonical = "University Elective"
                
                d["category"] = canonical
                if canonical not in seen_categories:
                    seen_categories.add(canonical)
                    clean_distribution.append(d)

            # Ensure all 4 standard degree categories are present
            for std_cat in standard_order:
                if std_cat not in seen_categories:
                    clean_distribution.append({
                        "category": std_cat,
                        "required": str(standard_defaults[std_cat]),
                        "earned": "0.0",
                        "left": str(standard_defaults[std_cat]),
                        "courses": []
                    })
                    seen_categories.add(std_cat)

            # Sort so standard categories appear in the exact official order
            def sort_key(d):
                cat = d["category"]
                if cat in standard_order:
                    return (0, standard_order.index(cat))
                return (1, cat)
            clean_distribution.sort(key=sort_key)

            # Inject courses and compute accurate earned credits from passed courses
            for dist in clean_distribution:
                dist["courses"] = []
                cat_name = dist["category"]
                calc_earned = 0.0

                for g in grades_list:
                    grade = g.get("grade", "").strip().upper()
                    # Only passed courses contribute to earned credits (S, A, B, C, D, E)
                    if grade in ["F", "N", "W", "FAIL", ""]:
                        continue

                    c_cat = categorize_course(g)
                    if c_cat.lower() == cat_name.lower():
                        c_credits = str(g.get("credits", "0")).strip()
                        try:
                            calc_earned += float(c_credits)
                        except:
                            pass

                        dist["courses"].append({
                            "course_code": g.get("course_code", ""),
                            "subject": g.get("subject", ""),
                            "type": g.get("type", ""),
                            "credits": c_credits,
                            "grade": grade,
                            "exam_month": g.get("exam_month", ""),
                        })

                # If earned was 0.0 or not matching, use the sum of passed courses
                curr_earned = float(dist.get("earned", 0) or 0)
                if curr_earned == 0.0 and calc_earned > 0.0:
                    dist["earned"] = str(calc_earned)
                elif calc_earned > 0.0:
                    dist["earned"] = str(calc_earned)

                req_val = float(dist.get("required", 0) or 0)
                dist["left"] = str(round(max(0.0, req_val - float(dist["earned"])), 2))

            data["distribution"] = clean_distribution

            # Compute overall summary
            tot_earned = sum(float(d["earned"]) for d in clean_distribution if d["category"] in standard_order)
            tot_req = sum(float(d["required"]) for d in clean_distribution if d["category"] in standard_order)
            
            parsed_earned = float(data["summary"].get("earned", 0) or 0)
            if parsed_earned == 0.0 or tot_earned > 0:
                data["summary"]["earned"] = str(tot_earned) if tot_earned > 0 else str(parsed_earned)

            parsed_total = float(data["summary"].get("total", 0) or 0)
            if parsed_total < 100:
                data["summary"]["total"] = str(tot_req) if tot_req >= 100 else "160.0"

            t_val = float(data["summary"]["total"])
            e_val = float(data["summary"]["earned"])
            data["summary"]["left"] = str(round(max(0.0, t_val - e_val), 2))

            self._cache["curriculum"] = data
            return data
        except Exception as e:
            print(f"Curriculum error: {e}")
            return {
                "summary": {"earned": "0", "total": "160", "left": "160"},
                "distribution": []
            }

    def _parse_curriculum(self, html: str) -> dict:
        """Parse HTML for credit summary and distribution (Curriculum or Grade Hist)."""
        soup = BeautifulSoup(html, "lxml")
        summary = {"earned": "0", "total": "0", "left": "0"}
        distribution = []
        DELIVERY_TYPES = {"ETL", "TH", "LO", "PJT", "NCC", "ETP", "SS", "OC", "AUDIT"}
        
        tables = soup.find_all("table")
        for table in tables:
            rows = table.find_all("tr")
            if not rows: continue
            
            header_row_idx = -1
            idx_cat = -1
            idx_req = -1
            idx_earned = -1
            idx_left = -1
            
            # Scan the first few rows for header columns (row 0 might be "CREDITS DISTRIBUTION" banner)
            for r_idx, row in enumerate(rows[:4]):
                cells = row.find_all(["th", "td"])
                texts = [c.get_text(strip=True).lower() for c in cells]
                
                c_idx = -1
                for i, h in enumerate(texts):
                    if any(k in h for k in ["category", "component", "bucket", "basket", "course distribution", "credit distribution"]):
                        c_idx = i
                        break
                
                r_idx_col = -1
                for i, h in enumerate(texts):
                    if any(k in h for k in ["total credit", "required", "minimum", "curriculum credit", "total"]):
                        if not any(x in h for x in ["earned", "registered", "completed", "done", "left", "remaining"]):
                            r_idx_col = i
                            break
                            
                e_idx_col = -1
                for i, h in enumerate(texts):
                    if any(k in h for k in ["earned", "completed", "done", "acquired"]):
                        e_idx_col = i
                        break
                        
                if c_idx != -1:
                    header_row_idx = r_idx
                    idx_cat = c_idx
                    if r_idx_col != -1: idx_req = r_idx_col
                    if e_idx_col != -1: idx_earned = e_idx_col
                    for i, h in enumerate(texts):
                        if any(k in h for k in ["left", "remaining", "pending"]):
                            idx_left = i
                    break
                    
            if header_row_idx == -1 or idx_cat == -1:
                continue
                
            total_earned = 0.0
            total_required = 0.0
            
            for row in rows[header_row_idx + 1:]:
                cols = row.find_all(["td", "th"])
                if len(cols) <= idx_cat:
                    continue
                texts = [c.get_text(strip=True) for c in cols]
                cat_name = texts[idx_cat] if idx_cat < len(texts) else ""
                
                # Exclude delivery types
                if cat_name.upper() in DELIVERY_TYPES:
                    continue
                    
                # Check for total/summary row
                if any(w in cat_name.lower() for w in ["total", "grand"]):
                    for t in texts:
                        nums = re.findall(r'\d+\.?\d*', t)
                        if nums:
                            val = float(nums[0])
                            if val > 100 and summary["total"] == "0":
                                summary["total"] = str(val)
                    if idx_req != -1 and idx_req < len(texts):
                        nums = re.findall(r'\d+\.?\d*', texts[idx_req])
                        if nums: summary["total"] = nums[0]
                    if idx_earned != -1 and idx_earned < len(texts):
                        nums = re.findall(r'\d+\.?\d*', texts[idx_earned])
                        if nums: summary["earned"] = nums[0]
                    continue
                    
                if not cat_name or any(s in cat_name.lower() for s in ["sl.", "serial", "s.no"]):
                    continue
                    
                try:
                    req_val = texts[idx_req] if idx_req != -1 and idx_req < len(texts) else "0"
                    earned_val = texts[idx_earned] if idx_earned != -1 and idx_earned < len(texts) else "0"
                    
                    rv = re.findall(r'\d+\.?\d*', req_val)
                    ev = re.findall(r'\d+\.?\d*', earned_val)
                    
                    r_num = float(rv[0]) if rv else 0.0
                    e_num = float(ev[0]) if ev else 0.0
                    
                    if r_num > 0 or e_num > 0:
                        left_num = max(0.0, r_num - e_num)
                        if idx_left != -1 and idx_left < len(texts):
                            lv = re.findall(r'\d+\.?\d*', texts[idx_left])
                            if lv: left_num = float(lv[0])
                            
                        distribution.append({
                            "category": cat_name,
                            "required": str(r_num),
                            "earned": str(e_num),
                            "left": str(left_num),
                            "courses": []
                        })
                        total_earned += e_num
                        total_required += r_num
                except Exception:
                    continue
                    
            if total_earned > 0 and summary["earned"] == "0":
                summary["earned"] = str(total_earned)
            if total_required > 0 and summary["total"] == "0":
                summary["total"] = str(total_required)

        # Check for summary rows in other tables if not yet found
        if summary["earned"] == "0" or summary["total"] == "0":
            for table in tables:
                for row in table.find_all("tr"):
                    cols = row.find_all(["td", "th"])
                    if len(cols) >= 2:
                        label = cols[0].get_text(strip=True).lower()
                        val_text = cols[-1].get_text(strip=True) 
                        if ("earned" in label or "completed" in label) and "registered" not in label and summary["earned"] == "0":
                            nums = re.findall(r'\d+\.?\d*', val_text)
                            if nums: summary["earned"] = nums[0]
                        elif "total" in label and any(k in label for k in ["required", "curriculum", "minimum", "credit"]) and summary["total"] == "0":
                            nums = re.findall(r'\d+\.?\d*', val_text)
                            if nums: summary["total"] = nums[0]

        try:
            e = float(summary["earned"])
            t = float(summary["total"])
            if t == 0: t = 160.0
            summary["total"] = str(t)
            summary["left"] = str(round(max(0.0, t - e), 2))
        except Exception:
            pass
            
        return {"summary": summary, "distribution": distribution}

    async def get_faculty_details(self, search_term: str) -> list:
        """Search for faculty details."""
        try:
            # Initialize page first
            await self._post_menu(ROUTES["faculty"])
            
            import datetime
            x_val = datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT")
            
            resp = await self._post_authenticated(
                ROUTES["faculty"],
                {
                    "empId": search_term,
                    "authorizedID": self.registration_number,
                    "x": x_val
                }
            )
            
            return self._parse_faculty_table(resp.text)
        except Exception as e:
            raise Exception(f"Faculty search error: {e}")

    def _parse_faculty_table(self, html: str) -> list:
        """Parse faculty search results - matches vitap_student_app Rust parser logic.
        
        VTOP faculty table: skip first header row, then for each data row:
        - cells[0] = Faculty Name
        - cells[1] = Designation
        - cells[2] = School/Centre
        - Extract emp_id from <button> element's id attribute or onclick attribute
        """
        soup = BeautifulSoup(html, "lxml")
        data = []
        
        all_rows = soup.find_all("tr")
        
        # Skip first header row - matching Rust: .skip(1)
        for row in all_rows[1:]:
            cells = row.find_all("td")
            if len(cells) < 4:
                continue
            
            # Extract emp_id from button in the row
            emp_id = ""
            button = row.find("button")
            if button:
                # Prefer the 'id' attribute on the button (e.g. id="70447")
                btn_id = button.get("id", "").strip()
                if btn_id:
                    emp_id = btn_id
                else:
                    # Fallback: extract from onclick attribute
                    onclick = button.get("onclick", "")
                    if "&quot;" in onclick:
                        parts = onclick.split("&quot;")
                        emp_id = parts[1] if len(parts) > 1 else ""
                    elif '"' in onclick:
                        parts = onclick.split('"')
                        emp_id = parts[1] if len(parts) > 1 else ""
                    else:
                        # Last fallback: extract digits
                        import re as _re
                        emp_id = "".join(c for c in onclick if c.isdigit())
            
            if not emp_id:
                continue  # Skip rows without a valid employee button
            
            def clean(cell):
                return cell.get_text(strip=True).replace("\t", "").replace("\n", "")
            
            data.append({
                "name": clean(cells[0]),
                "designation": clean(cells[1]),
                "school": clean(cells[2]),
                "emp_id": emp_id,
            })
        
        return data

    async def get_faculty_data(self, emp_id: str) -> dict:
        """Fetch detailed info for a single faculty member."""
        try:
            import datetime
            x_val = datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT")
            resp = await self._post_authenticated(
                "/vtop/hrms/EmployeeSearch1ForStudent",
                {
                    "empId": emp_id,
                    "authorizedID": self.registration_number,
                    "x": x_val
                }
            )
            return self._parse_faculty_data(resp.text)
        except Exception as e:
            raise Exception(f"Faculty data error: {e}")

    def _parse_faculty_data(self, html: str) -> dict:
        """Parse EmployeeSearch1ForStudent response."""
        soup = BeautifulSoup(html, "lxml")
        tables = soup.find_all("table", class_="table-bordered")
        
        details = {
            "name": "",
            "designation": "",
            "department": "",
            "school_centre": "",
            "email": "",
            "cabin_number": "",
            "office_hours": []
        }
        
        if not tables:
            tables = soup.find_all("table")
            
        if len(tables) > 0:
            for row in tables[0].find_all("tr"):
                cells = row.find_all("td")
                if len(cells) >= 2:
                    label = cells[0].get_text(strip=True).lower()
                    val = cells[1].get_text(strip=True)
                    if "name of the faculty" in label: details["name"] = val
                    elif "designation" in label: details["designation"] = val
                    elif "name of department" in label: details["department"] = val
                    elif "school" in label or "centre" in label: details["school_centre"] = val
                    elif "e-mail" in label: details["email"] = val
                    elif "cabin number" in label: details["cabin_number"] = val

        if len(tables) > 1:
            for row in tables[1].find_all("tr")[1:]:
                cells = row.find_all("td")
                if len(cells) >= 2:
                    day = cells[0].get_text(strip=True)
                    timings = cells[1].get_text(strip=True)
                    if day and timings and "open hours" not in day.lower() and "week day" not in day.lower():
                        details["office_hours"].append({"day": day, "timings": timings})

        return details

    async def get_digital_assignments(self, semester_id: str = None) -> list:
        """Fetch digital assignments."""
        try:
            sem_id = semester_id or "AP2025262"
            await self._post_menu(ROUTES["da"])
            
            resp = await self._post_authenticated(
                ROUTES["da"],
                {
                    "semesterSubId": sem_id,
                    "authorizedID": self.registration_number,
                }
            )
            
            return self._parse_da_table(resp.text)
        except Exception as e:
            raise Exception(f"DA error: {e}")

    def _parse_da_table(self, html: str) -> list:
        """Parse DA table."""
        soup = BeautifulSoup(html, "lxml")
        data = []
        
        tables = soup.find_all("table")
        for table in tables:
            rows = table.find_all("tr")
            for row in rows:
                cols = row.find_all("td")
                if len(cols) >= 6:
                    texts = [c.get_text(strip=True) for c in cols]
                    if any(h in texts[0].lower() for h in ["sl", "sno"]):
                        continue
                    
                    data.append({
                        "course_code": texts[1],
                        "subject": texts[2],
                        "type": texts[3],
                        "title": texts[4],
                        "max_marks": texts[5],
                        "weightage": texts[6] if len(texts) > 6 else "",
                        "due_date": texts[7] if len(texts) > 7 else "",
                        "status": texts[8] if len(texts) > 8 else "Pending",
                    })
        return data

    async def get_outing_status(self) -> list:
        """Fetch general outing history and current status."""
        try:
            url = ROUTES["outing"]
            data = {
                "verifyMenu": "true",
                "authorizedID": self.registration_number,
                "_csrf": self.post_login_csrf or self.csrf_token,
                "nocache": str(int(time.time() * 1000)),
            }
            resp = await self.client.post(url, data=data, headers=HEADERS)
            self._check_session_expired(resp)
            fresh_csrf = _find_csrf(resp.text)
            if fresh_csrf:
                self.post_login_csrf = fresh_csrf
            return self._parse_outing_table(resp.text)
        except Exception as e:
            raise Exception(f"Outing error: {e}")

    def _parse_outing_table(self, html: str) -> list:
        """Parse general outing table."""
        soup = BeautifulSoup(html, "lxml")
        data = []
        
        table = soup.find("table", id="BookingRequests") or soup.find("table", class_="table-bordered") or soup.find("table")
        if not table:
            return data
            
        rows = table.find_all("tr")
        for row in rows[1:]:  # skip header
            cols = row.find_all("td")
            if len(cols) >= 10:
                texts = [c.get_text(strip=True) for c in cols]
                row_html = str(row)
                
                # Extract leave_id from download link's data-url or regex
                leave_id = ""
                a_tag = row.find("a", attrs={"data-url": True})
                if a_tag and a_tag.get("data-url"):
                    leave_id = a_tag["data-url"].split("/")[-1].strip()
                if not leave_id:
                    m = re.search(r"downloadLeavePass/([A-Za-z0-9]+)", row_html) or re.search(r"deleteGeneralOuting\('([A-Za-z0-9]+)'\)", row_html)
                    if m:
                        leave_id = m.group(1)
                if not leave_id:
                    m = re.search(r"\b(L\d{8,14})\b", row_html)
                    if m:
                        leave_id = m.group(1)
                
                status_text = texts[9] if len(texts) > 9 else ""
                
                data.append({
                    "id": leave_id or texts[0],
                    "leaveId": leave_id,
                    "type": "General",
                    "place": texts[2] if len(texts) > 2 else "",
                    "purpose": texts[3] if len(texts) > 3 else "",
                    "out_date": f"{texts[4]} {texts[5]}" if len(texts) > 5 else (texts[4] if len(texts) > 4 else ""),
                    "in_date": f"{texts[6]} {texts[7]}" if len(texts) > 7 else (texts[6] if len(texts) > 6 else ""),
                    "status": status_text,
                })
        return data

    async def get_payment_history(self) -> list:
        """Fetch payment receipts and history."""
        try:
            data = {
                "verifyMenu": "true",
                "authorizedID": self.registration_number,
                "_csrf": self.post_login_csrf or self.csrf_token,
                "nocache": str(int(time.time() * 1000)),
            }
            resp = await self.client.post(ROUTES["payments"], data=data, headers=HEADERS)
            return self._parse_payments_table(resp.text)
        except Exception as e:
            raise Exception(f"Payments error: {e}")

    def _parse_payments_table(self, html: str) -> list:
        """Parse payments table from VTOP.
        
        VTOP payment receipts table typically has columns:
        Receipt No, Date, Application No, Fee Type, Amount, Payment Mode, Print Button
        """
        soup = BeautifulSoup(html, "lxml")
        data = []
        
        # Find the main receipts table
        table = soup.find("table", class_="table-bordered")
        if not table:
            table = soup.find("table")
        
        if not table:
            return data
        
        rows = table.find_all("tr")
        
        # Debug: print header row to understand column structure
        if rows:
            header_cells = rows[0].find_all(["th", "td"])
            headers = [c.get_text(strip=True) for c in header_cells]
            print(f"[PAYMENTS DEBUG] Header columns ({len(headers)}): {headers}")
            if len(rows) > 1:
                first_data = rows[1].find_all("td")
                first_vals = [c.get_text(strip=True) for c in first_data]
                print(f"[PAYMENTS DEBUG] First data row ({len(first_vals)}): {first_vals}")
        
        # Build a header-to-index map for robust column detection
        header_cells = rows[0].find_all(["th", "td"]) if rows else []
        header_map = {}
        for i, hc in enumerate(header_cells):
            h = hc.get_text(strip=True).lower()
            header_map[h] = i
        
        # Try to detect column indices from headers
        receipt_idx = None
        date_idx = None
        amount_idx = None
        desc_idx = None
        mode_idx = None
        appno_idx = None
        serial_idx = None
        campus_idx = None
        matched = set()
        
        for i, (h_raw, _) in enumerate(header_map.items()):
            h = h_raw.replace(".", "").replace(" ", "").replace("_", "")
            idx = header_map[h_raw]
            
            # Serial number (skip)
            if h in ("slno", "sno", "sino", "sr", "srno", "no", "#", ""):
                serial_idx = idx
                matched.add(idx)
            # Receipt number
            elif any(kw in h for kw in ("receiptno", "receiptnumber", "recno", "receiptid", "receipt")):
                receipt_idx = idx
                matched.add(idx)
            # Date
            elif any(kw in h for kw in ("date", "receiptdate", "paymentdate", "transactiondate", "transdate")):
                date_idx = idx
                matched.add(idx)
            # Amount
            elif any(kw in h for kw in ("amount", "totalamount", "paidamount", "feeamount")):
                amount_idx = idx
                matched.add(idx)
            # Fee type / description
            elif any(kw in h for kw in ("feetype", "feehead", "feeheading", "heading", "description", 
                                         "particular", "particulars", "category", "purpose",
                                         "feecategory", "feeparticular")):
                desc_idx = idx
                matched.add(idx)
            # Payment mode
            elif any(kw in h for kw in ("mode", "paymentmode", "paymode", "paytype", "method",
                                         "transactiontype", "transtype", "modeofpayment")):
                mode_idx = idx
                matched.add(idx)
            # Application number
            elif any(kw in h for kw in ("applicationno", "applno", "appno", "appnumber", "application")):
                appno_idx = idx
                matched.add(idx)
            # Campus
            elif any(kw in h for kw in ("campus", "campuscode", "location")):
                campus_idx = idx
                matched.add(idx)
            # Print / Action button columns (skip)
            elif any(kw in h for kw in ("print", "action", "download", "duplicate", "view")):
                matched.add(idx)
        
        print(f"[PAYMENTS DEBUG] Mapped: receipt={receipt_idx} date={date_idx} amount={amount_idx} desc={desc_idx} mode={mode_idx} appno={appno_idx} campus={campus_idx}")
        
        # For unmatched columns, try to infer from the first data row's values
        import re
        unmatched_indices = [i for i in range(len(header_map)) if i not in matched]
        
        if unmatched_indices and len(rows) > 1:
            sample_cells = rows[1].find_all("td")
            for ui in unmatched_indices:
                if ui >= len(sample_cells):
                    continue
                val = sample_cells[ui].get_text(strip=True)
                val_clean = val.replace(",", "").replace(".", "").strip()
                
                # Date pattern (e.g., 11-JUL-2026)
                if date_idx is None and re.search(r'\d{1,2}[-/]\w{3}[-/]\d{2,4}', val):
                    date_idx = ui
                # Application number (e.g., AM2600133122)
                elif appno_idx is None and re.match(r'^[A-Z]{2,4}\d{5,}$', val):
                    appno_idx = ui
                # Numeric value — likely amount
                elif amount_idx is None and val_clean.isdigit() and len(val_clean) >= 3:
                    amount_idx = ui
                # Text value — likely description or mode
                elif desc_idx is None and len(val) > 3 and not val.isdigit() and not val.startswith("AM"):
                    desc_idx = ui
                elif mode_idx is None and len(val) > 1 and not val.isdigit():
                    mode_idx = ui
            
            print(f"[PAYMENTS DEBUG] After inference: receipt={receipt_idx} date={date_idx} amount={amount_idx} desc={desc_idx} mode={mode_idx}")

        
        # Skip first row (header)
        for row in rows[1:]:
            cells = row.find_all("td")
            if len(cells) < 3:
                continue
            
            def clean(idx):
                if idx is not None and idx < len(cells):
                    return cells[idx].get_text(strip=True)
                return ""
            
            receipt_number = clean(receipt_idx)
            date_val = clean(date_idx)
            amount_val = clean(amount_idx)
            description = clean(desc_idx)
            payment_mode = clean(mode_idx)
            
            # Positional fallback if header detection missed key columns
            if not receipt_number and len(cells) >= 1:
                receipt_number = clean(0)
            if not date_val and len(cells) >= 2:
                date_val = clean(1)
            if not amount_val:
                # If column 4 exists and looks like amount
                if len(cells) >= 5 and clean(4).replace(",", "").replace(".", "").isdigit():
                    amount_val = clean(4)
                elif len(cells) >= 3 and clean(2).replace(",", "").replace(".", "").isdigit():
                    amount_val = clean(2)
            if not description and len(cells) >= 4:
                description = clean(3)
            
            # Extract receipt_id from any button onclick in the row
            receipt_id = ""
            for cell in reversed(cells):
                button = cell.find("button")
                if button:
                    onclick = button.get("onclick", "")
                    prefix = "doDuplicateReceipt('"
                    suffix = "')"
                    if prefix in onclick:
                        start = onclick.index(prefix) + len(prefix)
                        rest = onclick[start:]
                        if suffix in rest:
                            end = rest.index(suffix)
                            receipt_id = rest[:end]
                    break
            
            # Clean up amount
            if amount_val:
                amount_val = amount_val.replace("₹", "").replace("Rs", "").replace("Rs.", "").strip()
            
            # Fallback for description and payment_mode if either is empty/dash
            final_desc = description if (description and description != "-") else "Fee Payment"
            final_mode = payment_mode if (payment_mode and payment_mode != "-") else (description if description else "Online Payment")
            
            data.append({
                "receipt_no": receipt_number,
                "date": date_val,
                "amount": amount_val,
                "description": final_desc,
                "payment_mode": final_mode,
                "status": "Paid",
                "receipt_id": receipt_id,
            })
        
        return data


    async def get_courses(self, semester_id: str = None) -> list:
        """Fetch courses for a specific semester (using attendance page)."""
        try:
            sem_id = semester_id or "AP2025262"
            await self._post_menu(ROUTES["attendance"])
            
            resp = await self._post_authenticated(
                ROUTES["view_attend"],
                {
                    "semesterSubId": sem_id,
                    "authorizedID": self.registration_number,
                }
            )
            
            # Reuse attendance parser but only return basic course info
            attendance = self._parse_attendance_table(resp.text)
            courses = []
            for a in attendance:
                courses.append({
                    "course_code": a.get("course_code"),
                    "subject": a.get("subject"),
                    "type": a.get("type"),
                })
            return courses
        except Exception as e:
            raise Exception(f"Courses error: {e}")


    async def get_general_outing_pdf(self, leave_id: str) -> bytes:
        """Download General Outing PDF pass."""
        if not self.logged_in: raise Exception("Not logged in")
        import urllib.parse
        from datetime import datetime, timezone
        x_time = urllib.parse.quote(datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT"))
        url = f"/vtop/hostel/downloadLeavePass/{leave_id}?authorizedID={self.registration_number}&_csrf={self.post_login_csrf}&x={x_time}"
        resp = await self._get_authenticated(url)
        if resp.status_code == 200 and resp.content:
            if b"%PDF" not in resp.content[:1024]:
                raise Exception("Session expired. Please pull-to-refresh your Outings to log in again.")
            return resp.content
        raise Exception("Failed to download PDF")

    async def get_weekend_outing_pdf(self, booking_id: str) -> bytes:
        """Download Weekend Outing PDF pass."""
        if not self.logged_in: raise Exception("Not logged in")
        import urllib.parse
        from datetime import datetime, timezone
        x_time = urllib.parse.quote(datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT"))
        url = f"/vtop/hostel/downloadOutingForm/{booking_id}?authorizedID={self.registration_number}&_csrf={self.post_login_csrf}&x={x_time}"
        resp = await self._get_authenticated(url)
        if resp.status_code == 200 and resp.content:
            if b"%PDF" not in resp.content[:1024]:
                raise Exception("Session expired. Please pull-to-refresh your Outings to log in again.")
            return resp.content
        raise Exception("Failed to download PDF")

    async def _fetch_outing_form_hidden_fields(self, is_weekend=False) -> dict:
        """Helper to fetch pre-filled student details from the outing application page."""
        url = ROUTES["outing"] if not is_weekend else "/vtop/hostel/StudentWeekendOuting"
        resp = await self._post_menu(url)
        soup = BeautifulSoup(resp.text, "lxml")
        fields = {}
        
        # Extract fresh CSRF if available on the form page
        fresh_csrf = _find_csrf(resp.text)
        if fresh_csrf:
            self.post_login_csrf = fresh_csrf
        
        # Extract all input fields (hidden, text, etc.) by id and name
        for inp in soup.find_all("input"):
            val = inp.get("value", "")
            field_id = inp.get("id")
            field_name = inp.get("name")
            if field_id and field_id != "_csrf":
                fields[field_id] = val
            if field_name and field_name != "_csrf":
                fields[field_name] = val
        
        # Also extract selected values from <select> elements
        for sel in soup.find_all("select"):
            selected = sel.find("option", selected=True)
            val = selected.get("value", "") if selected else ""
            field_id = sel.get("id")
            field_name = sel.get("name")
            if field_id:
                fields[field_id] = val
            if field_name:
                fields[field_name] = val
        
        # Ensure student registration number is present
        fields.setdefault("regNo", self.registration_number)
        fields.setdefault("authorizedID", self.registration_number)
        
        print(f"[OUTING DEBUG] Form fields extracted: {fields}")
        
        if not fields.get("applicationNo"):
            print(f"[OUTING WARNING] applicationNo not found in form fields. Available keys: {list(fields.keys())}")
        return fields

    async def apply_general_outing(self, out_place: str, purpose: str, out_date: str, out_time: str, in_date: str, in_time: str) -> str:
        """Submit a General Outing."""
        try:
            fields = await self._fetch_outing_form_hidden_fields(is_weekend=False)
            
            # Times come as HH:MM
            out_parts = out_time.split(":") if ":" in out_time else [out_time, "00"]
            in_parts = in_time.split(":") if ":" in in_time else [in_time, "00"]
            
            norm_out_date = _normalize_outing_date(out_date)
            norm_in_date = _normalize_outing_date(in_date)
            
            data = {
                "authorizedID": self.registration_number,
                "LeaveId": "",
                "regNo": fields.get("regNo", self.registration_number),
                "name": fields.get("name", ""),
                "applicationNo": fields.get("applicationNo", ""),
                "gender": fields.get("gender", ""),
                "hostelBlock": fields.get("hostelBlock", ""),
                "roomNo": fields.get("roomNo", ""),
                "placeOfVisit": out_place,
                "purposeOfVisit": purpose,
                "outDate": norm_out_date,
                "outTimeHr": out_parts[0].strip(),
                "outTimeMin": out_parts[1].strip() if len(out_parts) > 1 else "00",
                "inDate": norm_in_date,
                "inTimeHr": in_parts[0].strip(),
                "inTimeMin": in_parts[1].strip() if len(in_parts) > 1 else "00",
                "parentContactNumber": fields.get("parentContactNumber", ""),
                "x": datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT"),
            }
            
            headers = {
                "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                "X-Requested-With": "XMLHttpRequest",
                "Referer": "https://vtop.vitap.ac.in/vtop/hostel/StudentGeneralOuting",
                "Origin": "https://vtop.vitap.ac.in",
            }
            
            data["_csrf"] = self.post_login_csrf or self.csrf_token
            print(f"[OUTING DEBUG] Submitting general outing: place={out_place}, outDate={norm_out_date}, outTime={out_time}, inDate={norm_in_date}, inTime={in_time}")
            
            resp = await self.client.post("/vtop/hostel/saveGeneralOutingForm", data=data, headers=headers)
            self._check_session_expired(resp)
            
            resp_text = resp.text
            print(f"[OUTING DEBUG] Response status: {resp.status_code}, length: {len(resp_text)}")
            print(f"[OUTING DEBUG] Response preview: {resp_text[:500]}")
            
            result = self._parse_outing_response(resp_text)
            print(f"[OUTING DEBUG] Parsed result: {result}")
            
            return result
        except Exception as e:
            print(f"[OUTING DEBUG] Exception in apply_general_outing: {e}")
            raise Exception(f"Failed to apply for general outing: {e}")

    async def apply_weekend_outing(self, out_place: str, purpose: str, out_date: str, out_time: str, contact_number: str) -> str:
        """Submit a Weekend Outing."""
        try:
            fields = await self._fetch_outing_form_hidden_fields(is_weekend=True)
            
            norm_outing_date = _normalize_outing_date(out_date)
            
            data = {
                "authorizedID": self.registration_number,
                "BookingId": "",
                "regNo": fields.get("regNo", self.registration_number),
                "name": fields.get("name", ""),
                "applicationNo": fields.get("applicationNo", ""),
                "gender": fields.get("gender", ""),
                "hostelBlock": fields.get("hostelBlock", ""),
                "roomNo": fields.get("roomNo", ""),
                "outPlace": out_place,
                "purposeOfVisit": purpose,
                "outingDate": norm_outing_date,
                "outTime": out_time,
                "contactNumber": contact_number,
                "parentContactNumber": fields.get("parentContactNumber", ""),
                "x": datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT"),
            }
            
            headers = {
                "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                "X-Requested-With": "XMLHttpRequest",
                "Referer": "https://vtop.vitap.ac.in/vtop/hostel/StudentWeekendOuting",
                "Origin": "https://vtop.vitap.ac.in",
            }
            
            data["_csrf"] = self.post_login_csrf or self.csrf_token
            print(f"[OUTING DEBUG] Submitting weekend outing: place={out_place}, date={norm_outing_date}, time={out_time}")
            
            resp = await self.client.post("/vtop/hostel/saveOutingForm", data=data, headers=headers)
            self._check_session_expired(resp)
            
            resp_text = resp.text
            print(f"[OUTING DEBUG] Weekend response status: {resp.status_code}, length: {len(resp_text)}")
            print(f"[OUTING DEBUG] Weekend response preview: {resp_text[:500]}")
            
            result = self._parse_outing_response(resp_text)
            print(f"[OUTING DEBUG] Parsed weekend result: {result}")
            
            return result
        except Exception as e:
            print(f"[OUTING DEBUG] Exception in apply_weekend_outing: {e}")
            raise Exception(f"Failed to apply for weekend outing: {e}")

    def _parse_outing_response(self, html: str) -> str:
        """Parse VTOP outing submit/delete response.
        
        Checks for:
        1. Explicit error spans (red text, .error, .alert-danger)
        2. Weekend success: green span with 'Successfully'/'Applied'/'Deleted'/'Saved'
        3. General outing success: SweetAlert modal h2/p with 'Successfully'/'Applied'/'Saved'
        4. Fallback h2 with success/error keywords
        5. Form page returned without success message = rejected
        6. Dashboard redirected = session expired / failed
        7. Default fallback
        """
        soup = BeautifulSoup(html, "lxml")
        
        # 1. Check for error messages (red text, error classes)
        for span in soup.select("span[style*='color: red'], span[style*='color:red'], .error, .alert-danger, span.help-block-error"):
            text = span.get_text(strip=True)
            if text and "disciplinary" not in text.lower() and "logs will be" not in text.lower():
                return f"Error: {text}"
        
        # Check for SweetAlert error modal
        sweet_alert = soup.select_one("div.sweet-alert")
        if sweet_alert:
            has_error_icon = bool(sweet_alert.select(".sa-error, .sa-warning, .error"))
            h2 = sweet_alert.select_one("h2")
            p = sweet_alert.select_one("p")
            title_text = h2.get_text(strip=True) if h2 else ""
            body_text = p.get_text(strip=True) if p else ""
            
            combined = f"{title_text} {body_text}".strip()
            if has_error_icon or any(kw in combined.lower() for kw in ("error", "failed", "cannot", "invalid", "not allowed", "already applied")):
                return f"Error: {combined if combined else 'Request rejected by VTOP'}"
            if any(kw in combined.lower() for kw in ("success", "applied", "saved", "deleted", "booked")):
                return title_text or body_text or combined

        # 2. Check for weekend outing success (green span)
        for span in soup.select("span.col-md-12[style*='color: green'], span.col-md-12[style*='color:green'], span[style*='color: green'], span[style*='color:green']"):
            text = span.get_text(strip=True)
            if text and any(kw in text.lower() for kw in ("success", "applied", "saved", "deleted", "booked")):
                return text

        # 3. Check for general outing success (SweetAlert modal h2 or p)
        if sweet_alert:
            sweet_h2 = sweet_alert.select_one("h2")
            if sweet_h2:
                text = sweet_h2.get_text(strip=True)
                if text:
                    return text
            sweet_p = sweet_alert.select_one("p")
            if sweet_p:
                text = sweet_p.get_text(strip=True)
                if text:
                    return text

        # 4. Fallback: any h2 with success/error keywords
        for h2 in soup.find_all("h2"):
            text = h2.get_text(strip=True)
            if text and any(kw in text.lower() for kw in ("successfully", "applied", "deleted", "saved", "booked")):
                return text
            if text and any(kw in text.lower() for kw in ("error", "failed")):
                return f"Error: {text}"
        
        # 5. If the outing form page was returned (silent failure — VTOP rejected the request)
        if "outingForm" in html or "saveOutingForm" in html or "saveGeneralOutingForm" in html or "StudentWeekendOuting" in html or "StudentGeneralOuting" in html:
            # Look for any colored span messages on the form
            for span in soup.select("span.col-sm-12[style*='color'], span.col-md-12[style*='color'], span[style*='color']"):
                text = span.get_text(strip=True)
                if text and "disciplinary" not in text.lower() and "logs will be" not in text.lower():
                    return f"Error: {text}"
            return "Error: Submission was rejected by VTOP. Please verify your details or check if you already have an active outing."
        
        # 6. If VTOP redirected to dashboard/home page (session expired or invalid request)
        page_text = soup.get_text(separator=" ", strip=True).lower()
        is_dashboard = any(kw in page_text for kw in ("quick links", "sign out", "login history", "my info"))
        if is_dashboard:
            return "Error: VTOP did not process the outing request. Your session may have expired. Please pull-to-refresh and try again."
            
        # 7. Final fallback
        return "Error: Unable to confirm outing submission from VTOP response. Please check outing history."

    async def delete_general_outing(self, leave_id: str) -> str:
        from datetime import datetime, timezone
        data = {
            "LeaveId": leave_id,
            "authorizedID": self.registration_number,
            "x": datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT"),
        }
        headers = {
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "X-Requested-With": "XMLHttpRequest",
            "Referer": "https://vtop.vitap.ac.in/vtop/hostel/StudentGeneralOuting",
            "Origin": "https://vtop.vitap.ac.in",
        }
        data["_csrf"] = self.post_login_csrf or self.csrf_token
        resp = await self.client.post("/vtop/hostel/deleteGeneralOutingInfo", data=data, headers=headers)
        return self._parse_outing_response(resp.text)

    async def delete_weekend_outing(self, booking_id: str) -> str:
        from datetime import datetime, timezone
        data = {
            "BookingId": booking_id,
            "authorizedID": self.registration_number,
            "x": datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT"),
        }
        headers = {
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "X-Requested-With": "XMLHttpRequest",
            "Referer": "https://vtop.vitap.ac.in/vtop/hostel/StudentWeekendOuting",
            "Origin": "https://vtop.vitap.ac.in",
        }
        data["_csrf"] = self.post_login_csrf or self.csrf_token
        resp = await self.client.post("/vtop/hostel/deleteBookingInfo", data=data, headers=headers)
        return self._parse_outing_response(resp.text)

    async def get_weekend_outing_status(self) -> list:
        """Fetch weekend outings (distinct from general outings)."""
        try:
            url = "/vtop/hostel/StudentWeekendOuting"
            data = {
                "verifyMenu": "true",
                "authorizedID": self.registration_number,
                "_csrf": self.post_login_csrf or self.csrf_token,
                "nocache": str(int(time.time() * 1000)),
            }
            resp = await self.client.post(url, data=data, headers=HEADERS)
            self._check_session_expired(resp)
            fresh_csrf = _find_csrf(resp.text)
            if fresh_csrf:
                self.post_login_csrf = fresh_csrf
            return self._parse_weekend_outing_table(resp.text)
        except Exception as e:
            raise Exception(f"Weekend outing error: {e}")

    def _parse_weekend_outing_table(self, html: str) -> list:
        """Parse weekend outing table."""
        soup = BeautifulSoup(html, "lxml")
        data = []
        table = soup.find("table", id="BookingRequests") or soup.find("table", class_="table-bordered") or soup.find("table")
        if not table:
            return data
            
        for row in table.find_all("tr")[1:]:  # skip header
            cols = row.find_all("td")
            if len(cols) >= 11:
                texts = [c.get_text(strip=True) for c in cols]
                row_html = str(row)
                
                # Check column structure:
                # Full weekend format (13 or 14 cols):
                # 0: S.No, 1: RegNo, 2: Block, 3: Room, 4: Place, 5: Purpose, 6: Time, 7: Contact, 8: ParentContact, 9: Date, 10: BookingId, 11: Action, 12: Status, (13: Download)
                # Shorter format (11 cols):
                # 0: S.No, 1: RegNo, 2: Block, 3: Room, 4: Place, 5: Purpose, 6: Time, 7: Date, 8: Action, 9: Status, 10: Download
                is_full_weekend = len(cols) >= 13
                
                if is_full_weekend:
                    place_val = texts[4]
                    purpose_val = texts[5]
                    time_val = texts[6]
                    date_val = texts[9]
                    booking_id_col = texts[10]
                    status_val = texts[12] if len(texts) > 12 else texts[-1]
                else:
                    place_val = texts[4] if len(texts) > 4 else ""
                    purpose_val = texts[5] if len(texts) > 5 else ""
                    time_val = texts[6] if len(texts) > 6 else ""
                    date_val = texts[7] if len(texts) > 7 else ""
                    booking_id_col = ""
                    status_val = texts[9] if len(texts) > 9 else texts[-1]
                
                booking_id = booking_id_col
                if not booking_id:
                    a_tag = row.find("a", attrs={"data-leave-url": True})
                    if a_tag and a_tag.get("data-leave-url"):
                        booking_id = a_tag["data-leave-url"].split("/")[-1].strip()
                if not booking_id:
                    m1 = re.search(r"deleteWeekendOuting\('([^']+)'\)", row_html) or re.search(r"deleteBookingInfo\('([^']+)'\)", row_html)
                    if m1:
                        booking_id = m1.group(1)
                if not booking_id:
                    m2 = re.search(r"downloadOutingForm/([^/\"'\?]+)", row_html)
                    if m2:
                        booking_id = m2.group(1)
                if not booking_id:
                    m3 = re.search(r"\b(W\d{8,14})\b", row_html)
                    if m3:
                        booking_id = m3.group(1)
                        
                data.append({
                    "id": booking_id or texts[0],
                    "bookingId": booking_id,
                    "type": "Weekend",
                    "place": place_val,
                    "purpose": purpose_val,
                    "out_date": f"{date_val} ({time_val})" if time_val else date_val,
                    "in_date": date_val,
                    "status": status_val,
                })
        return data


    async def get_payment_receipt_details(self, receipt_id: str) -> dict:
        """Fetch full receipt HTML and parse it."""
        try:
            data = {
                "verifyMenu": "true",
                "authorizedID": self.registration_number,
                "receitNo": receipt_id,
                "applno": receipt_id,
                "registerNumber": self.registration_number,
                "_csrf": self.post_login_csrf,
            }
            custom_headers = HEADERS.copy()
            custom_headers["X-Requested-With"] = "XMLHttpRequest"
            
            resp = await self.client.post("/vtop/finance/dupReceiptNewP2P", data=data, headers=custom_headers)
            
            return self._parse_print_payment_receipt(resp.text)
        except Exception as e:
            print(f"Payment receipt error: {e}")
            return {"error": str(e)}

    def _parse_print_payment_receipt(self, html: str) -> dict:
        from bs4 import BeautifulSoup
        soup = BeautifulSoup(html, "html.parser")
        details = {}
        try:
            receipt_details = soup.find("table", class_="table noborder")
            if not receipt_details:
                return {"error": "Receipt details table not found in HTML", "html": html}
            rows = receipt_details.find_all("tr")
            for row in rows:
                headers = row.find_all("th")
                cols = row.find_all("td")
                if len(headers) > 1 and len(cols) > 1:
                    if "Receipt Number" in headers[0].text.strip():
                        details["receipt_number"] = cols[0].text.strip()
                        details["name"] = cols[1].text.strip()
                    if "Receipt Date" in headers[0].text.strip():
                        details["receipt_date"] = cols[0].text.strip()
                        details["application_number/register_number"] = cols[1].text.strip()
                    if "Payment Year" in headers[0].text.strip():
                        details["payment_year"] = cols[0].text.strip()
                        details["campus"] = cols[1].text.strip()
                    if "Program Name" in headers[0].text.strip():
                        details["program_name"] = cols[0].text.strip()

            details["fee"] = []
            tables = soup.find_all("table", class_="table")
            if len(tables) > 1:
                hostel_fees_table = tables[1]
                rows = hostel_fees_table.find_all("tr")[1:]
                for row in rows:
                    cols = row.find_all("td")
                    if len(cols) == 4:
                        details["fee"].append({
                            "serial_number": cols[0].text.strip(),
                            "invoice_number": cols[1].text.strip(),
                            "description": cols[2].text.strip(),
                            "amount": cols[3].text.strip(),
                        })

            grand_total_div = soup.find("div", class_="text text-primary text-right")
            if grand_total_div and ":" in grand_total_div.text:
                details["grand_total"] = grand_total_div.text.strip().split(":")[1].strip()
            
            amount_in_words_div = soup.find(lambda tag: tag.name == "div" and tag.get("class") == ["text"] and tag.text and tag.text.strip().startswith("(Rupees"))
            if amount_in_words_div:
                details["amount_in_words"] = amount_in_words_div.text.strip()

            details["payment_details"] = []
            if len(tables) > 2:
                payment_table = tables[2]
                rows = payment_table.find_all("tr")[1:]
                for row in rows:
                    cols = row.find_all("td")
                    if len(cols) == 4:
                        details["payment_details"].append({
                            "payment_mode": cols[0].text.strip(),
                            "bank_name": cols[1].text.strip(),
                            "dd_no_online_transaction_id": cols[2].text.strip(),
                            "amount": cols[3].text.strip(),
                        })
            return details
        except Exception as e:
            return {"error": f"Parse error: {e}"}


    async def close(self):
        """Close HTTP client."""
        try:
            await self.client.aclose()
        except Exception:
            pass

