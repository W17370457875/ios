import xml.etree.ElementTree as ET
import json
import os
import struct
import sys
import io

base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

_buf = io.StringIO()
sys.stdout = _buf


def check(name, fn):
    try:
        fn()
        print("OK  ", name)
    except Exception as e:  # noqa
        print("FAIL", name, "->", e)


def xml_ok(p):
    ET.parse(p)


def json_ok(p):
    with open(p, encoding="utf-8") as f:
        json.load(f)


check("Info.plist", lambda: xml_ok(os.path.join(base, "Resources", "Info.plist")))
check("Entitlements.plist", lambda: xml_ok(os.path.join(base, "Resources", "Entitlements.plist")))
check("LaunchScreen.storyboard", lambda: xml_ok(os.path.join(base, "Resources", "LaunchScreen.storyboard")))
check("Assets Contents.json", lambda: json_ok(os.path.join(base, "Resources", "Assets.xcassets", "Contents.json")))
check("AppIcon Contents.json", lambda: json_ok(os.path.join(base, "Resources", "Assets.xcassets", "AppIcon.appiconset", "Contents.json")))

png = os.path.join(base, "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png")
with open(png, "rb") as f:
    sig = f.read(8)
assert sig == b"\x89PNG\r\n\x1a\n", sig
with open(png, "rb") as f:
    data = f.read()
w, h = struct.unpack(">II", data[16:24])
print("PNG OK size=%dx%d bytes=%d" % (w, h, len(data)))

try:
    import yaml
    with open(os.path.join(base, ".github", "workflows", "build-ipa.yml"), encoding="utf-8") as f:
        yaml.safe_load(f)
    print("OK   build-ipa.yml YAML")
except ImportError:
    print("SKIP build-ipa.yml YAML (pyyaml 未安装)")
except Exception as e:  # noqa
    print("FAIL build-ipa.yml YAML ->", e)

sys.stdout = sys.__stdout__
with open(os.path.join(base, "tools", "validate_result.txt"), "w", encoding="utf-8") as log:
    log.write(_buf.getvalue())
