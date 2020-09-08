#!/usr/bin/env python3
import os
import sys

def check_no_em_dash(root_dir):
    violations = []
    for root, dirs, files in os.walk(root_dir):
        if ".git" in dirs:
            dirs.remove(".git")
        if "bin" in dirs:
            dirs.remove("bin")
        if "build" in dirs:
            dirs.remove("build")
        if "__pycache__" in dirs:
            dirs.remove("__pycache__")
        
        for fname in files:
            if fname.endswith((".pyc", ".o", ".a", ".dylib", ".so", ".png", ".jpg", ".DS_Store")):
                continue
            fpath = os.path.join(root, fname)
            rel_path = os.path.relpath(fpath, root_dir)
            try:
                with open(fpath, "r", encoding="utf-8", errors="replace") as f:
                    content = f.read()
                    # Check for em dash (U+2014) and en dash (U+2013)
                    if "\u2014" in content:
                        violations.append((rel_path, "em-dash (U+2014)"))
                    if "\u2013" in content:
                        violations.append((rel_path, "en-dash (U+2013)"))
            except Exception as e:
                print(f"Warning: could not read {rel_path}: {e}")
    
    if violations:
        print("FAIL: Dash violations found:")
        for path, kind in violations:
            print(f"  {path}: {kind}")
        sys.exit(1)
    else:
        print("PASS: Zero em-dashes and en-dashes found across codebase.")

if __name__ == "__main__":
    repo_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    check_no_em_dash(repo_dir)
