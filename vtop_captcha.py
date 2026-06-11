import base64
import io
import json
import numpy as np
from PIL import Image
import os

# Load weights globally
_weights = None
_biases = None

def _load_model():
    global _weights, _biases
    if _weights is None:
        try:
            weights_path = os.path.join(os.path.dirname(__file__), 'weights.json')
            with open(weights_path, 'r') as f:
                model_config = json.load(f)
            _weights = np.array(model_config.get("weights"))
            _biases = np.array(model_config.get("biases"))
        except Exception as e:
            print(f"Error loading captcha weights.json: {e}")
            raise


def _saturation(img: Image.Image) -> np.ndarray:
    """
    Convert an RGB image to its HSV saturation channel.
    This is the key preprocessing step from the reference app.
    Saturation = (max(R,G,B) - min(R,G,B)) * 255 / max(R,G,B)
    This cleanly separates colored captcha text (high saturation)
    from gray/white background noise (low saturation).
    """
    rgb = np.array(img.convert("RGBA"), dtype=np.float32)
    # Process RGBA pixels
    height, width = rgb.shape[:2]
    saturate = np.zeros((height, width), dtype=np.uint8)
    
    for y in range(height):
        for x in range(width):
            r, g, b = rgb[y, x, 0], rgb[y, x, 1], rgb[y, x, 2]
            mx = max(r, g, b)
            mn = min(r, g, b)
            if mx > 0:
                saturate[y, x] = int((mx - mn) * 255.0 / mx)
            else:
                saturate[y, x] = 0
    
    return saturate


def partition_img(img: np.ndarray) -> list:
    """Partitions the captcha image into 6 character images.
    Uses the exact same coordinates as the reference app."""
    parts = []
    for i in range(6):
        x1 = (i + 1) * 25 + 2
        y1 = 7 + 5 * (i % 2) + 1
        x2 = (i + 2) * 25 + 1
        y2 = 35 - 5 * ((i + 1) % 2)
        part = img[y1:y2, x1:x2]
        parts.append(part)
    return parts


def convert_to_abs_bw(img: np.ndarray) -> np.ndarray:
    """Converts an image part to absolute black and white based on average pixel value."""
    if img.size == 0:
        raise ValueError("Cannot process empty image part.")
    avg = float(np.sum(img)) / float(img.size)
    return np.where(img > avg, 1, 0)


def solve_captcha_ml(parts: list) -> str:
    _load_model()
    LETTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    captcha = ""
    for single_letter in parts:
        dw_img = convert_to_abs_bw(single_letter)
        dw_img = dw_img.flatten().astype(np.float64)
        x = np.dot(dw_img, _weights) + _biases
        x = np.exp(x - np.max(x))  # numerical stability
        captcha += LETTERS[np.argmax(x)]
    return captcha


def solve_vtop_captcha(captcha_base64: str) -> str:
    """Solve a VTOP captcha from its base64-encoded image string.
    Uses saturation-based preprocessing matching the reference app."""
    try:
        if "," in captcha_base64:
            captcha_base64 = captcha_base64.split(",")[1]
            
        im = base64.b64decode(captcha_base64)
        img = Image.open(io.BytesIO(im))
        
        # Use saturation preprocessing (reference app's approach)
        sat_img = _saturation(img)
        
        parts = partition_img(sat_img)
        return solve_captcha_ml(parts)
    except Exception as e:
        print(f"An unexpected error occurred during ML captcha solving: {e}")
        return ""
