import json
import sys

DEFAULT_FLAGS = ["-X", "jit", "-X", "jit-enable-jit-list-wildcards", "-X", "jit-shadow-frame"]
DEFAULT_JIT_LIST = "/jitlist_main.txt"

if len(sys.argv) < 2:
    cfg = {}
else:
    cfg = json.load(open(sys.argv[1]))

flags = cfg.get("flags", DEFAULT_FLAGS)
jit_list = cfg.get("jit_list", DEFAULT_JIT_LIST)
flags += ["-X", f"jit-list-file={jit_list}"]

print(" ".join(flags))