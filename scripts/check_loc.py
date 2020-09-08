#!/usr/bin/env python3
import os
import sys

def count_lines(root_dir):
    stats = {}
    for root, dirs, files in os.walk(root_dir):
        if ".git" in dirs:
            dirs.remove(".git")
        if "bin" in dirs:
            dirs.remove("bin")
        if "build" in dirs:
            dirs.remove("build")
        if "vendor" in dirs:
            dirs.remove("vendor")
        if "__pycache__" in dirs:
            dirs.remove("__pycache__")
        
        for fname in files:
            ext = os.path.splitext(fname)[1].lower()
            if not ext:
                continue
            fpath = os.path.join(root, fname)
            try:
                with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
                    lines = sum(1 for line in f if line.strip())
                stats[ext] = stats.get(ext, 0) + lines
            except Exception:
                pass
    
    print("=== Line Count Summary (Non-empty lines, excluding vendor) ===")
    for ext, cnt in sorted(stats.items(), key=lambda x: -x[1]):
        print(f"  {ext:10s}: {cnt:6d} lines")
    print(f"Total Berry (.be) lines: {stats.get('.be', 0)}")
    return stats

if __name__ == "__main__":
    repo_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    count_lines(repo_dir)
