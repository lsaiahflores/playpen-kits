"""
bases — the BODY-BASE LIBRARY (Part 7.3). Six organic bodies built once and done well; Claude customizes a base (proportions, parts, colors),
it never starts from cubes. Each base is ONE joint table that drives BOTH the smooth skin-modifier body and the Rigify metarig fit, so the
mesh and its skeleton can never disagree.

Written in Rigify's own convention: the character faces -Y, its left is +X, feet at z=0, metres. (pn_organic.game() turns it to face +Y.)
Nodes are  name: ((x, y, z), half-width, half-depth, colour-group).  Only the LEFT ('.L') side is written; the right is mirrored.
"""
import copy


def mirror_joints(joints):
    """Write only the LEFT (+X) joints ('x.L') and the centre ones; the right side is mirrored automatically."""
    out = dict(joints)
    for k, v in joints.items():
        if k.endswith('.L'):
            out[k[:-2] + '.R'] = (-v[0], v[1], v[2])
    return out


def mirror_skin(nodes, edges):
    n2 = dict(nodes)
    e2 = list(edges)
    for k, v in nodes.items():
        if k.endswith('.L'):
            pos = v[0]
            n2[k[:-2] + '.R'] = ((-pos[0], pos[1], pos[2]),) + tuple(v[1:])
    for a, b in edges:
        a2 = a[:-2] + '.R' if a.endswith('.L') else a
        b2 = b[:-2] + '.R' if b.endswith('.L') else b
        if (a2, b2) != (a, b):
            e2.append((a2, b2))
    return n2, e2

HUMAN_BONES = {
    'spine': ('pelvis', 'spine1'), 'spine.001': ('spine1', 'spine2'), 'spine.002': ('spine2', 'spine3'), 'spine.003': ('spine3', 'neck_base'),
    'spine.004': ('neck_base', 'neck_mid'), 'spine.005': ('neck_mid', 'head_base'), 'spine.006': ('head_base', 'head_top'),
    'shoulder.L': ('clav_in.L', 'clav_out.L'), 'upper_arm.L': ('shoulder.L', 'elbow.L'), 'forearm.L': ('elbow.L', 'wrist.L'), 'hand.L': ('wrist.L', 'hand_end.L'),
    'shoulder.R': ('clav_in.R', 'clav_out.R'), 'upper_arm.R': ('shoulder.R', 'elbow.R'), 'forearm.R': ('elbow.R', 'wrist.R'), 'hand.R': ('wrist.R', 'hand_end.R'),
    'pelvis.L': ('pelvis', 'hip.L'), 'pelvis.R': ('pelvis', 'hip.R'),
    'thigh.L': ('hip.L', 'knee.L'), 'shin.L': ('knee.L', 'ankle.L'), 'foot.L': ('ankle.L', 'toe_base.L'), 'toe.L': ('toe_base.L', 'toe_tip.L'), 'heel.02.L': ('heel_out.L', 'heel_in.L'),
    'thigh.R': ('hip.R', 'knee.R'), 'shin.R': ('knee.R', 'ankle.R'), 'foot.R': ('ankle.R', 'toe_base.R'), 'toe.R': ('toe_base.R', 'toe_tip.R'), 'heel.02.R': ('heel_out.R', 'heel_in.R'),
}
HUMAN_ATTACH = {
    'head': 'DEF-spine.006', 'neck': 'DEF-spine.005', 'chest': 'DEF-spine.003', 'back': 'DEF-spine.002', 'belly': 'DEF-spine.001', 'hips': 'DEF-spine',
    'shoulder.L': 'DEF-shoulder.L', 'shoulder.R': 'DEF-shoulder.R', 'upper_arm.L': 'DEF-upper_arm.L', 'upper_arm.R': 'DEF-upper_arm.R',
    'forearm.L': 'DEF-forearm.L', 'forearm.R': 'DEF-forearm.R', 'hand.L': 'DEF-hand.L', 'hand.R': 'DEF-hand.R',
    'thigh.L': 'DEF-thigh.L', 'thigh.R': 'DEF-thigh.R', 'shin.L': 'DEF-shin.L', 'shin.R': 'DEF-shin.R', 'foot.L': 'DEF-foot.L', 'foot.R': 'DEF-foot.R',
}

