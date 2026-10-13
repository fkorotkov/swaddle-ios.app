"""Skill-specific scenes, using the approved Swaddle character and cotton palette."""
from __future__ import annotations

from milestone_illustration_art import Scene, C, FRAMES, FPS, animated, contour, group, oval, path, rgba, static


def rounded(x, y, w, h, radius=7):
    return dict(ty="rc", nm="Soft corners", p=static([x, y]), s=static([w, h]), r=static(radius), d=1)


class CatalogScene(Scene):
    def move(self, layer, points): self.motion(layer, "p", points)
    def rotate(self, layer, points): self.motion(layer, "r", points)
    def fade(self, layer, points): self.motion(layer, "o", points)

    def recolor(self, layer, pigment):
        # Preserve the reviewed shading and seams when changing a cotton garment.
        mapping = {tuple(rgba("sage" + suffix)[:3]): rgba(pigment + suffix)[:3]
                   for suffix in ("", "_light", "_shadow")}
        def visit(node):
            if isinstance(node, dict):
                if node.get("ty") == "gf":
                    colors = node["g"]["k"]["k"]
                    for n in range(0, len(colors), 4):
                        colors[n + 1:n + 4] = mapping.get(tuple(colors[n + 1:n + 4]), colors[n + 1:n + 4])
                elif node.get("ty") in ("fl", "st"):
                    values = node["c"]["k"]
                    values[:3] = mapping.get(tuple(values[:3]), values[:3])
                for value in node.values(): visit(value)
            elif isinstance(node, list):
                for value in node: visit(value)
        visit(layer)

    def figure(self, at=(166, 239), pose="sit", scale=100, adult=False, pigment="sage", role=None):
        if pose in ("sit", "back"):
            baby = self.seated_baby(at)
            if pose == "back":
                # A horizontal, supported pose on the cloth. The face stays
                # readable while the torso and tucked legs lie along the mat.
                baby["root"]["ks"]["r"] = static(74)
                baby["head"]["root"]["ks"]["r"] = static(-74)
                for n, leg in enumerate(baby["legs"]):
                    sign = -1 if n == 0 else 1
                    points = [[sign * 18, -39], [sign * 32, -23], [sign * 26, -3]]
                    self.bend(leg, [(0, points), (180, points)])
                    baby["leg_points"][n] = points
                    baby["feet"][n]["ks"]["p"] = static(points[-1])
        else:
            root = self.layer("Supported adult" if adult else "Standing child · narrow stance", at=at)
            if pose == "tummy":
                leg_points = [[[-67, -32], [-92, -8], [-120, -4]], [[-62, -27], [-86, -4], [-111, -2]]]
                arm_points = [[[20, -46], [36, -11], [54, -5]], [[31, -47], [58, -11], [80, -5]]]
                head_at = (64, -64)
            else:
                leg_points = [[[-16, -67], [-19, -35], [-17, -7]], [[16, -67], [19, -35], [17, -7]]]
                arm_points = [[[-27, -142], [-44, -114], [-39, -88]], [[27, -142], [44, -114], [39, -88]]]
                head_at = (0, -179)
            legs, feet = [], []
            for n, pts in enumerate(leg_points):
                legs.append(self.limb("Grounded leg " + str(n), pts, [25, 21, 13], root, far=n == 0))
                feet.append(self.bootie("Grounded foot " + str(n), pts[-1], root, far=n == 0, front=pose != "tummy"))
            if pose == "tummy":
                body = self.layer("Tummy cotton volume", [group(path([[-79, -48], [-60, -58], [-12, -61],
                    [29, -47], [24, -26], [-16, -18], [-65, -20]], smoothing=0.14),
                    gradient=(["sage_light", "sage", "sage_shadow"], [-70, -56], [25, -19])),
                    group(path([[-56, -53], [-23, -41], [18, -29]], False), stroke="light", width=2, opacity=70)], parent=root)
            else:
                body = self.body(root)
                body["ks"]["p"] = static([0, -28])
            head = self.head(root, head_at, profile=pose == "tummy")
            arms, hands = [], []
            for n, pts in enumerate(arm_points):
                arms.append(self.limb("Reaching arm " + str(n), pts, [18, 15, 11], root, far=n == 0))
                hands.append(self.hand("Rounded hand " + str(n), pts[-1], root, far=n == 0,
                                       angle=80 if pose == "tummy" else (-8 if n == 0 else 8)))
            baby = dict(root=root, body=body, head=head, legs=legs, feet=feet,
                        leg_points=leg_points, arms=arms, hands=hands, arm_points=arm_points)
        baby["root"]["ks"]["s"] = static([scale, scale])
        baby.update(at=list(at), head_at=baby["head"]["root"]["ks"]["p"]["k"], pose=pose)
        if pigment != "sage":
            for layer in self.layers:
                if layer.get("parent") == baby["body"]["ind"] or layer == baby["body"]:
                    self.recolor(layer, pigment)
        if adult:
            head_root = baby["head"]["root"]
            old_hair = {"Hair sweep", "Baby curl", "Wispy hair"}
            self.layers[:] = [l for l in self.layers if not (l["nm"] in old_hair and l.get("parent") == head_root["ind"])]
            # Indices remain globally unique after removing the curl layers.
            self.next_index = max(l["ind"] for l in self.layers) + 1
            self.layer("Caregiver hair · neutral", [group(path([[-34, 3], [-35, -21], [-24, -38], [-1, -43],
                [24, -36], [35, -17], [34, 5], [27, -6], [22, -21], [4, -27], [-13, -22], [-24, -9]], smoothing=0.14),
                gradient=(["ink", "gold_shadow"], [-25, -37], [30, -1]))], parent=head_root)
            # Compact adult silhouettes; the final cast pass bakes independent
            # palettes into each actor without changing the movement rig.
            female = self.layer("Caregiver hair · female", [
                group(path([[-34, 10], [-39, -12], [-31, -35], [-8, -44], [16, -42],
                    [35, -25], [37, 5], [30, 18], [25, 1], [23, -17], [6, -27],
                    [-13, -24], [-25, -8], [-27, 12]], smoothing=.14),
                    gradient=(["ink", "gold_shadow"], [-27, -38], [32, 11])),
                group(oval(39, 13, 22, 25), gradient=(["ink", "gold_shadow"], [31, 3], [49, 25])),
                group(path([[34, 7], [42, 10], [44, 18]], False), stroke="gold_shadow", width=1.4, opacity=50)
            ], parent=head_root)
            female["hd"] = True
            male = self.layer("Caregiver hair · male", [
                group(path([[-34, -3], [-35, -23], [-25, -36], [-7, -41], [10, -42],
                    [27, -34], [35, -18], [32, -3], [25, -13], [17, -23], [4, -27],
                    [-8, -23], [-19, -22], [-28, -12]], smoothing=.12),
                    gradient=(["ink", "gold_shadow"], [-24, -36], [29, -7])),
                group(path([[-17, -33], [-4, -36], [11, -34]], False), stroke="gold_shadow", width=1.2, opacity=45)
            ], parent=head_root)
            male["hd"] = True
        self.actor(baby["root"], role or ("caregiver" if adult else "child"))
        return baby

    def layer(self, *args, **kwargs):
        # Layer order and IDs are independent; removed curl layers must not cause ID reuse.
        layer = super().layer(*args, **kwargs)
        next_id = getattr(self, "next_index", layer["ind"])
        layer["ind"] = max(layer["ind"], next_id)
        self.next_index = layer["ind"] + 1
        return layer

    def caregiver(self, at=(311, 244), *, standing=False):
        return self.figure(at, "stand" if standing else "sit", adult=True, pigment="blue", scale=106)

    def hand_to(self, baby, n, destination, *, time=64, hold=119, return_at=152, angle=0):
        rest = baby["arm_points"][n]
        shoulder = rest[0]
        target = [shoulder, [(shoulder[0] + destination[0]) * .5 + (6 if n else -6),
                              (shoulder[1] + destination[1]) * .5], list(destination)]
        self.animate_arm(baby, n, [(0, rest), (18, rest), (time, target), (hold, target),
                                   (return_at, rest), (180, rest)],
                         [(0, 8 if n else -8), (time, angle), (hold, angle), (return_at, 8 if n else -8), (180, 8 if n else -8)])
        return target

    def gaze(self, baby, *, side=1, down=False, start=22, end=65):
        self.move(baby["head"]["eyes"], [(0, [0, 0]), (start, [0, 0]),
                  (end, [side * 4, 3 if down else -1]), (129, [side * 4, 3 if down else -1]), (158, [0, 0]), (180, [0, 0])])
        self.rotate(baby["head"]["root"], [(0, -side * 3), (start, -side * 3),
                    (end, side * (9 if down else 6)), (125, side * (9 if down else 6)), (158, -side * 3), (180, -side * 3)])

    def smile(self, baby, *, start=35, sad=False):
        neutral = contour([[-8, 20], [0, 21], [9, 20]], False, .25)
        expressive = contour([[-9, 19 if not sad else 24], [0, 25 if not sad else 20],
                              [10, 18 if not sad else 24]], False, .25)
        beginning = [(0, neutral)] + ([(start, neutral)] if start > 0 else [])
        baby["head"]["mouth"]["ks"] = animated(beginning + [
            (start + 22, expressive), (130, expressive), (158, neutral), (180, neutral)], shape=True)

    def sounds(self, at, *, start=25, beats=2, parent=None, pigment="gold", large=False):
        # Visible curved breaths, never a rendered word or a recorded voice.
        layers = []
        for n in range(beats):
            wave = self.layer("Voice breath " + str(n), [group(path([[0, -9 - n * 4], [7 + n * 2, 0],
                             [0, 9 + n * 4]], False), stroke=pigment, width=1.8 if not large else 2.5)], at=at, parent=parent)
            t = start + n * 10
            self.fade(wave, [(0, 0), (t, 0), (t + 10, 100), (t + 26, 100), (t + 45, 0), (180, 0)])
            self.move(wave, [(0, list(at)), (t, list(at)), (t + 45, [at[0] + 11, at[1] - 3]), (180, [at[0] + 11, at[1] - 3])])
            layers.append(wave)
        return layers

    def talk(self, baby, *, start=25, beats=2, pigment="gold", large=False):
        mouth = self.layer("Soft speaking mouth", [group(oval(0, 21, 10 if not large else 13,
                     11 if not large else 15), "ink"), group(oval(0, 24, 6, 3), "rose")], parent=baby["head"]["root"])
        frames = [(0, 0)]
        for n in range(beats):
            t = start + n * 30
            frames += [(t, 0), (t + 8, 100), (t + 20, 0)]
        frames.append((180, 0)); self.fade(mouth, frames)
        self.sounds((baby["head_at"][0] + 44, baby["head_at"][1] - 8), start=start, beats=beats,
                    parent=baby["root"], pigment=pigment, large=large)

    def heart(self, at, parent=None):
        h = self.layer("Gentle connection", [group(path([[0, 12], [-13, 0], [-14, -9], [-5, -13],
             [0, -7], [5, -13], [14, -9], [13, 0]], smoothing=.16), "rose", opacity=72)], at=at, parent=parent)
        self.fade(h, [(0, 0), (52, 0), (72, 100), (120, 100), (153, 0), (180, 0)])
        self.move(h, [(0, list(at)), (52, list(at)), (130, [at[0], at[1] - 9]), (180, [at[0], at[1] - 9])])
        return h

    def prop(self, kind, at, *, parent=None, scale=100, name=None):
        root = self.layer(name or kind.title(), at=at, parent=parent, scale=scale)
        details = []
        if kind in ("rattle", "mobile"):
            details = [group(rounded(0, 17, 10, 36, 5), gradient=(["gold_light", "gold"], [-4, 0], [5, 33])),
                group(oval(0, -10, 35, 35), gradient=(["rose_light", "rose", "rose_shadow"], [-15, -25], [16, 7])),
                group([oval(-7, -13, 4, 4), oval(7, -5, 4, 4), oval(6, -17, 3, 3)], "light", opacity=85)]
        elif kind == "ring":
            details = [group(oval(0, 0, 40, 40), stroke="gold", width=9),
                       group(path([[-13, -11], [-5, -16], [6, -15]], False), stroke="gold_light", width=2)]
        elif kind == "ball":
            details = [group(oval(0, 0, 42, 42), gradient=(["gold_light", "gold", "gold_shadow"], [-19, -18], [18, 20])),
                group(path([[-11, -18], [-1, -4], [9, 7], [13, 16]], False), stroke="light", width=4, opacity=76)]
        elif kind in ("cup", "box"):
            details = [group(path([[-24, -21], [-21, 25], [21, 25], [24, -21]], smoothing=.06),
                         gradient=(["blue_light", "blue", "blue_shadow"], [-21, -21], [24, 24])),
                       group(oval(0, -21, 48, 12), "blue_shadow"),
                       group(path([[-22, -21], [0, -27], [22, -21]], False), stroke="light", width=1.8, opacity=85)]
        elif kind == "bottle":
            details = [group(rounded(0, 5, 32, 52, 10), gradient=(["light", "paper"], [-15, -16], [17, 31])),
                group(rounded(0, -22, 30, 8, 3), "sage"), group(rounded(0, -31, 12, 13, 6), "gold_light"),
                group([path([[4, -6], [11, -6]], False), path([[4, 3], [11, 3]], False), path([[4, 12], [11, 12]], False)], stroke="blue_shadow", width=1.2)]
        elif kind == "spoon":
            details = [group(rounded(0, 16, 7, 41, 3), "gold"),
                group(oval(0, -8, 18, 24), gradient=(["light", "paper"], [-7, -19], [8, 3]))]
        elif kind == "bear":
            details = [group([oval(-18, -25, 17, 17), oval(18, -25, 17, 17), oval(0, -10, 43, 42),
                       oval(0, 22, 43, 48), oval(-22, 29, 18, 20), oval(22, 29, 18, 20)],
                       gradient=(["gold_light", "gold", "gold_shadow"], [-22, -29], [25, 47])),
                group(oval(0, 0, 21, 13), "paper"), group([oval(-8, -11, 3.5, 4), oval(8, -11, 3.5, 4), oval(0, -1, 4, 3)], "ink")]
        elif kind == "phone":
            details = [group(rounded(0, 0, 26, 47, 9), gradient=(["blue_light", "blue", "blue_shadow"], [-11, -20], [13, 23])),
                group(rounded(0, -5, 16, 20, 3), "paper"), group([oval(-4, 13, 2.5, 2.5), oval(4, 13, 2.5, 2.5), oval(0, 18, 2.5, 2.5)], "light")]
        elif kind == "car":
            details = [group(rounded(0, 0, 66, 22, 8), gradient=(["sage_light", "sage", "sage_shadow"], [-29, -11], [32, 12])),
                group(rounded(-4, -15, 32, 24, 8), "blue"), group(rounded(-4, -16, 23, 13, 3), "blue_light"),
                group([oval(-22, 13, 16, 16), oval(22, 13, 16, 16)], "ink"),
                group([oval(-22, 13, 6, 6), oval(22, 13, 6, 6)], "gold_light")]
        elif kind == "crayon":
            details = [group(rounded(0, 0, 9, 39, 2), "rose"), group(path([[-4.5, -20], [0, -29], [4.5, -20]], smoothing=.02), "gold"),
                       group(rounded(0, 0, 9, 15, 0), "rose_light")]
        elif kind == "broom":
            details = [group(rounded(0, -31, 6, 96, 3), "gold"),
                group(path([[-6, 13], [-19, 43], [19, 43], [6, 13]], smoothing=.05), "paper"),
                group([path([[-5, 18], [-10, 38]], False), path([[0, 17], [0, 39]], False), path([[5, 18], [10, 38]], False)], stroke="gold", width=1.2)]
        elif kind == "bird":
            details = [group([oval(0, 0, 37, 24), oval(12, -10, 22, 22)], "gold"),
                group(path([[22, -11], [32, -7], [22, -3]], smoothing=.02), "rose"), group(oval(14, -12, 3.5, 3.5), "ink"),
                group(path([[-11, -3], [1, 8], [8, -3]], False), stroke="gold_light", width=3)]
        elif kind in ("plate", "paper"):
            details = ([group(oval(0, 0, 93, 32), "paper"), group(oval(0, -1, 70, 20), stroke="gold", width=1)] if kind == "plate" else
                       [group(path([[-44, -17], [35, -20], [45, 18], [-35, 21]], smoothing=.04), "light")])
        elif kind == "shirt":
            details = [group(path([[-14, -28], [-39, -13], [-30, 7], [-21, 1], [-20, 36], [20, 36], [21, 1], [30, 7], [39, -13], [14, -28], [8, -20], [-8, -20]], smoothing=.04),
                             gradient=(["blue_light", "blue", "blue_shadow"], [-35, -25], [31, 34])),
                       group(path([[-10, -24], [0, -18], [10, -24]], False), stroke="light", width=1.5)]
        elif kind == "cloth":
            details = [group(path([[-44, -34], [44, -34], [40, 29], [21, 34], [0, 30], [-20, 35], [-42, 30]], smoothing=.08),
                             gradient=(["paper", "light", "paper"], [-40, -34], [42, 34])),
                       group(path([[-31, -24], [-29, 21], [-5, 27]], False), stroke="gold", width=.8, opacity=45)]
        elif kind == "mirror":
            self.actor(root)
            details = [group(oval(0, 0, 79, 91), "gold"), group(oval(0, 0, 67, 79), "blue_light"),
                group(oval(0, 0, 42, 45), "skin_light"), group([oval(-8, 0, 3.5, 5), oval(8, 0, 3.5, 5)], "ink"),
                group(path([[-7, 12], [0, 16], [7, 12]], False), stroke="ink", width=1.2)]
        elif kind == "speaker":
            details = [group(path([[-23, -10], [-11, -10], [5, -22], [5, 22], [-11, 10], [-23, 10]], smoothing=.04), "blue")]
        elif kind == "switch":
            details = [group(rounded(0, 0, 66, 44, 13), "blue"), group(oval(-16, 0, 17, 17), "gold"),
                       group(oval(16, 0, 16, 16), "rose"), group(path([[-28, -16], [0, -19], [26, -15]], False), stroke="blue_light", width=1)]
        elif kind == "book":
            details = [group(path([[-56, -30], [-8, -28], [0, -18], [8, -28], [56, -30], [56, 30], [8, 36], [0, 28], [-8, 36], [-56, 30]], smoothing=.035), "gold"),
                group(path([[-53, -28], [-7, -25], [0, -16], [0, 27], [-7, 32], [-53, 27]], smoothing=.035), "light"),
                group(path([[0, -16], [7, -25], [53, -28], [53, 27], [7, 32], [0, 27]], smoothing=.035), "paper"),
                group(path([[0, -16], [0, 28]], False), stroke="gold_shadow", width=.8),
                group([oval(26, -1, 22, 22), oval(18, -12, 8, 8), oval(34, -12, 8, 8)], "gold"),
                group([path([[-42, -11], [-16, -11]], False), path([[-42, 0], [-22, 0]], False), path([[-42, 11], [-16, 11]], False)], stroke="sage", width=2)]
        else:
            raise ValueError("Unknown illustration prop: " + kind)
        self.layer((name or kind.title()) + " illustrated material", details, parent=root)
        return root

    def sofa(self):
        return self.layer("Low cloth sofa", [group(rounded(296, 174, 142, 73, 19), "sage_light"),
             group(rounded(295, 213, 148, 28, 11), gradient=(["sage", "sage_shadow"], [223, 201], [369, 229])),
             group([rounded(237, 235, 10, 15, 2), rounded(352, 235, 10, 15, 2)], "gold_shadow"),
             group(path([[229, 167], [295, 170], [358, 167]], False), stroke="light", width=1.1, opacity=70)])

    def food(self, at, parent=None, *, name="Small food piece"):
        return self.layer(name, [group(oval(0, 0, 8, 7), "gold_light"),
                                 group(path([[-2, -1], [1, 0]], False), stroke="gold", width=.8)], at=at, parent=parent)

    def footsteps(self, baby, *, running=False, distance=75):
        times = [0, 24, 48, 72, 96, 120, 150, 180]
        xs = [baby["at"][0], baby["at"][0], baby["at"][0] + distance*.2, baby["at"][0] + distance*.45,
              baby["at"][0] + distance*.7, baby["at"][0] + distance, baby["at"][0] + distance, baby["at"][0] + distance]
        ys = [baby["at"][1], baby["at"][1], baby["at"][1] - (4 if running else 1), baby["at"][1],
              baby["at"][1] - (4 if running else 1), baby["at"][1], baby["at"][1], baby["at"][1]]
        self.move(baby["root"], list(zip(times, zip(xs, ys))))
        for n, leg in enumerate(baby["legs"]):
            hip = baby["leg_points"][n][0]
            poses = []
            for j, t in enumerate(times):
                offset = (-1 if (j + n) % 2 else 1) * (16 if running else 11)
                ankle = [hip[0] + offset, -7 if (j + n) % 2 else -19 if running else -13]
                knee = [(hip[0] + ankle[0])*.5 + (3 if n else -3), -36 if (j+n)%2 else -42]
                poses.append((t, [hip, knee, ankle]))
            self.bend(leg, poses)
            self.move(baby["feet"][n], [(t, pts[-1]) for t, pts in poses])
            rest = baby["arm_points"][n]
            self.animate_arm(baby, n, [(t, [rest[0], [rest[1][0] + (7 if (j+n)%2 else -7), rest[1][1]],
                                [rest[2][0] + (11 if (j+n)%2 else -11), rest[2][1] - (8 if running else 0)]]) for j,t in enumerate(times)])
        self.rotate(baby["head"]["root"], [(0, 0), (48, -3), (72, 2), (96, -3), (120, 2), (150, 0), (180, 0)])

    def compose(self, skill, board):
        action, prop = board["action"], board["prop"]
        months = skill.get("months") or 12
        self.stage(action)
        if prop == "sofa": self.sofa()
        if prop == "steps":
            self.layer("Three low steps", [group(path([[223, 239], [223, 219], [261, 219], [261, 199],
                      [299, 199], [299, 179], [345, 179], [345, 239]], smoothing=.015),
                      gradient=(["blue_light", "blue", "blue_shadow"], [224, 179], [346, 239])),
                      group([path([[224, 219], [261, 219]], False), path([[262, 199], [299, 199]], False),
                             path([[300, 179], [343, 179]], False)], stroke="light", width=1.4)])
        standing = {"pull-stand", "cruise", "first-steps", "explore-check", "walk", "run", "stairs",
                    "stand-help", "walk-help", "stand-balance", "walk-independent", "kick-ball", "climb-sofa", "sweep"}
        tummy = {"head-lift", "forearm-push", "straight-push", "roll"}
        pose = "stand" if action in standing else "tummy" if action in tummy else "back" if action == "limbs" else "sit"
        caregivers = {"calm", "look-face", "arrival", "shared-smile", "track-person", "attention-smile", "chuckle",
                      "get-attention", "answer-sound", "turn-voice", "steady-head", "recognize", "take-turns", "shy",
                      "name-response", "caregiver-leaves", "peekaboo", "arms-up", "pat-a-cake", "parent-name", "pause-no",
                      "held-cup", "show-toy", "cuddle", "give-gesture", "explore-check", "read-together", "give-voice",
                      "comfort", "check-face", "stand-help", "walk-help"}
        adult = self.caregiver((302 if action != "shy" else 267, 244), standing=action == "walk-help") if action in caregivers else None
        baby = self.figure((140 if pose == "back" else 143 if adult else 173, 239), pose, scale=87 if months <= 4 else 100)
        head = baby["head"]
        poster = 100

        if action in {"calm", "cuddle", "shy", "comfort"}:
            dest = [219 if action != "comfort" else 237, 239]
            self.move(baby["root"], [(0, baby["at"]), (24, baby["at"]), (80, dest), (136, dest), (180, dest)])
            self.rotate(baby["root"], [(0, 0), (75, -10 if action == "shy" else 8), (137, -10 if action == "shy" else 8), (180, 0)])
            self.hand_to(adult, 0, [-74, -88], time=75, hold=139, return_at=160, angle=-30)
            self.hand_to(baby, 1, [48, -104], time=80, hold=135, angle=40)
            self.smile(baby, start=45, sad=action == "shy")
            if action == "comfort": self.smile(adult, start=0, sad=True)
            else: self.heart((246, 50))
            if action == "calm":
                self.motion(head["eyes"], "s", [(0, [100, 100]), (50, [100, 100]), (90, [100, 20]), (140, [100, 20]), (180, [100, 100])])
            if action == "shy":
                stranger = self.figure((352, 235), "stand", scale=60, adult=True, pigment="rose", role="other")
                self.fade(stranger["root"], [(0, 0), (21, 0), (64, 70), (132, 70), (165, 0), (180, 0)])
        elif action in {"look-face", "track-person", "look-toy", "look-hands", "turn-voice", "name-response", "named-object", "check-face", "recognize"}:
            self.gaze(baby, down=action == "named-object")
            if adult: self.gaze(adult, side=-1)
            if action == "track-person":
                self.move(adult["root"], [(0, [273, 244]), (24, [273, 244]), (95, [335, 244]), (140, [335, 244]), (180, [273, 244])])
            if action == "look-toy":
                toy = self.prop("rattle", (285, 131))
                self.rotate(toy, [(0, -8), (44, 9), (88, -8), (132, 9), (180, -8)])
            if action == "look-hands":
                self.hand_to(baby, 0, [-22, -138], angle=-10)
                self.hand_to(baby, 1, [25, -139], angle=15)
                self.gaze(baby, down=True)
            if action in {"turn-voice", "name-response"}: self.talk(adult, start=15, beats=1, pigment="blue_shadow")
            if action == "named-object":
                self.prop("ball", (285, 218)); self.sounds((314, 108), start=22, beats=1)
            if action == "check-face": self.prop("rattle", (359, 205), scale=65)
            if action == "recognize": self.smile(baby, start=70); self.heart((221, 58))
        elif action in {"arrival", "shared-smile", "attention-smile", "chuckle", "get-attention", "laugh"}:
            self.smile(baby, start=32)
            if adult: self.smile(adult, start=15); self.gaze(adult, side=-1)
            if action == "arrival":
                self.move(adult["root"], [(0, [352, 244]), (28, [352, 244]), (84, [285, 244]), (145, [285, 244]), (180, [352, 244])])
            if action in {"chuckle", "laugh", "get-attention"}:
                self.move(baby["root"], [(0, baby["at"]), (35, baby["at"]),
                    (46, [baby["at"][0], 234]), (57, baby["at"]), (68, [baby["at"][0], 234]), (79, baby["at"]), (180, baby["at"])])
                self.talk(baby, start=42, beats=3 if action == "laugh" else 2, large=action == "laugh")
            if action in {"attention-smile", "get-attention"}: self.hand_to(baby, 1, [47, -145], time=61, hold=115)
            if action == "shared-smile": self.heart((222, 62))
        elif action in {"coo", "vowels", "answer-sound", "take-turns", "raspberry", "squeal", "babble", "parent-name", "object-word", "many-words", "two-words"}:
            start = 65 if action in {"answer-sound", "take-turns"} else 27
            beats = 3 if action in {"babble", "many-words"} else 2
            self.talk(baby, start=start, beats=beats, large=action in {"squeal", "two-words"})
            poster=start+12
            self.gaze(baby, side=1)
            if adult: self.talk(adult, start=15, beats=1, pigment="blue_shadow"); self.gaze(adult, side=-1)
            if action == "take-turns": self.talk(adult, start=126, beats=1, pigment="blue_shadow")
            if action == "raspberry":
                tongue = self.layer("Rounded little tongue", [group(rounded(0, 24, 7, 9, 4), "rose")], parent=head["root"])
                self.fade(tongue, [(0, 0), (29, 0), (38, 100), (73, 100), (96, 0), (180, 0)])
                self.sounds((53, -118), start=38, beats=3, parent=baby["root"], pigment="rose")
            if action == "object-word":
                self.prop("ball", (293, 218)); self.hand_to(baby, 1, [81, -56], time=65, hold=116, angle=60)
            if action == "many-words":
                for n, kind in enumerate(("ball", "cup", "book")):
                    toy = self.prop(kind, (260 + n * 42, 215), scale=45)
                    self.fade(toy, [(0, 45), (25+n*26, 45), (38+n*26, 100), (135, 100), (180, 45)])
            if action == "two-words": self.prop("bottle", (297, 195)); self.hand_to(baby, 1, [85, -63], time=68, angle=65)
        elif action == "sound-react":
            self.prop("speaker", (291, 137)); self.sounds((313, 137), start=20, beats=3, pigment="blue_shadow")
            self.gaze(baby, start=29, end=51); self.talk(baby, start=61, beats=1)
            self.rotate(head["root"], [(0, -7), (31, -7), (48, 9), (117, 9), (150, -7), (180, -7)])
        elif action in {"head-lift", "forearm-push", "straight-push"}:
            self.move(head["root"], [(0, [64, -39]), (23, [64, -39]), (78, [64, -73]), (127, [64, -73]), (156, [64, -39]), (180, [64, -39])])
            self.rotate(head["root"], [(0, 16), (78, -5), (127, -5), (156, 16), (180, 16)])
            if action != "head-lift":
                for n, arm in enumerate(baby["arms"]):
                    rest = baby["arm_points"][n]
                    target = [[20+n*11, -61 if action == "straight-push" else -49],
                              [39+n*16, -32 if action == "straight-push" else -12], [54+n*26, -5]]
                    self.animate_arm(baby, n, [(0, rest), (23, rest), (78, target), (127, target), (156, rest), (180, rest)])
                if action == "straight-push": self.move(baby["body"], [(0, [0, 0]), (78, [0, -17]), (127, [0, -17]), (156, [0, 0]), (180, [0, 0])])
        elif action == "limbs":
            for n, limb in enumerate(baby["arms"] + baby["legs"]):
                rest = (baby["arm_points"] + baby["leg_points"])[n]
                frames = []
                for j, t in enumerate((0, 27, 54, 81, 108, 135, 158, 180)):
                    delta = (10 if (j+n)%2 else -8)
                    frames.append((t, [rest[0], [rest[1][0], rest[1][1]-delta], [rest[2][0]+delta*.5, rest[2][1]-delta]]))
                self.bend(limb, frames)
                endcap = baby["hands"][n][0] if n<2 else baby["feet"][n-2]
                self.move(endcap, [(t, pts[-1]) for t,pts in frames])
        elif action == "open-hand":
            self.hand_to(baby, 1, [39, -139], angle=8)
            hand_root, hand_shape, vertices = baby["hands"][1]
            closed = contour([[x*.66, y*.76] for x,y in vertices], smoothing=.18)
            opened = contour(vertices, smoothing=.18)
            hand_shape["ks"] = animated([(0, closed), (34, closed), (68, opened), (111, opened), (147, closed), (180, closed)], shape=True)
            self.gaze(baby, down=True)
        elif action == "anticipate-bottle":
            bottle = self.prop("bottle", (304, 148))
            self.move(bottle, [(0, [329, 170]), (25, [329, 170]), (83, [246, 112]), (131, [246, 112]), (160, [329, 170]), (180, [329, 170])])
            self.rotate(bottle, [(0, -15), (83, -45), (131, -45), (180, -15)])
            self.talk(baby, start=68, beats=1); self.gaze(baby)
        elif action == "steady-head":
            self.move(baby["root"], [(0, [214, 231]), (45, [214, 227]), (89, [214, 231]), (133, [214, 227]), (180, [214, 231])])
            self.hand_to(adult, 0, [-85, -77], time=32, hold=144, return_at=163, angle=-60)
            self.hand_to(adult, 1, [-51, -37], time=32, hold=144, return_at=163, angle=-75)
            self.rotate(head["root"], [(0, 0), (180, 0)])
        elif action in {"hold-toy", "reach-grab", "show-toy"}:
            dest = [63, -51] if action != "show-toy" else [68, -146]
            rest=baby["arm_points"][1]
            pickup=[rest[0],[55,-74],[76,-29]]
            held=[rest[0],[46,-137] if action=="show-toy" else [48,-87],dest]
            if action == "hold-toy":
                frames=[(0,rest),(23,rest),(78,held),(123,held),(158,rest),(180,rest)]
                toy=self.prop("rattle",(0,0),parent=baby["root"])
                self.move(toy,[(t,[pts[-1][0]+6,pts[-1][1]-9]) for t,pts in frames])
            else:
                frames=[(0,rest),(18,rest),(55,pickup),(78,held),(123,held),(139,pickup),(158,rest),(180,rest)]
                toy=self.prop("rattle",(82,-39),parent=baby["root"])
                self.move(toy,[(0,[82,-39]),(55,[82,-39]),(78,[dest[0]+6,dest[1]-9]),
                               (123,[dest[0]+6,dest[1]-9]),(139,[82,-39]),(180,[82,-39])])
            self.animate_arm(baby,1,frames,[(0,8),(55,28),(78,28),(123,28),(158,8),(180,8)])
            self.rotate(toy, [(0, 8), (78, -12), (123, -12), (180, 8)])
            self.gaze(baby, down=action != "show-toy")
            if adult: self.gaze(adult, side=-1); self.smile(adult, start=83)
        elif action == "bat-toy":
            self.line("Hanging cotton cord", [[272, 25], [272, 92]], "gold", 1.2)
            toy = self.prop("rattle", (272, 117))
            self.hand_to(baby, 1, [87, -127], time=65, hold=75, return_at=116, angle=60)
            self.rotate(toy, [(0, -4), (61, -4), (73, 23), (91, -17), (111, 11), (137, -6), (180, -4)])
            self.move(toy, [(0, [272,117]), (61, [272,117]), (73, [285,113]), (91, [261,116]), (111, [280,116]), (137, [267,117]), (180, [272,117])])
        elif action in {"hand-mouth", "explore-mouth"}:
            self.hand_to(baby, 1, [6, -132], time=69, hold=123, angle=-20)
            if action == "hand-mouth": self.hand_to(baby, 0, [-6, -132], time=73, hold=123, angle=20)
            else:
                ring = self.prop("ring", (215, 201))
                self.move(ring, [(0,[215,201]), (23,[215,201]), (69,[baby["at"][0]+6,105]), (123,[baby["at"][0]+6,105]), (156,[215,201]), (180,[215,201])])
            self.gaze(baby, down=True)
        elif action == "mirror":
            mirror = self.prop("mirror", (287, 153)); self.gaze(baby); self.smile(baby, start=64)
            self.rotate(mirror, [(0,-3), (76,3), (132,3), (180,-3)])
        elif action == "closed-lips":
            spoon = self.prop("spoon", (301, 124))
            self.move(spoon, [(0,[324,128]), (22,[324,128]), (76,[223,118]), (115,[223,118]), (155,[324,128]), (180,[324,128])])
            self.rotate(spoon, [(0,-65),(76,-70),(180,-65)])
            self.gaze(baby, side=-1); self.smile(baby, start=0)
        elif action == "roll":
            # Change the view of the tucked torso around its long axis. Avoid
            # pivoting the entire child through the floor like a cartwheel.
            supine = self.figure((118,239), "back", scale=90)
            self.fade(supine["root"], [(0,0),(66,0),(93,100),(157,100),(180,0)])
            self.rotate(supine["root"], [(0,66),(66,66),(108,74),(157,74),(180,66)])
            self.rotate(baby["root"], [(0,0),(27,0),(72,9),(157,9),(180,0)])
            self.fade(baby["root"], [(0,100),(66,100),(93,0),(157,0),(180,100)])
            self.hand_to(baby, 1, [47,-76], time=66, hold=130, angle=-40)
            poster=122
        elif action in {"supported-sit", "sit-alone", "sit-balance", "get-sitting"}:
            if action == "supported-sit":
                for n in (0,1): self.hand_to(baby,n,[-40 if n==0 else 40,-13],time=54,hold=142,return_at=164,angle=65 if n else -65)
                self.rotate(baby["root"], [(0,0),(54,5),(107,2),(144,5),(180,0)])
            elif action == "get-sitting":
                self.rotate(baby["root"], [(0,-40),(21,-40),(58,-16),(94,0),(153,0),(180,-40)])
                self.move(baby["root"], [(0,[153,241]),(21,[153,241]),(94,[173,239]),(153,[173,239]),(180,[153,241])])
                self.hand_to(baby,0,[-54,-8],time=39,hold=68,return_at=117,angle=-70)
            else:
                self.rotate(baby["root"], [(0,0),(38,-3),(81,3),(123,-1),(157,0),(180,0)])
                if action == "sit-balance": self.hand_to(baby,1,[77,-98],time=75,hold=111,return_at=150,angle=60)
                else: self.hand_to(baby,1,[51,-78],time=78,hold=120,return_at=158,angle=30)
        elif action == "expressions":
            shapes = [contour([[-9,19],[0,25],[10,18]],False,.25), contour([[-9,24],[0,19],[10,24]],False,.25),
                      contour([[-6,21],[0,21],[6,21]],False,.25), contour([[-9,20],[0,18],[10,20]],False,.25)]
            head["mouth"]["ks"] = animated([(0,shapes[0]),(31,shapes[0]),(51,shapes[1]),(72,shapes[1]),
                         (94,shapes[2]),(115,shapes[2]),(135,shapes[3]),(159,shapes[3]),(180,shapes[0])],shape=True)
            surprised=self.layer("Surprised open mouth",[group(oval(0,21,9,11),"ink")],parent=head["root"])
            self.fade(surprised,[(0,0),(79,0),(94,100),(109,100),(123,0),(180,0)])
            self.rotate(head["root"],[(0,-3),(51,3),(94,0),(135,-3),(180,-3)])
        elif action == "caregiver-leaves":
            self.move(adult["root"],[(0,[274,244]),(28,[274,244]),(99,[356,244]),(145,[356,244]),(180,[274,244])])
            self.hand_to(baby,1,[82,-111],time=83,hold=138,angle=60); self.smile(baby,start=56,sad=True)
        elif action == "peekaboo":
            cloth=self.prop("cloth",(302,89),scale=95)
            self.move(cloth,[(0,[302,89]),(31,[302,89]),(65,[302,173]),(94,[302,173]),(120,[302,89]),(155,[302,89]),(180,[302,89])])
            self.hand_to(adult,0,[-39,-97],time=65,hold=94,return_at=120,angle=-60)
            self.smile(baby,start=56); self.talk(baby,start=74,beats=1)
            poster=82
        elif action == "arms-up":
            self.hand_to(baby,0,[-45,-167],time=63,hold=135,angle=-18)
            self.hand_to(baby,1,[45,-167],time=63,hold=135,angle=18)
            self.hand_to(adult,0,[-75,-97],time=108,hold=139,angle=-65); self.gaze(baby)
        elif action == "dropped-toy":
            toy=self.prop("rattle",(279,128))
            self.move(toy,[(0,[279,128]),(32,[279,128]),(62,[283,227]),(72,[283,218]),(83,[283,227]),(147,[283,227]),(180,[279,128])])
            self.rotate(toy,[(0,-12),(32,-12),(62,49),(83,65),(180,-12)]); self.gaze(baby,down=True,start=41,end=80)
        elif action in {"bang-objects", "hand-transfer", "clap", "pat-a-cake"}:
            left=baby["arm_points"][0]; right=baby["arm_points"][1]
            for n in (0,1):
                side=-1 if n==0 else 1; rest=baby["arm_points"][n]
                wide=[rest[0],[side*39,-98],[side*39,-95]]
                together=[rest[0],[side*26,-99],[side*9,-101]]
                frames=[(0,rest),(30,wide),(53,together),(72,wide),(92,together),(110,wide),(130,together),(157,rest),(180,rest)]
                self.animate_arm(baby,n,frames,[(0,side*8),(30,side*40),(53,side*70),(130,side*70),(157,side*8),(180,side*8)])
                if action=="bang-objects":
                    block=self.block("Hand block "+str(n),(0,0),"gold" if n==0 else "blue")
                    block["parent"]=baby["root"]["ind"]; block["ks"]["s"]=static([60,60])
                    self.move(block,[(t,[p[-1][0],p[-1][1]-12]) for t,p in frames])
            if action=="hand-transfer":
                ring=self.prop("ring",(-40,-99),parent=baby["root"],scale=65)
                self.move(ring,[(0,[-40,-99]),(30,[-40,-99]),(53,[-5,-111]),(72,[0,-111]),(110,[38,-105]),(152,[38,-105]),(180,[-40,-99])])
            if action=="pat-a-cake":
                for n in (0,1): self.hand_to(adult,n,[-49+n*20,-111],time=67,hold=121,angle=-80)
            if action=="clap": self.smile(baby,start=39); self.heart((243,71))
        elif action in {"rake-food", "pincer", "finger-food", "self-feed", "try-spoon", "spoon-feed"}:
            self.prop("plate",(282,225))
            for n in range(4): self.food((264+n*12,220+(n%2)*3),name="Food on plate "+str(n))
            rest=baby["arm_points"][1]
            at_plate=[rest[0],[57,-72],[89,-28]]
            at_mouth=[rest[0],[43,-114],[8,-132]]
            target=at_plate if action=="rake-food" else at_mouth if action in {"finger-food","self-feed","try-spoon","spoon-feed"} else [rest[0],[58,-77],[90,-65]]
            frames=[(0,rest),(26,rest),(54,at_plate),(100,target),(126,target),(157,rest),(180,rest)]
            self.animate_arm(baby,1,frames,[(0,8),(54,70),(100,-15 if target==at_mouth else 65),(126,-15 if target==at_mouth else 65),(157,8),(180,8)])
            self.gaze(baby,down=True)
            if action=="rake-food":
                for n in range(3):
                    food=self.food((274+n*10,220),name="Food drawn closer "+str(n))
                    self.move(food,[(0,[274+n*10,220]),(53,[274+n*10,220]),(111,[241+n*9,222]),(154,[241+n*9,222]),(180,[274+n*10,220])])
            elif action in {"try-spoon","spoon-feed"}:
                spoon=self.prop("spoon",(0,0),parent=baby["root"],scale=70)
                self.move(spoon,[(t,[p[-1][0],p[-1][1]-10]) for t,p in frames])
                self.rotate(spoon,[(0,15),(54,80),(100,-20),(126,-20),(180,15)])
                if action=="try-spoon":
                    dropped=self.food((247,142),name="Small dropped spoonful")
                    self.fade(dropped,[(0,0),(109,0),(113,100),(139,100),(153,0),(180,0)])
                    self.move(dropped,[(0,[247,142]),(111,[247,142]),(141,[257,227]),(180,[257,227])])
            else:
                food=self.food((263,220),name="Picked-up bite")
                self.move(food,[(0,[263,220]),(54,[263,220]),(100,[baby["at"][0]+target[-1][0],baby["at"][1]+target[-1][1]-10]),(127,[baby["at"][0]+target[-1][0],baby["at"][1]+target[-1][1]-10]),(180,[263,220])])
                if target==at_mouth:self.fade(food,[(0,100),(113,100),(125,0),(180,0)])
        else:
            poster=self.later_scene(action,prop,baby,adult)
        self.close_loop()
        return dict(v="5.12.2",fr=FPS,ip=0,op=FRAMES,w=420,h=280,nm=skill["id"],ddd=0,assets=[],
                    layers=list(reversed(self.layers)),markers=[dict(tm=poster,cm="poster",dr=1)],
                    meta=dict(g="Swaddle original milestone illustration",a=board["description"],loop="gentle hidden reset"),
                    swaddleActors=self.actors())

    def later_scene(self, action, prop, baby, adult):
        poster=100
        if action == "pause-no":
            toy=self.prop("rattle",(284,219))
            rest=baby["arm_points"][1]; reach=[rest[0],[63,-84],[84,-52]]
            stopped=[rest[0],[51,-95],[61,-69]]
            self.animate_arm(baby,1,[(0,rest),(20,rest),(66,reach),(81,reach),(103,stopped),(140,stopped),(163,rest),(180,rest)])
            self.talk(adult,start=65,beats=1,pigment="blue_shadow"); self.gaze(baby)
        elif action in {"put-container", "find-hidden", "copy-play"}:
            if action == "put-container":
                container=self.prop("box",(292,211),scale=115)
                block=self.block("Block being placed",(244,214),"gold")
                block["ks"]["s"]=static([66,66])
                self.move(block,[(0,[244,214]),(31,[244,214]),(69,[269,164]),(96,[292,176]),(125,[292,206]),(155,[292,206]),(180,[244,214])])
                self.fade(block,[(0,100),(107,100),(125,0),(180,0)])
                self.hand_to(baby,1,[98,-61],time=102,hold=132,angle=75)
            elif action == "find-hidden":
                self.prop("rattle",(281,211),scale=80)
                cloth=self.prop("cloth",(281,189),scale=80)
                self.move(cloth,[(0,[281,189]),(26,[281,189]),(91,[312,128]),(139,[312,128]),(180,[281,189])])
                self.rotate(cloth,[(0,-5),(91,17),(139,17),(180,-5)])
                self.hand_to(baby,1,[113,-109],time=91,hold=139,return_at=165,angle=35)
                self.smile(baby,start=85); self.gaze(baby,down=True)
            else:
                playmate=self.figure((313,239),scale=76,pigment="blue",role="other")
                self.prop("box",(285,220),scale=63)
                for n, rig in enumerate((playmate,baby)):
                    origin=[285 if n==0 else 237,212]
                    target=[rig["at"][0]+(-40 if n==0 else 45),161]
                    block=self.block("Copied play block "+str(n),origin,"gold" if n==0 else "blue")
                    block["ks"]["s"]=static([53,53])
                    self.move(block,[(0,origin),(20+n*50,origin),(61+n*50,target),(145,target),(180,origin)])
                    self.hand_to(rig,0 if n==0 else 1,[-41 if n==0 else 53,-99],time=61+n*50,hold=140,return_at=164,angle=-40 if n==0 else 40)
                    self.gaze(rig,side=-1 if n==0 else 1)
        elif action in {"pull-stand", "climb-sofa"}:
            for n,leg in enumerate(baby["legs"]):
                sign=-1 if n==0 else 1
                crouch=[[sign*16,-21],[sign*32,-10],[sign*17,-7]]
                self.bend(leg,[(0,crouch),(25,crouch),(103,baby["leg_points"][n]),(151,baby["leg_points"][n]),(180,crouch)])
            self.move(baby["body"],[(0,[0,18]),(25,[0,18]),(103,[0,-28]),(151,[0,-28]),(180,[0,18])])
            self.move(baby["head"]["root"],[(0,[0,-133]),(25,[0,-133]),(103,[0,-179]),(151,[0,-179]),(180,[0,-133])])
            for n in (0,1):
                rest=baby["arm_points"][n]
                shoulder=[rest[0][0],rest[0][1]+46]
                hold=[[rest[0][0],rest[0][1]],[50+n*14,-105],[77+n*16,-70]]
                low=[shoulder,[50+n*14,-80],[77+n*16,-70]]
                self.animate_arm(baby,n,[(0,low),(25,low),(103,hold),(151,hold),(180,low)])
            if action == "climb-sofa":
                self.move(baby["root"],[(0,[173,239]),(30,[173,239]),(81,[213,232]),(118,[262,213]),(151,[285,202]),(180,[173,239])])
                self.rotate(baby["root"],[(0,0),(65,12),(110,8),(151,0),(180,0)])
                self.motion(baby["root"],"s",[(0,[83,83]),(180,[83,83])])
                poster=146
        elif action in {"cruise", "first-steps", "explore-check", "walk", "run", "walk-help", "walk-independent", "stairs"}:
            self.footsteps(baby,running=action=="run",distance=47 if action=="cruise" else 69 if action=="first-steps" else 87)
            if action == "cruise":
                self.hand_to(baby,1,[85,-68],time=35,hold=144,return_at=165,angle=75)
            if action == "explore-check": self.gaze(baby,side=-1,start=86,end=124); self.gaze(adult,side=-1)
            if action == "walk-help":
                self.move(adult["root"],[(0,[302,244]),(24,[302,244]),(120,[338,244]),(150,[338,244]),(180,[302,244])])
                self.hand_to(adult,0,[-69,-100],time=41,hold=143,return_at=163,angle=-70)
                self.hand_to(baby,1,[57,-155],time=41,hold=143,return_at=163,angle=25)
            if action == "stairs":
                self.motion(baby["root"],"s",[(0,[73,73]),(180,[73,73])])
                self.move(baby["root"],[(0,[173,239]),(24,[173,239]),(59,[231,218]),(94,[270,198]),(129,[315,178]),(157,[315,178]),(180,[173,239])])
                self.rotate(baby["root"],[(0,0),(59,5),(94,5),(129,0),(180,0)])
                poster=125
        elif action in {"held-cup", "cup-spill"}:
            cup=self.prop("cup",(244,211),scale=65)
            dest=[baby["at"][0]+12,105]
            self.move(cup,[(0,[244,211]),(29,[244,211]),(85,dest),(119,dest),(153,[244,211]),(180,[244,211])])
            self.rotate(cup,[(0,0),(85,-13),(108,-23 if action=="cup-spill" else -16),(119,-13),(153,0),(180,0)])
            self.hand_to(baby,1,[21,-116],time=85,hold=119,angle=-20)
            if adult: self.hand_to(adult,0,[-95,-111],time=85,hold=119,angle=-45)
            if action=="cup-spill":
                for n in range(3):
                    drop=self.layer("Spilled drop "+str(n),[group(oval(0,0,3,5),"blue",opacity=72)],at=(190+n*4,123))
                    self.fade(drop,[(0,0),(99+n*4,0),(104+n*4,100),(129+n*4,100),(140+n*4,0),(180,0)])
                    self.move(drop,[(0,[190+n*4,123]),(104+n*4,[190+n*4,123]),(139+n*4,[198+n*5,206]),(180,[190+n*4,123])])
        elif action == "hug-toy":
            bear=self.prop("bear",(231,207),scale=76)
            self.move(bear,[(0,[231,207]),(28,[231,207]),(83,[173,159]),(139,[173,159]),(164,[231,207]),(180,[231,207])])
            self.hand_to(baby,0,[-24,-79],time=83,hold=139,angle=-65)
            self.hand_to(baby,1,[24,-79],time=83,hold=139,angle=65)
            self.smile(baby,start=82); self.heart((248,77))
        elif action in {"give-gesture", "give-voice"}:
            ring=self.prop("ring",(218,190),scale=70,name="Ring being offered")
            self.move(ring,[(0,[218,190]),(29,[218,190]),(98,[258,169]),(135,[258,169]),(180,[218,190])])
            self.hand_to(baby,1,[80,-63],time=98,hold=135,angle=65)
            self.hand_to(adult,0,[-49,-73],time=37 if action=="give-gesture" else 96,hold=135,angle=-65)
            if action=="give-voice": self.talk(adult,start=22,beats=1,pigment="blue_shadow")
            self.gaze(baby); self.gaze(adult,side=-1)
        elif action in {"point-help", "point-interest"}:
            if action == "point-help":
                self.layer("Toy shelf",[group(rounded(286,118,107,9,3),"gold"),group(rounded(245,133,7,27,2),"gold_shadow"),group(rounded(326,133,7,27,2),"gold_shadow")])
                self.prop("rattle",(294,91),scale=80)
            else:
                self.line("Bird's little branch",[[265,106],[294,99],[331,103]],"gold_shadow",1.6)
                bird=self.prop("bird",(301,84),scale=88)
                self.rotate(bird,[(0,-3),(65,6),(105,-3),(140,3),(180,-3)])
            self.hand_to(baby,1,[86,-144],time=77,hold=133,angle=48); self.gaze(baby)
        elif action == "pretend-phone":
            phone=self.prop("phone",(232,204),scale=83)
            self.move(phone,[(0,[232,204]),(23,[232,204]),(83,[203,98]),(139,[203,98]),(164,[232,204]),(180,[232,204])])
            self.rotate(phone,[(0,19),(83,7),(139,7),(180,19)])
            self.hand_to(baby,1,[36,-137],time=83,hold=139,angle=5); self.talk(baby,start=93,beats=2)
        elif action == "wash-hands":
            self.layer("Low wash basin",[group(oval(280,218,112,29),"blue_light"),group(oval(280,216,90,18),"blue_shadow",opacity=60),
                       group(path([[227,218],[240,239],[319,239],[334,218]],smoothing=.05),"blue")])
            self.layer("Curved tap",[group(path([[309,214],[309,153],[293,141],[270,144],[263,156]],False),stroke="gold",width=8),
                      group(rounded(263,158,15,6,2),"gold_light")])
            for n in (0,1): self.hand_to(baby,n,[70+n*13,-47],time=69,hold=139,angle=60 if n else -60)
            for n in range(4):
                drop=self.layer("Running water "+str(n),[group(oval(0,0,3,5),"blue_light",opacity=80)],at=(262+n%2*3,164))
                self.move(drop,[(0,[262+n%2*3,164]),(24+n*8,[262+n%2*3,164]),(64+n*8,[258+n%2*5,210]),(127,[258+n%2*5,210]),(180,[262+n%2*3,164])])
                self.fade(drop,[(0,0),(30+n*8,0),(35+n*8,100),(82+n*8,100),(137,0),(180,0)])
        elif action in {"read-together", "book-point"}:
            book=self.prop("book",(252 if adult else 280,195),scale=80)
            self.gaze(baby,down=True)
            self.hand_to(baby,1,[76,-61],time=71,hold=132,angle=65)
            if adult:
                self.gaze(adult,side=-1,down=True); self.hand_to(adult,0,[-36,-59],time=91,hold=132,angle=-70)
                page=self.layer("Turning paper page",[group(path([[0,-16],[7,-25],[53,-28],[53,27],[7,32],[0,27]],smoothing=.035),"light")],parent=book)
                self.motion(page,"s",[(0,[100,100]),(61,[100,100]),(84,[8,100]),(109,[-100,100]),(155,[-100,100]),(180,[100,100])])
        elif action == "dress-sleeve":
            shirt=self.prop("shirt",(279,159),scale=95)
            self.hand_to(baby,1,[96,-94],time=102,hold=135,angle=50)
            self.move(shirt,[(0,[289,167]),(29,[289,167]),(103,[262,151]),(135,[262,151]),(180,[289,167])])
            self.rotate(shirt,[(0,-8),(103,4),(135,4),(180,-8)])
        elif action == "sweep":
            broom=self.prop("broom",(255,182),scale=110)
            frames=[(0,[247,184]),(28,[247,184]),(54,[277,184]),(82,[240,184]),(110,[279,184]),(140,[245,184]),(180,[247,184])]
            self.move(broom,frames); self.rotate(broom,[(0,-15),(54,13),(82,-18),(110,14),(140,-15),(180,-15)])
            self.hand_to(baby,1,[75,-100],time=38,hold=140,angle=60)
            for n in range(4):
                dust=self.layer("Soft crumb "+str(n),[group(oval(0,0,3,2),"gold_shadow",opacity=38)],at=(271+n*7,233))
                self.move(dust,[(0,[271+n*7,233]),(55,[279+n*6,233]),(113,[298+n*5,232]),(180,[271+n*7,233])])
        elif action == "push-car":
            car=self.prop("car",(254,219),scale=88)
            self.move(car,[(0,[237,219]),(29,[237,219]),(99,[315,219]),(147,[315,219]),(180,[237,219])])
            self.hand_to(baby,1,[106,-48],time=99,hold=109,return_at=144,angle=75); self.gaze(baby,down=True)
        elif action == "scribble":
            paper=self.prop("paper",(260,220))
            scribble=self.layer("Crayon trace",[group([path([[-28,-2],[-14,-5],[-20,7],[-2,3],[-7,-7],[11,2]],False,.09),
                        dict(ty="tm",s=static(0),e=animated([(0,0),(37,0),(129,100),(180,100)]),o=static(0),m=1)],stroke="rose",width=2)],at=(260,220))
            points=[(0,[56,-39]),(37,[56,-39]),(58,[69,-39]),(76,[61,-30]),(97,[83,-34]),(115,[74,-46]),(129,[94,-36]),(153,[56,-39]),(180,[56,-39])]
            rest=baby["arm_points"][1]
            self.animate_arm(baby,1,[(t,[rest[0],[52,(rest[0][1]+p[1])*.5+12],p]) for t,p in points])
            crayon=self.prop("crayon",(0,0),parent=baby["root"],scale=80)
            self.move(crayon,[(t,[p[0]-4,p[1]-4]) for t,p in points]); crayon["ks"]["r"]=static(135)
            self.gaze(baby,down=True); poster=125
        elif action == "kiss-nod":
            self.hand_to(baby,1,[3,-132],time=51,hold=71,return_at=138,angle=-15)
            heart=self.heart((221,102)); self.move(heart,[(0,[221,102]),(71,[184,106]),(135,[257,69]),(180,[221,102])])
            self.rotate(baby["head"]["root"],[(0,0),(30,0),(52,9),(69,0),(99,9),(116,0),(180,0)])
        elif action == "body-parts":
            rest=baby["arm_points"][1]
            nose=[rest[0],[44,-114],[3,-140]]; foot=[rest[0],[16,-68],[-20,-8]]
            self.animate_arm(baby,1,[(0,rest),(25,rest),(59,nose),(83,nose),(119,foot),(144,foot),(165,rest),(180,rest)])
            self.gaze(baby,down=True,start=83,end=116); poster=65
        elif action == "open-container":
            box=self.prop("box",(264,209),scale=80)
            lid=self.layer("Container lid",[group(oval(0,0,41,12),"blue_light"),group(path([[-19,1],[0,6],[19,1]],False),stroke="blue",width=1.1)],at=(264,191))
            self.hand_to(baby,0,[72,-33],time=55,hold=143,angle=60)
            self.hand_to(baby,1,[103,-80],time=110,hold=142,angle=65)
            self.move(lid,[(0,[264,191]),(54,[264,191]),(110,[278,148]),(142,[278,148]),(180,[264,191])])
            self.rotate(lid,[(0,0),(110,14),(142,14),(180,0)])
        elif action == "toy-button":
            toy=self.prop("switch",(280,214),scale=90)
            self.hand_to(baby,1,[93,-27],time=79,hold=104,return_at=139,angle=65)
            glow=self.layer("Toy light",[group(oval(295,214,13,13),"gold_light"),group(oval(295,214,25,25),"gold_light",opacity=30)])
            self.fade(glow,[(0,0),(75,0),(83,100),(130,100),(151,0),(180,0)])
            self.motion(glow,"s",[(0,[100,100]),(86,[100,100]),(101,[102,102]),(130,[100,100]),(180,[100,100])])
        elif action == "toy-meal":
            self.prop("plate",(291,224)); self.prop("spoon",(327,212),scale=70)
            food=self.food((231,217),name="Pretend food")
            self.move(food,[(0,[231,217]),(26,[231,217]),(68,[254,168]),(109,[286,216]),(150,[286,216]),(180,[231,217])])
            self.hand_to(baby,1,[108,-35],time=109,hold=124,return_at=155,angle=65)
            self.gaze(baby,down=True)
        elif action == "kick-ball":
            ball=self.prop("ball",(232,221))
            leg=baby["legs"][1]; rest=baby["leg_points"][1]
            lifted=[rest[0],[21,-44],[39,-32]]; kicked=[rest[0],[36,-39],[58,-23]]
            self.bend(leg,[(0,rest),(29,rest),(63,lifted),(87,kicked),(115,rest),(180,rest)])
            self.move(baby["feet"][1],[(0,rest[-1]),(29,rest[-1]),(63,lifted[-1]),(87,kicked[-1]),(115,rest[-1]),(180,rest[-1])])
            self.move(ball,[(0,[232,221]),(81,[232,221]),(103,[281,215]),(142,[341,220]),(180,[232,221])])
            self.rotate(ball,[(0,0),(81,0),(142,130),(180,0)]); self.gaze(baby,down=True)
        elif action in {"stand-help", "stand-balance"}:
            self.rotate(baby["body"],[(0,0),(44,-2),(82,2),(128,-1),(157,0),(180,0)])
            self.rotate(baby["head"]["root"],[(0,0),(44,2),(82,-2),(128,1),(180,0)])
            if adult:
                self.hand_to(adult,0,[-101,-91],time=47,hold=145,return_at=165,angle=-75)
                self.hand_to(baby,1,[54,-135],time=47,hold=145,return_at=165,angle=40)
            else:
                self.hand_to(baby,0,[-53,-114],time=63,hold=126,angle=-55)
                self.hand_to(baby,1,[53,-114],time=63,hold=126,angle=55)
        else:
            raise ValueError("Unimplemented milestone action: " + action)
        return poster
