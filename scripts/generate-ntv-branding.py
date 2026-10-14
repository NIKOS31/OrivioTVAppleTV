"""Package the existing supplied mark at predictable Top Shelf dimensions.

Pillow is an authoring dependency only; generated PNGs are committed resources.
No image generation, remote artwork, recolouring or new mark design is involved.
"""
import json
from pathlib import Path
from PIL import Image, ImageOps
root=Path(__file__).resolve().parent.parent
asset=root/'OrivioTV/Assets.xcassets/NTVLogo.imageset'
entries=json.loads((asset/'Contents.json').read_text())['images']
source=next(e['filename'] for e in entries if e.get('filename'))
logo=Image.open(asset/source).convert('RGBA')
logo=logo.crop(logo.getbbox())

def banner(destination, size, mark_size, y_offset=0):
    canvas=Image.new('RGBA',size,(16,19,27,255))
    mark=ImageOps.contain(logo,mark_size,Image.Resampling.LANCZOS)
    canvas.alpha_composite(mark,((size[0]-mark.width)//2,(size[1]-mark.height)//2+y_offset))
    canvas.convert('RGB').save(destination)

resources=root/'OrivioTopShelf/Resources'
banner(resources/'topshelf-full.png',(1920,1080),(400,260),-40)
for name,size,limit in [('topshelf-wide.png',(2320,720),(340,220)),('topshelf-wide@2x.png',(4640,1440),(680,440))]:
    banner(resources/name,size,limit)
brand=root/'OrivioTV/Assets.xcassets/App Icon & Top Shelf Image.brandassets'
for name,size,limit in [('topshelf.png',(1920,720),(320,208)),('topshelf@2x.png',(3840,1440),(640,416))]:
    banner(brand/'Top Shelf Image.imageset'/name,size,limit)
for name,size,limit in [('topshelf-wide.png',(2320,720),(340,220)),('topshelf-wide@2x.png',(4640,1440),(680,440))]:
    banner(brand/'Top Shelf Image Wide.imageset'/name,size,limit)
print(json.dumps({'suppliedMarkPreserved':True,'fullScreenMarkBounds':[400,260],'fullScreenSize':[1920,1080]}))
