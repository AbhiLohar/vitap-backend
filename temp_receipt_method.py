    async def get_payment_receipt_details(self, receipt_id: str) -> dict:
        """Fetch full receipt HTML and parse it."""
        try:
            # We must use the post_login_csrf from the current session state
            data = {
                "verifyMenu": "true",
                "authorizedID": self.registration_number,
                "applNo": receipt_id,  # VTOP expects applNo for fetching dup receipt
                "_csrf": self.post_login_csrf,
            }
            # Try applNo first
            resp = await self.client.post("/vtop/finance/dupReceiptNewP2P", data=data, headers=HEADERS)
            if "Receipt Number" not in resp.text:
                # Fallback if it expects receiptNo
                data["receiptNo"] = receipt_id
                del data["applNo"]
                resp = await self.client.post("/vtop/finance/dupReceiptNewP2P", data=data, headers=HEADERS)
            
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
                return {"error": "Receipt details table not found in HTML"}
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
