"""
animations — the BASE ANIMATIONS (Part 7.4), keyed on the Rigify FK controls: idle-loop, walk-loop, run-loop, jump, attack, hit, die.
Each body style (upright, hunched, stocky, lanky, quadruped, flyer) has its own numbers so a grunt does not walk like a brute.
All rotations are about WORLD axes; with the character facing +Y, +X rotation swings a hanging limb FORWARD, -X swings it back.
Godot imports the "-loop" suffix as looping.
"""
import math
import pn_organic as po

# style -> numbers (degrees / metres at figure scale 1). swing = leg swing, knee = knee flex, arm = arm swing, bob = body bob, lean = forward lean
STYLES = {
    'upright':  dict(swing=26, knee=38, arm=22, bob=0.025, lean=3, twist=6, sway=2, speed=1.0),
    'hunched':  dict(swing=34, knee=46, arm=30, bob=0.035, lean=8, twist=9, sway=3, speed=1.15),
    'stocky':   dict(swing=22, knee=30, arm=26, bob=0.030, lean=2, twist=4, sway=7, speed=1.2),
    'lanky':    dict(swing=22, knee=50, arm=16, bob=0.045, lean=5, twist=8, sway=2, speed=0.85),
    'quadruped': dict(swing=30, knee=34, arm=0, bob=0.02, lean=0, twist=3, sway=2, speed=1.0),
    'flyer':    dict(swing=6, knee=10, arm=0, bob=0.05, lean=4, twist=2, sway=2, speed=1.0),
}
LOOPS = {'idle-loop', 'walk-loop', 'run-loop'}


def _leg(side, thigh, shin, foot):
    return {f'thigh_fk.{side}': {'rot': [('x', thigh)]}, f'shin_fk.{side}': {'rot': [('x', shin)]}, f'foot_fk.{side}': {'rot': [('x', foot)]}}


def _fleg(side, thigh, shin, foot):
    return {f'front_thigh_fk.{side}': {'rot': [('x', thigh)]}, f'front_shin_fk.{side}': {'rot': [('x', shin)]}, f'front_foot_fk.{side}': {'rot': [('x', foot)]}}


def _merge(*ds):
    out = {}
    for d in ds:
        for k, v in d.items():
            cur = out.setdefault(k, {'rot': []})
            cur['rot'] = cur.get('rot', []) + v.get('rot', [])
            if 'loc' in v:
                cur['loc'] = v['loc']
    return out


def biped_walk(rig, st, scale, frames, fast=1.0, name='walk-loop'):
    act = po.new_action(rig, name, True)
    F = frames
    for f in range(0, F + 1, 2):
        ph = 2 * math.pi * f / F
        pose = {}
        for side, off in (('L', 0.0), ('R', math.pi)):
            p = ph + off
            thigh = st['swing'] * fast * math.sin(p)
            shin = -st['knee'] * fast * max(0.0, math.cos(p))
            foot = -(thigh + shin) * 0.55
            pose = _merge(pose, _leg(side, thigh, shin, foot))
            arm = -st['arm'] * fast * math.sin(p)
            pose = _merge(pose, {f'upper_arm_fk.{side}': {'rot': [('x', arm)]}, f'forearm_fk.{side}': {'rot': [('x', 14 + 10 * fast * max(0.0, math.sin(p)))]}})
        pose = _merge(pose, {'torso': {'rot': [('z', st['twist'] * math.sin(ph)), ('x', -st['lean'] * fast), ('y', st['sway'] * math.sin(ph))], 'loc': (0, 0, -st['bob'] * scale * (0.5 + 0.5 * abs(math.cos(ph))) * fast)},
                            'head': {'rot': [('z', -st['twist'] * 0.6 * math.sin(ph))]}})
        po.key_pose(rig, f + 1, pose)
    po.finish_action(rig, act, True)


