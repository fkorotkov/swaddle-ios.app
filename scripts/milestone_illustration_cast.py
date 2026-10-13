"""Bake a balanced, reproducible cast into the existing vector scenes.

These are illustration palettes and hairstyles, never racial categories or
profile data. Independent shuffles keep adult and child appearances varied.
"""
import hashlib
from collections import Counter

from milestone_illustration_art import group, oval, path, rgba

SKIN = {
    "light": ["#ecc19f", "#f7dcc0", "#d8a685", "#d79683"],
    "golden": ["#dcb58a", "#eed0a9", "#bd946b", "#c98b75"],
    "warm": ["#c89470", "#dfb28e", "#a87152", "#bc7d68"],
    "tan": ["#ad7d59", "#c79b78", "#8b5d40", "#a76c57"],
    "brown": ["#885b40", "#aa7a59", "#66402e", "#915442"],
    "deepBrown": ["#654332", "#85604a", "#452c23", "#794a3e"],
}
HAIR = {
    "black": ["#293630", "#46544a"], "brown": ["#594735", "#8b6e4c"],
    "blonde": ["#af8c57", "#d8b77c"], "auburn": ["#865039", "#b37b51"],
    "gray": ["#727c72", "#a5aa9a"],
}
CHILD_STYLES = ["wisps", "crop", "waves", "curls"]


def shuffled(values, salt):
    # Stable across processes and Python releases; no process-random hash/seed.
    return sorted(values, key=lambda value: hashlib.sha256(f"swaddle-cast-v1/{salt}/{value}".encode()).digest())


def balanced(ids, choices, salt):
    order, options = shuffled(ids, salt + "/scenes"), shuffled(choices, salt + "/choices")
    return {key: options[index % len(options)] for index, key in enumerate(order)}


def assignments(scenes):
    casts = {scene["nm"]: {} for scene in scenes}
    for role in ("child", "caregiver", "other"):
        ids = [scene["nm"] for scene in scenes if any(actor["role"] == role for actor in scene["swaddleActors"])]
        fields = {"skinTone": list(SKIN), "hairColor": list(HAIR) if role == "caregiver" else list(HAIR)[:-1]}
        if role != "caregiver": fields["hairStyle"] = CHILD_STYLES
        for field, choices in fields.items():
            for key, value in balanced(ids, choices, role + "/" + field).items():
                casts[key].setdefault(role, {})[field] = value
    return casts


def distribution(casts):
    return {role: {field: dict(sorted(Counter(cast[role][field] for cast in casts.values() if role in cast).items()))
                   for field in ("skinTone", "hairColor", "hairStyle") if any(field in cast.get(role, {}) for cast in casts.values())}
            for role in ("child", "caregiver", "other")}


def child_hair(style):
    if style == "curls":
        return [group([oval(x, y, 17, 15) for x, y in [(-23, -27), (-13, -34), (0, -37), (14, -33), (25, -25)]],
                      gradient=(["ink", "gold_shadow"], [-25, -37], [25, -20]))]
    points = ([[-32, -16], [-29, -30], [-15, -39], [2, -42], [19, -36], [30, -24],
               [32, -14], [23, -23], [8, -28], [-7, -26], [-21, -20]] if style == "crop" else
              [[-32, -18], [-28, -32], [-12, -40], [6, -40], [24, -31], [33, -18],
               [26, -23], [20, -18], [10, -25], [0, -20], [-9, -26], [-19, -20], [-25, -22]])
    return [group(path(points, smoothing=.19), gradient=(["ink", "gold_shadow"], [-24, -37], [24, -17]))]


def bake(scene, cast):
    layers = scene["layers"]
    roots = {actor["id"]: actor["role"] for actor in scene.pop("swaddleActors")}
    parents = {layer["ind"]: layer["parent"] for layer in layers if "parent" in layer}

    def role_for(index):
        visited = set()
        while index not in visited:
            visited.add(index)
            if index in roots: return roots[index]
            index = parents.get(index)
            if index is None: return None
        raise ValueError("Cyclic actor rig")

    def colors(values, pairs):
        for source, target in pairs:
            if all(abs(a - b) < .00002 for a, b in zip(values[:3], rgba(source)[:3])):
                return rgba(target)[:3] + values[3:]
        return values

    def recolor(node, pairs):
        if isinstance(node, dict):
            if node.get("ty") in ("fl", "st"):
                node["c"]["k"] = colors(node["c"]["k"], pairs)
            elif node.get("ty") == "gf":
                values = node["g"]["k"]["k"]
                for stop in range(node["g"]["p"]):
                    offset = stop * 4 + 1
                    values[offset:offset + 3] = colors(values[offset:offset + 3], pairs)
            else:
                for value in node.values(): recolor(value, pairs)
        elif isinstance(node, list):
            for value in node: recolor(value, pairs)

    removed = set()
    for layer in layers:
        role = role_for(layer["ind"])
        if role not in cast: continue
        person, name = cast[role], layer["nm"]
        style = person.get("hairStyle", "wisps")
        if style != "wisps":
            if name == "Hair sweep": layer["shapes"] = child_hair(style)
            if name in ("Baby curl", "Wispy hair"): removed.add(layer["ind"])
        if role == "other" and name.startswith("Caregiver hair · "):
            # Incidental adults are their own character, never styled as the viewer.
            if name != "Caregiver hair · neutral": removed.add(layer["ind"])
            else: layer["nm"] = "Other adult hair"
        pairs = list(zip(SKIN["light"], SKIN[person["skinTone"]]))
        if "hair" in name.lower() or name in ("Baby curl", "Brows", "Other brow"):
            pairs += list(zip(["#3d5149", "#b08860"], HAIR[person["hairColor"]]))
        elif name.startswith("Eye ") or name in ("Smile", "Open mouth", "Surprised open mouth"):
            pairs += [("#3d5149", "#202b25")]
        recolor(layer.get("shapes", []), pairs)
    scene["layers"] = [layer for layer in layers if layer["ind"] not in removed]
    return scene
