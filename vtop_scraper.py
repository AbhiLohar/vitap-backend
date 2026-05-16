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
            for row in rows:
                cols = row.find_all("td")
                if len(cols) >= 6:
                    texts = [c.get_text(strip=True) for c in cols]
                    if any(h in texts[0].lower() for h in ["sl", "serial", "sno"]):
                        continue
                        
                    n = len(texts)
                    # Extract venue and seat_no from the last column which usually looks like "AB1-201-R1C1-12"
                    # We want "AB1-201" as Venue and "R1C1-12" as Seat No
                    raw_venue = texts[n-1] if n > 8 else "-"
                    venue = raw_venue
                    seat_no = "-"
                    
                    if "-" in raw_venue:
                        parts = raw_venue.split("-")
                        if len(parts) >= 4:
                            # Typical: AB-1-201-R1C1-10 -> Venue: AB-1-201, Seat: R1C1-10
                            # The seat part is usually the last two hyphenated segments like R1C1-10
                            seat_no = "-".join(parts[-2:])
                            venue = "-".join(parts[:-2])
                        elif len(parts) >= 2:
                            seat_no = parts[-1]
                            venue = "-".join(parts[:-1])

                    data.append({
                        "course_code": texts[1] if n > 1 else "",
                        "subject": texts[2] if n > 2 else "",
                        "type": texts[3] if n > 3 else "",
                        "class_id": texts[4] if n > 4 else "",
                        "slot": texts[5] if n > 5 else "",
                        "date": texts[6] if n > 6 else "-",
                        "session": texts[7] if n > 7 else "-",
                        "venue": venue,
                        "seat_no": seat_no,
                        "exam_time": texts[n-2] if n > 10 else "-",
                        "reporting_time": texts[n-2] if n == 10 else (texts[n-3] if n == 11 else (texts[8] if n > 8 else "-")),
                    })
                elif len(cols) == 5:
                    texts = [c.get_text(strip=True) for c in cols]
                    data.append({
                        "course_code": texts[0],
                        "subject": texts[1],
                        "date": texts[2],
                        "session": texts[3],
                        "venue": texts[4],
                        "seat_no": "-"
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
                    elif "email" in label:
                        profile["email"] = value
            
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
                
                # If no explicit category column, try first text column
                if idx_cat == -1:
                    for i, h in enumerate(header_texts):
                        if not any(c.isdigit() for c in h):
                            idx_cat = i
                            break
                
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

    async def close(self):
        """Close HTTP client."""
        try:
            await self.client.aclose()
        except Exception:
            pass