QUAD_BONES = {
    'spine.004': ('rump', 'hip_mid'), 'spine.003': ('rump', 'tail1'), 'spine.002': ('tail1', 'tail2'), 'spine.001': ('tail2', 'tail3'), 'spine': ('tail3', 'tail_tip'),
    'spine.005': ('hip_mid', 'back1'), 'spine.006': ('back1', 'back2'), 'spine.007': ('back2', 'chest'), 'spine.008': ('chest', 'neck_base'),
    'spine.009': ('neck_base', 'neck_mid'), 'spine.010': ('neck_mid', 'head_base'), 'spine.011': ('head_base', 'nose_tip'),
    'shoulder.L': ('shoulder_in.L', 'shoulder_out.L'), 'front_thigh.L': ('fshoulder.L', 'felbow.L'), 'front_shin.L': ('felbow.L', 'fwrist.L'),
    'front_foot.L': ('fwrist.L', 'fpaw.L'), 'front_toe.L': ('fpaw.L', 'ftoe.L'),
    'shoulder.R': ('shoulder_in.R', 'shoulder_out.R'), 'front_thigh.R': ('fshoulder.R', 'felbow.R'), 'front_shin.R': ('felbow.R', 'fwrist.R'),
    'front_foot.R': ('fwrist.R', 'fpaw.R'), 'front_toe.R': ('fpaw.R', 'ftoe.R'),
    'pelvis.L': ('pelvis_c', 'pelvis_out.L'), 'pelvis.R': ('pelvis_c', 'pelvis_out.R'),
    'thigh.L': ('rhip.L', 'rknee.L'), 'shin.L': ('rknee.L', 'rhock.L'), 'foot.L': ('rhock.L', 'rpaw.L'), 'toe.L': ('rpaw.L', 'rtoe.L'),
    'thigh.R': ('rhip.R', 'rknee.R'), 'shin.R': ('rknee.R', 'rhock.R'), 'foot.R': ('rhock.R', 'rpaw.R'), 'toe.R': ('rpaw.R', 'rtoe.R'),
}
QUAD_ATTACH = {
    'head': 'DEF-spine.011', 'neck': 'DEF-spine.009', 'chest': 'DEF-spine.008', 'back': 'DEF-spine.006', 'hips': 'DEF-spine.004', 'tail_tip': 'DEF-spine.001',
    'shoulder.L': 'DEF-shoulder.L', 'shoulder.R': 'DEF-shoulder.R', 'foot.L': 'DEF-foot.L', 'foot.R': 'DEF-foot.R',
    'hand.L': 'DEF-front_foot.L', 'hand.R': 'DEF-front_foot.R', 'thigh.L': 'DEF-thigh.L', 'thigh.R': 'DEF-thigh.R',
    'upper_arm.L': 'DEF-front_thigh.L', 'upper_arm.R': 'DEF-front_thigh.R',
}


