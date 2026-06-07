#!/usr/bin/env python3
"""Generates Godot .tscn / .tres resources whose frame data is too verbose to
hand-author: the player's 12 directional animations and the enemy SpriteFrames.

Run from the project root:  python3 tools/gen_resources.py
"""
import os, itertools

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

_id = itertools.count(1)
def nid(prefix="r"):
    return f"{prefix}{next(_id)}"

def atlas_subs(ext_id, regions):
    """Return (list_of_sub_ids, text_block) for AtlasTexture sub-resources."""
    ids, blocks = [], []
    for (x, y, w, h) in regions:
        sid = nid("atlas")
        ids.append(sid)
        blocks.append(
            f'[sub_resource type="AtlasTexture" id="{sid}"]\n'
            f'atlas = ExtResource("{ext_id}")\n'
            f'region = Rect2({x}, {y}, {w}, {h})\n'
        )
    return ids, "".join(blocks)

def anim_dict(name, sub_ids, speed, loop):
    frames = ", ".join(
        '{\n"duration": 1.0,\n"texture": SubResource("%s")\n}' % s for s in sub_ids
    )
    return '{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %s\n}' % (
        frames, "true" if loop else "false", name, float(speed)
    )

# ---------------------------------------------------------------------------
# Player: scenes/player.tscn
# ---------------------------------------------------------------------------
def gen_player():
    global _id
    _id = itertools.count(1)
    FW, FH, NF = 96, 80, 8  # frame w/h, frames per strip (768x80 / 96)
    strip = [(i * FW, 0, FW, FH) for i in range(NF)]

    base = "res://assets/sprites/FREE_Adventurer 2D Pixel Art/Sprites"
    # (anim_name, subfolder/file, uid, speed, loop)
    specs = [
        ("idle_down",  "IDLE/idle_down",   "o1uk5ehcmtq3", 6, True),
        ("idle_up",    "IDLE/idle_up",     "bif0uin4umhbx", 6, True),
        ("idle_left",  "IDLE/idle_left",   "csi1t6oiwsubw", 6, True),
        ("idle_right", "IDLE/idle_right",  "lhwsgpol0vtc",  6, True),
        ("run_down",   "RUN/run_down",     "g7fpphgtnvq2", 12, True),
        ("run_up",     "RUN/run_up",       "c2wnh5vgn8afi", 12, True),
        ("run_left",   "RUN/run_left",     "da47fgjq1qjg3", 12, True),
        ("run_right",  "RUN/run_right",    "bbqmsghtyc0dr", 12, True),
        ("attack_down","ATTACK 1/attack1_down",  "bd3xp5jtgu1cf", 14, False),
        ("attack_up",  "ATTACK 1/attack1_up",    "5243g441u2m1",  14, False),
        ("attack_left","ATTACK 1/attack1_left",  "xw71kse8tmry",  14, False),
        ("attack_right","ATTACK 1/attack1_right","cgxekvvngsyj1", 14, False),
    ]

    ext_blocks, sub_blocks, anims = [], [], []
    ext_count = 0
    for name, rel, uid, speed, loop in specs:
        ext_count += 1
        eid = f"t{ext_count}"
        ext_blocks.append(
            f'[ext_resource type="Texture2D" uid="uid://{uid}" '
            f'path="{base}/{rel}.png" id="{eid}"]\n'
        )
        ids, block = atlas_subs(eid, strip)
        sub_blocks.append(block)
        anims.append(anim_dict(name, ids, speed, loop))

    sf_id = nid("sf")
    load_steps = ext_count + sum(NF for _ in specs) + 2 + 1  # ext + atlases + sf + shape, +1 script
    header = f'[gd_scene load_steps={load_steps} format=3 uid="uid://dvb4ma1eql0id"]\n\n'
    script = '[ext_resource type="Script" uid="uid://bnh82xx6fkcps" path="res://scripts/player.gd" id="player_script"]\n'
    sframes = (
        f'[sub_resource type="SpriteFrames" id="{sf_id}"]\n'
        f'animations = [{", ".join(anims)}]\n'
    )
    shape_id = nid("shape")
    shape = (
        f'[sub_resource type="RectangleShape2D" id="{shape_id}"]\n'
        f'size = Vector2(34, 44)\n'
    )
    nodes = (
        '[node name="Player" type="CharacterBody2D"]\n'
        'collision_layer = 1\n'
        'collision_mask = 1\n'
        'script = ExtResource("player_script")\n\n'
        '[node name="AnimatedSprite2D" type="AnimatedSprite2D" parent="."]\n'
        'scale = Vector2(2, 2)\n'
        f'sprite_frames = SubResource("{sf_id}")\n'
        'animation = &"idle_down"\n'
        'autoplay = "idle_down"\n\n'
        '[node name="CollisionShape2D" type="CollisionShape2D" parent="."]\n'
        'position = Vector2(0, 12)\n'
        f'shape = SubResource("{shape_id}")\n'
    )
    out = header + script + "".join(ext_blocks) + "\n" + "".join(sub_blocks) + sframes + shape + "\n" + nodes
    write("scenes/player.tscn", out)

