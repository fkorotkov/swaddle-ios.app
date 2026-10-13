"""Shared original vector character rig from the reviewed Swaddle scenes.

Hands remain rounded and detail-free. Seated legs are short and tucked.
"""
from __future__ import annotations

import math
import copy

FPS, FRAMES = 30, 180
C = dict(ink="#3d5149", edge="#7f9a8b", paper="#f4efdf", light="#fff9ee",
         skin="#ecc19f", skin_light="#f7dcc0", skin_shadow="#d8a685",
         blush="#d79683", sage="#a8bda1", sage_light="#d7dfbd", sage_shadow="#829e85",
         blue="#a3c4ca", blue_light="#d4e6e6", blue_shadow="#7fa4ae",
         gold="#d1a775", gold_light="#efd5a8", gold_shadow="#b08860",
         rose="#d1a096", rose_light="#ebc7bb", rose_shadow="#b38379")


def rgba(value):
    value = C.get(value, value).lstrip("#")
    return [round(int(value[n:n + 2], 16) / 255, 5) for n in (0, 2, 4)] + [1]


def static(value):
    return {"a": 0, "k": value}


def animated(points, shape=False):
    frames = []
    for n, (time, value) in enumerate(points):
        wrap = lambda x: [x] if shape or isinstance(x, (int, float)) else x
        frame = {"t": time, "s": wrap(value)}
        if n + 1 < len(points):
            frame.update(e=wrap(points[n + 1][1]), i={"x": [0.67], "y": [1]},
                         o={"x": [0.33], "y": [0]})
        frames.append(frame)
    return {"a": 1, "k": frames}


def transform(at=(0, 0), scale=(100, 100), angle=0, opacity=100):
    return dict(a=static([0, 0]), p=static(list(at)), s=static(list(scale)),
                r=static(angle), o=static(opacity), sk=static(0), sa=static(0))


def contour(vertices, closed=True, smoothing=0.16):
    count = len(vertices)
    incoming, outgoing = [], []
    for n, point in enumerate(vertices):
        before = vertices[(n - 1) % count] if closed or n else point
        after = vertices[(n + 1) % count] if closed or n + 1 < count else point
        tangent = [(after[axis] - before[axis]) * smoothing for axis in (0, 1)]
        incoming.append([-v for v in tangent]); outgoing.append(tangent)
    return dict(v=[list(p) for p in vertices], i=incoming, o=outgoing, c=closed)


def path(vertices, closed=True, smoothing=0.16, name="Organic contour"):
    return dict(ty="sh", nm=name, ks=static(contour(vertices, closed, smoothing)))


def oval(x, y, w, h):
    return dict(ty="el", nm="Soft oval", p=static([x, y]), s=static([w, h]), d=1)


def group(geometry, fill=None, stroke=None, width=1, opacity=100, gradient=None):
    items = geometry if isinstance(geometry, list) else [geometry]
    if gradient:
        colors, start, end = gradient
        values = []
        for n, pigment in enumerate(colors): values += [n / (len(colors) - 1)] + rgba(pigment)[:3]
        items.append(dict(ty="gf", nm="Soft pigment wash", o=static(opacity), t=1,
                          g=dict(p=len(colors), k=static(values)), s=static(list(start)),
                          e=static(list(end)), r=1))
    elif fill:
        items.append(dict(ty="fl", nm="Pigment", c=static(rgba(fill)), o=static(opacity), r=1))
    if stroke:
        items.append(dict(ty="st", nm="Fine contour", c=static(rgba(stroke)), o=static(opacity),
                          w=static(width), lc=2, lj=2, ml=4))
    items.append(dict(ty="tr", **transform()))
    return dict(ty="gr", nm="Illustrated detail", it=items)