def _humanoid_nodes(j, r):
    """Skin nodes for the human-metarig bases. `r` = radii dict (half-width, half-depth) per body part."""
    n = {
        'pelvis': (j['pelvis'], *r['pelvis'], 'torso'),
        'spine1': (j['spine1'], *r['spine1'], 'torso'),
        'spine2': (j['spine2'], *r['spine2'], 'torso'),
        'spine3': (j['spine3'], *r['spine3'], 'torso'),
        'neck_base': (j['neck_base'], *r['neck'], 'head'),
        'neck_mid': (j['neck_mid'], *r['neck'], 'head'),
        'head_c': (j['head_c'], *r['head'], 'head'),
        'head_top': (j['head_top'], *r['head_top'], 'head'),
        'clav_out.L': (j['clav_out.L'], *r['clav'], 'arms'),
        'shoulder.L': (j['shoulder.L'], *r['upper_arm'], 'arms'),
        'elbow.L': (j['elbow.L'], *r['forearm'], 'arms'),
        'wrist.L': (j['wrist.L'], *r['wrist'], 'hands'),
        'hand_end.L': (j['hand_end.L'], *r['hand'], 'hands'),
        'hip.L': (j['hip.L'], *r['thigh'], 'legs'),
        'knee.L': (j['knee.L'], *r['knee'], 'legs'),
        'ankle.L': (j['ankle.L'], *r['ankle'], 'feet'),
        'toe_base.L': (j['toe_base.L'], *r['foot'], 'feet'),
        'toe_tip.L': (j['toe_tip.L'], *r['toe'], 'feet'),
    }
    e = [('pelvis', 'spine1'), ('spine1', 'spine2'), ('spine2', 'spine3'), ('spine3', 'neck_base'), ('neck_base', 'neck_mid'), ('neck_mid', 'head_c'), ('head_c', 'head_top'),
         ('spine3', 'clav_out.L'), ('clav_out.L', 'shoulder.L'), ('shoulder.L', 'elbow.L'), ('elbow.L', 'wrist.L'), ('wrist.L', 'hand_end.L'),
         ('pelvis', 'hip.L'), ('hip.L', 'knee.L'), ('knee.L', 'ankle.L'), ('ankle.L', 'toe_base.L'), ('toe_base.L', 'toe_tip.L')]
    return n, e


# ------------------------------------------------------------------ 1. chunky sculpted humanoid (toy-figure proportions)
def chunky_humanoid():
    j = {
        'pelvis': (0, 0.00, 0.58), 'spine1': (0, 0, 0.68), 'spine2': (0, -0.005, 0.80), 'spine3': (0, -0.01, 0.92), 'neck_base': (0, -0.01, 1.00),
        'neck_mid': (0, -0.02, 1.04), 'head_base': (0, -0.02, 1.07), 'head_top': (0, -0.03, 1.44), 'head_c': (0, -0.04, 1.25),
        'clav_in.L': (0.04, -0.03, 0.96), 'clav_out.L': (0.20, -0.01, 0.96), 'shoulder.L': (0.25, 0.0, 0.93), 'elbow.L': (0.36, 0.0, 0.73),
        'wrist.L': (0.41, -0.07, 0.57), 'hand_end.L': (0.42, -0.11, 0.49),
        'hip.L': (0.10, 0, 0.56), 'knee.L': (0.11, -0.03, 0.30), 'ankle.L': (0.11, 0.01, 0.075), 'toe_base.L': (0.11, -0.08, 0.035), 'toe_tip.L': (0.11, -0.15, 0.03),
        'heel_out.L': (0.15, 0.05, 0.0), 'heel_in.L': (0.07, 0.05, 0.0),
    }
    r = dict(pelvis=(0.15, 0.11), spine1=(0.16, 0.115), spine2=(0.19, 0.125), spine3=(0.22, 0.13), neck=(0.08, 0.08), head=(0.20, 0.19), head_top=(0.12, 0.12), clav=(0.07, 0.07),
             upper_arm=(0.075, 0.075), forearm=(0.07, 0.07), wrist=(0.065, 0.065), hand=(0.075, 0.07),
             thigh=(0.09, 0.09), knee=(0.08, 0.08), ankle=(0.075, 0.075), foot=(0.08, 0.07), toe=(0.07, 0.04))
    n, e = _humanoid_nodes(j, r)
    return dict(id='chunky-humanoid', kind='human', joints=j, nodes=n, edges=e, bone_map=HUMAN_BONES, attach=HUMAN_ATTACH, delete=['breast.L', 'breast.R'],
                height=1.46, anim='upright', blobs=[((0, -0.06, 0.93), 0.16, (1.35, 0.9, 1.0))],   # a broad chest
                nonhuman=False, label='Chunky sculpted humanoid')


