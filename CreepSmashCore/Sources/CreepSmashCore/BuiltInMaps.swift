// Built-in maps – all original designs of CreepSmash iOS.
// Generated with tools/maps/generate.py (path and background image) and tools/maps/embed.py (this file).

extension GameMap {
    public static let blue: GameMap = try! GameMap.parse(id: "blue", name: "Blue", text: #"""
###
### BLUE – own map of CreepSmash iOS
###

map_blue.jpg

SET_ALPHA_BACKGROUND_COLOR:OFF

# blocked cells
1;9
9;11
13;13
12;4
4;4
8;8
15;4

# path
0,13
1,13
2,13
3,13
4,13
4,12
4,11
4,10
5,10
6,10
7,10
7,11
7,12
7,13
8,13
9,13
10,13
11,13
11,12
11,11
11,10
12,10
13,10
14,10
14,9
14,8
14,7
14,6
13,6
12,6
11,6
10,6
10,5
10,4
10,3
9,3
8,3
7,3
6,3
6,4
6,5
6,6
5,6
4,6
3,6
2,6
2,5
2,4
2,3
2,2
2,1
3,1
4,1
5,1
6,1
7,1
8,1
9,1
10,1
11,1
12,1
13,1
14,1
15,1
"""#)

    public static let neon: GameMap = try! GameMap.parse(id: "neon", name: "Neon", text: #"""
###
### NEON – own map of CreepSmash iOS
###

map_neon.jpg

SET_ALPHA_BACKGROUND_COLOR:OFF

# blocked cells

# path
0,14
1,14
2,14
3,14
4,14
5,14
6,14
7,14
8,14
9,14
10,14
11,14
12,14
13,14
13,13
13,12
13,11
12,11
11,11
10,11
9,11
8,11
7,11
6,11
5,11
4,11
3,11
2,11
2,10
2,9
2,8
3,8
4,8
5,8
6,8
7,8
8,8
9,8
10,8
11,8
12,8
13,8
13,7
13,6
13,5
12,5
11,5
10,5
9,5
8,5
7,5
6,5
5,5
4,5
3,5
2,5
2,4
2,3
2,2
3,2
4,2
5,2
6,2
7,2
8,2
9,2
10,2
11,2
12,2
13,2
14,2
15,2
"""#)

    public static let spirale: GameMap = try! GameMap.parse(id: "spirale", name: "Spiral", text: #"""
###
### SPIRAL – own map of CreepSmash iOS
###

map_spirale.jpg

SET_ALPHA_BACKGROUND_COLOR:OFF

# blocked cells

# path
0,13
1,13
2,13
3,13
4,13
5,13
6,13
7,13
8,13
9,13
10,13
11,13
12,13
13,13
13,12
13,11
13,10
13,9
13,8
13,7
13,6
13,5
13,4
13,3
13,2
12,2
11,2
10,2
9,2
8,2
7,2
6,2
5,2
4,2
3,2
2,2
2,3
2,4
2,5
2,6
2,7
2,8
2,9
2,10
3,10
4,10
5,10
6,10
7,10
8,10
9,10
10,10
10,9
10,8
10,7
10,6
10,5
9,5
8,5
7,5
6,5
5,5
5,6
5,7
6,7
7,7
"""#)

    public static let canyon: GameMap = try! GameMap.parse(id: "canyon", name: "Canyon", text: #"""
###
### CANYON – own map of CreepSmash iOS
###

map_canyon.jpg

SET_ALPHA_BACKGROUND_COLOR:OFF

# blocked cells
2;6
3;6
2;7
9;8
9;9
13;9
14;9
13;10
3;13
4;14
8;1
13;1
14;2

# path
0,3
1,3
2,3
3,3
4,3
5,3
6,3
6,4
6,5
6,6
6,7
6,8
6,9
6,10
6,11
6,12
7,12
8,12
9,12
10,12
11,12
11,11
11,10
11,9
11,8
11,7
11,6
11,5
12,5
13,5
14,5
15,5
"""#)

    public static let platine: GameMap = try! GameMap.parse(id: "platine", name: "Circuit", text: #"""
###
### CIRCUIT – own map of CreepSmash iOS
###

map_platine.jpg

SET_ALPHA_BACKGROUND_COLOR:OFF

# blocked cells
1;1
1;2
5;6
5;7
5;10
11;2
12;2
11;9
15;14
14;14
1;13

# path
0,8
1,8
2,8
3,8
3,7
3,6
3,5
3,4
3,3
4,3
5,3
6,3
7,3
7,4
7,5
7,6
7,7
7,8
7,9
7,10
7,11
7,12
7,13
8,13
9,13
10,13
10,12
10,11
10,10
10,9
10,8
10,7
10,6
11,6
12,6
13,6
13,7
13,8
13,9
13,10
13,11
14,11
15,11
"""#)

    public static let vulkan: GameMap = try! GameMap.parse(id: "vulkan", name: "Volcano", text: #"""
###
### VOLCANO – own map of CreepSmash iOS
###

map_vulkan.jpg

SET_ALPHA_BACKGROUND_COLOR:OFF

# blocked cells
2;7
5;4
6;10
8;6
9;12
11;3
12;9
15;8
14;12

# path
1,15
1,14
1,13
1,12
1,11
1,10
1,9
1,8
1,7
1,6
1,5
1,4
1,3
1,2
1,1
2,1
3,1
4,1
4,2
4,3
4,4
4,5
4,6
4,7
4,8
4,9
4,10
4,11
4,12
4,13
4,14
5,14
6,14
7,14
7,13
7,12
7,11
7,10
7,9
7,8
7,7
7,6
7,5
7,4
7,3
7,2
7,1
8,1
9,1
10,1
10,2
10,3
10,4
10,5
10,6
10,7
10,8
10,9
10,10
10,11
10,12
10,13
10,14
11,14
12,14
13,14
13,13
13,12
13,11
13,10
13,9
13,8
13,7
13,6
13,5
13,4
13,3
13,2
13,1
14,1
15,1
"""#)

    public static let rennbahn: GameMap = try! GameMap.parse(id: "rennbahn", name: "Raceway", text: #"""
###
### RACEWAY – own map of CreepSmash iOS
###

map_rennbahn.jpg

SET_ALPHA_BACKGROUND_COLOR:OFF

# blocked cells
6;7
7;7
8;7
9;7
6;8
7;8
8;8
9;8

# path
0,12
1,12
2,12
4,12
6,12
8,12
10,12
12,12
13,12
13,11
13,9
13,7
13,5
13,4
13,3
12,3
10,3
8,3
6,3
4,3
3,3
2,3
2,4
2,6
2,8
2,10
2,11
2,12
4,12
6,12
8,12
10,12
12,12
13,12
13,11
13,9
13,7
13,5
13,4
13,3
12,3
10,3
8,3
6,3
4,3
3,3
2,3
2,4
2,6
2,8
2,10
2,11
2,12
4,12
6,12
8,12
10,12
12,12
13,12
13,11
13,9
13,7
13,5
13,4
13,3
14,3
15,3
"""#)

    public static let wurmloch: GameMap = try! GameMap.parse(id: "wurmloch", name: "Wormhole", text: #"""
###
### WORMHOLE – own map of CreepSmash iOS
###

map_wurmloch.jpg

SET_ALPHA_BACKGROUND_COLOR:OFF

# blocked cells

# path
0,2
1,2
2,2
3,2
4,2
5,2
5,3
5,4
5,5
5,6
4,6
3,6
2,6
1,6
1,7
1,8
1,9
1,10
2,10
3,10
4,10
5,10
6,10
10,2
11,2
12,2
13,2
14,2
14,3
14,4
14,5
14,6
14,7
13,7
12,7
11,7
10,7
10,8
10,9
10,10
3,12
3,13
3,14
4,14
5,14
6,14
7,14
8,14
9,14
10,14
11,14
12,14
12,13
12,12
12,11
13,11
14,11
15,11
"""#)

    public static let polarlicht: GameMap = try! GameMap.parse(id: "polarlicht", name: "Aurora", text: #"""
###
### AURORA – own map of CreepSmash iOS
###

map_polarlicht.jpg

SET_ALPHA_BACKGROUND_COLOR:OFF

# blocked cells
6;4
5;12
13;13
15;4
10;6
1;12

# path
0,9
1,9
2,9
3,9
3,8
3,7
3,6
3,5
3,4
3,3
3,2
3,3
3,4
3,5
3,6
3,7
3,8
3,9
4,9
5,9
6,9
7,9
8,9
8,10
8,11
8,12
8,13
8,14
8,13
8,12
8,11
8,10
8,9
9,9
10,9
11,9
12,9
12,8
12,7
12,6
12,5
12,4
12,3
12,4
12,5
12,6
12,7
12,8
12,9
13,9
14,9
15,9
"""#)

    public static let kreuzung: GameMap = try! GameMap.parse(id: "kreuzung", name: "Crossroads", text: #"""
###
### CROSSROADS – own map of CreepSmash iOS
###

map_kreuzung.jpg

SET_ALPHA_BACKGROUND_COLOR:OFF

# blocked cells

# path
0,10
1,10
2,10
3,10
4,10
5,10
6,10
7,10
8,10
9,10
10,10
10,9
10,8
10,7
10,6
10,5
10,4
10,3
9,3
8,3
7,3
6,3
5,3
5,4
5,5
5,6
5,7
5,8
5,9
5,10
5,11
5,12
5,13
6,13
7,13
8,13
9,13
10,13
11,13
12,13
13,13
13,12
13,11
13,10
13,9
13,8
13,7
12,7
11,7
10,7
9,7
8,7
7,7
6,7
5,7
4,7
3,7
2,7
2,6
2,5
2,4
2,3
2,2
2,1
3,1
4,1
5,1
6,1
7,1
8,1
9,1
10,1
11,1
12,1
13,1
14,1
15,1
"""#)

    public static let mahlstrom: GameMap = try! GameMap.parse(id: "mahlstrom", name: "Maelstrom", text: #"""
###
### MAELSTROM – own map of CreepSmash iOS
###

map_mahlstrom.jpg

SET_ALPHA_BACKGROUND_COLOR:OFF

# blocked cells

# path
0,1
1,1
2,1
3,1
4,1
5,1
6,1
7,1
8,1
9,1
10,1
11,1
12,1
13,1
14,1
14,2
14,3
14,4
14,5
14,6
14,7
14,8
14,9
14,10
14,11
14,12
14,13
14,14
13,14
12,14
11,14
10,14
9,14
8,14
7,14
6,14
5,14
4,14
3,14
2,14
1,14
1,13
1,12
1,11
1,10
1,9
1,8
1,7
1,6
1,5
1,4
2,4
3,4
4,4
5,4
6,4
7,4
8,4
9,4
10,4
11,4
11,5
11,6
11,7
11,8
11,9
11,10
11,11
10,11
9,11
8,11
7,11
6,11
5,11
4,11
4,10
4,9
4,8
4,7
5,7
6,7
7,7
8,7
8,11
8,15
"""#)

    public static let pendel: GameMap = try! GameMap.parse(id: "pendel", name: "Pendulum", text: #"""
###
### PENDULUM – own map of CreepSmash iOS
###

map_pendel.jpg

SET_ALPHA_BACKGROUND_COLOR:OFF

# blocked cells
8;11
15;6
6;7

# path
0,2
1,2
2,2
3,2
4,2
5,2
6,2
7,2
8,2
9,2
10,2
11,2
12,2
12,3
12,4
12,5
11,5
10,5
9,5
8,5
7,5
6,5
5,5
4,5
3,5
2,5
2,6
2,7
2,8
2,9
3,9
4,9
5,9
6,9
7,9
8,9
9,9
10,9
11,9
12,9
13,9
14,9
12,9
10,9
8,9
6,9
4,9
2,9
2,10
2,11
2,12
2,13
3,13
4,13
5,13
6,13
7,13
8,13
9,13
10,13
11,13
12,13
13,13
14,13
11,13
8,13
5,13
2,13
2,14
2,15
"""#)

    public static let asteroiden: GameMap = try! GameMap.parse(id: "asteroiden", name: "Asteroids", text: #"""
###
### ASTEROIDS – own map of CreepSmash iOS
###

map_asteroiden.jpg

SET_ALPHA_BACKGROUND_COLOR:OFF

# blocked cells
5;1
5;2
12;9
8;14
9;14
3;7
14;13
1;6
8;5
11;5

# path
0,1
1,2
2,3
3,4
4,5
5,6
6,5
7,4
8,3
9,2
10,1
11,2
12,3
13,4
14,5
14,6
14,7
14,8
14,9
13,10
12,11
11,12
10,13
9,12
8,11
7,10
6,9
5,10
4,11
3,12
2,13
2,14
2,15
"""#)

    public static let stromschnellen: GameMap = try! GameMap.parse(id: "stromschnellen", name: "Rapids", text: #"""
###
### RAPIDS – own map of CreepSmash iOS
###

map_stromschnellen.jpg

SET_ALPHA_BACKGROUND_COLOR:OFF

# blocked cells
11;7
7;9
1;5
15;8
9;12

# path
3,0
3,1
3,2
3,3
4,3
5,3
6,3
7,3
8,3
8,2
8,1
9,1
10,1
11,1
12,1
13,1
13,2
13,3
13,4
13,6
13,8
13,10
12,10
11,10
10,10
9,10
9,9
9,8
9,7
9,6
8,6
7,6
6,6
5,6
5,9
5,12
5,13
5,14
6,14
7,14
8,14
9,14
10,14
11,14
11,13
11,12
12,12
13,12
14,12
15,12
"""#)

    /// All built-in maps in the order shown in the selection.
    public static let all: [GameMap] = [.blue, .neon, .spirale, .canyon, .platine, .vulkan, .rennbahn, .wurmloch, .polarlicht, .kreuzung, .mahlstrom, .pendel, .asteroiden, .stromschnellen]

    public static func named(_ id: String) -> GameMap? { all.first { $0.id == id } }
}
