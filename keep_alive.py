import requests
import time
import sys

# Update this with your Render service URL
RENDER_URL = "https://vitap-backend.onrender.com"

def keep_alive():
    print(f"Starting keep-alive for {RENDER_URL}")
    while True:
        try:
            resp = requests.get(f"{RENDER_URL}/health")
            if resp.status_code == 200:
                print(f"[{time.strftime('%H:%M:%S')}] Ping successful: {resp.json().get('status')}")
            else:
                print(f"[{time.strftime('%H:%M:%S')}] Ping failed: {resp.status_code}")
        except Exception as e:
            print(f"[{time.strftime('%H:%M:%S')}] Error: {e}")
        
        # Render free tier sleeps after 15 mins of inactivity. 
        # Ping every 10 mins to stay awake.
        time.sleep(600)

if __name__ == "__main__":
    try:
        keep_alive()
    except KeyboardInterrupt:
        print("\nKeep-alive stopped.")
        sys.exit(0)
