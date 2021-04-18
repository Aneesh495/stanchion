#!/usr/bin/env python3
"""
Backdate git commits across a target historical window using RNG with good variance.
Preserves exact tree objects, author names, author emails, and commit messages.

Copyright (c) 2026 Aneesh Krishna
Licensed under the Apache License, Version 2.0
"""

import os
import sys
import random
import subprocess
from datetime import datetime, timezone, timedelta

def get_commits():
    cmd = ["git", "log", "--reverse", "--format=%H"]
    res = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return [line.strip() for line in res.stdout.strip().split("\n") if line.strip()]

def get_commit_metadata(commit_hash):
    # Tree
    tree = subprocess.run(["git", "rev-parse", f"{commit_hash}^{{tree}}"], capture_output=True, text=True, check=True).stdout.strip()
    # Author Name
    an = subprocess.run(["git", "log", "-1", "--format=%an", commit_hash], capture_output=True, text=True, check=True).stdout.strip()
    # Author Email
    ae = subprocess.run(["git", "log", "-1", "--format=%ae", commit_hash], capture_output=True, text=True, check=True).stdout.strip()
    # Commit Message
    msg = subprocess.run(["git", "log", "-1", "--format=%B", commit_hash], capture_output=True, text=True, check=True).stdout
    return tree, an, ae, msg

def generate_dates(n_commits, start_dt, end_dt, seed=20200908):
    random.seed(seed)
    total_sec = (end_dt - start_dt).total_seconds()
    
    # Gamma distribution gives natural developer pacing with variance
    intervals = [random.gammavariate(3.2, 1.0) for _ in range(n_commits - 1)]
    s = sum(intervals)
    scaled = [x / s * total_sec for x in intervals]
    
    raw_dates = [start_dt]
    cur = start_dt
    for step in scaled:
        cur = cur + timedelta(seconds=step)
        raw_dates.append(cur)
        
    final_dates = []
    prev_dt = start_dt
    for i, dt in enumerate(raw_dates):
        if i == 0:
            final_dates.append(start_dt)
            continue
            
        hour = dt.hour
        # If hour falls in late-night / deep sleeping hours (03:00 to 08:30 UTC),
        # nudge into active coding windows (morning / afternoon / evening)
        if 2 <= hour < 9:
            target_hour = random.choice([9, 10, 11, 14, 15, 16, 20, 21, 22])
            candidate = dt + timedelta(hours=(target_hour - hour), minutes=random.randint(-15, 15))
        else:
            candidate = dt + timedelta(minutes=random.randint(-10, 10))
            
        # Ensure strict monotonicity: at least 20 minutes separation
        if candidate <= prev_dt + timedelta(minutes=20):
            candidate = prev_dt + timedelta(minutes=random.randint(25, 120))
            
        final_dates.append(candidate)
        prev_dt = candidate
        
    return final_dates

def main():
    commits = get_commits()
    n = len(commits)
    print(f"Found {n} commits to backdate.")
    
    # 7.3-month low-activity window: 2020-09-08 to 2021-04-18
    start_dt = datetime(2020, 9, 8, 14, 18, 22, tzinfo=timezone.utc)
    end_dt = datetime(2021, 4, 18, 21, 35, 40, tzinfo=timezone.utc)
    
    dates = generate_dates(n, start_dt, end_dt)
    
    print(f"Window Start: {dates[0].strftime('%Y-%m-%d %H:%M:%S %z')}")
    print(f"Window End:   {dates[-1].strftime('%Y-%m-%d %H:%M:%S %z')}")
    
    # Replay commits using git commit-tree
    new_parent = None
    new_commits = []
    
    for i, orig_hash in enumerate(commits):
        tree, an, ae, msg = get_commit_metadata(orig_hash)
        target_dt = dates[i]
        date_str = target_dt.strftime("%Y-%m-%dT%H:%M:%S%z")
        
        env = os.environ.copy()
        env["GIT_AUTHOR_NAME"] = an
        env["GIT_AUTHOR_EMAIL"] = ae
        env["GIT_AUTHOR_DATE"] = date_str
        env["GIT_COMMITTER_NAME"] = an
        env["GIT_COMMITTER_EMAIL"] = ae
        env["GIT_COMMITTER_DATE"] = date_str
        
        cmd = ["git", "commit-tree", tree, "-m", msg]
        if new_parent:
            cmd.extend(["-p", new_parent])
            
        res = subprocess.run(cmd, env=env, capture_output=True, text=True, check=True)
        new_hash = res.stdout.strip()
        new_parent = new_hash
        new_commits.append(new_hash)
        
    print(f"Successfully replayed {len(new_commits)} commits.")
    print(f"Updating refs/heads/main to {new_parent}...")
    subprocess.run(["git", "update-ref", "refs/heads/main", new_parent], check=True)
    subprocess.run(["git", "checkout", "main"], check=True)
    print("Done! History successfully backdated.")

if __name__ == "__main__":
    main()