def biped_idle(rig, st, scale, frames=48):
    act = po.new_action(rig, 'idle-loop', True)
    for f in range(0, frames + 1, 8):
        ph = 2 * math.pi * f / frames
        pose = {'chest': {'rot': [('x', 1.6 * math.sin(ph))]}, 'head': {'rot': [('x', -1.5 * math.sin(ph)), ('z', 3 * math.sin(ph * 0.5))]},
                'torso': {'rot': [('y', st['sway'] * 0.4 * math.sin(ph * 0.5))], 'loc': (0, 0, 0.006 * scale * math.sin(ph))},
                'upper_arm_fk.L': {'rot': [('x', 2.5 * math.sin(ph))]}, 'upper_arm_fk.R': {'rot': [('x', -2.5 * math.sin(ph))]}}
        po.key_pose(rig, f + 1, pose)
    po.finish_action(rig, act, True)


def biped_attack(rig, st, scale):
    act = po.new_action(rig, 'attack', False)
    keys = {
        1: {},
        5: {'upper_arm_fk.R': {'rot': [('x', -75)]}, 'forearm_fk.R': {'rot': [('x', 50)]}, 'torso': {'rot': [('z', -18), ('x', 6)]}},
        9: {'upper_arm_fk.R': {'rot': [('x', 95)]}, 'forearm_fk.R': {'rot': [('x', 5)]}, 'torso': {'rot': [('z', 20), ('x', -10)], 'loc': (0, 0.09 * scale, -0.02 * scale)}, 'thigh_fk.L': {'rot': [('x', 25)]}, 'thigh_fk.R': {'rot': [('x', -12)]}},
        14: {'upper_arm_fk.R': {'rot': [('x', 60)]}, 'torso': {'rot': [('z', 8)], 'loc': (0, 0.04 * scale, 0)}},
        20: {},
    }
    for f, pose in keys.items():
        po.key_pose(rig, f, pose or {'torso': {'rot': []}, 'upper_arm_fk.R': {'rot': []}})
    po.finish_action(rig, act, False)


def biped_hit(rig, st, scale):
    act = po.new_action(rig, 'hit', False)
    for f, pose in {1: {}, 4: {'torso': {'rot': [('x', 14), ('z', 8)], 'loc': (0, -0.05 * scale, 0)}, 'head': {'rot': [('x', 18)]}, 'upper_arm_fk.L': {'rot': [('x', -20)]}, 'upper_arm_fk.R': {'rot': [('x', -20)]}},
                    9: {'torso': {'rot': [('x', 6)]}}, 14: {}}.items():
        po.key_pose(rig, f, pose or {'torso': {'rot': []}})
    po.finish_action(rig, act, False)


def biped_die(rig, st, scale, side=False):
    act = po.new_action(rig, 'die', False)
    fall = (lambda deg: [('y', -deg)]) if side else (lambda deg: [('x', deg)])   # a hunched body topples sideways, an upright one falls back
    for f, pose in {1: {}, 6: {'thigh_fk.L': {'rot': [('x', 18)]}, 'thigh_fk.R': {'rot': [('x', 18)]}, 'shin_fk.L': {'rot': [('x', -40)]}, 'shin_fk.R': {'rot': [('x', -40)]}, 'torso': {'rot': [('x', 14)], 'loc': (0, 0, -0.2 * scale)}},
                    16: {'root': {'rot': fall(62), 'loc': (0, -0.15 * scale, 0)}, 'thigh_fk.L': {'rot': [('x', 20)]}, 'thigh_fk.R': {'rot': [('x', 10)]}, 'upper_arm_fk.L': {'rot': [('x', -50)]}, 'upper_arm_fk.R': {'rot': [('x', -35)]}},
                    26: {'root': {'rot': fall(90), 'loc': (0, -0.3 * scale, 0)}, 'upper_arm_fk.L': {'rot': [('x', -60)]}, 'upper_arm_fk.R': {'rot': [('x', -50)]}}}.items():
        po.key_pose(rig, f, pose or {'torso': {'rot': []}})
    po.finish_action(rig, act, False)


