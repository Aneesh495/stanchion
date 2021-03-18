# Stanchion Test Suite: Subsystem Latency Profiler & Percentile Statistics
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import system_profiler as ProfilerModule
import math
import string
import global

var OperationMetric = ProfilerModule["OperationMetric"]
var SystemProfiler = ProfilerModule["SystemProfiler"]

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

print(">>> Running test_system_profiler suite...")

var profiler = SystemProfiler()

# 1. Registration & Initial State
var initial_summary = profiler.get_summary("SAFETY_LOOP")
assert_true(initial_summary != nil, "SAFETY_LOOP registered by default")
assert_equal(initial_summary["count"], 0, "Initial sample count is 0")
assert_equal(initial_summary["sla_limit_ms"], 10.0, "SLA limit is 10.0 ms")

# 2. Record 100 Synthesized Latency Samples (1.0 ms to 10.0 ms)
for i : 1 .. 100
    profiler.record("SAFETY_LOOP", real(i) * 0.1) # 0.1 ms to 10.0 ms
end

var s1 = profiler.get_summary("SAFETY_LOOP")
assert_equal(s1["count"], 100, "Recorded 100 samples")
assert_equal(s1["min_ms"], 0.1, "Min latency is 0.1 ms")
assert_equal(s1["max_ms"], 10.0, "Max latency is 10.0 ms")
assert_true(s1["p50_ms"] >= 4.9 && s1["p50_ms"] <= 5.2, "Median p50 is approximately 5.0 ms")
assert_true(s1["p95_ms"] >= 9.3 && s1["p95_ms"] <= 9.7, "p95 is approximately 9.5 ms")
assert_equal(s1["sla_breaches"], 0, "No SLA breaches when all latencies <= 10.0 ms")

# 3. SLA Breach Detection
# Inject an abnormal 25.5 ms latency spike
profiler.record("SAFETY_LOOP", 25.5)
var s2 = profiler.get_summary("SAFETY_LOOP")
assert_equal(s2["sla_breaches"], 1, "Recorded 1 SLA breach")
assert_equal(s2["max_ms"], 25.5, "New max latency is 25.5 ms")

# 4. Custom Operation Registration
profiler.register_operation("CUSTOM_TASK", 5.0)
profiler.record("CUSTOM_TASK", 3.2)
profiler.record("CUSTOM_TASK", 4.1)
var s_custom = profiler.get_summary("CUSTOM_TASK")
assert_equal(s_custom["count"], 2, "Custom operation recorded 2 samples")
assert_equal(s_custom["sla_limit_ms"], 5.0, "Custom SLA limit is 5.0 ms")

# 5. Render Report Check
var rep = profiler.render_report()
assert_true(string.find(rep, "SAFETY_LOOP") >= 0, "Report contains SAFETY_LOOP")
assert_true(string.find(rep, "CUSTOM_TASK") >= 0, "Report contains CUSTOM_TASK")

print("test_system_profiler: " + str(test_passed) + " passed, " + str(test_failed) + " failed")
if test_failed > 0
    import os
    os.exit(1)
end