# ---------------------------------------------------------------------------
# Enemy SpriteFrames .tres files
# ---------------------------------------------------------------------------
def gen_frames(path, uid_self, anims_spec):
    """anims_spec: list of (anim_name, [(ext_uid, ext_path, [regions])], speed, loop)
    Each animation can pull frames from one texture."""
    global _id
    _id = itertools.count(1)
    ext_lines, sub_blocks, anims = [], [], []
    ext_map = {}
    ext_count = 0
    total_atlas = 0
    for name, src_uid, src_path, regions, speed, loop in anims_spec:
        if src_uid not in ext_map:
            ext_count += 1
            eid = f"t{ext_count}"
            ext_map[src_uid] = eid
            ext_lines.append(
                f'[ext_resource type="Texture2D" uid="uid://{src_uid}" path="{src_path}" id="{eid}"]\n'
            )
        eid = ext_map[src_uid]
        ids, block = atlas_subs(eid, regions)
        total_atlas += len(regions)
        sub_blocks.append(block)
        anims.append(anim_dict(name, ids, speed, loop))
    load_steps = ext_count + total_atlas + 1
    header = f'[gd_resource type="SpriteFrames" load_steps={load_steps} format=3 uid="uid://{uid_self}"]\n\n'
    body = "".join(ext_lines) + "\n" + "".join(sub_blocks)
    res = f'[resource]\nanimations = [{", ".join(anims)}]\n'
    write(path, header + body + res)

def grid(cols, frame_w, frame_h, row):
    return [(c * frame_w, row * frame_h, frame_w, frame_h) for c in range(cols)]

def write(rel, text):
    full = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as f:
        f.write(text)
    print("wrote", rel)