def limb_contour(points, widths):
    left, right = [], []
    for n, point in enumerate(points):
        before, after = points[max(n - 1, 0)], points[min(n + 1, len(points) - 1)]
        dx, dy = after[0] - before[0], after[1] - before[1]
        length = math.hypot(dx, dy) or 1
        normal = (-dy / length, dx / length)
        left.append([point[a] + normal[a] * widths[n] / 2 for a in (0, 1)])
        right.append([point[a] - normal[a] * widths[n] / 2 for a in (0, 1)])
    # Eight points preserve topology during morphs, including rounded joint ends.
    dx, dy = points[-1][0] - points[-2][0], points[-1][1] - points[-2][1]
    length = math.hypot(dx, dy) or 1
    tip = [points[-1][0] + dx / length * widths[-1] * 0.28,
           points[-1][1] + dy / length * widths[-1] * 0.28]
    dx, dy = points[0][0] - points[1][0], points[0][1] - points[1][1]
    length = math.hypot(dx, dy) or 1
    cap = [points[0][0] + dx / length * widths[0] * 0.28,
           points[0][1] + dy / length * widths[0] * 0.28]
    return contour(left + [tip] + list(reversed(right)) + [cap], smoothing=0.19)


class Scene:
    def __init__(self, name):
        self.name, self.layers, self.limbs = name, [], {}
        self.actor_roles = {}

    def actor(self, root, role="child"):
        self.actor_roles[root["ind"]] = role
        return root

    def actors(self):
        return [dict(id=key, role=value) for key, value in sorted(self.actor_roles.items())]

    def layer(self, name, shapes=None, at=(0, 0), parent=None, angle=0, scale=100):
        layer = dict(ind=len(self.layers) + 1, ty=4 if shapes else 3, nm=name,
                     ip=0, op=FRAMES, st=0, sr=1, ao=0,
                     ks=transform(at, (scale, scale), angle))
        if shapes: layer["shapes"] = list(reversed(shapes))
        if parent: layer["parent"] = parent["ind"]
        self.layers.append(layer)
        return layer

    def motion(self, layer, key, points):
        layer["ks"][key] = animated(points)

    def line(self, name, points, ink="edge", width=1, parent=None, opacity=100):
        return self.layer(name, [group(path(points, False), stroke=ink, width=width, opacity=opacity)], parent=parent)

    def limb(self, name, points, widths, parent, far=False):
        shape = dict(ty="sh", nm="Tapered anatomy", ks=static(limb_contour(points, widths)))
        layer = self.layer(name, [group(shape, gradient=(
            ["skin_shadow", "skin"] if far else ["skin_light", "skin", "skin_shadow"],
            points[0], [points[-1][0] + 12, points[-1][1]]))], parent=parent)
        self.limbs[layer["ind"]] = (shape, widths)
        return layer

    def bend(self, limb, points):
        shape, widths = self.limbs[limb["ind"]]
        shape["ks"] = animated([(t, limb_contour(p, widths)) for t, p in points], shape=True)

    def stage(self, kind):
        # A cut piece of cotton is the visual link to Swaddle's folded-fabric identity.
        self.layer("Cotton play cloth", [group(path([[71, 215], [163, 204], [297, 206],
            [365, 223], [333, 249], [147, 257], [54, 239]], smoothing=0.13),
            gradient=(["paper", "light", "paper"], [120, 215], [290, 261]))])
        self.layer("Folded hem", [group(path([[314, 247], [350, 234], [355, 224], [363, 226], [333, 249]], smoothing=0.08), "sage", opacity=21)])
        self.line("Cotton edge", [[78, 244], [175, 252], [270, 249], [320, 241]], "gold", 0.7, opacity=35)
        for n in range(13):
            x = 82 + n * 18
            self.line("Hem stitch " + str(n), [[x, 245], [x + 3.2, 245.7]], "light", 0.9, opacity=85)
        self.layer("Soft contact shadow", [group(oval(198, 237, 220, 11), "sage_shadow", opacity=12)])
        if kind == "stack":
            self.layer("Resting wooden ring", [group(oval(105, 230, 36, 12), stroke="gold", width=5),
                       group(path([[91, 226], [105, 222], [117, 225]], False), stroke="gold_light", width=1.4)])
        self.stage_layers = {layer["ind"] for layer in self.layers}

    def close_loop(self):
        """Reset one-way actions while faded, leaving the cotton ground steady.

        Full range playback always returns to identical key values. The reset
        happens below a zero-opacity parent, rather than reversing a skill.
        """
        def close(value):
            if isinstance(value, dict):
                if value.get("a") == 1 and isinstance(value.get("k"), list):
                    frames = value["k"]
                    first = copy.deepcopy(frames[0]["s"])
                    frames[:] = [f for f in frames if f["t"] <= 165]
                    previous = frames[-1]
                    last = copy.deepcopy(previous["s"])
                    previous["e"] = last
                    frames.extend([
                        dict(t=172, s=last, e=first, i={"x": [0.67], "y": [1]}, o={"x": [0.33], "y": [0]}),
                        dict(t=180, s=first)])
                else:
                    for nested in value.values(): close(nested)
            elif isinstance(value, list):
                for nested in value: close(nested)
        for layer in self.layers:
            if layer["ind"] not in self.stage_layers: close(layer)
        reset = self.layer("Loop reset · hidden return")
        for layer in self.layers[:-1]:
            if layer["ind"] not in self.stage_layers and "parent" not in layer:
                layer["parent"] = reset["ind"]
        self.motion(reset, "o", [(0, 0), (10, 100), (154, 100), (170, 0), (180, 0)])
        self.inherit_opacity()

    def inherit_opacity(self):
        """Lottie parenting carries transforms, not opacity.

        Bake the intended rig/group fades into each drawable layer. Most
        layers need only the shared reset track. Overlapping local fades are
        sampled every two frames with linear interpolation, preserving the
        original easing without relying on unsupported inherited opacity.
        """
        layers = {layer["ind"]: layer for layer in self.layers}
        original = {key: copy.deepcopy(layer["ks"]["o"]) for key, layer in layers.items()}

        def evaluate(prop, time):
            if prop["a"] == 0: return prop["k"]
            keys = prop["k"]
            if time <= keys[0]["t"]: return keys[0]["s"][0]
            for first, last in zip(keys, keys[1:]):
                if time <= last["t"]:
                    start, end = first["s"][0], first.get("e", last["s"])[0]
                    if start == end: return start
                    progress = (time-first["t"])/(last["t"]-first["t"])
                    x1, x2 = first.get("o", {}).get("x", [.33])[0], first.get("i", {}).get("x", [.67])[0]
                    y1, y2 = first.get("o", {}).get("y", [0])[0], first.get("i", {}).get("y", [1])[0]
                    def cubic(u, p1, p2): return 3*(1-u)**2*u*p1 + 3*(1-u)*u*u*p2 + u**3
                    low, high = 0., 1.
                    for _ in range(20):
                        mid=(low+high)*.5
                        if cubic(mid,x1,x2) < progress: low=mid
                        else: high=mid
                    return start+(end-start)*cubic((low+high)*.5,y1,y2)
            return keys[-1]["s"][0]

        for layer in self.layers:
            if layer["ty"] != 4: continue
            props, cursor = [], layer
            while True:
                prop=original[cursor["ind"]]
                if prop["a"] == 1 or prop["k"] != 100: props.append(prop)
                if "parent" not in cursor: break
                cursor=layers[cursor["parent"]]
            if not props: continue
            if len(props)==1:
                layer["ks"]["o"]=copy.deepcopy(props[0])
                continue
            values=[]
            for t in range(0,181,2):
                alpha=100.
                for prop in props: alpha*=evaluate(prop,t)/100
                values.append((t,round(alpha,5)))
            # Keep the ends of holds, and all samples along visible fades.
            values=[value for i,value in enumerate(values) if i in (0,len(values)-1)
                    or values[i-1][1]!=value[1] or values[i+1][1]!=value[1]]
            track=animated(values)
            for key in track["k"][:-1]:
                key["i"]={"x":[1],"y":[1]}; key["o"]={"x":[0],"y":[0]}
            layer["ks"]["o"]=track

    def bootie(self, name, at, parent, far=False, angle=0, front=False):
        root = self.layer(name, at=at, parent=parent, angle=angle)
        points = ([[-9, -9], [5, -11], [12, -5], [14, 3], [8, 10],
                   [-8, 10], [-14, 3], [-13, -5]] if front else
                  [[-13, -8], [-2, -12], [14, -8], [18, 0], [8, 6], [-12, 5], [-17, -1]])
        seam = [[-10, -5], [0, -3], [10, -5]] if front else [[-13, 2], [0, 4], [14, 1]]
        self.layer(name + " cotton sock", [group(path(points, smoothing=0.19),
            gradient=(["paper", "light"] if far else ["light", "paper"], [-9, -9], [12, 7])),
            group(path(seam, False), stroke="gold", width=0.7, opacity=45)], parent=root)
        if not front:
            self.line(name + " toe seam", [[-4, -8], [1, -2], [0, 3]], "gold", 0.7, root, 30)
        return root

    def hand(self, name, at, parent, angle=0, far=False):
        root = self.layer(name, at=at, parent=parent, angle=angle)
        points = [[-7, 11], [-10, 1], [-9, -10], [-2, -17], [7, -15],
                  [13, -8], [13, 2], [7, 12], [0, 14]]
        hand_shape = dict(ty="sh", nm="Simple rounded hand", ks=static(contour(points, smoothing=0.18)))
        self.layer(name + " palm", [group(hand_shape, gradient=(["skin", "skin_shadow"] if far else
            ["skin_light", "skin"], [-8, -20], [15, 13]))], parent=root)
        return root, hand_shape, points

    def head(self, parent, at, profile=False):
        root = self.layer("Head follow-through", at=at, parent=parent)
        self.layer("Neck", [group(path([[-10, 22], [10, 22], [11, 31], [-12, 31]], smoothing=0.15),
            gradient=(["skin", "skin_shadow"], [0, 22], [0, 31]))], parent=root)
        self.layer("Ears", [group([oval(-32, 5, 15, 22), oval(32, 5, 15, 22)], "skin"),
            group([oval(-34, 6, 6, 11), oval(34, 6, 6, 11)], "skin_shadow", opacity=48)], parent=root)
        face_points = [[0, -37], [26, -30], [33, -10], [34, 10], [23, 28],
                       [2, 35], [-22, 29], [-34, 13], [-34, -10], [-25, -30]]
        self.layer("Soft face", [group(path(face_points, smoothing=0.19),
            gradient=(["skin_light", "skin", "skin_shadow"], [-26, -31], [30, 38])),
            group([oval(-20, 13, 14, 8), oval(21, 13, 14, 8)], "blush", opacity=44)], parent=root)
        # Three Bézier locks retain the little curl without drawing an emoji head.
        self.line("Hair sweep", [[-15, -30], [-5, -38], [10, -35], [15, -28]], "ink", 2.3, root, 88)
        self.line("Baby curl", [[-3, -33], [-2, -42], [5, -44], [12, -41], [10, -36]], "ink", 2.1, root, 88)
        self.line("Wispy hair", [[-19, -24], [-16, -32], [-9, -35]], "gold_shadow", 1.1, root, 65)
        self.line("Brows", [[-16, -8], [-11, -10], [-6, -8]], "gold_shadow", 1.1, root, 65)
        self.line("Other brow", [[7, -8], [12, -10], [17, -8]], "gold_shadow", 1.1, root, 65)
        eyes = self.layer("Attentive gaze", at=(5 if profile else 0, 0), parent=root)
        xs = (-6, 17) if profile else (-12, 13)
        for n, x in enumerate(xs):
            self.layer("Eye " + str(n), [group(oval(x, 2, 4.8 if n == 0 or not profile else 4.1, 7), "ink"),
                group(oval(x - 0.6, 0.6, 1.3, 1.6), "light")], parent=eyes)
        self.line("Little nose", [[3, 7], [6, 11], [3, 13]], "skin_shadow", 1.1, root, 70)
        self.layer("Nose light", [group(oval(2, 9, 3, 3), "skin_light", opacity=65)], parent=root)
        mouth = path([[-8, 19], [0, 23], [9, 18]], False, 0.25, "Small smile")
        self.layer("Smile", [group(mouth, stroke="ink", width=1.7, opacity=85)], parent=root)
        self.line("Lower lip", [[-3, 26], [3, 26]], "blush", 1.1, root, 50)
        self.motion(eyes, "s", [(0, [100, 100]), (35, [100, 100]), (38, [100, 8]),
            (42, [100, 100]), (139, [100, 100]), (143, [100, 8]), (147, [100, 100]), (180, [100, 100])])
        return dict(root=root, eyes=eyes, mouth=mouth)

    def body(self, parent, crawl=False):
        root = self.layer("Soft cotton onesie", parent=parent)
        if crawl:
            points = [[-38, -90], [-12, -102], [27, -95], [44, -76], [35, -44],
                      [5, -32], [-31, -42], [-49, -61]]
            seam = [[-38, -81], [-20, -71], [-2, -60], [24, -43]]
        else:
            points = [[-12, -127], [17, -125], [31, -109], [31, -77], [24, -43],
                      [6, -34], [-19, -40], [-31, -70], [-31, -105]]
            seam = [[-17, -119], [-15, -99], [-2, -73], [19, -48]]
        self.layer("Cotton volume", [group(path(points, smoothing=0.19),
            gradient=(["sage_light", "sage", "sage_shadow"], [-34, -118], [41, -25]))], parent=root)
        self.line("Wrapped neckline", seam, "light", 2.3, root, 82)
        self.line("Seam shadow", [[p[0] + 2, p[1] + 1] for p in seam], "sage_shadow", 0.7, root, 65)
        folds = ([[-37, -72], [-23, -64], [-12, -63]], [[19, -87], [13, -80], [12, -75]]) if crawl else (
            [[-23, -78], [-16, -74], [-11, -73]], [[22, -58], [14, -61], [9, -59]])
        for n, fold in enumerate(folds):
            self.line("Fabric fold " + str(n), fold, "sage_shadow", 0.9, root, 60)
            self.line("Fabric fold light " + str(n), [[x, y - 1.2] for x, y in fold], "light", 0.7, root, 42)
        button_at = (17, -48) if crawl else (15, -61)
        self.layer("Pearl snap", [group(oval(*button_at, 4, 4), "light"),
            group(oval(button_at[0] + 0.7, button_at[1] + 0.6, 1, 1), "gold")], parent=root)
        return root

    def seated_baby(self, at=(190, 239)):
        root = self.layer("Seated baby · center of weight", at=at)
        self.actor(root)
        # Short, tucked legs with inward-facing shins read as sitting, rather
        # than the long outward diagonals of a standing pose.
        legs = [([[-18, -39], [-40, -15], [-22, -6]], [30, 27, 14]),
                ([[18, -39], [40, -15], [22, -6]], [30, 27, 14])]
        leg_layers, feet = [], []
        for n, (points, widths) in enumerate(legs):
            leg_layers.append(self.limb("Bent leg " + str(n), points, widths, root, far=n == 0))
            feet.append(self.bootie("Cotton bootie " + str(n), points[-1], root, far=n == 0,
                        angle=-3 if n == 0 else 3, front=True))
        body = self.body(root)
        head = self.head(root, (0, -151))
        arm_points = [[[-27, -116], [-46, -89], [-42, -57]], [[27, -114], [48, -91], [42, -62]]]
        arms, hands = [], []
        for n, points in enumerate(arm_points):
            arms.append(self.limb("Soft arm " + str(n), points, [18, 15, 11], root, far=n == 0))
            hands.append(self.hand("Hand " + str(n), points[-1], root, angle=-8 if n == 0 else 8))
        return dict(root=root, body=body, head=head, arms=arms, hands=hands, arm_points=arm_points,
                    legs=leg_layers, feet=feet, leg_points=[p for p, _ in legs])

    def animate_arm(self, baby, n, points, angles=None):
        self.bend(baby["arms"][n], points)
        self.motion(baby["hands"][n][0], "p", [(t, p[-1]) for t, p in points])
        if angles: self.motion(baby["hands"][n][0], "r", angles)

    def wave(self):
        self.stage("wave")
        baby = self.seated_baby((194, 239))
        rest = baby["arm_points"][1]
        lift = [[27, -114], [56, -140], [66, -174]]
        inward = [[27, -114], [53, -137], [58, -171]]
        outward = [[27, -114], [59, -140], [72, -175]]
        self.animate_arm(baby, 1, [(0, rest), (20, rest),
            (35, [[27, -114], [52, -103], [62, -113]]), (59, lift), (69, inward),
            (83, outward), (97, inward), (111, outward), (127, lift), (156, lift), (180, lift)],
            [(0, 10), (35, 17), (59, -7), (69, -23), (83, 9), (97, -22), (111, 8), (127, -6), (180, -6)])
        self.motion(baby["body"], "r", [(0, -1), (22, -2.8), (55, 2.4), (78, 1), (120, 0.8), (180, 0.8)])
        self.motion(baby["head"]["root"], "r", [(0, -5), (25, -6), (62, 5), (92, 3), (132, 1), (180, 1)])
        self.motion(baby["head"]["eyes"], "p", [(0, [-2, 0]), (18, [-2, 0]), (38, [1, -0.4]), (180, [1, -0.4])])
        baby["head"]["mouth"]["ks"] = animated([(0, contour([[-8, 19], [0, 23], [9, 18]], False, 0.25)),
            (58, contour([[-10, 18], [0, 25], [11, 17]], False, 0.25)),
            (180, contour([[-10, 18], [0, 25], [11, 17]], False, 0.25))], shape=True)
        self.motion(baby["body"], "s", [(0, [100, 100]), (55, [100.7, 100]),
            (100, [100, 100]), (145, [100.5, 100]), (180, [100, 100])])

    def crawl(self):
        self.stage("crawl")
        root = self.layer("Crawling · center of weight", at=(120, 238))
        self.actor(root)
        far_leg = self.limb("Far knee and shin", [[-26, -47], [-37, -12], [-70, -7]], [27, 24, 16], root, far=True)
        far_foot = self.bootie("Far bootie", (-70, -7), root, far=True, angle=-18)
        far_arm = self.limb("Far supporting arm", [[22, -71], [30, -33], [23, -5]], [19, 16, 11], root, far=True)
        far_hand = self.hand("Far palm", (23, -5), root, far=True, angle=84)[0]
        body = self.body(root, crawl=True)
        near_leg = self.limb("Near knee and shin", [[-34, -52], [-30, -7], [-64, -2]], [30, 26, 16], root)
        near_foot = self.bootie("Near bootie", (-64, -2), root, angle=-12)
        head = self.head(root, (54, -105), profile=True)
        near_arm = self.limb("Near supporting arm", [[33, -75], [52, -39], [54, -4]], [21, 17, 12], root)
        near_hand = self.hand("Near palm", (54, -4), root, angle=84)[0]
        times = list(range(0, 181, 18))
        centers = list(zip([112, 113, 127, 145, 164, 182, 200, 218, 224, 224, 224],
                           [238, 237, 236, 238, 237, 236, 238, 237, 238, 238, 238]))
        # Matching parent/limb key times keep planted contacts still on the cloth.
        # Opposite hand and knee lift together; the other pair carries the weight.
        contacts = [
            (far_arm, far_hand, [22, -71],
             list(zip([135, 152, 175, 175, 175, 211, 252, 252, 252, 252, 252],
                      [233, 217, 233, 233, 233, 217, 233, 233, 233, 233, 233]))),
            (near_arm, near_hand, [33, -75],
             list(zip([166, 166, 166, 212, 236, 236, 236, 267, 289, 289, 289],
                      [235, 235, 235, 213, 235, 235, 235, 213, 235, 235, 235]))),
        ]
        for arm, hand, shoulder, positions in contacts:
            frames = []
            for t, center, contact in zip(times, centers, positions):
                wrist = [contact[a] - center[a] for a in (0, 1)]
                elbow = [shoulder[0] * 0.48 + wrist[0] * 0.52 + 5,
                         shoulder[1] * 0.48 + wrist[1] * 0.52 - 2]
                frames.append((t, [shoulder, elbow, wrist]))
            self.bend(arm, frames)
            self.motion(hand, "p", [(t, p[-1]) for t, p in frames])
        knees = [
            (far_leg, far_foot, [-26, -47],
             list(zip([75, 75, 75, 120, 146, 146, 146, 185, 205, 205, 205],
                      [231, 231, 231, 220, 231, 231, 231, 220, 231, 231, 231]))),
            (near_leg, near_foot, [-34, -52],
             list(zip([82, 100, 112, 112, 112, 157, 184, 184, 184, 184, 184],
                      [232, 220, 232, 232, 232, 220, 232, 232, 232, 232, 232]))),
        ]
        for leg, foot, hip, positions in knees:
            frames = []
            for t, center, contact in zip(times, centers, positions):
                knee = [contact[a] - center[a] for a in (0, 1)]
                frames.append((t, [hip, knee, [knee[0] - 28, knee[1] + 5]]))
            self.bend(leg, frames)
            self.motion(foot, "p", [(t, p[-1]) for t, p in frames])
        self.motion(root, "p", [(t, list(p)) for t, p in zip(times, centers)])
        self.motion(body, "r", [(0, -1), (32, 2), (64, -1), (97, 2), (132, -1), (180, -1)])
        self.motion(head["root"], "r", [(0, 9), (35, 4), (69, 8), (108, 2), (151, -1), (180, -1)])
        self.motion(head["root"], "p", [(0, [54, -103]), (33, [54, -105]), (68, [54, -102]),
            (110, [54, -107]), (151, [54, -105]), (180, [54, -105])])
        self.motion(head["eyes"], "p", [(0, [6, 1]), (114, [6, 1]), (153, [6, -1]), (180, [6, -1])])

    def block(self, name, at, pigment):
        root = self.layer(name, at=at)
        # Three faces and subtle grain make this a small wooden object, not a UI tile.
        self.layer(name + " wood", [
            group(path([[-21, -13], [0, -25], [22, -13], [1, 0]], smoothing=0.035), pigment + "_light"),
            group(path([[-21, -13], [1, 0], [1, 26], [-21, 12]], smoothing=0.035),
                  gradient=([pigment, pigment + "_shadow"], [-19, -12], [1, 26])),
            group(path([[1, 0], [22, -13], [22, 12], [1, 26]], smoothing=0.035), pigment),
            group(path([[-19, -12], [1, -1], [19, -11]], False, 0.035), stroke="light", width=0.8, opacity=70)], parent=root)
        self.line(name + " grain", [[-17, 1], [-13, 5], [-5, 7]], pigment + "_shadow", 0.7, root, 45)
        self.line(name + " other grain", [[6, 9], [11, 6], [17, 6]], pigment + "_shadow", 0.6, root, 35)
        return root

    def stack(self):
        self.stage("stack")
        self.layer("Block contact shadow", [group(oval(315, 239, 63, 9), "sage_shadow", opacity=16)])
        self.block("Lower wooden block", (314, 212), "gold")
        baby = self.seated_baby((184, 239))
        rest = baby["arm_points"][1]
        arm_frames = [(0, rest), (17, rest), (42, [[27, -114], [54, -74], [60, -34]]),
            (66, [[27, -114], [66, -101], [73, -88]]),
            (99, [[27, -114], [77, -104], [108, -90]]),
            (125, [[27, -114], [76, -83], [110, -58]]),
            (137, [[27, -114], [76, -83], [110, -58]]),
            (157, [[27, -114], [64, -83], [72, -68]]), (180, [[27, -114], [64, -83], [72, -68]])]
        self.animate_arm(baby, 1, arm_frames, [(0, 10), (42, 58), (66, 75), (125, 75), (137, 75), (157, 10), (180, 10)])
        self.motion(baby["body"], "r", [(0, 0), (22, -2), (69, 4), (118, 3), (161, 0), (180, 0)])
        self.motion(baby["head"]["root"], "r", [(0, 5), (20, 7), (61, 11), (114, 9), (154, 3), (180, 3)])
        self.motion(baby["head"]["eyes"], "p", [(0, [3, 2]), (45, [3, 3]), (88, [4, 0]), (132, [4, 2]), (180, [4, 2])])
        upper = self.block("Upper wooden block", (264, 212), "blue")
        self.motion(upper, "p", [(0, [264, 212]), (42, [264, 212]), (66, [277, 159]),
            (99, [311, 157]), (125, [314, 186]), (132, [314, 187]), (141, [314, 186]), (180, [314, 186])])
        self.motion(upper, "r", [(0, -2), (42, -2), (66, -8), (99, 3), (125, 0), (180, 0)])
        baby["head"]["mouth"]["ks"] = animated([(0, contour([[-8, 19], [0, 23], [9, 18]], False, 0.25)),
            (134, contour([[-8, 19], [0, 23], [9, 18]], False, 0.25)),
            (157, contour([[-10, 18], [0, 25], [11, 17]], False, 0.25)),
            (180, contour([[-10, 18], [0, 25], [11, 17]], False, 0.25))], shape=True)

    def build(self, action, poster, description):
        getattr(self, action)()
        self.close_loop()
        return dict(v="5.12.2", fr=FPS, ip=0, op=FRAMES, w=420, h=280, nm=self.name,
                    ddd=0, assets=[], layers=list(reversed(self.layers)),
                    markers=[dict(tm=poster, cm="poster", dr=1)],
                    meta=dict(g="Swaddle original milestone illustration", a=description), swaddleActors=self.actors())