# ------------------------------------------------------------------ 2. hunched digitigrade creature
def hunched_digitigrade():
    j = {
        'pelvis': (0, 0.10, 0.80), 'spine1': (0, 0.04, 0.90), 'spine2': (0, -0.06, 0.99), 'spine3': (0, -0.17, 1.06), 'neck_base': (0, -0.27, 1.09),
        'neck_mid': (0, -0.35, 1.10), 'head_base': (0, -0.41, 1.10), 'head_top': (0, -0.66, 1.07), 'head_c': (0, -0.50, 1.10),
        'clav_in.L': (0.05, -0.19, 1.03), 'clav_out.L': (0.17, -0.20, 1.03), 'shoulder.L': (0.21, -0.20, 1.00), 'elbow.L': (0.27, -0.28, 0.77),
        'wrist.L': (0.29, -0.43, 0.57), 'hand_end.L': (0.30, -0.54, 0.50),
        'hip.L': (0.13, 0.11, 0.78), 'knee.L': (0.15, -0.08, 0.52), 'ankle.L': (0.15, 0.13, 0.30), 'toe_base.L': (0.15, -0.03, 0.04), 'toe_tip.L': (0.15, -0.14, 0.0),
        'heel_out.L': (0.19, 0.16, 0.0), 'heel_in.L': (0.11, 0.16, 0.0), 'tail1': (0, 0.28, 0.74), 'tail2': (0, 0.52, 0.62), 'tail3': (0, 0.78, 0.50),
    }
    r = dict(pelvis=(0.13, 0.12), spine1=(0.13, 0.12), spine2=(0.15, 0.13), spine3=(0.16, 0.14), neck=(0.07, 0.07), head=(0.09, 0.11), head_top=(0.045, 0.05), clav=(0.06, 0.06),
             upper_arm=(0.055, 0.055), forearm=(0.045, 0.045), wrist=(0.04, 0.04), hand=(0.05, 0.04),
             thigh=(0.085, 0.085), knee=(0.06, 0.06), ankle=(0.04, 0.04), foot=(0.045, 0.04), toe=(0.05, 0.03))
    n, e = _humanoid_nodes(j, r)
    n['tail1'] = (j['tail1'], 0.08, 0.08, 'torso'); n['tail2'] = (j['tail2'], 0.05, 0.05, 'torso'); n['tail3'] = (j['tail3'], 0.025, 0.025, 'torso')
    e += [('pelvis', 'tail1'), ('tail1', 'tail2'), ('tail2', 'tail3')]
    return dict(id='hunched-digitigrade', kind='human', joints=j, nodes=n, edges=e, bone_map=HUMAN_BONES, attach=HUMAN_ATTACH, delete=['breast.L', 'breast.R'],
                height=1.12, anim='hunched', blobs=[((0, -0.27, 1.06), 0.13, (1.1, 1.2, 1.0)), ((0, -0.55, 1.08), 0.07, (0.9, 1.4, 0.8))],
                nonhuman=True, label='Hunched digitigrade creature')


