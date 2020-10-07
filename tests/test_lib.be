# Stanchion Test Suite: Standard Library Extensions
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math_ext as MathExt
import time_util as TimeUtil
import string_util as StringUtil
import collection as Col
import uuid as UUID
import token_hash as TokenHash
import crc as CRC

var Deque = Col["Deque"]
var RingBuffer = Col["RingBuffer"]
var PriorityQueue = Col["PriorityQueue"]
var SortedSet = Col["SortedSet"]

import string
import global
var total_assertions = 0

def check(condition, desc)
    global.total_assertions = global.total_assertions + 1
    if !condition
        print("[FAIL] " + desc)
        assert(false)
    end
end

print(">>> Running test_lib.be ...")

# 1. MathExt Tests
var nums = [10.0, 20.0, 30.0, 40.0, 50.0]
check(MathExt.mean(nums) == 30.0, "MathExt.mean([10,20,30,40,50]) == 30.0")
check(MathExt.clamp(15.0, 0.0, 10.0) == 10.0, "MathExt.clamp upper")
check(MathExt.clamp(-5.0, 0.0, 10.0) == 0.0, "MathExt.clamp lower")
check(MathExt.clamp(5.0, 0.0, 10.0) == 5.0, "MathExt.clamp inside")

var x_pts = [0.0, 10.0, 20.0]
var y_pts = [0.0, 50.0, 100.0]
check(MathExt.lerp_1d(x_pts, y_pts, 5.0) == 25.0, "MathExt.lerp_1d midpoint")
check(MathExt.lerp_1d(x_pts, y_pts, 0.0) == 0.0, "MathExt.lerp_1d start")
check(MathExt.lerp_1d(x_pts, y_pts, 20.0) == 100.0, "MathExt.lerp_1d end")

var s = MathExt.apparent_power(120.0, 50.0)
check(s > 129.9 && s < 130.1, "MathExt.apparent_power")
var pf = MathExt.power_factor(120.0, 50.0)
check(pf > 0.92 && pf < 0.93, "MathExt.power_factor")

# 2. TimeUtil Tests
check(TimeUtil.is_leap_year(2024) == true, "2024 is leap year")
check(TimeUtil.is_leap_year(2025) == false, "2025 is not leap year")
check(TimeUtil.is_leap_year(2000) == true, "2000 is leap year (400-divisible)")
check(TimeUtil.is_leap_year(1900) == false, "1900 is not leap year (100-divisible)")

var epoch_test = TimeUtil.to_epoch_seconds(2026, 1, 1, 0, 0, 0)
var back_dt = TimeUtil.from_epoch_seconds(epoch_test)
check(back_dt["year"] == 2026 && back_dt["month"] == 1 && back_dt["day"] == 1, "TimeUtil roundtrip")

var iso_str = "2026-04-12T09:15:30Z"
var parsed_sec = TimeUtil.parse_iso8601(iso_str)
var formatted_iso = TimeUtil.to_iso8601(parsed_sec)
check(iso_str == formatted_iso, "TimeUtil ISO 8601 roundtrip")

check(TimeUtil.intervals_overlap(100, 200, 150, 250) == true, "Intervals overlap")
check(TimeUtil.intervals_overlap(100, 200, 201, 250) == false, "Intervals disjoint")
check(TimeUtil.overlap_duration(100, 200, 150, 250) == 50, "Interval overlap duration")

# 3. StringUtil Tests
check(StringUtil.trim("   abc \t\r\n") == "abc", "StringUtil.trim")
check(StringUtil.lpad("42", 5, "0") == "00042", "StringUtil.lpad")
check(StringUtil.rpad("42", 5, " ") == "42   ", "StringUtil.rpad")
check(StringUtil.int_to_hex(255, 4) == "00FF", "StringUtil.int_to_hex")
check(StringUtil.hex_to_int("00FF") == 255, "StringUtil.hex_to_int")
var raw_bytes = StringUtil.string_to_bytes("HELLO")
check(StringUtil.bytes_to_string(raw_bytes) == "HELLO", "Bytes to string roundtrip")
check(StringUtil.sanitize_identifier("ID#99-A/B*C") == "ID_99-A_B_C", "Sanitize identifier")

# 4. Collection Tests
var dq = Deque()
dq.push_back(1)
dq.push_front(2)
dq.push_back(3)
check(dq.pop_front() == 2, "Deque pop_front")
check(dq.pop_back() == 3, "Deque pop_back")
check(dq.pop_front() == 1, "Deque pop_front final")
check(dq.is_empty(), "Deque empty")

var rb = RingBuffer(3)
rb.push("a")
rb.push("b")
rb.push("c")
rb.push("d")
check(rb.size() == 3, "RingBuffer size")
check(rb.oldest() == "b", "RingBuffer oldest")
check(rb.latest() == "d", "RingBuffer latest")

var pq = PriorityQueue(true)
pq.push({"priority": 100, "name": "c"})
pq.push({"priority": 10,  "name": "a"})
pq.push({"priority": 50,  "name": "b"})
check(pq.pop()["name"] == "a", "PQ min top 1")
check(pq.pop()["name"] == "b", "PQ min top 2")
check(pq.pop()["name"] == "c", "PQ min top 3")

var ss = SortedSet()
check(ss.add(20), "SortedSet add 20")
check(ss.add(10), "SortedSet add 10")
check(ss.add(30), "SortedSet add 30")
check(ss.add(20) == false, "SortedSet duplicate 20")
check(ss.contains(10) && ss.contains(20) && ss.contains(30), "SortedSet contains")
check(ss.remove(20), "SortedSet remove 20")
check(ss.contains(20) == false, "SortedSet not contains 20")

# 5. UUID Tests
var u = UUID.v4()
check(UUID.is_valid(u), "UUID.v4 is valid")
check(u[14] == "4", "UUID version 4")
check(UUID.is_valid(UUID.nil_uuid()), "UUID nil is valid")

# 6. TokenHash Tests
var h1 = TokenHash.hex_digest("EVSE-TOKEN-1", "salt")
var h2 = TokenHash.hex_digest("EVSE-TOKEN-1", "salt")
var h3 = TokenHash.hex_digest("EVSE-TOKEN-2", "salt")
check(h1 == h2, "TokenHash deterministic")
check(h1 != h3, "TokenHash distinct")
check(TokenHash.secure_compare(h1, h2), "TokenHash secure_compare true")
check(!TokenHash.secure_compare(h1, h3), "TokenHash secure_compare false")

# 7. CRC Tests
check(CRC.crc16_string("123456789") == 19255, "CRC16 Modbus test vector")
check(CRC.crc32_string("123456789") == 3421780262, "CRC32 IEEE test vector")

print(string.format("[PASS] test_lib.be passed with %d assertions verified.", total_assertions))
