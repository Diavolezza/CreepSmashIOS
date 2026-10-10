#!/usr/bin/env python3
"""Writes CreepSmashCore/.../BuiltInMaps.swift from tools/maps/out/*.map and puts the pictures into the
asset catalog: map_<id> (960 px, the board) and map_<id>_small (480 px, the map cards in the menus)."""
import json, os, shutil
from PIL import Image
HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, 'out')
TARGET = os.path.join(HERE, '..', '..', 'CreepSmashCore', 'Sources', 'CreepSmashCore', 'BuiltInMaps.swift')
MAPS = [('blue', 'Blue'), ('neon', 'Neon'), ('spirale', 'Spiral'), ('canyon', 'Canyon'),
        ('platine', 'Circuit'), ('vulkan', 'Volcano'),
        ('rennbahn', 'Raceway'), ('wurmloch', 'Wormhole'), ('polarlicht', 'Aurora'), ('kreuzung', 'Crossroads'),
        ('mahlstrom', 'Maelstrom'), ('pendel', 'Pendulum'), ('asteroiden', 'Asteroids'), ('stromschnellen', 'Rapids')]
parts = ['// Built-in maps – all original designs of CreepSmash iOS.',
         '// Generated with tools/maps/generate.py (path and background image) and tools/maps/embed.py (this file).',
         '', 'extension GameMap {']
for mid, name in MAPS:
    text = open(os.path.join(OUT, f'map_{mid}.map'), encoding='utf-8').read().rstrip('\n')
    parts.append(f'    public static let {mid}: GameMap = try! GameMap.parse(id: "{mid}", name: "{name}", text: #"""')
    parts.append(text)
    parts.append('"""#)')
    parts.append('')
parts.append('    /// All built-in maps in the order shown in the selection.')
parts.append('    public static let all: [GameMap] = [' + ', '.join('.' + m for m, _ in MAPS) + ']')
parts.append('')
parts.append('    public static func named(_ id: String) -> GameMap? { all.first { $0.id == id } }')
parts.append('}')
open(TARGET, 'w', encoding='utf-8').write('\n'.join(parts) + '\n')
print(TARGET)

ASSETS = os.path.join(HERE, '..', '..', 'CreepSmash', 'Assets.xcassets', 'Maps')
for mid, _ in MAPS:
    source = os.path.join(OUT, f'map_{mid}.jpg')
    for name, size in ((f'map_{mid}', None), (f'map_{mid}_small', 480)):
        folder = os.path.join(ASSETS, f'{name}.imageset')
        os.makedirs(folder, exist_ok=True)
        target = os.path.join(folder, f'{name}.jpg')
        if size is None:
            shutil.copyfile(source, target)
        else:
            Image.open(source).resize((size, size), Image.LANCZOS).save(target, quality=85)
        contents = {'images': [{'filename': f'{name}.jpg', 'idiom': 'universal'}], 'info': {'author': 'xcode', 'version': 1}}
        json.dump(contents, open(os.path.join(folder, 'Contents.json'), 'w'), indent=2)
print(ASSETS)