# ------------------------------------------------------------------ 3. small stocky creature
def small_stocky():
    j = {
        'pelvis': (0, 0, 0.34), 'spine1': (0, 0, 0.42), 'spine2': (0, -0.01, 0.50), 'spine3': (0, -0.02, 0.58), 'neck_base': (0, -0.02, 0.63),
        'neck_mid': (0, -0.03, 0.66), 'head_base': (0, -0.03, 0.68), 'head_top': (0, -0.05, 0.94), 'head_c': (0, -0.05, 0.80),
        'clav_in.L': (0.03, -0.04, 0.58), 'clav_out.L': (0.14, -0.04, 0.58), 'shoulder.L': (0.18, -0.03, 0.55), 'elbow.L': (0.25, -0.04, 0.42),
        'wrist.L': (0.28, -0.09, 0.31), 'hand_end.L': (0.29, -0.12, 0.26),
        'hip.L': (0.08, 0, 0.33), 'knee.L': (0.09, -0.02, 0.18), 'ankle.L': (0.09, 0.0, 0.05), 'toe_base.L': (0.09, -0.06, 0.02), 'toe_tip.L': (0.09, -0.11, 0.02),
        'heel_out.L': (0.12, 0.04, 0.0), 'heel_in.L': (0.06, 0.04, 0.0),
    }
    r = dict(pelvis=(0.12, 0.10), spine1=(0.14, 0.11), spine2=(0.15, 0.12), spine3=(0.15, 0.12), neck=(0.07, 0.07), head=(0.14, 0.13), head_top=(0.09, 0.09), clav=(0.05, 0.05),
             upper_arm=(0.05, 0.05), forearm=(0.05, 0.05), wrist=(0.045, 0.045), hand=(0.055, 0.05),
             thigh=(0.07, 0.07), knee=(0.065, 0.065), ankle=(0.06, 0.06), foot=(0.065, 0.055), toe=(0.055, 0.035))
    n, e = _humanoid_nodes(j, r)
    return dict(id='small-stocky', kind='human', joints=j, nodes=n, edges=e, bone_map=HUMAN_BONES, attach=HUMAN_ATTACH, delete=['breast.L', 'breast.R'],
                height=0.94, anim='stocky', blobs=[((0, -0.03, 0.46), 0.14, (1.2, 1.05, 1.0))],   # a round belly
                nonhuman=True, label='Small stocky creature')


# ------------------------------------------------------------------ 4. tall lanky creature
def tall_lanky():
    j = {
        'pelvis': (0, 0, 1.18), 'spine1': (0, 0, 1.40), 'spine2': (0, -0.01, 1.62), 'spine3': (0, -0.02, 1.84), 'neck_base': (0, -0.03, 1.95),
        'neck_mid': (0, -0.07, 2.08), 'head_base': (0, -0.10, 2.18), 'head_top': (0, -0.13, 2.50), 'head_c': (0, -0.11, 2.32),
        'clav_in.L': (0.04, -0.03, 1.88), 'clav_out.L': (0.18, -0.03, 1.88), 'shoulder.L': (0.22, -0.02, 1.84), 'elbow.L': (0.28, -0.05, 1.42),
        'wrist.L': (0.31, -0.12, 1.00), 'hand_end.L': (0.32, -0.15, 0.82),
        'hip.L': (0.10, 0, 1.15), 'knee.L': (0.12, -0.07, 0.62), 'ankle.L': (0.12, 0.02, 0.10), 'toe_base.L': (0.12, -0.10, 0.03), 'toe_tip.L': (0.12, -0.22, 0.03),
        'heel_out.L': (0.16, 0.06, 0.0), 'heel_in.L': (0.08, 0.06, 0.0),
    }
    r = dict(pelvis=(0.10, 0.07), spine1=(0.09, 0.07), spine2=(0.10, 0.075), spine3=(0.13, 0.08), neck=(0.045, 0.045), head=(0.08, 0.10), head_top=(0.05, 0.06), clav=(0.04, 0.04),
             upper_arm=(0.035, 0.035), forearm=(0.03, 0.03), wrist=(0.025, 0.025), hand=(0.04, 0.03),
             thigh=(0.05, 0.05), knee=(0.04, 0.04), ankle=(0.03, 0.03), foot=(0.04, 0.03), toe=(0.035, 0.025))
    n, e = _humanoid_nodes(j, r)
    return dict(id='tall-lanky', kind='human', joints=j, nodes=n, edges=e, bone_map=HUMAN_BONES, attach=HUMAN_ATTACH, delete=['breast.L', 'breast.R'],
                height=2.5, anim='lanky', blobs=[], nonhuman=True, label='Tall lanky creature')


