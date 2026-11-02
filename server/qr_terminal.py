#!/usr/bin/env python3
"""Print a terminal QR code for the given URL (requires `pip install qrcode`)."""
import sys

def qr(url: str):
    try:
        import qrcode
    except ImportError:
        print(f"  ⚠️  pip install qrcode  for QR codes")
        print(f"  → {url}")
        return
    qr = qrcode.QRCode(border=2)
    qr.add_data(url)
    qr.make(fit=True)
    qr.print_ascii()

if __name__ == "__main__":
    qr(sys.argv[1])