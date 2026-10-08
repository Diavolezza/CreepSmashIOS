#!/usr/bin/env python3
"""Writes CreepSmashCore/.../BuiltInMaps.swift from tools/maps/out/*.map."""
import os
HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, 'out')
TARGET = os.path.join(HERE, '..', '..', 'CreepSmashCore', 'Sources', 'CreepSmashCore', 'BuiltInMaps.swift')
MAPS = [('blue', 'Blue'), ('neon', 'Neon'), ('spirale', 'Spiral'), ('canyon', 'Canyon'),
        ('platine', 'Circuit'), ('vulkan', 'Volcano')]
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
