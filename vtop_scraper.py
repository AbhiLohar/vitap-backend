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
        """Parse attendance HTML table."""
        soup = BeautifulSoup(html, "lxml")
        data = []
        
        tables = soup.find_all("table")
        for table in tables:
            rows = table.find_all("tr")
            for row in rows:
                cols = row.find_all("td")
                if len(cols) >= 6:
                    texts = [c.get_text(strip=True) for c in cols]
                    # Skip header-like rows
                    if any(h in texts[0].lower() for h in ["sl.no", "serial", "sno"]):
                        continue
                    if any(h in texts[1].lower() for h in ["course", "subject", "title"]):
                        continue
                    
                    # Find the percentage column
                    attendance_pct = ""
                    for t in texts:
                        if "%" in t:
                            attendance_pct = t
                            break
                    
                    # Standard VTOP attendance table columns:
                    # Sl.No | Course Code | Course Title | Type | Category | FAT Type | Attended | Total | Percentage
                    if len(cols) >= 8:
                        subject = texts[2] if len(texts) > 2 else ""
                        is_lab = "lab" in subject.lower() or "practical" in subject.lower()
                        
                        data.append({
                            "course_code": texts[1] if len(texts) > 1 else "",
                            "subject": subject,
                            "type": "Lab" if is_lab else "Theory",
                            "present": texts[6] if len(texts) > 6 else "",
                            "total_classes": texts[7] if len(texts) > 7 else "",
                            "attendance": attendance_pct or (texts[8] if len(texts) > 8 else "0%"),
                        })
                    elif len(cols) >= 6:
                        subject = texts[1] if len(texts) > 1 else ""
                        is_lab = "lab" in subject.lower() or "practical" in subject.lower()
                        
                        data.append({
                            "course_code": texts[0],
                            "subject": subject,
                            "type": "Lab" if is_lab else "Theory",
                            "present": texts[4],
                            "total_classes": texts[5],
                            "attendance": attendance_pct or texts[3],
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
        """Parse marks table and group by subject."""
        soup = BeautifulSoup(html, "lxml")
        grouped_data = {} # Key: (course_code, type)
        
        last_course_code = ""
        last_subject = ""
        last_faculty = ""
        
        tables = soup.find_all("table")
        for table in tables:
            rows = table.find_all("tr")
            for row in rows:
                cols = row.find_all(["td", "th"])
                texts = [c.get_text(separator=" ", strip=True) for c in cols]
                
                if not texts or len(texts) < 3:
                    continue
                    
                # Ignore header rows
                if any(h in texts[0].lower() for h in ["sl", "serial", "sno"]):
                    continue
                
                # Outer course row detection: [1, CSE1001, Intro to CS, ...]
                if len(texts[1]) >= 4 and texts[1][:3].isalpha() and any(char.isdigit() for char in texts[1]):
                    last_course_code = texts[1]
                    last_subject = texts[2] if len(texts) > 2 else ""
                    
                    if len(texts) >= 11:
                        last_faculty = texts[10].split("-")[0].strip().upper()
                    elif len(texts) >= 9:
                        last_faculty = texts[-1].split("-")[0].strip().upper()
                    continue

                # Inner marks row detection
                exam_types = ["CAT", "FAT", "QUIZ", "ASSESSMENT", "MID", "TERM", "LAB", "CHALLENGE", "PROJECT", "SEMINAR"]
                if len(texts) >= 5 and any(ext in texts[1].upper() for ext in exam_types):
                    is_lab = "lab" in last_subject.lower() or "practical" in last_subject.lower() or "lab" in texts[1].lower()
                    m_type = "Lab" if is_lab else "Theory"
                    
                    key = (last_course_code, m_type)
                    if key not in grouped_data:
                        grouped_data[key] = {
                            "course_code": last_course_code,
                            "subject": last_subject,
                            "faculty": last_faculty or "FACULTY NAME",
                            "type": m_type,
                            "total_marks": 0.0,
                            "max_marks": 0.0,
                            "components": []
                        }
                    
                    try:
                        obtained = float(texts[3]) if texts[3] and texts[3] != "-" else 0.0
                        total = float(texts[2]) if texts[2] and texts[2] != "-" else 0.0
                        
                        grouped_data[key]["total_marks"] += obtained
                        grouped_data[key]["max_marks"] += total
                        grouped_data[key]["components"].append({
                            "name": texts[1],
                            "marks": texts[3],
                            "max": texts[2],
                            "status": texts[5] if len(texts) > 5 else ""
                        })
                    except (ValueError, TypeError):
                        pass

        # Convert to list and format numbers
        result = []
        for item in grouped_data.values():
            item["total_marks"] = round(item["total_marks"], 2)
            item["max_marks"] = round(item["max_marks"], 2)
            result.append(item)
            
        return result
    
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
    
    def _parse_grades(self, html: str) -> list:
        """Parse grades table."""
        soup = BeautifulSoup(html, "lxml")
        data = []
        
        tables = soup.find_all("table")
        for table in tables:
            rows = table.find_all("tr")
            for row in rows:
                cols = row.find_all("td")
                if len(cols) >= 4:
                    texts = [c.get_text(strip=True) for c in cols]
                    if any(h in texts[0].lower() for h in ["sl", "serial", "sno", "course code"]):
                        continue
                    
                    data.append({
                        "course_code": texts[0] if len(texts) > 0 else "",
                        "subject": texts[1] if len(texts) > 1 else "",
                        "type": texts[2] if len(texts) > 2 else "",
                        "credits": texts[3] if len(texts) > 3 else "",
                        "grade": texts[4] if len(texts) > 4 else "",
                    })
        
        return data
    
    async def get_cgpa(self) -> dict:
        """Calculate CGPA from grade history."""
        grades = await self.get_grades()
        total_credits = 0.0
        earned_points = 0.0
        
        grade_points = {
            "S": 10, "A": 9, "B": 8, "C": 7, "D": 6, "E": 5, "F": 0, "N": 0
        }
        
        for g in grades:
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
                
        cgpa = round(earned_points / total_credits, 2) if total_credits > 0 else 0.0
        return {
            "cgpa": cgpa,
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

    async def get_exam_schedule(self, semester_id: str = None, exam_type: str = "FAT") -> list:
        """Fetch exam schedule for a specific type."""
        try:
            sem_id = semester_id or "AP2025262"
            
            # Initialize page with verifyMenu
            await self._post_menu(ROUTES["exam_sched"])
            
            # Fetch schedule
            resp = await self._post_authenticated(
                ROUTES["view_exam"],
                {
                    "semesterSubId": sem_id,
                    "examType": exam_type,
                    "authorizedID": self.registration_number,
                }
            )
            
            return self._parse_exam_schedule(resp.text)
        except Exception as e:
            print(f"Exam schedule error: {e}")
            return []
    
    def _parse_exam_schedule(self, html: str) -> list:
        """Parse exam schedule table."""
        soup = BeautifulSoup(html, "lxml")
        data = []
        
        tables = soup.find_all("table")
        for table in tables:
            rows = table.find_all("tr")
            if not rows: continue
            
            header = rows[0]
            th_cells = [th.get_text(strip=True).lower() for th in header.find_all(["th", "td"])]
            
            col_map = {
                "course_code": -1, "subject": -1, "date": -1, "session": -1, "venue": -1, "seat": -1, "time": -1, "type": -1
            }
            
            for i, text in enumerate(th_cells):
                if "course code" in text: col_map["course_code"] = i
                elif "course title" in text or "subject" in text: col_map["subject"] = i
                elif "date" in text and "exam" in text: col_map["date"] = i
                elif "date" in text: col_map["date"] = i
                elif "session" in text: col_map["session"] = i
                elif "venue" in text or "room" in text: col_map["venue"] = i
                elif "seat" in text: col_map["seat"] = i
                elif "time" in text and "exam" in text: col_map["time"] = i
                elif "type" in text: col_map["type"] = i
                
            if col_map["course_code"] == -1: continue
            
            for row in rows[1:]:
                cols = [c.get_text(strip=True) for c in row.find_all("td")]
                if len(cols) <= col_map["course_code"]: continue
                
                venue_val = cols[col_map["venue"]] if col_map["venue"] != -1 and col_map["venue"] < len(cols) else "-"
                seat_val = cols[col_map["seat"]] if col_map["seat"] != -1 and col_map["seat"] < len(cols) else "-"
                
                if col_map["seat"] == -1 and "-" in venue_val:
                    parts = venue_val.split("-")
                    if len(parts) >= 2:
                        seat_val = parts[-1]
                        venue_val = "-".join(parts[:-1])
                        
                data.append({
                    "course_code": cols[col_map["course_code"]] if col_map["course_code"] != -1 else "",
                    "subject": cols[col_map["subject"]] if col_map["subject"] != -1 else "",
                    "type": cols[col_map["type"]] if col_map["type"] != -1 else "",
                    "date": cols[col_map["date"]] if col_map["date"] != -1 else "-",
                    "session": cols[col_map["session"]] if col_map["session"] != -1 else "-",
                    "venue": venue_val,
                    "seat_no": seat_val,
                    "exam_time": cols[col_map["time"]] if col_map["time"] != -1 else "-",
                })
        return data
    
    async def get_profile(self) -> dict:
        """Fetch student profile with caching."""
        if "profile" in self._cache:
            return self._cache["profile"]
            
        try:
            resp = await self._post_authenticated(
                ROUTES["profile"],
                {"authorizedID": self.registration_number}
            )
            
            soup = BeautifulSoup(resp.text, "lxml")
            profile = {
                "name": "",
                "reg_no": self.registration_number,
                "program": "",
                "branch": "",
                "school": "",
                "email": "",
                "mentor": "",
            }
            
            # Look for profile data in table rows
            for row in soup.find_all("tr"):
                cols = row.find_all("td")
                if len(cols) >= 2:
                    label = cols[0].get_text(strip=True).lower()
                    value = cols[1].get_text(strip=True)
                    
                    if "name" in label and "student" in label:
                        profile["name"] = value
                    elif "name" in label and not profile["name"]:
                        profile["name"] = value
                    elif "register" in label or "reg" in label:
                        profile["reg_no"] = value
                    elif "program" in label:
                        profile["program"] = value
                    elif "branch" in label:
                        profile["branch"] = value
                    elif "school" in label:
                        profile["school"] = value
                    elif "email" in label and "alternate" not in label:
                        profile["email"] = value
                    elif any(k in label for k in ["mentor", "proctor", "faculty advisor", "faculty counselor"]):
                        profile["mentor"] = value
            
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
                    elif any(k in h_lower for k in ["required", "minimum", "curriculum"]) and "earned" not in h_lower:
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
        """Parse faculty search results."""
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
                        "name": texts[1],
                        "school": texts[2],
                        "designation": texts[3],
                        "room": texts[4],
                        "email": texts[5] if len(texts) > 5 else "",
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
        """Parse payments table."""
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
                        "receipt_no": texts[1],
                        "date": texts[2],
                        "amount": texts[3],
                        "payment_mode": texts[4],
                        "status": texts[5] if len(texts) > 5 else "Success",
                        "description": texts[6] if len(texts) > 6 else "",
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
            attendance = self._parse_attendance(resp.text)
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
