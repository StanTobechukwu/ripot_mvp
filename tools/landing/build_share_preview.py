"""Compose a 1200x630 social card from the existing fictional report (ReportLab + Poppler)."""
from pathlib import Path
import subprocess
import tempfile
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

for name, family in [("RipotSans", "DejaVu Sans"), ("RipotBold", "DejaVu Sans:style=Bold")]:
    font = subprocess.check_output(["fc-match", "-f", "%{file}", family], text=True)
    pdfmetrics.registerFont(TTFont(name, font))

ROOT = Path(__file__).resolve().parents[2]
images = ROOT / 'landing/y/images'
with tempfile.TemporaryDirectory() as tmp:
    pdf = Path(tmp) / 'preview.pdf'
    c = canvas.Canvas(str(pdf), pagesize=(1200, 630))
    c.setFillColor(HexColor('#edf5f2')); c.rect(0, 0, 1200, 630, fill=1, stroke=0)
    c.drawImage(str(images/'ripot-icon.png'), 56, 505, 62, 62, mask='auto')
    c.setFillColor(HexColor('#123e36')); c.setFont('RipotBold', 42); c.drawString(134, 521, 'Ripot')
    c.setFont('RipotBold', 40)
    for y, line in [(400, 'Professional reports.'), (346, 'Made simple.')]: c.drawString(56, y, line)
    c.setFont('RipotSans', 23)
    for y, line in [(278, 'Create, sign and share'), (245, 'clinical reports with images.')]: c.drawString(56, y, line)
    c.setFillColor(HexColor('#006c5e')); c.roundRect(56, 138, 260, 60, 15, fill=1, stroke=0)
    c.setFillColor(HexColor('#ffffff')); c.setFont('RipotBold', 26); c.drawString(90, 157, 'ripot.app')
    c.setFillColor(HexColor('#49665e')); c.setFont('RipotSans', 13)
    c.drawString(56, 73, 'Fictional demonstration report. No real patient data.')
    c.setFont('RipotSans', 10)
    c.drawString(56, 48, 'Report photos: melvil / Wikimedia Commons (CC BY-SA 4.0).')
    c.setFillColor(HexColor('#ccdcd5')); c.roundRect(751, 28, 404, 566, 8, fill=1, stroke=0)
    c.drawImage(str(images/'ripot-colonoscopy-aligned-48.png'), 742, 39, 400, 566)
    c.save()
    subprocess.run(['pdftoppm', '-singlefile', '-jpeg', '-jpegopt', 'quality=90', '-scale-to-x', '1200', '-scale-to-y', '630', str(pdf), str(images/'ripot-report-share')], check=True)