# ------------------------------------------------------------------ 5. quadruped
def quadruped():
    j = {
        'rump': (0, 0.44, 0.80), 'hip_mid': (0, 0.35, 0.81), 'tail1': (0, 0.55, 0.76), 'tail2': (0, 0.78, 0.74), 'tail3': (0, 0.96, 0.74), 'tail_tip': (0, 1.10, 0.76),
        'back1': (0, 0.18, 0.78), 'back2': (0, 0.03, 0.77), 'chest': (0, -0.10, 0.79), 'neck_base': (0, -0.36, 0.84), 'neck_mid': (0, -0.43, 0.86),
        'head_base': (0, -0.49, 0.88), 'nose_tip': (0, -0.66, 0.98), 'head_c': (0, -0.56, 0.92),
        'shoulder_in.L': (0.06, -0.26, 0.89), 'shoulder_out.L': (0.12, -0.34, 0.72), 'fshoulder.L': (0.12, -0.32, 0.69), 'felbow.L': (0.12, -0.22, 0.44),
        'fwrist.L': (0.11, -0.21, 0.17), 'fpaw.L': (0.11, -0.25, 0.04), 'ftoe.L': (0.11, -0.37, 0.0),
        'pelvis_c': (0, 0.38, 0.60), 'pelvis_out.L': (0.08, 0.28, 0.85), 'rhip.L': (0.12, 0.34, 0.74), 'rknee.L': (0.12, 0.27, 0.47), 'rhock.L': (0.11, 0.48, 0.25),
        'rpaw.L': (0.11, 0.41, 0.04), 'rtoe.L': (0.11, 0.28, 0.0),
    }
    n = {
        'rump': (j['rump'], 0.14, 0.15, 'body'), 'hip_mid': (j['hip_mid'], 0.15, 0.15, 'body'), 'back1': (j['back1'], 0.14, 0.14, 'body'), 'back2': (j['back2'], 0.14, 0.14, 'body'),
        'chest': (j['chest'], 0.16, 0.17, 'body'), 'neck_base': (j['neck_base'], 0.10, 0.11, 'head'), 'neck_mid': (j['neck_mid'], 0.09, 0.09, 'head'),
        'head_c': (j['head_c'], 0.09, 0.10, 'head'), 'nose_tip': (j['nose_tip'], 0.045, 0.045, 'head'),
        'tail1': (j['tail1'], 0.07, 0.07, 'body'), 'tail2': (j['tail2'], 0.05, 0.05, 'tail'), 'tail3': (j['tail3'], 0.035, 0.035, 'tail'), 'tail_tip': (j['tail_tip'], 0.02, 0.02, 'tail'),
        'fshoulder.L': (j['fshoulder.L'], 0.07, 0.08, 'legs'), 'felbow.L': (j['felbow.L'], 0.05, 0.05, 'legs'), 'fwrist.L': (j['fwrist.L'], 0.04, 0.04, 'legs'), 'fpaw.L': (j['fpaw.L'], 0.05, 0.05, 'feet'),
        'ftoe.L': (j['ftoe.L'], 0.04, 0.03, 'feet'),
        'rhip.L': (j['rhip.L'], 0.09, 0.10, 'legs'), 'rknee.L': (j['rknee.L'], 0.06, 0.06, 'legs'), 'rhock.L': (j['rhock.L'], 0.04, 0.04, 'legs'), 'rpaw.L': (j['rpaw.L'], 0.05, 0.05, 'feet'),
        'rtoe.L': (j['rtoe.L'], 0.04, 0.03, 'feet'),
    }
    e = [('rump', 'hip_mid'), ('hip_mid', 'back1'), ('back1', 'back2'), ('back2', 'chest'), ('chest', 'neck_base'), ('neck_base', 'neck_mid'), ('neck_mid', 'head_c'), ('head_c', 'nose_tip'),
         ('rump', 'tail1'), ('tail1', 'tail2'), ('tail2', 'tail3'), ('tail3', 'tail_tip'),
         ('chest', 'fshoulder.L'), ('fshoulder.L', 'felbow.L'), ('felbow.L', 'fwrist.L'), ('fwrist.L', 'fpaw.L'), ('fpaw.L', 'ftoe.L'),
         ('hip_mid', 'rhip.L'), ('rhip.L', 'rknee.L'), ('rknee.L', 'rhock.L'), ('rhock.L', 'rpaw.L'), ('rpaw.L', 'rtoe.L')]
    return dict(id='quadruped', kind='quadruped', joints=j, nodes=n, edges=e, bone_map=QUAD_BONES, attach=QUAD_ATTACH, delete=['breast.L', 'breast.R'],
                height=0.98, anim='quadruped', blobs=[((0, 0.1, 0.8), 0.2, (1.0, 1.9, 0.9)), ((0, -0.58, 0.92), 0.09, (1.0, 1.3, 0.9))],
                nonhuman=True, label='Quadruped')


