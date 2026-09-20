import unittest
import re
import sys
import os
from bs4 import BeautifulSoup

sys.path.insert(0, os.path.dirname(__file__))

class TestCurriculumParsing(unittest.TestCase):
    def test_official_vtop_curriculum_table(self):
        # Sample HTML representing the exact VTOP Credits Distribution table from user's screenshot
        html = """
        <table class="table table-bordered">
            <tbody>
                <tr>
                    <td colspan="5" align="center" style="background-color: #f2dede; color: #a94442;">
                        <b>CREDITS DISTRIBUTION</b>
                    </td>
                </tr>
                <tr>
                    <th>Sl.No.</th>
                    <th>Category</th>
                    <th>Total Credits</th>
                    <th>Earned Credits</th>
                    <th>View</th>
                </tr>
                <tr>
                    <td>1.</td>
                    <td>University Core</td>
                    <td>89</td>
                    <td>71.0</td>
                    <td><button class="btn btn-primary">+</button></td>
                </tr>
                <tr>
                    <td>2.</td>
                    <td>Programme Core</td>
                    <td>40</td>
                    <td>40.0</td>
                    <td><button class="btn btn-primary">+</button></td>
                </tr>
                <tr>
                    <td>3.</td>
                    <td>Programme Elective</td>
                    <td>22</td>
                    <td>22.0</td>
                    <td><button class="btn btn-primary">+</button></td>
                </tr>
                <tr>
                    <td>4.</td>
                    <td>University Elective</td>
                    <td>9</td>
                    <td>6.0</td>
                    <td><button class="btn btn-primary">+</button></td>
                </tr>
                <tr>
                    <td>5.</td>
                    <td>Total Credits</td>
                    <td>160</td>
                    <td>139.0</td>
                    <td></td>
                </tr>
            </tbody>
        </table>
        """
        
        from vtop_scraper import VTOPSession
        session = VTOPSession()
        parsed = session._parse_curriculum(html)
        
        summary = parsed["summary"]
        distribution = parsed["distribution"]
        
        self.assertEqual(summary["total"], "160.0")
        self.assertEqual(summary["earned"], "139.0")
        self.assertEqual(summary["left"], "21.0")
        
        dist_map = {d["category"]: d for d in distribution}
        self.assertEqual(dist_map["University Core"]["required"], "89.0")
        self.assertEqual(dist_map["University Core"]["earned"], "71.0")
        self.assertEqual(dist_map["University Core"]["left"], "18.0")
        
        self.assertEqual(dist_map["Programme Core"]["required"], "40.0")
        self.assertEqual(dist_map["Programme Core"]["earned"], "40.0")
        self.assertEqual(dist_map["Programme Core"]["left"], "0.0")
        
        self.assertEqual(dist_map["Programme Elective"]["required"], "22.0")
        self.assertEqual(dist_map["Programme Elective"]["earned"], "22.0")
        self.assertEqual(dist_map["Programme Elective"]["left"], "0.0")
        
        self.assertEqual(dist_map["University Elective"]["required"], "9.0")
        self.assertEqual(dist_map["University Elective"]["earned"], "6.0")
        self.assertEqual(dist_map["University Elective"]["left"], "3.0")

    def test_get_curriculum_preserves_official_vtop_earned(self):
        import asyncio
        from unittest.mock import AsyncMock, patch
        from vtop_scraper import VTOPSession

        session = VTOPSession()
        session.registration_number = "21BCE0001"

        # Mock HTML returned by VTOP curriculum page
        html = """
        <table class="table table-bordered">
            <tr><th>Sl.No.</th><th>Category</th><th>Total Credits</th><th>Earned Credits</th><th>View</th></tr>
            <tr><td>1.</td><td>University Core</td><td>89</td><td>71.0</td><td>+</td></tr>
            <tr><td>2.</td><td>Programme Core</td><td>40</td><td>40.0</td><td>+</td></tr>
            <tr><td>3.</td><td>Programme Elective</td><td>22</td><td>22.0</td><td>+</td></tr>
            <tr><td>4.</td><td>University Elective</td><td>9</td><td>6.0</td><td>+</td></tr>
            <tr><td>5.</td><td>Total Credits</td><td>160</td><td>139.0</td><td></td></tr>
        </table>
        """

        # Mock grades where student took courses that happen to be labeled UE totaling 15 credits
        mock_grades = {
            "courses": [
                {"course_code": "CSE1001", "subject": "PSPP", "type": "ETH", "credits": "4", "grade": "A", "course_distribution": "UC"},
                {"course_code": "MAT1001", "subject": "Calc", "type": "TH", "credits": "4", "grade": "S", "course_distribution": "UC"},
                {"course_code": "CSE2001", "subject": "DSA", "type": "ETH", "credits": "4", "grade": "A", "course_distribution": "PC"},
                {"course_code": "CSE3001", "subject": "OS", "type": "ETH", "credits": "4", "grade": "B", "course_distribution": "PC"},
                {"course_code": "CSE4001", "subject": "Cloud", "type": "TH", "credits": "3", "grade": "A", "course_distribution": "PE"},
                {"course_code": "MGT1001", "subject": "Management", "type": "TH", "credits": "3", "grade": "A", "course_distribution": "UE"},
                {"course_code": "FRL1001", "subject": "French", "type": "TH", "credits": "3", "grade": "S", "course_distribution": "UE"},
                {"course_code": "HUM1002", "subject": "Ethics", "type": "TH", "credits": "3", "grade": "A", "course_distribution": "UE"},
                {"course_code": "OC1001", "subject": "Open Course 1", "type": "TH", "credits": "3", "grade": "A", "course_distribution": "UE"},
                {"course_code": "OC1002", "subject": "Open Course 2", "type": "TH", "credits": "3", "grade": "A", "course_distribution": "UE"},
            ]
        }

        async def run_test():
            session._post_menu = AsyncMock()
            session._post_authenticated = AsyncMock()
            mock_resp = AsyncMock()
            mock_resp.text = html
            session._post_authenticated.return_value = mock_resp
            session.get_grades = AsyncMock(return_value=mock_grades)

            data = await session.get_curriculum()
            return data

        data = asyncio.run(run_test())
        dist_map = {d["category"]: d for d in data["distribution"]}

        # VTOP official values must be preserved!
        self.assertEqual(dist_map["University Elective"]["earned"], "6.0", f"Expected 6.0, got {dist_map['University Elective']['earned']}")
        self.assertEqual(dist_map["University Elective"]["required"], "9.0")
        self.assertEqual(dist_map["University Elective"]["left"], "3.0")

        self.assertEqual(dist_map["Programme Elective"]["earned"], "22.0", f"Expected 22.0, got {dist_map['Programme Elective']['earned']}")
        self.assertEqual(dist_map["University Core"]["earned"], "71.0", f"Expected 71.0, got {dist_map['University Core']['earned']}")
        self.assertEqual(dist_map["Programme Core"]["earned"], "40.0")

        self.assertEqual(data["summary"]["earned"], "139.0")
        self.assertEqual(data["summary"]["total"], "160.0")
        self.assertEqual(data["summary"]["left"], "21.0")

    def test_parse_grades_dynamic_headers(self):
        from vtop_scraper import VTOPSession
        session = VTOPSession()

        html = """
        <table class="table">
            <tbody>
                <tr><td>140.0</td><td>139.0</td><td>8.33</td></tr>
            </tbody>
        </table>
        <table class="customTable">
            <thead>
                <tr>
                    <th>Sl.No</th>
                    <th>Course Code</th>
                    <th>Course Title</th>
                    <th>Course Type</th>
                    <th>Credit</th>
                    <th>Grade</th>
                    <th>Exam Month</th>
                    <th>Result Declared</th>
                    <th>Course Option</th>
                    <th>Course Distribution</th>
                </tr>
            </thead>
            <tbody>
                <tr class="tableContent">
                    <td>1</td>
                    <td>CSE1001</td>
                    <td>Problem Solving</td>
                    <td>ETH</td>
                    <td>4.0</td>
                    <td>A</td>
                    <td>NOV-2023</td>
                    <td>20-DEC-2023</td>
                    <td>Regular</td>
                    <td>PC</td>
                </tr>
            </tbody>
        </table>
        """
        parsed = session._parse_grades(html)
        self.assertEqual(len(parsed["courses"]), 1)
        self.assertEqual(parsed["courses"][0]["course_code"], "CSE1001")
        self.assertEqual(parsed["courses"][0]["course_distribution"], "PC")
        self.assertEqual(parsed["courses"][0]["credits"], "4.0")

    def test_get_curriculum_fallback_degree_audit_reconciliation(self):
        """When VTOP curriculum page is empty, fallback must reconcile excess UE into PE/UC accurately."""
        import asyncio
        from unittest.mock import AsyncMock
        from vtop_scraper import VTOPSession

        session = VTOPSession()
        session.registration_number = "21BCE0001"

        # Mock empty response from curriculum endpoints
        empty_html = "<html><body>No data available</body></html>"

        # Mock Grade History where student has courses: 69 UC, 40 PC, 15 PE, 15 UE
        mock_grades = {
            "credits_registered": "140.0",
            "credits_earned": "139.0",
            "cgpa": "8.33",
            "courses": (
                # 69 credits of UC: 10*3 + 10*3 + 3 + 3 + 3 = 69
                [{"course_code": f"MAT100{i}", "subject": "Math", "type": "TH", "credits": "3", "grade": "A", "course_distribution": "UC"} for i in range(10)]
                + [{"course_code": f"PHY100{i}", "subject": "Physics", "type": "TH", "credits": "3", "grade": "A", "course_distribution": "UC"} for i in range(10)]
                + [
                    {"course_code": "CHY1001", "subject": "Chem", "type": "TH", "credits": "3", "grade": "A", "course_distribution": "UC"},
                    {"course_code": "ENG1001", "subject": "Eng", "type": "TH", "credits": "3", "grade": "A", "course_distribution": "UC"},
                    {"course_code": "STS1001", "subject": "SoftSkills", "type": "SS", "credits": "3", "grade": "A", "course_distribution": "UC"},
                ]
                # 40 credits of PC: 10*4 = 40
                + [{"course_code": f"CSE200{i}", "subject": "Core", "type": "TH", "credits": "4", "grade": "A", "course_distribution": "PC"} for i in range(10)]
                # 15 credits of PE: 5*3 = 15
                + [{"course_code": f"CSE300{i}", "subject": "Elective", "type": "TH", "credits": "3", "grade": "A", "course_distribution": "PE"} for i in range(5)]
                # 15 credits labeled UE: 5*3 = 15
                + [{"course_code": f"MGT100{i}", "subject": "Open", "type": "TH", "credits": "3", "grade": "A", "course_distribution": "UE"} for i in range(5)]
            )
        }

        async def run_test():
            session._post_menu = AsyncMock(return_value=AsyncMock(text=empty_html))
            session._post_authenticated = AsyncMock(return_value=AsyncMock(text=empty_html))
            session.get_grades = AsyncMock(return_value=mock_grades)

            data = await session.get_curriculum()
            return data

        data = asyncio.run(run_test())
        dist_map = {d["category"]: d for d in data["distribution"]}

        # Guaranteed invariants:
        # 1. University Elective MUST NOT exceed 9.0 and MUST be 6.0
        self.assertEqual(dist_map["University Elective"]["earned"], "6.0", f"Expected 6.0, got {dist_map['University Elective']['earned']}")
        self.assertEqual(dist_map["University Elective"]["required"], "9.0")
        self.assertEqual(dist_map["University Elective"]["left"], "3.0")

        # 2. Programme Elective absorbed 7.0 to reach 22.0
        self.assertEqual(dist_map["Programme Elective"]["earned"], "22.0", f"Expected 22.0, got {dist_map['Programme Elective']['earned']}")
        self.assertEqual(dist_map["Programme Elective"]["required"], "22.0")
        self.assertEqual(dist_map["Programme Elective"]["left"], "0.0")

        # 3. University Core reached 71.0
        self.assertEqual(dist_map["University Core"]["earned"], "71.0", f"Expected 71.0, got {dist_map['University Core']['earned']}")
        self.assertEqual(dist_map["University Core"]["required"], "89.0")
        self.assertEqual(dist_map["University Core"]["left"], "18.0")

        # 4. Programme Core is 40.0
        self.assertEqual(dist_map["Programme Core"]["earned"], "40.0")
        self.assertEqual(dist_map["Programme Core"]["required"], "40.0")
        self.assertEqual(dist_map["Programme Core"]["left"], "0.0")

        # 5. Summary totals
        self.assertEqual(data["summary"]["earned"], "139.0")
        self.assertEqual(data["summary"]["total"], "160.0")
        self.assertEqual(data["summary"]["left"], "21.0")

if __name__ == "__main__":
    unittest.main()