# ---- Ant: Ants.png 1080x768, cells 90x96 (12 cols x 8 rows), brown = cols 0-2
# row 3 = top-down walk (faces up); row 5 = splayed dead pose
A = "res://assets/sprites/Ants.png"
ant_anims = [
    ("move",     "c305vhlbj30b3", A, grid(3, 90, 96, 3), 6, True),
    ("squashed", "c305vhlbj30b3", A, grid(3, 90, 96, 5), 6, False),
]
# ---- Beetle (Level 2 "fly"): BeetleMove rows 0=down 1=left 2=right 3=up; BeetleAttack rows 0=down 1=right 2=left 3=up.
# BeetleMove 128x128 (32x32, 4 cols x 4 rows); BeetleAttack 192x128 (6 cols x 4 rows).
B_MOVE_UID, B_MOVE = "2ot7o7kck1qx", "res://assets/sprites/BeetleMove.png"
B_ATK_UID,  B_ATK  = "biejstprque7i", "res://assets/sprites/BeetleAttack.png"
beetle_anims = [
    ("default",      B_MOVE_UID, B_MOVE, grid(4, 32, 32, 0), 9,  True),   # autoplay alias
    ("walk_down",    B_MOVE_UID, B_MOVE, grid(4, 32, 32, 0), 9,  True),
    ("walk_left",    B_MOVE_UID, B_MOVE, grid(4, 32, 32, 1), 9,  True),
    ("walk_right",   B_MOVE_UID, B_MOVE, grid(4, 32, 32, 2), 9,  True),
    ("walk_up",      B_MOVE_UID, B_MOVE, grid(4, 32, 32, 3), 9,  True),
    ("attack_down",  B_ATK_UID,  B_ATK,  grid(6, 32, 32, 0), 10, True),
    ("attack_left",  B_ATK_UID,  B_ATK,  grid(6, 32, 32, 2), 10, True),
    ("attack_right", B_ATK_UID,  B_ATK,  grid(6, 32, 32, 1), 10, True),
    ("attack_up",    B_ATK_UID,  B_ATK,  grid(6, 32, 32, 3), 10, True),
]
# ---- Level 1 bugs: Bugs.png 1080x768, 90x96 cells. Top-down walk on row 0; 4 colours
# in column groups of 3 (brown 0-2, dark 3-5, olive 6-8, maroon 9-11). Rendered like the
# ant: a single "move" loop rotated to face travel (sprite_forward = UP). No death frame,
# so the squash is done in code (bug.gd `splatter`).
BUGS_UID, BUGS = "cuhlqb87i3uva", "res://assets/sprites/Bugs.png"
def bug_anims(col0):
    regions = [(c * 90, 0, 90, 96) for c in (col0, col0 + 1, col0 + 2)]
    return [("move", BUGS_UID, BUGS, regions, 6, True)]

# ---- Boss: Mantis, same 4-direction layout (rows 0=down 1=right 2=left 3=up).
# MantisMove 128x128 (4 cols x 4 rows); MantisAttack 224x128 (7 cols x 4 rows). No death frame.
M_MOVE_UID, M_MOVE = "drq7ynxek8vim", "res://assets/sprites/MantisMove.png"
M_ATK_UID,  M_ATK  = "c5ghgkvu1bmgu", "res://assets/sprites/MantisAttack.png"
boss_anims = [
    ("default",      M_MOVE_UID, M_MOVE, grid(4, 32, 32, 0), 8,  True),   # autoplay alias
    ("walk_down",    M_MOVE_UID, M_MOVE, grid(4, 32, 32, 0), 8,  True),
    ("walk_left",    M_MOVE_UID, M_MOVE, grid(4, 32, 32, 2), 8,  True),
    ("walk_right",   M_MOVE_UID, M_MOVE, grid(4, 32, 32, 1), 8,  True),
    ("walk_up",      M_MOVE_UID, M_MOVE, grid(4, 32, 32, 3), 8,  True),
    ("attack_down",  M_ATK_UID,  M_ATK,  grid(7, 32, 32, 0), 10, True),
    ("attack_left",  M_ATK_UID,  M_ATK,  grid(7, 32, 32, 2), 10, True),
    ("attack_right", M_ATK_UID,  M_ATK,  grid(7, 32, 32, 1), 10, True),
    ("attack_up",    M_ATK_UID,  M_ATK,  grid(7, 32, 32, 3), 10, True),
]

if __name__ == "__main__":
    gen_player()
    gen_frames("scenes/frames/ant_frames.tres",    "b0antfr0001a", ant_anims)
    gen_frames("scenes/frames/beetle_frames.tres", "b0beetfr001a", beetle_anims)
    gen_frames("scenes/frames/boss_frames.tres",   "b0bossfr001a", boss_anims)
    gen_frames("scenes/frames/bug_brown_frames.tres",  "b0bugbrn001a", bug_anims(0))
    gen_frames("scenes/frames/bug_dark_frames.tres",   "b0bugdrk001a", bug_anims(3))
    gen_frames("scenes/frames/bug_olive_frames.tres",  "b0bugolv001a", bug_anims(6))
    gen_frames("scenes/frames/bug_maroon_frames.tres", "b0bugmrn001a", bug_anims(9))
    print("done")