# ------------------------------------------------------------------ 6. flyer (human metarig: the arms ARE the wings)
def flyer():
    j = {
        'pelvis': (0, 0, 0.30), 'spine1': (0, 0, 0.36), 'spine2': (0, -0.01, 0.42), 'spine3': (0, -0.02, 0.48), 'neck_base': (0, -0.03, 0.53),
        'neck_mid': (0, -0.05, 0.56), 'head_base': (0, -0.06, 0.58), 'head_top': (0, -0.10, 0.74), 'head_c': (0, -0.08, 0.66),
        'clav_in.L': (0.03, -0.03, 0.48), 'clav_out.L': (0.10, -0.02, 0.50), 'shoulder.L': (0.13, 0.0, 0.50), 'elbow.L': (0.50, 0.04, 0.54),
        'wrist.L': (0.88, 0.10, 0.50), 'hand_end.L': (1.12, 0.16, 0.44),
        'hip.L': (0.05, 0, 0.28), 'knee.L': (0.06, -0.03, 0.17), 'ankle.L': (0.06, 0.0, 0.07), 'toe_base.L': (0.06, -0.05, 0.03), 'toe_tip.L': (0.06, -0.10, 0.02),
        'heel_out.L': (0.08, 0.03, 0.0), 'heel_in.L': (0.04, 0.03, 0.0),
    }
    r = dict(pelvis=(0.08, 0.07), spine1=(0.09, 0.08), spine2=(0.10, 0.09), spine3=(0.10, 0.09), neck=(0.045, 0.045), head=(0.09, 0.10), head_top=(0.04, 0.05), clav=(0.04, 0.04),
             upper_arm=(0.035, 0.03), forearm=(0.025, 0.02), wrist=(0.02, 0.015), hand=(0.02, 0.012),
             thigh=(0.035, 0.035), knee=(0.025, 0.025), ankle=(0.02, 0.02), foot=(0.025, 0.02), toe=(0.02, 0.015))
    n, e = _humanoid_nodes(j, r)
    return dict(id='flyer', kind='human', joints=j, nodes=n, edges=e, bone_map=HUMAN_BONES, attach=HUMAN_ATTACH, delete=['breast.L', 'breast.R'],
                height=0.74, anim='flyer', blobs=[((0, -0.01, 0.42), 0.10, (1.0, 1.1, 1.2))], nonhuman=True, label='Flyer')


BASE_BUILDERS = {
    'chunky-humanoid': chunky_humanoid, 'hunched-digitigrade': hunched_digitigrade, 'small-stocky': small_stocky,
    'tall-lanky': tall_lanky, 'quadruped': quadruped, 'flyer': flyer,
}