def biped_jump(rig, st, scale):
    act = po.new_action(rig, 'jump', False)
    crouch = {'thigh_fk.L': {'rot': [('x', 38)]}, 'thigh_fk.R': {'rot': [('x', 38)]}, 'shin_fk.L': {'rot': [('x', -62)]}, 'shin_fk.R': {'rot': [('x', -62)]}, 'torso': {'rot': [('x', -14)], 'loc': (0, 0, -0.16 * scale)},
              'upper_arm_fk.L': {'rot': [('x', -35)]}, 'upper_arm_fk.R': {'rot': [('x', -35)]}}
    air = {'thigh_fk.L': {'rot': [('x', 14)]}, 'thigh_fk.R': {'rot': [('x', -6)]}, 'shin_fk.L': {'rot': [('x', -30)]}, 'shin_fk.R': {'rot': [('x', -12)]}, 'torso': {'rot': [('x', 2)], 'loc': (0, 0, 0.22 * scale)},
           'upper_arm_fk.L': {'rot': [('x', 150)]}, 'upper_arm_fk.R': {'rot': [('x', 150)]}}
    for f, pose in {1: {}, 5: crouch, 11: air, 18: air, 24: crouch, 30: {}}.items():
        po.key_pose(rig, f, pose or {'torso': {'rot': []}})
    po.finish_action(rig, act, False)


# ---- quadruped
def quad_walk(rig, st, scale, frames, fast=1.0, name='walk-loop'):
    act = po.new_action(rig, name, True)
    F = frames
    for f in range(0, F + 1, 2):
        ph = 2 * math.pi * f / F
        pose = {}
        for fs, rs, off in (('L', 'R', 0.0), ('R', 'L', math.pi)):     # diagonal pairs move together
            p = ph + off
            pose = _merge(pose, _fleg(fs, st['swing'] * fast * math.sin(p), -st['knee'] * fast * max(0.0, math.cos(p)), 0),
                          _leg(rs, st['swing'] * fast * math.sin(p + math.pi), st['knee'] * 0.8 * fast * max(0.0, math.cos(p + math.pi)), 0))
        pose = _merge(pose, {'torso': {'rot': [('z', st['twist'] * math.sin(ph)), ('y', st['sway'] * math.sin(ph))], 'loc': (0, 0, -st['bob'] * scale * abs(math.cos(ph)) * fast)},
                             'head': {'rot': [('x', 5 * math.sin(2 * ph))]}, 'spine.002': {'rot': [('z', 18 * math.sin(ph))]}, 'spine.001': {'rot': [('z', 24 * math.sin(ph - 0.6))]}})
        po.key_pose(rig, f + 1, pose)
    po.finish_action(rig, act, True)


def quad_idle(rig, st, scale, frames=48):
    act = po.new_action(rig, 'idle-loop', True)
    for f in range(0, frames + 1, 8):
        ph = 2 * math.pi * f / frames
        po.key_pose(rig, f + 1, {'chest': {'rot': [('x', 1.5 * math.sin(ph))]}, 'head': {'rot': [('x', 3 * math.sin(ph * 0.5)), ('z', 6 * math.sin(ph))]},
                                 'spine.002': {'rot': [('z', 14 * math.sin(ph))]}, 'spine.001': {'rot': [('z', 20 * math.sin(ph - 0.6))]}})
    po.finish_action(rig, act, True)


