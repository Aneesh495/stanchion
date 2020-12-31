# Stanchion Test Suite: Multi-Tier Composite Schedule Engine
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import composite_schedule as CompositeModule
import math
import string
import global

var SchedulePeriod = CompositeModule["SchedulePeriod"]
var MultiTierCompositeScheduler = CompositeModule["MultiTierCompositeScheduler"]

var test_passed = 0
var test_failed = 0

def assert_true(cond, msg)
    if cond
        test_passed = test_passed + 1
    else
        test_failed = test_failed + 1
        print("FAIL: " + str(msg))
    end
end

def assert_equal(a, b, msg)
    if a == b
        test_passed = test_passed + 1
    else
        test_failed = test_failed + 1
        print("FAIL: " + str(msg) + " (expected " + str(b) + ", got " + str(a) + ")")
    end
end

print(">>> Running test_composite_schedule suite...")

var scheduler = MultiTierCompositeScheduler(64.0) # 64A hardware ceiling

# 1. Baseline Schedule Generation (No external profiles: defaults to 64A)
var sched_base = scheduler.generate_composite_schedule(1770000000, 7200, "A", 230.0)
var periods_base = sched_base["chargingSchedulePeriod"]
assert_equal(size(periods_base), 1, "Exactly 1 period generated for baseline")
assert_equal(periods_base[0]["limit"], 64.0, "Baseline limit is 64.0A")

# 2. Add Level 1 Profile: 32A for first hour, 16A for second hour
var p1 = [SchedulePeriod(0, 32.0, 3), SchedulePeriod(3600, 16.0, 3)]
scheduler.add_profile(101, 1, "TxDefaultProfile", "None", p1)

var sched1 = scheduler.generate_composite_schedule(0, 7200, "A", 230.0)
var p_list1 = sched1["chargingSchedulePeriod"]
assert_equal(size(p_list1), 2, "Generated 2 composite periods")
assert_equal(p_list1[0]["limit"], 32.0, "Period 0 limit is 32A")
assert_equal(p_list1[1]["limit"], 16.0, "Period 1 limit is 16A")

# 3. Add Level 2 Profile (Overrides Level 1): 24A starting at t=1800
var p2 = [SchedulePeriod(1800, 24.0, 3)]
scheduler.add_profile(201, 2, "TxProfile", "None", p2)

var sched2 = scheduler.generate_composite_schedule(0, 7200, "A", 230.0)
var p_list2 = sched2["chargingSchedulePeriod"]
assert_equal(size(p_list2), 2, "Level 2 profile overrides starting at t=1800")
assert_equal(p_list2[0]["limit"], 32.0, "From 0 to 1800s: 32A")
assert_equal(p_list2[1]["startPeriod"], 1800, "Period 1 starts at 1800s")
assert_equal(p_list2[1]["limit"], 24.0, "From 1800s onwards: Level 2 limit 24A takes precedence")

# 4. Unit Conversion to Watts (W)
# At 24A 3-phase 230V: P = 3 * 230 * 24 = 16560 W
var sched_watts = scheduler.generate_composite_schedule(1800, 3600, "W", 230.0)
var p_watts = sched_watts["chargingSchedulePeriod"]
assert_equal(p_watts[0]["limit"], 16560.0, "Converted 24A to 16,560 Watts")
assert_equal(sched_watts["chargingRateUnit"], "W", "Schedule unit is W")

print("test_composite_schedule: " + str(test_passed) + " passed, " + str(test_failed) + " failed")
if test_failed > 0
    import os
    os.exit(1)
end
