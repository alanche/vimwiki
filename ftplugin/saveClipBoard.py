# Save the clipBoard image contents into the specific file
# Written By Alan Che <alan-che@qq.com>
from PIL import ImageGrab
import sys
filename = sys.argv[1]
im = ImageGrab.grabclipboard()
if im is not None:
  im.save(filename,"png")
  print("OK")
else:
  print("ERROR")
