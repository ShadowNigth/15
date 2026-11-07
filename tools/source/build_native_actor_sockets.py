"""Calibrate unchanged p_ meshes onto native hands and native weapon aim frames.
Development-only numpy/scipy tooling; no geometry or animation is rewritten.
"""
import json
from pathlib import Path
import numpy as np
from .glb_read import load
from .add_cs2_knives import original_pose

ROOT = Path(__file__).resolve().parents[2]


def main():
    report = json.loads((ROOT / 'data/native_gun_animation_report.json').read_text())
    weapons = json.loads((ROOT / 'data/weapons.json').read_text())['weapons']
    output = {}
    # CS2 muzzle axes: +X forward, +Z up. Agent faces +Z; p_ meshes face -Z.
    muzzle_target = np.array([[0., 1., 0.], [0., 0., 1.], [1., 0., 0.]])
    turn = np.diag([-1., 1., -1.])
    legacy_turn = np.array([[0., 0., 1.], [0., 1., 0.], [-1., 0., 0.]])
    for role, classic in [('ct', 'urban'), ('t', 'terror')]:
        document, buffer = load(ROOT / f'assets/models/native/{role}.glb')
        old_document, old_buffer = load(ROOT / f'assets/models/players/{classic}.glb')
        nodes = {node.get('name'): i for i, node in enumerate(document['nodes'])}
        old_hand = next(i for i, n in enumerate(old_document['nodes']) if n.get('name') == 'Bip01 R Hand')
        clips = {animation['name'] for animation in document['animations']}
        output[role] = {}
        for weapon_id, spec in weapons.items():
            source = report.get(weapon_id, {}).get('source_weapon', 'default_' + role)
            hold = 'hold_' + source
            if hold not in clips:
                hold = ('hold_default_' + role if weapon_id == 'knife' else
                        'hold_usp_silencer' if spec.get('slot') == 2 else 'hold_ak47')
            pose = original_pose(document, buffer, hold)
            source = hold.removeprefix('hold_')
            muzzle = nodes.get('cswp_' + source + '/muzzle', nodes.get('cswp_' + source + '/muzzle_r'))
            correction = np.eye(3)
            if muzzle is not None:
                # Remove the baked weapon yaw/pitch/roll from the upper pose.
                # Merely matching a classic hand leaves rifles pointing sideways.
                correction = muzzle_target @ np.linalg.inv(pose[muzzle][:3, :3])
                expected = np.eye(3)
            else:
                extension = 'onehanded' if spec.get('slot') == 2 else 'knife' if weapon_id == 'knife' else 'carbine'
                old = original_pose(old_document, old_buffer, 'ref_aim_' + extension)[old_hand]
                expected = legacy_turn @ old[:3, :3]
            hand = correction @ pose[nodes['hand_R']][:3, :3]
            socket = np.linalg.inv(hand) @ turn @ expected
            output[role][weapon_id] = {
                'hold': hold,
                'basis': socket.round(8).tolist(),
                'pelvis_basis': (correction @ pose[nodes['pelvis']][:3, :3]).round(8).tolist(),
                'expected_basis': expected.round(8).tolist(),
            }
    (ROOT / 'data/native_actor_sockets.json').write_text(json.dumps(output, indent=2) + '\n')


if __name__ == '__main__':
    main()
