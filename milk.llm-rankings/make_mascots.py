#!/usr/bin/env python3
"""Generate 10x10 8-bit mascots into ./mascots/<slug>.png (no dependencies).

Each sprite is the LEFT half (5 columns x 10 rows); it is mirrored to 10x10.
Original pixel creatures with a nod to each lab's theme, not brand logos.
Run:  python3 -I make_mascots.py [output-dir]
"""
import struct
import sys
import zlib
from pathlib import Path

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent / 'mascots'

SPRITES = {
    # Anthropic: sunburst critter
    'anthropic': ({'a': '#d97757', 'e': '#3b1d12'}, [
        '....a', '.a..a', '..aaa', '.aaaa', 'aaeaa', '.aaaa', '..aaa', '.a..a', '....a', '.....']),
    # OpenAI: teal hex ring
    'openai': ({'a': '#10a37f', 'b': '#0b7a5d'}, [
        '..aaa', '.aaaa', 'aaabb', 'aab..', 'aab..', 'aab..', 'aab..', 'aaabb', '.aaaa', '..aaa']),
    # Google: four-colour sparkle
    'google': ({'a': '#4285f4', 'c': '#ea4335', 'd': '#fbbc05', 'g': '#34a853'}, [
        '....a', '....a', '...aa', '..aaa', 'cccdd', 'cccdd', '..ggg', '...gg', '....g', '....g']),
    # Meta: blue llama
    'meta': ({'a': '#0866ff', 'b': '#bcd7ff', 'e': '#0a1a3a', 'k': '#0a1a3a'}, [
        '..a..', '..a..', '.aaaa', '.aaaa', '.aeaa', '.aaaa', '..aab', '..bbb', '..bkb', '..bbb']),
    # DeepSeek: blue whale with spout
    'deepseek': ({'a': '#4d6bfe', 'b': '#c8d3ff', 'e': '#0a1030', 'k': '#8fb0ff'}, [
        '...k.', '....k', '.....', '.aaaa', 'aaaaa', 'aeaaa', 'aaaaa', 'abbbb', '.abbb', '..aaa']),
    # Mistral: orange block "M" gust
    'mistral': ({'a': '#fa520f', 'b': '#ffa110', 'c': '#ffd800'}, [
        'cc...', 'ccc..', 'cccc.', 'bbbbb', 'bb.bb', 'aa..a', 'aa..a', 'aa..a', 'aa...', 'aa...']),
    # Alibaba/Qwen: purple smiley blob
    'alibaba': ({'a': '#7b5cff', 'b': '#4a35c9', 'e': '#150a40', 'k': '#ffffff'}, [
        '.aaaa', 'aaaaa', 'aaeaa', 'aaaaa', 'aaaaa', 'aakkk', '.aaaa', '..bbb', '.bb.b', '.bb..']),
    # Kimi: moon face
    'kimi': ({'o': '#1c2340', 'a': '#bcd0ff', 'b': '#8fa8e8', 'e': '#1c2340'}, [
        '..ooo', '.oaaa', 'oaaaa', 'oaeaa', 'oaaaa', 'oabba', 'oaabb', '.oaaa', '..ooo', '.....']),
    # xAI / SpaceXAI: rocket
    'xai': ({'o': '#2a2a2a', 'a': '#e8e8e8', 'w': '#5ec8ff', 'k': '#ff5c5c', 'y': '#ffc933'}, [
        '....o', '...oa', '..oaa', '..oaw', '..oaw', '..oaa', '.oaaa', 'oa.kk', 'o..kk', '....y']),
    # Xiaomi: orange square face
    'xiaomi': ({'a': '#ff6900', 'w': '#ffffff', 'e': '#1a1a1a', 'o': '#7a2f00'}, [
        '.aaaa', 'aaaaa', 'awwaa', 'aweaa', 'aaaaa', 'aaooo', 'aaaaa', 'aaaaa', 'aaaaa', '.aaaa']),
    # NVIDIA: green eye
    'nvidia': ({'a': '#76b900', 'w': '#ffffff', 'e': '#111111'}, [
        '.....', '..aaa', '.aaaa', 'aawww', 'awwee', 'awwee', 'aawww', '.aaaa', '..aaa', '.....']),
    # Fallback: little grey robot
    'robot': ({'o': '#2b2b2b', 'a': '#9aa5b1', 'b': '#6b7683', 'k': '#ff5c5c', 'e': '#22d3ee'}, [
        '....o', '....k', '.oooo', 'oaaaa', 'oaeea', 'oaaaa', 'oabbb', '.oooo', '.oaao', '..ooo']),
}


def png(path, rows):
    height, width = len(rows), len(rows[0])
    raw = b''.join(b'\x00' + b''.join(bytes(px) for px in row) for row in rows)

    def chunk(tag, data):
        body = tag + data
        return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body) & 0xffffffff)

    data = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
    path.write_bytes(data)


def main():
    OUT.mkdir(exist_ok=True)
    for slug, (palette, half) in SPRITES.items():
        assert len(half) == 10 and all(len(r) == 5 for r in half), slug
        rgb = {k: tuple(int(v[i:i + 2], 16) for i in (1, 3, 5)) + (255,) for k, v in palette.items()}
        rows = []
        for line in half:
            full = line + line[::-1]
            rows.append([rgb[c] if c in rgb else (0, 0, 0, 0) for c in full])
        png(OUT / (slug + '.png'), rows)
        print('wrote', slug)


if __name__ == '__main__':
    main()
