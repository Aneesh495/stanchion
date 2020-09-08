#!/usr/bin/env python3
"""
Stanchion Test Suite Runner
Discovers and executes Berry test scripts under tests/
"""

import os
import sys
import subprocess
import time

def run_tests():
    repo_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    stanchion_bin = os.path.join(repo_dir, "bin", "stanchion")
    berry_bin = os.path.join(repo_dir, "bin", "berry")

    if os.path.exists(stanchion_bin):
        runner_bin = stanchion_bin
    elif os.path.exists(berry_bin):
        runner_bin = berry_bin
    else:
        print("Error: neither bin/stanchion nor bin/berry found. Run 'make' first.")
        sys.exit(1)

    tests_dir = os.path.join(repo_dir, "tests")
    if not os.path.isdir(tests_dir):
        print("No tests directory found.")
        sys.exit(0)

    test_files = sorted([
        f for f in os.listdir(tests_dir)
        if f.startswith("test_") and f.endswith(".be") and f != "test_all.be"
    ])

    if not test_files:
        print("No test files found under tests/.")
        sys.exit(0)

    print(f"============================================================")
    print(f"Running Stanchion Test Suites with {os.path.basename(runner_bin)}")
    print(f"Found {len(test_files)} test suite file(s)")
    print(f"============================================================")

    passed = 0
    failed = 0
    start_total = time.time()

    for idx, tf in enumerate(test_files, 1):
        tpath = os.path.join(tests_dir, tf)
        t_start = time.time()
        res = subprocess.run([runner_bin, tpath], capture_output=True, text=True, cwd=repo_dir)
        elapsed = (time.time() - t_start) * 1000.0

        if res.returncode == 0:
            passed += 1
            status = "PASS"
            print(f"[{idx:02d}/{len(test_files):02d}] {tf:32s} ... {status:4s} ({elapsed:6.1f} ms)")
        else:
            failed += 1
            status = "FAIL"
            print(f"[{idx:02d}/{len(test_files):02d}] {tf:32s} ... {status:4s} ({elapsed:6.1f} ms)")
            print(f"--- STDOUT ---\n{res.stdout}")
            print(f"--- STDERR ---\n{res.stderr}")

    total_elapsed = time.time() - start_total
    print(f"============================================================")
    print(f"Results: {passed} passed, {failed} failed in {total_elapsed:.2f} s")
    print(f"============================================================")

    if failed > 0:
        sys.exit(1)
    else:
        print("All test suites passed successfully.")

if __name__ == "__main__":
    run_tests()
