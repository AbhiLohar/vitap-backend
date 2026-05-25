"""
VTOP HTTP-based scraper with automatic captcha solving.
Replaces Playwright browser automation with pure HTTP requests.
Inspired by vitap-vtop-client library.
"""
import base64
import io
import re
import asyncio
import httpx
from bs4 import BeautifulSoup
from PIL import Image, ImageFilter

# ── Constants ──────────────────────────────────────────────
VTOP_BASE = "https://vtop.vitap.ac.in"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Connection": "close",
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
    "curriculum":   "/vtop/academics/common/Curriculum",
    "faculty":      "/vtop/hrms/EmployeeSearchForStudent",
    "outing":       "/vtop/hostel/StudentGeneralOuting",
    "da":           "/vtop/examinations/doDigitalAssignment",
    "payments":     "/vtop/finance/listReceipts",
}

# Known semester IDs for VIT-AP (fallback when dropdown not found)
# Pattern: AP{start_year}{end_year_last_digit}{type}
# Types: 2=Fall, 4=Winter, 5=Summer-1, 6=Summer-2, 7=Summer
KNOWN_SEMESTERS = {
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
    Solve VTOP captcha using ddddocr.
    """
    try:
        import ddddocr
        if "," in b64_data:
            b64_data = b64_data.split(",")[1]
        img_bytes = base64.b64decode(b64_data)
        
        ocr = ddddocr.DdddOcr(show_ad=False)
        text = ocr.classification(img_bytes)
        
        # Clean up
        text = re.sub(r'[^A-Za-z0-9]', '', text)
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
    # Try common VTOP error containers first
    for sel in ["#errMsg", "#errorMsg", ".alert-danger", ".error-msg", "p.text-danger"]:
        el = soup.select_one(sel)
        if el and el.get_text(strip=True):
            err_text = el.get_text(strip=True)
            if "captcha" in err_text.lower():
                return "Invalid Captcha"
            return err_text
            
    # Check body text for known errors
    text = soup.get_text(separator=" ", strip=True)
    text_lower = text.lower()
    if "invalid captcha" in text_lower:
        return "Invalid Captcha"
    if "invalid" in text_lower and ("user" in text_lower or "password" in text_lower or "credential" in text_lower):
        return "Invalid Credentials"
    if "not available" in text_lower and "user" in text_lower:
        return "User Id Not Available"
        
    # Return a snippet of the page text so we can see what VTOP is complaining about
    return f"Unknown Error: {text[:100]}"


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
    
    async def login(self, username: str, password: str, max_retries: int = 10) -> str:
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
                
                captcha_b64 = _find_captcha_b64(resp.text)
                if not captcha_b64:
                    # Try dedicated endpoint if not on page
                    captcha_resp = await self.client.get("/vtop/get/new/captcha")
                    captcha_b64 = _find_captcha_b64(captcha_resp.text)
                
                if not captcha_b64:
                    print("Captcha not found, retrying...")
                    await asyncio.sleep(1)
                    continue
                
                # Solve captcha
                solved = _solve_captcha_image(captcha_b64)
                if not solved:
                    await asyncio.sleep(0.5)
                    continue
                print(f"Captcha solved: {solved}")
                
                # Submit login
                login_data = {
                    "_csrf": self.csrf_token,
                    "username": self.registration_number,
                    "password": password,
                    "captchaStr": solved,
                }
                resp = await self.client.post(ROUTES["login"], data=login_data)
                
                final_url = str(resp.url)
                text_lower = resp.text.lower()
                
                # Detect OTP requirement first
                if "otp" in text_lower and ("sent" in text_lower or "mail" in text_lower or "enter" in text_lower):
                    print("OTP required detected in page text")
                    self._otp_required = True
                    current_csrf = _find_csrf(resp.text)
                    if current_csrf:
                        self.csrf_token = current_csrf
                    return "otp_required"
                    
                if "otp" in final_url.lower() or "twofactor" in final_url.lower():
                    print("OTP required detected in URL")
                    self._otp_required = True
                    return "otp_required"
                
                if ROUTES["content"] in final_url or "/vtop/content" in final_url:
                    print("Login successful!")
                    # Update post-login CSRF
                    self.post_login_csrf = _find_csrf(resp.text)
                    if not self.post_login_csrf:
                        content_resp = await self.client.get(ROUTES["content"])
                        self.post_login_csrf = _find_csrf(content_resp.text)
                    
                    self.logged_in = True
                    return "success"
                
                elif ROUTES["login_error"] in final_url or "/vtop/login/error" in final_url:
                    error_msg = _find_login_error(resp.text)
                    print(f"Login error: {error_msg}")
                    
                    if "captcha" in error_msg.lower():
                        # Update CSRF from error page for next attempt
                        self.csrf_token = _find_csrf(resp.text)
                        await asyncio.sleep(0.5)
                        continue
                    else:
                        raise Exception(f"Login failed: {error_msg}")
                
                else:
                    print(f"Unexpected page: {final_url}")
                    # Update CSRF and retry
                    self.csrf_token = _find_csrf(resp.text)
                    await asyncio.sleep(1)
                    continue
                    
            except httpx.RequestError as e:
                print(f"Network error: {e}")
                if attempt == max_retries - 1:
                    raise Exception(f"Connection failed after {max_retries} attempts")
                await asyncio.sleep(2)
            except Exception as e:
                if "Login failed" in str(e):
                    raise
                print(f"Unexpected error: {e}")
                if attempt == max_retries - 1:
                    raise
                await asyncio.sleep(1)
        
        raise Exception("Login failed after maximum captcha retries. Please check your credentials or try again.")
        
    async def submit_otp(self, otp: str) -> str:
        """Submit OTP for two-factor auth."""
        try:
            # Use the exact endpoint and parameters from VTOP's JS
            otp_data = {
                "otpCode": otp,
                "_csrf": self.csrf_token
            }
            
            # Primary VTOP security OTP endpoint
            try:
                resp = await self.client.post("/vtop/validateSecurityOtp", data=otp_data)
                
                # Check for JSON response (SUCCESS)
                if resp.headers.get("content-type", "").startswith("application/json"):
                    data = resp.json()
                    if data.get("status") == "SUCCESS":
                        # Fetch the redirectUrl to establish the session
                        redirect_url = data.get("redirectUrl", ROUTES["content"])
                        content_resp = await self.client.get(redirect_url)
                        self.post_login_csrf = _find_csrf(content_resp.text)
                        self.logged_in = True
                        return "success"
                    elif data.get("status") == "INVALID":
                        return "failed"
            except Exception as e:
                print(f"Primary OTP endpoint failed: {e}")

            # Fallback to older endpoints just in case
            for endpoint in ["/vtop/login/verify", "/vtop/verifyOTP", "/vtop/login"]:
                try:
                    resp = await self.client.post(endpoint, data=otp_data)
                    final_url = str(resp.url)
                    
                    if "/vtop/content" in final_url or "/vtop/home" in final_url:
                        content_resp = await self.client.get(ROUTES["content"])
                        self.post_login_csrf = _find_csrf(content_resp.text)
                        self.logged_in = True
                        return "success"
                except httpx.RequestError:
                    continue
            
            return "failed"
        except Exception as e:
            print(f"OTP submission error: {e}")
            return "failed"
    
    async def resend_otp(self) -> str:
        """Resend OTP to user's registered email — matches reference app's resendSecurityOtp endpoint."""
        try:
            otp_data = {
                "_csrf": self.csrf_token,
            }
            resp = await self.client.post("/vtop/resendSecurityOtp", data=otp_data)
            
            if resp.headers.get("content-type", "").startswith("application/json"):
                data = resp.json()
                status = data.get("status", "")
                if status == "SUCCESS":
                    print("OTP resent successfully")
                    return "success"
                else:
                    print(f"Resend OTP failed: {data}")
                    return "failed"
            
            # Non-JSON response
            if "success" in resp.text.lower() or "sent" in resp.text.lower():
                return "success"
            
            return "failed"
        except Exception as e:
            print(f"Resend OTP error: {e}")
            return "failed"
    
    async def _post_authenticated(self, url: str, data: dict) -> httpx.Response:
        """Make an authenticated POST request."""
        if not self.logged_in:
            raise Exception("Not logged in")
        data["_csrf"] = self.post_login_csrf
        resp = await self.client.post(url, data=data)
        return resp

    async def _get_authenticated(self, url: str) -> httpx.Response:
        """Make an authenticated GET request."""
        if not self.logged_in:
            raise Exception("Not logged in")
        resp = await self.client.get(url)
        return resp

    async def _post_menu(self, url: str) -> httpx.Response:
        """Initialize a VTOP page with verifyMenu — required for VTOP to load dropdowns."""
        # Optimization: Only initialize if not already done in this session
        if url in self._initialized_pages:
            return await self.client.get(url)
            
        import time
        data = {
            "verifyMenu": "true",
            "authorizedID": self.registration_number,
            "_csrf": self.post_login_csrf,
            "nocache": str(int(round(time.time() * 1000))),
        }
        resp = await self.client.post(url, data=data, headers=HEADERS)
        if resp.status_code == 200:
            self._initialized_pages.add(url)
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
    
    async def get_attendance(self, semester_id: str = None) -> list:
        """Fetch attendance data."""
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
            print(f"Attendance error: {e}")
            return []
    
    def _parse_attendance_table(self, html: str) -> list:
        """Parse attendance HTML table - matches vitap_student_app Rust parser logic.
        
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
        
        return data
    
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
            print(f"Timetable error: {e}")
            return []
    
    def _parse_timetable(self, html: str) -> list:
        """Parse VTOP timetable grid and merge with course details."""
        soup = BeautifulSoup(html, "lxml")
        data = []
        
        # 1. Parse Course Details Table (for Faculty and Full Names)
        course_map = {} # Key: (CourseCode, Type) -> {faculty, full_name}
        
        # The first table usually contains course details
        details_table = soup.find("table")
        if details_table:
            rows = details_table.find_all("tr")
            for row in rows:
                cells = row.find_all("td")
                if len(cells) >= 10:
                    course_text = cells[2].get_text(separator=" ", strip=True)
                    # "CSE3008 - Introduction to Machine Learning ( Embedded Theory )"
                    parts = course_text.split("-")
                    code = parts[0].strip() if parts else ""
                    
                    type_str = "LECTURE"
                    if "LAB" in course_text.upper() or "PRACTICAL" in course_text.upper():
                        type_str = "LAB"
                    
                    faculty = cells[8].get_text(separator=" ", strip=True).split("-")[0].strip()
                    full_name = parts[1].split("(")[0].strip() if len(parts) > 1 else code
                    
                    course_map[(code, type_str)] = {
                        "faculty": faculty,
                        "full_name": full_name
                    }

        # 2. Parse Timetable Grid
        day_map = {
            "MON": "Monday", "TUE": "Tuesday", "WED": "Wednesday",
            "THU": "Thursday", "FRI": "Friday", "SAT": "Saturday", "SUN": "Sunday"
        }
        
        table = soup.find("table", {"id": "timeTableStyle"})
        if not table:
            return []

        rows = table.find_all("tr")
        
        # Extract all time columns
        theory_start = []
        theory_end = []
        lab_start = []
        lab_end = []
        
        last_type = None
        for row in rows:
            row_text = row.get_text(strip=True).upper()
            cells = row.find_all(["th", "td"])
            times = [c.get_text(strip=True) for c in cells if ":" in c.get_text()]
            
            if "THEORY" in row_text:
                last_type = "THEORY"
                if "START" in row_text: theory_start = times
            elif "LAB" in row_text:
                last_type = "LAB"
                if "START" in row_text: lab_start = times
            elif "END" in row_text:
                if last_type == "THEORY": theory_end = times
                elif last_type == "LAB": lab_end = times
        
        current_day = None
        for row in rows:
            cells = row.find_all(["th", "td"])
            if not cells: continue
            
            row_text = row.get_text(separator=" ", strip=True).upper()
            for abbr, full in day_map.items():
                if f" {abbr} " in f" {row_text} " or row_text.startswith(abbr):
                    current_day = full
                    break
            
            if not current_day: continue
            
            is_lab = "LAB" in row_text
            start_times = lab_start if is_lab else theory_start
            end_times = lab_end if is_lab else theory_end
            type_tag = "LAB" if is_lab else "LECTURE"
            
            # Identify columns
            start_col = 2 if any(abbr in cells[0].get_text().upper() for abbr in day_map) else 1
            
            for idx, cell in enumerate(cells[start_col:]):
                cell_text = cell.get_text(separator="\n", strip=True)
                if len(cell_text) < 5 or cell_text == "-" or "LUNCH" in cell_text.upper():
                    continue
                
                parts = cell_text.split("-")
                slot = parts[0] if parts else ""
                code = parts[1] if len(parts) > 1 else ""
                room = parts[3] if len(parts) > 3 else ""
                
                s_time = start_times[idx] if idx < len(start_times) else ""
                e_time = end_times[idx] if idx < len(end_times) else ""
                
                # Enrich with faculty and full name
                info = course_map.get((code, type_tag), {})
                
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
        
        return data
    
    async def get_marks(self, semester_id: str = None) -> list:
        """Fetch marks data."""
        try:
            sem_id = semester_id or "AP2025262"
            
            # Initialize page first
            await self._post_menu(ROUTES["marks"])
            
            resp = await self._post_authenticated(
                ROUTES["view_marks"],
                {
                    "semesterSubId": sem_id,
                    "authorizedID": self.registration_number,
                }
            )
            
            return self._parse_marks(resp.text)
        except Exception as e:
            print(f"Marks error: {e}")
            return []
    
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
        
        bmarks = False
        current_course = {
            "serial_number": "", "course_code": "", "subject": "",
            "type": "", "faculty": "", "slot": "", "details": []
        }
        
        for row in content_rows:
            cells = row.find_all("td", recursive=False)
            
            if bmarks:
                # This row contains marks details as nested sub-rows
                detail_rows = row.find_all("tr", class_="tableContent-level1")
                details = []
                for drow in detail_rows:
                    dcells = drow.find_all("td")
                    dtexts = [clean(c.get_text()) for c in dcells]
                    
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
                
                courses.append(current_course.copy())
                current_course = {
                    "serial_number": "", "course_code": "", "subject": "",
                    "type": "", "faculty": "", "slot": "", "details": []
                }
            else:
                # This is a course info row
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
            
            bmarks = not bmarks
        
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
            print(f"Grades error: {e}")
            return []
    
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
            print(f"Exam schedule error: {e}")
            return []
    
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
    
    async def get_profile(self) -> dict:
        """Fetch student profile with caching - matches vitap_student_app Rust parser logic."""
        if "profile" in self._cache:
            return self._cache["profile"]
            
        try:
            resp = await self._post_authenticated(
                ROUTES["profile"],
                {"authorizedID": self.registration_number}
            )
            
            soup = BeautifulSoup(resp.text, "lxml")
            
            def extract_table_value(label_text):
                """Search for a table row whose first cell contains the label and return second cell value."""
                for row in soup.find_all("tr"):
                    tds = row.find_all("td")
                    if len(tds) >= 2:
                        label = tds[0].get_text(strip=True).upper()
                        if label_text.upper() in label:
                            return tds[1].get_text(strip=True)
                return ""
            
            # Extract base64 profile picture
            base64_pfp = ""
            img = soup.find("img", class_=lambda c: c and "border" in c if c else False)
            if img:
                src = img.get("src", "")
                if "base64," in src:
                    base64_pfp = src.split("base64,", 1)[1]
            
            # Extract main profile fields
            profile = {
                "name": extract_table_value("STUDENT NAME"),
                "reg_no": self.registration_number,
                "application_number": extract_table_value("APPLICATION NUMBER"),
                "dob": extract_table_value("DATE OF BIRTH"),
                "gender": extract_table_value("GENDER"),
                "blood_group": extract_table_value("BLOOD GROUP"),
                "email": extract_table_value("EMAIL"),
                "program": extract_table_value("PROGRAMME"),
                "branch": extract_table_value("BRANCH"),
                "school": extract_table_value("SCHOOL"),
                "base64_pfp": base64_pfp,
            }
            
            # If name wasn't found with "STUDENT NAME", try just "NAME"
            if not profile["name"]:
                profile["name"] = extract_table_value("NAME")
            
            # Extract Mentor/Proctor details from the "PROCTOR INFORMATION" accordion section
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
            
            # Look for the proctor information section
            proctor_section = None
            for div in soup.find_all("div", class_="accordion-item"):
                if "PROCTOR" in div.get_text().upper():
                    proctor_section = div
                    break
            
            if proctor_section:
                def extract_mentor_value(label_text):
                    for row in proctor_section.find_all("tr"):
                        tds = row.find_all("td")
                        if len(tds) >= 2:
                            label = tds[0].get_text(strip=True).upper()
                            if label_text.upper() in label:
                                return tds[1].get_text(strip=True)
                    return ""
                
                mentor["faculty_id"] = extract_mentor_value("FACULTY ID")
                mentor["faculty_name"] = extract_mentor_value("FACULTY NAME")
                mentor["faculty_designation"] = extract_mentor_value("FACULTY DESIGNATION")
                mentor["school"] = extract_mentor_value("SCHOOL")
                mentor["cabin"] = extract_mentor_value("CABIN")
                mentor["faculty_department"] = extract_mentor_value("FACULTY DEPARTMENT")
                mentor["faculty_email"] = extract_mentor_value("FACULTY EMAIL")
                mentor["faculty_intercom"] = extract_mentor_value("FACULTY INTERCOM")
                mentor["faculty_mobile"] = extract_mentor_value("FACULTY MOBILE")
            
            profile["mentor"] = mentor["faculty_name"]
            profile["mentor_details"] = mentor
            
            self._cache["profile"] = profile
            return profile
        except Exception as e:
            print(f"Profile error: {e}")
            return {"name": "Student", "reg_no": self.registration_number}
    
    async def get_curriculum(self) -> dict:
        """Fetch curriculum with multiple fallbacks and caching."""
        if "curriculum" in self._cache:
            return self._cache["curriculum"]
            
        try:
            print(f"Fetching curriculum for {self.registration_number}")
            # 1. Try Curriculum Page
            resp = await self._post_authenticated(
                ROUTES["curriculum"],
                {"authorizedID": self.registration_number}
            )
            data = self._parse_curriculum(resp.text)
            
            print(f"Initial parse: {data['summary']}")
            
            # 2. If nothing found, try Grade History page for summary
            if data["summary"]["earned"] == "0" and not data["distribution"]:
                print("Curriculum page empty, trying Grade History fallback...")
                resp = await self._post_authenticated(
                    ROUTES["grade_hist"],
                    {"authorizedID": self.registration_number}
                )
                gh_data = self._parse_curriculum(resp.text)
                print(f"Grade History parse: {gh_data['summary']}")
                data["summary"] = gh_data["summary"]
                if not data["distribution"]:
                    data["distribution"] = gh_data["distribution"]

            # 3. If still nothing, calculate from Grade History table
            if data["summary"]["earned"] == "0":
                print("Summary still 0, calculating from grades...")
                grades = await self.get_grades()
                earned = 0.0
                for g in grades:
                    try:
                        # Only count if grade is passed (not F, N, W, etc.)
                        grade = g.get("grade", "").upper()
                        if grade and grade not in ["F", "N", "W", "E", "FAIL"]:
                            earned += float(g.get("credits", 0))
                    except: continue
                data["summary"]["earned"] = str(earned)
                # We can't easily get buckets from grades without a mapping
                
            # Inject detailed courses into distribution using grades
            try:
                grades = await self.get_grades()
                
                # Map course types to bucket names
                def match_category(c_type, cat_name):
                    c = c_type.upper()
                    n = cat_name.lower()
                    if c == "PC" and "programme core" in n: return True
                    if c == "PE" and "programme elective" in n: return True
                    if c == "UC" and "university core" in n: return True
                    if c == "UE" and "university elective" in n: return True
                    if c == "NC" and "non credit" in n: return True
                    if c == "BRIDGE" and "bridge" in n: return True
                    if c == "ECA" and ("extra" in n or "co-curric" in n): return True
                    return False

                for dist in data["distribution"]:
                    dist["courses"] = []
                    cat_name = dist["category"]
                    
                    for g in grades:
                        # Only add passed/completed courses
                        grade = g.get("grade", "").upper()
                        if grade in ["F", "N", "W", "FAIL", ""]: continue
                        
                        if match_category(g.get("type", ""), cat_name):
                            dist["courses"].append({
                                "course_code": g.get("course_code", ""),
                                "subject": g.get("subject", ""),
                                "credits": g.get("credits", ""),
                                "grade": grade
                            })
            except Exception as ex:
                print(f"Error enriching curriculum courses: {ex}")

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
        
        tables = soup.find_all("table")
        for table in tables:
            rows = table.find_all("tr")
            if not rows: continue
            
            # Get header texts from first row
            header_cells = rows[0].find_all(["th", "td"])
            header_texts = [th.get_text(strip=True).lower() for th in header_cells]
            header_str = " ".join(header_texts)
            
            # Detect distribution table by looking for keywords in headers
            is_dist_table = any(k in header_str for k in [
                "category", "curriculum", "bucket", "component", 
                "required", "earned", "completed", "credit type"
            ])
            
            if is_dist_table:
                # Find column indices dynamically
                idx_cat = -1
                idx_req = -1
                idx_earned = -1
                idx_left = -1
                
                for i, h in enumerate(header_texts):
                    h_lower = h.lower()
                    if any(k in h_lower for k in ["category", "component", "bucket", "type", "credit type"]):
                        idx_cat = i
                    elif any(k in h_lower for k in ["required", "minimum", "curriculum", "total credit", "total"]) and "earned" not in h_lower:
                        idx_req = i
                    elif any(k in h_lower for k in ["earned", "completed", "done"]):
                        idx_earned = i
                    elif "left" in h_lower or "remaining" in h_lower or "pending" in h_lower:
                        idx_left = i
                
                # If no explicit category column, try to guess based on 'basket' or skip
                if idx_cat == -1:
                    for i, h in enumerate(header_texts):
                        if "basket" in h.lower() or "title" in h.lower():
                            idx_cat = i
                            break
                            
                # Strict check: skip if we still couldn't confidently find category and required columns
                if idx_cat == -1:
                    continue
                
                if idx_cat != -1:
                    total_earned = 0.0
                    total_required = 0.0
                    
                    for row in rows[1:]:
                        cols = row.find_all("td")
                        if len(cols) <= idx_cat:
                            continue
                        texts = [c.get_text(strip=True) for c in cols]
                        cat_name = texts[idx_cat] if idx_cat < len(texts) else ""
                        
                        # Skip header/footer/total rows
                        if not cat_name or any(s in cat_name.lower() for s in [
                            "total", "sl.", "serial", "s.no", "grand"
                        ]):
                            # But check if it's a summary/total row
                            if "total" in cat_name.lower():
                                for t in texts:
                                    nums = re.findall(r'\d+\.?\d*', t)
                                    if nums:
                                        val = float(nums[0])
                                        if val > 100:
                                            summary["total"] = str(val)
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
                                
                                # Check if left column exists
                                if idx_left != -1 and idx_left < len(texts):
                                    lv = re.findall(r'\d+\.?\d*', texts[idx_left])
                                    if lv:
                                        left_num = float(lv[0])
                                
                                distribution.append({
                                    "category": cat_name,
                                    "required": str(r_num),
                                    "earned": str(e_num),
                                    "left": str(left_num)
                                })
                                total_earned += e_num
                                total_required += r_num
                        except:
                            continue
                    
                    if total_earned > 0:
                        summary["earned"] = str(total_earned)
                    if total_required > 0:
                        summary["total"] = str(total_required)

            # Check for summary rows (Total Credits Earned, etc.) in ALL tables
            for row in rows:
                cols = row.find_all(["td", "th"])
                if len(cols) >= 2:
                    label = cols[0].get_text(strip=True).lower()
                    val_text = cols[-1].get_text(strip=True) 
                    
                    if "earned" in label or "completed" in label:
                        if "registered" not in label:
                            nums = re.findall(r'\d+\.?\d*', val_text)
                            if nums: 
                                summary["earned"] = nums[0]
                                print(f"Found Earned: {nums[0]} via label {label}")
                    elif "total" in label and any(k in label for k in ["required", "curriculum", "minimum", "credit"]):
                        nums = re.findall(r'\d+\.?\d*', val_text)
                        if nums: 
                            summary["total"] = nums[0]
                            print(f"Found Total: {nums[0]} via label {label}")

        # Final Summary Logic
        if summary["earned"] == "0" and distribution:
            summary["earned"] = str(sum(float(d["earned"]) for d in distribution))
            summary["total"] = str(sum(float(d["required"]) for d in distribution))
            
        try:
            e = float(summary["earned"])
            t = float(summary["total"])
            if t == 0: t = 160.0
            summary["total"] = str(t)
            summary["left"] = str(round(max(0.0, t - e), 2))
            print(f"Final calculation: Earned={e}, Total={t}, Left={summary['left']}")
        except Exception as ex: 
            print(f"Calc error: {ex}")
            pass
            
        return {"summary": summary, "distribution": distribution}

    async def get_faculty_details(self, search_term: str) -> list:
        """Search for faculty details."""
        try:
            # Initialize page first
            await self._post_menu(ROUTES["faculty"])
            
            resp = await self._post_authenticated(
                ROUTES["faculty"],
                {
                    "empId": search_term,
                    "authorizedID": self.registration_number,
                }
            )
            
            return self._parse_faculty_table(resp.text)
        except Exception as e:
            print(f"Faculty search error: {e}")
            return []

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
            print(f"DA error: {e}")
            return []

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
        """Fetch outing history and current status."""
        try:
            # Initialize page
            await self._post_menu(ROUTES["outing"])
            
            resp = await self._post_authenticated(
                ROUTES["outing"],
                {
                    "authorizedID": self.registration_number,
                    "verifyMenu": "true"
                }
            )
            
            return self._parse_outing_table(resp.text)
        except Exception as e:
            print(f"Outing error: {e}")
            return []

    def _parse_outing_table(self, html: str) -> list:
        """Parse outing table."""
        soup = BeautifulSoup(html, "lxml")
        data = []
        
        tables = soup.find_all("table")
        for table in tables:
            rows = table.find_all("tr")
            for row in rows:
                cols = row.find_all("td")
                if len(cols) >= 5:
                    texts = [c.get_text(strip=True) for c in cols]
                    if any(h in texts[0].lower() for h in ["sl", "sno"]):
                        continue
                    
                    data.append({
                        "id": texts[0],
                        "type": texts[1],
                        "place": texts[2],
                        "out_date": texts[3],
                        "in_date": texts[4],
                        "status": texts[5] if len(texts) > 5 else "Pending",
                    })
        return data

    async def get_payment_history(self) -> list:
        """Fetch payment receipts and history."""
        try:
            await self._post_menu(ROUTES["payments"])
            
            resp = await self._post_authenticated(
                ROUTES["payments"],
                {
                    "authorizedID": self.registration_number,
                }
            )
            
            return self._parse_payments_table(resp.text)
        except Exception as e:
            print(f"Payments error: {e}")
            return []

    def _parse_payments_table(self, html: str) -> list:
        """Parse payments table - matches vitap_student_app Rust parser logic.
        
        VTOP payment receipts table (table.table-bordered):
        Skip header row, then for each data row with >= 5 cells:
        cells[0]=receipt_number, [1]=date, [2]=amount, [3]=campus_code, [4]=button with onclick
        """
        soup = BeautifulSoup(html, "lxml")
        data = []
        
        # Find the main receipts table
        table = soup.find("table", class_="table-bordered")
        if not table:
            # Fallback: try any table
            table = soup.find("table")
        
        if not table:
            return data
        
        rows = table.find_all("tr")
        
        # Skip first row (header)
        for row in rows[1:]:
            cells = row.find_all("td")
            if len(cells) >= 5:
                def clean(cell):
                    return cell.get_text(strip=True)
                
                receipt_number = clean(cells[0])
                date = clean(cells[1])
                amount = clean(cells[2])
                campus_code = clean(cells[3])
                
                # Extract receipt_no from button onclick
                receipt_no = ""
                button = cells[4].find("button") if len(cells) > 4 else None
                if button:
                    onclick = button.get("onclick", "")
                    # Example: javascript:doDuplicateReceipt('27640/26/AMR');
                    prefix = "doDuplicateReceipt('"
                    suffix = "')"
                    if prefix in onclick:
                        start = onclick.index(prefix) + len(prefix)
                        rest = onclick[start:]
                        if suffix in rest:
                            end = rest.index(suffix)
                            receipt_no = rest[:end]
                
                data.append({
                    "receipt_no": receipt_number,
                    "date": date,
                    "amount": amount,
                    "payment_mode": campus_code,
                    "status": "Paid",
                    "receipt_id": receipt_no,
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
            print(f"Courses error: {e}")
            return []


    async def get_general_outing_pdf(self, leave_id: str) -> bytes:
        """Download General Outing PDF pass."""
        if not self.logged_in: raise Exception("Not logged in")
        import urllib.parse
        from datetime import datetime, timezone
        x_time = urllib.parse.quote(datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT"))
        url = f"/vtop/hostel/downloadLeavePass/{leave_id}?authorizedID={self.registration_number}&_csrf={self.post_login_csrf}&x={x_time}"
        resp = await self._get_authenticated(url)
        if resp.status_code == 200 and resp.content:
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
            return resp.content
        raise Exception("Failed to download PDF")

    async def _fetch_outing_form_hidden_fields(self, is_weekend=False) -> dict:
        """Helper to fetch pre-filled student details from the outing application page."""
        url = ROUTES["outing"] if not is_weekend else "/vtop/hostel/StudentWeekendOuting"
        resp = await self._post_menu(url)
        soup = BeautifulSoup(resp.text, "lxml")
        fields = {}
        for inp in soup.find_all("input"):
            id_val = inp.get("id") or inp.get("name")
            if id_val:
                fields[id_val] = inp.get("value", "")
        if not fields.get("applicationNo"):
            raise Exception("Could not parse outing form fields")
        return fields

    async def apply_general_outing(self, out_place: str, purpose: str, out_date: str, out_time: str, in_date: str, in_time: str) -> str:
        """Submit a General Outing."""
        try:
            fields = await self._fetch_outing_form_hidden_fields(is_weekend=False)
            
            # Times come as HH:MM
            out_parts = out_time.split(":")
            in_parts = in_time.split(":")
            
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
                "outDate": out_date,
                "outTimeHr": out_parts[0],
                "outTimeMin": out_parts[1],
                "inDate": in_date,
                "inTimeHr": in_parts[0],
                "inTimeMin": in_parts[1],
                "parentContactNumber": fields.get("parentContactNumber", ""),
            }
            resp = await self._post_authenticated("/vtop/hostel/saveGeneralOutingForm", data)
            
            # Check response for success message
            text_lower = resp.text.lower()
            if "success" in text_lower or "submitted" in text_lower:
                return "Successfully applied for General Outing"
            
            # Extract error message if any
            soup = BeautifulSoup(resp.text, "lxml")
            msg = soup.get_text(strip=True)[:100]
            return f"Failed: {msg}"
        except Exception as e:
            raise Exception(f"Failed to apply for general outing: {e}")

    async def apply_weekend_outing(self, out_place: str, purpose: str, out_date: str, out_time: str, contact_number: str) -> str:
        """Submit a Weekend Outing."""
        try:
            fields = await self._fetch_outing_form_hidden_fields(is_weekend=True)
            
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
                "outingDate": out_date,
                "outTime": out_time,
                "contactNumber": contact_number,
                "parentContactNumber": fields.get("parentContactNumber", ""),
            }
            resp = await self._post_authenticated("/vtop/hostel/saveOutingForm", data)
            
            text_lower = resp.text.lower()
            if "success" in text_lower or "booked" in text_lower:
                return "Successfully applied for Weekend Outing"
                
            soup = BeautifulSoup(resp.text, "lxml")
            msg = soup.get_text(strip=True)[:100]
            return f"Failed: {msg}"
        except Exception as e:
            raise Exception(f"Failed to apply for weekend outing: {e}")

    async def delete_general_outing(self, leave_id: str) -> str:
        data = {"LeaveId": leave_id, "authorizedID": self.registration_number}
        resp = await self._post_authenticated("/vtop/hostel/deleteGeneralOutingInfo", data)
        return "Deleted successfully" if "success" in resp.text.lower() else "Failed to delete"

    async def delete_weekend_outing(self, booking_id: str) -> str:
        data = {"BookingId": booking_id, "authorizedID": self.registration_number}
        resp = await self._post_authenticated("/vtop/hostel/deleteBookingInfo", data)
        return "Deleted successfully" if "success" in resp.text.lower() else "Failed to delete"

    async def get_weekend_outing_status(self) -> list:
        """Fetch weekend outings (distinct from general outings)."""
        try:
            url = "/vtop/hostel/StudentWeekendOuting"
            await self._post_menu(url)
            resp = await self._post_authenticated(url, {"authorizedID": self.registration_number, "verifyMenu": "true"})
            
            soup = BeautifulSoup(resp.text, "lxml")
            data = []
            tables = soup.find_all("table")
            for table in tables:
                for row in table.find_all("tr"):
                    cols = row.find_all("td")
                    if len(cols) >= 5:
                        texts = [c.get_text(strip=True) for c in cols]
                        if "sno" in texts[0].lower() or "sl" in texts[0].lower(): continue
                        data.append({
                            "id": texts[0],
                            "type": "Weekend",
                            "place": texts[2] if len(texts) > 2 else "",
                            "out_date": texts[3] if len(texts) > 3 else "",
                            "in_date": texts[4] if len(texts) > 4 else "",
                            "status": texts[5] if len(texts) > 5 else "Pending",
                        })
            return data
        except Exception as e:
            print(f"Weekend outing error: {e}")
            return []


    async def close(self):
        """Close HTTP client."""
        try:
            await self.client.aclose()
        except Exception:
            pass
