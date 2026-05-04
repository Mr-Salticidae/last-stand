import json, struct, os, sys

ROOT = "D:/MyGame/LastStand/last-stand/assets/models/quaternius"
files = [
    ("warehouse", ["Shelf Tall.glb", "Shelf Small.glb", "Crate.glb", "Pallet.glb"]),
    ("outpost", ["Barrel.glb", "Bag.glb", "Bags.glb", "Watch Tower.glb", "Tires.glb", "Wood Planks.glb"]),
    ("training", ["Stone Wall.glb", "Wooden Wall.glb", "Fence.glb", "Chest.glb"]),
]

for sub, names in files:
    print(f"\n--- {sub} ---")
    for nm in names:
        fp = os.path.join(ROOT, sub, nm)
        with open(fp, "rb") as f:
            data = f.read()
        if data[:4] != b"glTF":
            print(f"{nm}: not GLB")
            continue
        jlen = struct.unpack("<I", data[12:16])[0]
        jtxt = data[20:20+jlen].decode("utf-8", errors="replace").rstrip("\x00 ")
        g = json.loads(jtxt)
        mins, maxs = [], []
        for acc in g.get("accessors", []):
            if "min" in acc and "max" in acc and len(acc["min"]) == 3:
                mins.append(acc["min"])
                maxs.append(acc["max"])
        if mins:
            xmin = min(m[0] for m in mins); ymin = min(m[1] for m in mins); zmin = min(m[2] for m in mins)
            xmax = max(m[0] for m in maxs); ymax = max(m[1] for m in maxs); zmax = max(m[2] for m in maxs)
            print(f"{nm:25s}  X={xmax-xmin:6.2f}  Y={ymax-ymin:6.2f}  Z={zmax-zmin:6.2f}   y=[{ymin:.2f}..{ymax:.2f}]")
        else:
            print(f"{nm:25s}  (no min/max)")