def quad_attack(rig, st, scale):
    act = po.new_action(rig, 'attack', False)
    for f, pose in {1: {}, 5: {'torso': {'rot': [('x', 12)], 'loc': (0, -0.08 * scale, 0)}, 'head': {'rot': [('x', 20)]}},
                    9: {'torso': {'rot': [('x', -14)], 'loc': (0, 0.18 * scale, -0.03 * scale)}, 'head': {'rot': [('x', -26)]}, 'front_thigh_fk.L': {'rot': [('x', 40)]}, 'front_thigh_fk.R': {'rot': [('x', 40)]}},
                    16: {'torso': {'rot': [('x', -3)], 'loc': (0, 0.05 * scale, 0)}}, 22: {}}.items():
        po.key_pose(rig, f, pose or {'torso': {'rot': []}})
    po.finish_action(rig, act, False)


def quad_hit(rig, st, scale):
    act = po.new_action(rig, 'hit', False)
    for f, pose in {1: {}, 4: {'torso': {'rot': [('x', 10)], 'loc': (0, -0.07 * scale, 0)}, 'head': {'rot': [('x', 22)]}}, 14: {}}.items():
        po.key_pose(rig, f, pose or {'torso': {'rot': []}})
    po.finish_action(rig, act, False)


def quad_die(rig, st, scale):
    act = po.new_action(rig, 'die', False)
    for f, pose in {1: {}, 10: {'torso': {'loc': (0, 0, -0.18 * scale), 'rot': [('y', 20)]}, 'front_thigh_fk.L': {'rot': [('x', 30)]}, 'front_thigh_fk.R': {'rot': [('x', 30)]}},
                    22: {'root': {'rot': [('y', 80)], 'loc': (0, 0, 0.05 * scale)}, 'torso': {'loc': (0, 0, -0.1 * scale), 'rot': []}}}.items():
        po.key_pose(rig, f, pose or {'torso': {'rot': []}})
    po.finish_action(rig, act, False)


def quad_jump(rig, st, scale):
    act = po.new_action(rig, 'jump', False)
    crouch = {'torso': {'rot': [('x', 10)], 'loc': (0, 0, -0.1 * scale)}, 'thigh_fk.L': {'rot': [('x', 30)]}, 'thigh_fk.R': {'rot': [('x', 30)]}}
    air = {'torso': {'rot': [('x', -12)], 'loc': (0, 0, 0.2 * scale)}, 'front_thigh_fk.L': {'rot': [('x', 60)]}, 'front_thigh_fk.R': {'rot': [('x', 60)]}, 'thigh_fk.L': {'rot': [('x', -35)]}, 'thigh_fk.R': {'rot': [('x', -35)]}}
    for f, pose in {1: {}, 5: crouch, 11: air, 18: air, 24: crouch, 30: {}}.items():
        po.key_pose(rig, f, pose or {'torso': {'rot': []}})
    po.finish_action(rig, act, False)


# ---- flyer: the arms are wings; flap about the world Y axis (+ = wing tip down on the left, mirrored on the right)
def flyer_flap(rig, st, scale, frames, amp, name, loop=True, bob=0.05):
    act = po.new_action(rig, name, loop)
    for f in range(0, frames + 1, 2):
        ph = 2 * math.pi * f / frames
        a = amp * math.sin(ph)
        lag = amp * 0.7 * math.sin(ph - 0.7)
        po.key_pose(rig, f + 1, {
            'upper_arm_fk.L': {'rot': [('y', a)]}, 'upper_arm_fk.R': {'rot': [('y', -a)]},
            'forearm_fk.L': {'rot': [('y', lag * 0.6)]}, 'forearm_fk.R': {'rot': [('y', -lag * 0.6)]},
            'torso': {'loc': (0, 0, -bob * scale * math.sin(ph)), 'rot': [('x', -st['lean'] + 3 * math.sin(ph))]},
            'thigh_fk.L': {'rot': [('x', 8 * math.sin(ph - 0.5))]}, 'thigh_fk.R': {'rot': [('x', 8 * math.sin(ph - 0.5))]}})
    po.finish_action(rig, act, loop)


