import numpy as np
from PIL import Image
import os

# 폴더 설정
REF_DIR = "./input"
TARGET_DIR = "./target"
OUTPUT_LUT = "./learned.cube"

LUT_SIZE = 64
IMG_SIZE = 512


grid = np.zeros((LUT_SIZE, LUT_SIZE, LUT_SIZE, 3), dtype=np.float32)
count = np.zeros((LUT_SIZE, LUT_SIZE, LUT_SIZE), dtype=np.float32)


print("이미지 로드 중...")

files = sorted([
    f for f in os.listdir(REF_DIR)
    if f.lower().endswith((".jpg",".jpeg",".png"))
])

for f in files:

    ref_path = os.path.join(REF_DIR, f)
    tgt_path = os.path.join(TARGET_DIR, f)

    if not os.path.exists(tgt_path):
        print("target 없음:", f)
        continue

    ref_img = Image.open(ref_path).convert("RGB").resize((IMG_SIZE, IMG_SIZE))
    tgt_img = Image.open(tgt_path).convert("RGB").resize((IMG_SIZE, IMG_SIZE))

    ref = np.array(ref_img).astype(np.float32) / 255.0
    tgt = np.array(tgt_img).astype(np.float32) / 255.0

    ref_pixels = ref.reshape(-1,3)
    tgt_pixels = tgt.reshape(-1,3)

    for i in range(len(ref_pixels)):

        r,g,b = ref_pixels[i]
        ro,go,bo = tgt_pixels[i]

        ri = int(r*(LUT_SIZE-1))
        gi = int(g*(LUT_SIZE-1))
        bi = int(b*(LUT_SIZE-1))

        grid[ri,gi,bi] += [ro,go,bo]
        count[ri,gi,bi] += 1


print("LUT 평균 계산")

lut = np.zeros_like(grid)

mask = count > 0
lut[mask] = grid[mask] / count[mask][...,None]


print("빈 영역 보정")

for r in range(LUT_SIZE):
    for g in range(LUT_SIZE):
        for b in range(LUT_SIZE):

            if count[r,g,b] == 0:

                neighbors = []

                for dr in [-1,0,1]:
                    for dg in [-1,0,1]:
                        for db in [-1,0,1]:

                            rr = r+dr
                            gg = g+dg
                            bb = b+db

                            if 0<=rr<LUT_SIZE and 0<=gg<LUT_SIZE and 0<=bb<LUT_SIZE:

                                if count[rr,gg,bb] > 0:
                                    neighbors.append(lut[rr,gg,bb])

                if neighbors:
                    lut[r,g,b] = np.mean(neighbors, axis=0)
                else:
                    lut[r,g,b] = [r/(LUT_SIZE-1), g/(LUT_SIZE-1), b/(LUT_SIZE-1)]


print("cube 파일 저장")

lines = []

lines.append('TITLE "Learned LUT"')
lines.append(f"LUT_3D_SIZE {LUT_SIZE}")
lines.append("DOMAIN_MIN 0 0 0")
lines.append("DOMAIN_MAX 1 1 1")
lines.append("")

for b in range(LUT_SIZE):
    for g in range(LUT_SIZE):
        for r in range(LUT_SIZE):

            ro,go,bo = lut[r,g,b]

            lines.append(f"{ro:.6f} {go:.6f} {bo:.6f}")

with open(OUTPUT_LUT,"w") as f:
    f.write("\n".join(lines))


print("완료")
print("LUT 생성:", OUTPUT_LUT)