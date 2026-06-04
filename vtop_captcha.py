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

def partition_img(img: np.ndarray) -> list[np.ndarray]:
    """Partitions the captcha image into 6 character images."""
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
    avg = np.sum(img)
    avg /= 24 * 22
    return np.where(img > avg, 0, 1)

def solve_captcha_ml(img: list[np.ndarray]) -> str:
    _load_model()
    LETTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    captcha = ""
    for single_letter in img:
        dw_img = convert_to_abs_bw(single_letter)
        dw_img = dw_img.flatten()
        x = np.dot(dw_img, _weights) + _biases
        x = np.exp(x)
        captcha += LETTERS[np.argmax(x)]
    return captcha

def solve_vtop_captcha(captcha_base64: str) -> str:
    try:
        if "," in captcha_base64:
            captcha_base64 = captcha_base64.split(",")[1]
            
        im = base64.b64decode(captcha_base64)
        img = Image.open(io.BytesIO(im)).convert("L")
        img = np.array(img)
        
        parts = partition_img(img)
        return solve_captcha_ml(parts)
    except Exception as e:
        print(f"An unexpected error occurred during ML captcha solving: {e}")
        return ""
