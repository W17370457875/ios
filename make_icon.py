#!/usr/bin/env python3
"""生成 App 图标（1024x1024 PNG），不依赖 Pillow，纯标准库实现。

用法: python3 tools/make_icon.py [输出路径]
"""
import struct
import sys
import zlib

SIZE = 1024
SS = 2  # 每边超采样倍数

BG = (27, 77, 177, 255)      # 底色
WIN = (255, 255, 255, 255)   # 窗口主体
BAR = (220, 230, 247, 255)   # 标题栏
LINE = (232, 237, 246, 255)  # 正文占位线条
DOT_RED = (255, 95, 87, 255)
DOT_YELLOW = (254, 188, 46, 255)
DOT_GREEN = (40, 200, 64, 255)

WIN_BOX = (192.0, 288.0, 832.0, 736.0)  # x0, y0, x1, y1
WIN_RADIUS = 56.0
BAR_BOTTOM = 384.0
DOTS = ((240.0, DOT_RED), (296.0, DOT_YELLOW), (352.0, DOT_GREEN))
DOT_R = 16.0
LINES = ((430.0, 462.0, 240.0, 700.0), (500.0, 532.0, 240.0, 600.0))


def in_rounded_rect(x, y, box, radius):
    x0, y0, x1, y1 = box
    if x < x0 or x > x1 or y < y0 or y > y1:
        return False
    cx = min(max(x, x0 + radius), x1 - radius)
    cy = min(max(y, y0 + radius), y1 - radius)
    dx = x - cx
    dy = y - cy
    return dx * dx + dy * dy <= radius * radius


def color_at(x, y):
    if not in_rounded_rect(x, y, WIN_BOX, WIN_RADIUS):
        return BG
    if y <= BAR_BOTTOM:
        for cx, color in DOTS:
            dx = x - cx
            dy = y - 336.0
            if dx * dx + dy * dy <= DOT_R * DOT_R:
                return color
        return BAR
    for y0, y1, x0, x1 in LINES:
        if in_rounded_rect(x, y, (x0, y0, x1, y1), 16.0):
            return LINE
    return WIN


def render():
    rows = []
    step = 1.0 / SS
    total = SS * SS
    for py in range(SIZE):
        row = bytearray()
        for px in range(SIZE):
            r = g = b = a = 0
            for sy in range(SS):
                y = py + (sy + 0.5) * step
                for sx in range(SS):
                    x = px + (sx + 0.5) * step
                    cr, cg, cb, ca = color_at(x, y)
                    r += cr
                    g += cg
                    b += cb
                    a += ca
            row += bytes((r // total, g // total, b // total, a // total))
        rows.append(row)
    return rows


def write_png(path, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    out = b"\x89PNG\r\n\x1a\n"
    out += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
    out += chunk(b"IDAT", zlib.compress(raw, 9))
    out += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(out)


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
    write_png(target, render())
    print("icon written:", target)
