#!/usr/bin/env python3
# Локальный фолбэк: раскодирует все *.b64 в настоящие файлы (если workflow
# GitHub Actions не отработал). Запуск из корня репы: python3 tools/decode_textures.py
import base64, os
count = 0
for root, _, files in os.walk("."):
    if ".git" in root:
        continue
    for name in files:
        if name.endswith(".b64"):
            p = os.path.join(root, name)
            out = p[:-4]
            with open(p, "rb") as f:
                data = base64.b64decode(f.read())
            with open(out, "wb") as f:
                f.write(data)
            os.remove(p)
            print("decoded:", out)
            count += 1
print("done, files:", count)
