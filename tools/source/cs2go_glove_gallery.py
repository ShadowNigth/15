"""Fetch the 96 actual glove catalogue thumbnails from pinned cs2go.
No generated images, game integration, asset reinterpretation, or paint baking.
"""
import base64
import concurrent.futures
import html
import io
import json
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
PIN = 'fb970df0ee8175d9b212d310f6a928f9f61014f2'
API = 'repos/3kh0/cs2go/contents/packages/assets/public'
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'docs/evidence/cs2go-gloves'
CACHE = ROOT/'.cache/cs2go-glove-thumbnails'
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'


def fetch(path):
    target = CACHE/path.lstrip('/')
    if not target.exists():
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(subprocess.check_output(['gh', 'api', '-H', 'Accept: application/vnd.github.raw+json', API+path+'?ref='+PIN]))
    return target.read_bytes()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    rows = json.loads(fetch('/skins/gloves/catalog.json'))
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        images = list(pool.map(lambda row: fetch(row['image']), rows))
    titlefont = ImageFont.truetype(FONT, 28)
    font = ImageFont.truetype(FONT, 15)
    families = dict.fromkeys(row['item'] for row in rows)
    cards = []
    sheets = []
    for family in families:
        selected = [(row, data) for row, data in zip(rows, images) if row['item'] == family]
        name = selected[0][0]['name'].split(' | ')[0]
        columns = min(4, len(selected))
        canvas = Image.new('RGB', (columns*290, 100+((len(selected)+columns-1)//columns)*245), '#18212b')
        draw = ImageDraw.Draw(canvas)
        draw.text((22, 15), name+' — cs2go', fill='white', font=titlefont)
        draw.text((22, 57), 'Imagenes originales del catalogo; no son capturas del juego modificado.', fill='#adc1d2', font=font)
        for index, (row, data) in enumerate(selected):
            image = Image.open(io.BytesIO(data)).convert('RGBA')
            image.thumbnail((260, 185))
            x, y = (index % columns)*290, 100+(index//columns)*245
            canvas.paste(image, (x+(290-image.width)//2, y+(185-image.height)//2), image)
            label = row['name'].split(' | ')[-1]
            draw.text((x+12, y+190), label, fill='white', font=font)
            draw.text((x+12, y+213), row['id'], fill='#adc1d2', font=font)
        sheet = str(family)+'.jpg'
        canvas.save(OUT/sheet, quality=92)
        sheets.append({'family': name, 'file': sheet, 'finishes': len(selected)})
    for row, data in zip(rows, images):
        url = 'https://github.com/3kh0/cs2go/blob/'+PIN+'/packages/assets/public'+row['image']
        cards.append('<article data-name="'+html.escape(row['name'].lower(), quote=True)+'"><img loading="lazy" alt="'+html.escape(row['name'], quote=True)+'" src="data:image/webp;base64,'+base64.b64encode(data).decode()+'"><h3>'+html.escape(row['name'])+'</h3><p>'+html.escape(row['id'])+'</p><a href="'+url+'" target="_blank" rel="noopener">Ver archivo original en cs2go ↗</a></article>')
    document = '''<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Guantes de cs2go — catálogo original</title><style>*{box-sizing:border-box}body{margin:0;background:#111923;color:#eef5fb;font:16px system-ui}header{padding:36px max(24px,5vw);border-bottom:1px solid #344559}h1{font-size:clamp(28px,4vw,48px);margin:8px 0}header p{color:#b3c7d9;max-width:850px;line-height:1.6}input{width:min(600px,100%);padding:15px;border:1px solid #455c72;border-radius:8px;background:#1d2a39;color:white;font:inherit}main{padding:30px max(24px,5vw);display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:18px}article{padding:18px;border:1px solid #344559;border-radius:12px;background:#1b2735}img{width:100%;height:190px;object-fit:contain}h3{font-size:17px}p{color:#b3c7d9}a{color:#85c8ff;font-size:14px}[hidden]{display:none}</style><header><p>3kh0 / cs2go · referencia independiente</p><h1>96 acabados de guantes · 10 modelos</h1><p>Estas son las imágenes originales incluidas en el catálogo del repositorio cs2go, no imágenes generadas ni capturas de nuestro juego. Se muestran sin retarget, giros ni intercambio de manos. Esto no vuelve a instalar los guantes retirados.</p><p>Fuente fijada: <code>'''+PIN+'''</code>. Los derechos de Valve/autores permanecen separados.</p><input id="search" type="search" placeholder="Buscar: Sport, Driver, Hand Wraps, Bronze Morph…" aria-label="Buscar guantes"></header><main>'''+''.join(cards)+'''</main><script>document.getElementById('search').addEventListener('input',e=>{const q=e.target.value.trim().toLowerCase();document.querySelectorAll('article').forEach(card=>card.hidden=!card.dataset.name.includes(q))})</script></html>'''
    (OUT/'catalogo.html').write_text(document)
    (OUT/'manifest.json').write_text(json.dumps({'source':'https://github.com/3kh0/cs2go','commit':PIN,'kind':'Original repository catalogue thumbnails, not modified-game screenshots','sheets':sheets,'options':rows}, indent=2)+'\n')
    markdown = '# Guantes del catálogo de cs2go\n\nImágenes originales del repositorio, no capturas del juego modificado ni imágenes generadas. No se vuelven a instalar en el juego. Fuente fijada: [3kh0/cs2go @ '+PIN[:12]+'](https://github.com/3kh0/cs2go/tree/'+PIN+').\n\n96 acabados en 10 modelos. [Galería HTML con buscador](catalogo.html) (descargar y abrir localmente; todas las imágenes están integradas).\n\n'
    for sheet in sheets:
        markdown += '## '+sheet['family']+' ('+str(sheet['finishes'])+')\n\n!['+sheet['family']+']('+sheet['file']+')\n\n'
    (OUT/'README.md').write_text(markdown)
    print('Saved', len(rows), 'original thumbnails in', len(sheets), 'family sheets and offline HTML gallery.')

if __name__ == '__main__': main()