def get_base(base_id, opts=None):
    """A fresh base spec with the user's proportion tweaks applied (all optional, all multipliers):
       scale (overall), head (head size), shoulders (width), legs (length), bulk (girth), arms (length)."""
    if base_id not in BASE_BUILDERS:
        raise ValueError('unknown base %r (choose: %s)' % (base_id, ', '.join(BASE_BUILDERS)))
    spec = BASE_BUILDERS[base_id]()
    o = opts or {}
    sc = float(o.get('scale', 1.0))
    bulk = float(o.get('bulk', 1.0))
    head = float(o.get('head', 1.0))
    shoulders = float(o.get('shoulders', 1.0))
    legs = float(o.get('legs', 1.0))
    arms = float(o.get('arms', 1.0))
    j = spec['joints']
    z0 = 0.0
    if legs != 1.0 and spec['kind'] == 'human':
        # lengthen/shorten the legs and move everything above the hips with them
        hipz = j['hip.L'][2]
        dz = hipz * (legs - 1.0)
        for k, v in list(j.items()):
            if v[2] >= hipz - 0.02 and not k.startswith(('heel', 'toe', 'ankle', 'knee')):
                j[k] = (v[0], v[1], v[2] + dz)
        for k in ('knee.L', 'ankle.L'):
            j[k] = (j[k][0], j[k][1], j[k][2] * legs)
        for nm, nd in list(spec['nodes'].items()):
            pos = nd[0]
            if nm in j:
                spec['nodes'][nm] = (j[nm],) + tuple(nd[1:])
    if shoulders != 1.0 and spec['kind'] == 'human':
        for k in ('clav_in.L', 'clav_out.L', 'shoulder.L', 'elbow.L', 'wrist.L', 'hand_end.L'):
            if k in j:
                j[k] = (j[k][0] * shoulders, j[k][1], j[k][2])
    if arms != 1.0 and spec['kind'] == 'human':
        sh = j['shoulder.L']
        for k in ('elbow.L', 'wrist.L', 'hand_end.L'):
            v = j[k]
            j[k] = (sh[0] + (v[0] - sh[0]) * arms, sh[1] + (v[1] - sh[1]) * arms, sh[2] + (v[2] - sh[2]) * arms)
    # rebuild node positions from the (possibly edited) joints, then radii tweaks
    for nm, nd in list(spec['nodes'].items()):
        pos = j.get(nm, nd[0])
        rx, ry = nd[1] * bulk, nd[2] * bulk
        if nd[3] == 'head' and nm.startswith('head'):
            rx, ry = rx * head, ry * head
        spec['nodes'][nm] = (pos, rx, ry) + tuple(nd[3:])
    if head != 1.0 and 'head_c' in j and spec['kind'] == 'human':
        hb, ht = j['head_base'], j['head_top']
        # the head grows from its base, not from the floor
        j['head_top'] = (ht[0], ht[1], hb[2] + (ht[2] - hb[2]) * head)
        hc = j['head_c']
        j['head_c'] = (hc[0], hc[1], hb[2] + (hc[2] - hb[2]) * head)
        for nm in ('head_c', 'head_top'):
            nd = spec['nodes'][nm]
            spec['nodes'][nm] = (j[nm],) + tuple(nd[1:])
    spec['joints'] = _scaled(j, sc)
    spec['nodes'] = {k: ((v[0][0] * sc, v[0][1] * sc, v[0][2] * sc), v[1] * sc, v[2] * sc) + tuple(v[3:]) for k, v in spec['nodes'].items()}
    spec['blobs'] = [((p[0] * sc, p[1] * sc, p[2] * sc), r * sc, s) for p, r, s in spec['blobs']]
    spec['height'] = spec['height'] * sc
    spec['scale'] = sc
    spec['joints'] = mirror_joints(spec['joints'])
    spec['nodes'], spec['edges'] = mirror_skin(spec['nodes'], spec['edges'])
    return spec


def _scaled(j, sc):
    return {k: (v[0] * sc, v[1] * sc, v[2] * sc) for k, v in j.items()}


def catalog():
    out = []
    for bid, fn in BASE_BUILDERS.items():
        s = fn()
        out.append({'id': bid, 'label': s['label'], 'nonHuman': s['nonhuman'], 'heightM': s['height'], 'kind': s['kind'], 'anim': s['anim']})
    return out