def flyer_oneshots(rig, st, scale):
    act = po.new_action(rig, 'attack', False)
    for f, pose in {1: {}, 6: {'torso': {'rot': [('x', 12)], 'loc': (0, -0.1 * scale, 0.1 * scale)}, 'upper_arm_fk.L': {'rot': [('y', -40)]}, 'upper_arm_fk.R': {'rot': [('y', 40)]}},
                    11: {'torso': {'rot': [('x', -45)], 'loc': (0, 0.3 * scale, -0.15 * scale)}, 'upper_arm_fk.L': {'rot': [('y', 30)]}, 'upper_arm_fk.R': {'rot': [('y', -30)]}}, 22: {}}.items():
        po.key_pose(rig, f, pose or {'torso': {'rot': []}})
    po.finish_action(rig, act, False)
    act = po.new_action(rig, 'hit', False)
    for f, pose in {1: {}, 4: {'torso': {'rot': [('x', 22)], 'loc': (0, -0.08 * scale, 0)}, 'upper_arm_fk.L': {'rot': [('y', 35)]}, 'upper_arm_fk.R': {'rot': [('y', -35)]}}, 14: {}}.items():
        po.key_pose(rig, f, pose or {'torso': {'rot': []}})
    po.finish_action(rig, act, False)
    act = po.new_action(rig, 'die', False)
    for f, pose in {1: {}, 8: {'torso': {'rot': [('x', 40)], 'loc': (0, 0, -0.1 * scale)}, 'upper_arm_fk.L': {'rot': [('y', 60)]}, 'upper_arm_fk.R': {'rot': [('y', -60)]}},
                    22: {'root': {'rot': [('x', 80)]}, 'upper_arm_fk.L': {'rot': [('y', 80)]}, 'upper_arm_fk.R': {'rot': [('y', -80)]}}}.items():
        po.key_pose(rig, f, pose or {'torso': {'rot': []}})
    po.finish_action(rig, act, False)
    act = po.new_action(rig, 'jump', False)
    for f, pose in {1: {}, 6: {'torso': {'loc': (0, 0, -0.08 * scale)}, 'upper_arm_fk.L': {'rot': [('y', -60)]}, 'upper_arm_fk.R': {'rot': [('y', 60)]}},
                    12: {'torso': {'loc': (0, 0, 0.25 * scale)}, 'upper_arm_fk.L': {'rot': [('y', 45)]}, 'upper_arm_fk.R': {'rot': [('y', -45)]}}, 24: {}}.items():
        po.key_pose(rig, f, pose or {'torso': {'rot': []}})
    po.finish_action(rig, act, False)


def bake_all(rig, base):
    """Create every base animation for this body style. Returns the action names."""
    po.set_fk(rig)
    scale = base.get('scale', 1.0)
    style = base['anim']
    st = STYLES[style]
    if style == 'quadruped':
        quad_idle(rig, st, scale); quad_walk(rig, st, scale, 24, 1.0, 'walk-loop'); quad_walk(rig, st, scale, 14, 1.5, 'run-loop')
        quad_jump(rig, st, scale); quad_attack(rig, st, scale); quad_hit(rig, st, scale); quad_die(rig, st, scale)
    elif style == 'flyer':
        flyer_flap(rig, st, scale, 24, 38, 'idle-loop', True, 0.04)
        flyer_flap(rig, st, scale, 20, 42, 'walk-loop', True, 0.05)
        flyer_flap(rig, st, scale, 12, 46, 'run-loop', True, 0.06)
        flyer_oneshots(rig, st, scale)
    else:
        biped_idle(rig, st, scale)
        biped_walk(rig, st, scale, int(24 / st['speed']), 1.0, 'walk-loop')
        biped_walk(rig, st, scale, int(14 / st['speed']), 1.6, 'run-loop')
        biped_jump(rig, st, scale); biped_attack(rig, st, scale); biped_hit(rig, st, scale); biped_die(rig, st, scale, side=(style == 'hunched'))
    return sorted(a.name for a in __import__('bpy').data.actions)
