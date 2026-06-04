"""
Test different captcha preprocessing approaches to find the most accurate one.
VTOP captchas have RED text on light background with noise lines.
"""
import httpx
import asyncio
import base64
from bs4 import BeautifulSoup
from PIL import Image, ImageEnhance, ImageFilter
import numpy as np
import io
import ddddocr

def preprocess_v1_grayscale(img_bytes):
    """Simple grayscale + contrast"""
    pil_img = Image.open(io.BytesIO(img_bytes)).convert('L')
    enhanced = ImageEnhance.Contrast(pil_img).enhance(1.5)
    buf = io.BytesIO()
    enhanced.save(buf, format='PNG')
    return buf.getvalue()

def preprocess_v2_red_channel(img_bytes):
    """Extract red channel only - text is red/maroon"""
    pil_img = Image.open(io.BytesIO(img_bytes)).convert('RGB')
    r, g, b = pil_img.split()
    # Text is red: high R, low G, low B
    # Invert so text becomes dark on white
    arr_r = np.array(r, dtype=np.float32)
    arr_g = np.array(g, dtype=np.float32)
    arr_b = np.array(b, dtype=np.float32)
    # Red text has R much higher than G and B
    mask = ((arr_r > 80) & (arr_g < 150) & (arr_b < 150) & (arr_r > arr_g + 20))
    result = np.where(mask, 0, 255).astype(np.uint8)  # black text, white bg
    out = Image.fromarray(result, mode='L')
    buf = io.BytesIO()
    out.save(buf, format='PNG')
    return buf.getvalue()

def preprocess_v3_threshold(img_bytes):
    """Grayscale + aggressive threshold"""
    pil_img = Image.open(io.BytesIO(img_bytes)).convert('L')
    # Threshold: dark pixels = text
    arr = np.array(pil_img)
    binary = np.where(arr < 160, 0, 255).astype(np.uint8)
    out = Image.fromarray(binary, mode='L')
    buf = io.BytesIO()
    out.save(buf, format='PNG')
    return buf.getvalue()

def preprocess_v4_red_enhanced(img_bytes):
    """Red channel extraction + median filter to remove noise lines"""
    pil_img = Image.open(io.BytesIO(img_bytes)).convert('RGB')
    arr = np.array(pil_img, dtype=np.float32)
    r, g, b = arr[:,:,0], arr[:,:,1], arr[:,:,2]
    # Red text: R significantly higher than G and B
    mask = ((r > 80) & (g < 140) & (b < 140) & ((r - g) > 30))
    result = np.where(mask, 0, 255).astype(np.uint8)
    out = Image.fromarray(result, mode='L')
    # Median filter to clean noise
    out = out.filter(ImageFilter.MedianFilter(3))
    buf = io.BytesIO()
    out.save(buf, format='PNG')
    return buf.getvalue()

async def main():
    ocr = ddddocr.DdddOcr(show_ad=False)
    c = httpx.AsyncClient(verify=False, follow_redirects=True, base_url='https://vtop.vitap.ac.in',
                          headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"})
    
    r = await c.get('/vtop/')
    csrf = r.text.split('name="_csrf" value="')[1].split('"')[0]
    await c.post('/vtop/prelogin/setup', data={'_csrf': csrf, 'flag': 'VTOP'})
    
    methods = {
        "v1_gray": preprocess_v1_grayscale,
        "v2_red": preprocess_v2_red_channel,
        "v3_thresh": preprocess_v3_threshold,
        "v4_red_enh": preprocess_v4_red_enhanced,
    }
    
    for i in range(8):
        r3 = await c.get('/vtop/get/new/captcha')
        soup = BeautifulSoup(r3.text, 'lxml')
        for img in soup.find_all('img'):
            src = img.get('src', '')
            if src.startswith('data:image'):
                b64 = src.split(',')[1]
                raw = base64.b64decode(b64)
                
                with open(f'cap_{i}.jpg', 'wb') as f:
                    f.write(raw)
                
                results = {}
                for name, func in methods.items():
                    processed = func(raw)
                    text = ocr.classification(processed)
                    text = ''.join(c for c in text if c.isalnum())
                    results[name] = text
                    
                    # Also save preprocessed for visual inspection
                    with open(f'cap_{i}_{name}.png', 'wb') as f:
                        f.write(processed)
                
                # Also try raw
                raw_text = ocr.classification(raw)
                raw_text = ''.join(c for c in raw_text if c.isalnum())
                
                print(f"#{i}: raw='{raw_text}' | " + " | ".join(f"{k}='{v}'({len(v)})" for k, v in results.items()))
                break
        await asyncio.sleep(0.3)

asyncio.run(main())
