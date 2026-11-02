"""Tiny QC reader (Crowbar decompiles): $sequence / $animation / $weightlist / $bodygroup."""
import re

def tokenize(text):
    text = re.sub(r'//[^\n]*', '', text)
    toks = []
    for m in re.finditer(r'"([^"]*)"|(\{|\})|([^\s{}"]+)', text):
        if m.group(1) is not None:
            toks.append(('s', m.group(1)))
        elif m.group(2):
            toks.append((m.group(2), m.group(2)))
        else:
            toks.append(('w', m.group(3)))
    return toks

def parse_block(toks, i):
    """parse { ... } returns (list of token/blocks, new i)"""
    assert toks[i][0] == '{'
    i += 1
    out = []
    while toks[i][0] != '}':
        if toks[i][0] == '{':
            blk, i = parse_block(toks, i)
            out.append(blk)
        else:
            out.append(toks[i][1])
            i += 1
    return out, i + 1

def parse_qc(path):
    toks = tokenize(open(path, encoding='utf-8', errors='replace').read())
    cmds = []
    i = 0
    while i < len(toks):
        t = toks[i]
        if t[0] == 'w' and t[1].startswith('$'):
            name = t[1].lower()
            args = []
            i += 1
            while i < len(toks) and not (toks[i][0] == 'w' and toks[i][1].startswith('$')):
                if toks[i][0] == '{':
                    blk, i = parse_block(toks, i)
                    args.append(blk)
                    # sequence/animation blocks end after their block
                    if name in ('$sequence', '$animation', '$bodygroup', '$model', '$texturegroup', '$collisionjoints', '$collisionmodel', '$keyvalues', '$attachment', '$poseparameter', '$includemodel', '$lod', '$ikchain', '$weightlist', '$boneflexdriver', '$hboxset', '$declaresequence'):
                        break
                else:
                    args.append(toks[i][1])
                    i += 1
            cmds.append((name, args))
        else:
            i += 1
    return cmds

def flatten_events(blk):
    evs = []
    for x in blk:
        if isinstance(x, list):
            if x and str(x[0]).lower() == 'event':
                evs.append(x[1:])
            else:
                evs += flatten_events(x)
    return evs

def sequences(path):
    cmds = parse_qc(path)
    anims = {}
    seqs = []
    for name, args in cmds:
        if name in ('$animation', '$sequence'):
            nm = args[0]
            blk = None
            smd = None
            if len(args) > 1 and isinstance(args[1], list):
                blk = args[1]
            elif len(args) > 1:
                smd = args[1]
                blk = []
                for a in args[2:]:
                    if isinstance(a, list):
                        blk.extend(a)
                    else:
                        blk.append(a)
            info = {'name': nm, 'smd': smd, 'fps': None, 'loop': False, 'events': [], 'flags': [], 'raw': blk}
            if blk:
                j = 0
                flat = blk
                while j < len(flat):
                    a = flat[j]
                    if isinstance(a, list):
                        if a and str(a[0]).lower() == 'event':
                            info['events'].append(a[1:])
                        j += 1
                        continue
                    al = str(a).lower()
                    if al == 'fps':
                        info['fps'] = float(flat[j + 1]); j += 2; continue
                    if al == 'loop':
                        info['loop'] = True
                    elif al.endswith('.smd') and info['smd'] is None:
                        info['smd'] = a
                    elif al in ('delta', 'subtract', 'blend', 'addlayer', 'blendlayer', 'blendwidth', 'worldspace', 'autoplay', 'hidden', 'realtime', 'snap', 'post', 'predelta', 'cmdlist', 'iklock', 'ikrule'):
                        info['flags'].append(al)
                    elif info['smd'] is None and isinstance(a, str) and j == 0:
                        info['smd'] = a  # animation name reference
                    j += 1
            (anims if name == '$animation' else {})[nm] = info
            if name == '$sequence':
                seqs.append(info)
    return seqs, anims, cmds
