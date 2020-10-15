# Stanchion Test Suite: Core Architectural Foundations
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import types as Types
import events as EventBus
import timer as VirtualScheduler
import logger as Logger
import fsm as FSM
import config as StationConfig
import errors as ErrorsModule
import math
import string
import global

var ErrorSeverity = ErrorsModule["Severity"]
var ErrorCode = ErrorsModule["Code"]
var StationError = ErrorsModule["StationError"]

var total_assertions = 0

def check(condition, desc)
    global.total_assertions = global.total_assertions + 1
    if !condition
        print("[FAIL] " + desc)
        assert(false)
    end
end

print(">>> Running test_core.be ...")

# 1. Types & Electrical Conversions
var amps_50 = Types.duty_cycle_to_amps(0.50)
check(math.abs(amps_50 - 30.0) < 0.001, "50% duty = 30A")
var duty_30 = Types.amps_to_duty_cycle(30.0)
check(math.abs(duty_30 - 0.50) < 0.001, "30A = 50% duty")
check(Types.duty_cycle_to_amps(0.05) == 0.0, "<10% duty = 0A")
check(Types.amps_to_duty_cycle(3.0) == 1.0, "<6A returns 1.0 digital")

var p_3ph = Types.calculate_3phase_kw(32.0, 230.0, 1.0)
check(math.abs(p_3ph - 22.08) < 0.01, "32A 230V 3-phase = 22.08 kW")
var p_1ph = Types.calculate_1phase_kw(32.0, 230.0, 1.0)
check(math.abs(p_1ph - 7.36) < 0.01, "32A 230V 1-phase = 7.36 kW")

# 2. EventBus Pub-Sub & Priority Ordering
var bus = EventBus()
var ev_results = []
var sub_meter = bus.subscribe("meter.*", def(ev) ev_results.push("wildcard:" + str(ev.payload)) end, 50)
var sub_tick  = bus.subscribe("meter.tick", def(ev) ev_results.push("exact:" + str(ev.payload)) end, 100)
var sub_other = bus.subscribe("safety.*", def(ev) ev_results.push("safety") end, 10)

bus.publish("meter.tick", 400.0, "grid")
check(ev_results.size() == 2, "EventBus delivered to 2 matching subscribers")
check(ev_results[0] == "exact:400", "Priority 100 executed before priority 50")
check(ev_results[1] == "wildcard:400", "Wildcard subscriber executed second")

bus.unsubscribe(sub_tick)
ev_results = []
bus.publish("meter.tick", 400.0, "grid")
check(ev_results.size() == 1, "Unsubscribed exact handler not called")
check(ev_results[0] == "wildcard:400", "Wildcard subscriber still called")

# 3. VirtualScheduler
var sched = VirtualScheduler(5000)
var task_ticks = []
var id1 = sched.schedule_once(100, def(t) task_ticks.push("once@" + str(t)) end)
var id2 = sched.schedule_interval(50, 50, def(t) task_ticks.push("repeat@" + str(t)) end)

sched.advance_time(120)
# Triggers at: 5050 (repeat), 5100 (repeat), 5100 (once)
check(task_ticks.size() == 3, "Scheduler fired 3 tasks")
check(sched.now_ms() == 5120, "Scheduler time advanced correctly")
sched.cancel(id2)
task_ticks = []
sched.advance_time(100)
check(task_ticks.size() == 0, "Cancelled interval task did not fire")

# 4. Logger Memory Sink & Filtering
var log = Logger("test-core", 30, 16) # min level INFO
log.debug("Debug should be filtered", nil)
log.info("Info message", {"key": "val"})
log.warn("Warning alert", nil)
var logs = log.get_recent_logs()
check(logs.size() == 2, "Logger filtered DEBUG and preserved INFO & WARN")
check(logs[0]["level"] == "INFO", "Log 1 level is INFO")
check(logs[1]["level"] == "WARN", "Log 2 level is WARN")

# 5. Finite State Machine (FSM)
var fsm = FSM("EVSE_1", Types.STATE_AVAILABLE, {"cable_plugged": false})
fsm.add_transition(Types.STATE_AVAILABLE, "PLUGIN", Types.STATE_PREPARING,
    def(ctx) return ctx["cable_plugged"] end,
    def(ctx, data) ctx["cable_locked"] = true end
)
fsm.add_transition(Types.STATE_PREPARING, "AUTH_SUCCESS", Types.STATE_CHARGING, nil, nil)
fsm.add_transition(Types.STATE_CHARGING, "STOP", Types.STATE_FINISHING, nil, nil)
fsm.add_transition(Types.STATE_FINISHING, "UNPLUG", Types.STATE_AVAILABLE, nil, nil)

# Attempt transition with guard failing
var trans_result = fsm.trigger("PLUGIN", nil)
check(trans_result == false, "Guard prevented transition when cable not plugged")
check(fsm.get_state() == Types.STATE_AVAILABLE, "Remains in Available state")

# Set condition and transition
fsm.context["cable_plugged"] = true
check(fsm.trigger("PLUGIN", nil) == true, "Transition to Preparing succeeded")
check(fsm.get_state() == Types.STATE_PREPARING, "FSM in Preparing state")
check(fsm.context["cable_locked"] == true, "Transition action executed")

check(fsm.trigger("AUTH_SUCCESS", nil) == true, "Transition to Charging succeeded")
check(fsm.get_state() == Types.STATE_CHARGING, "FSM in Charging state")

check(fsm.trigger("STOP", nil) == true, "Transition to Finishing succeeded")
check(fsm.get_state() == Types.STATE_FINISHING, "FSM in Finishing state")

check(fsm.trigger("UNPLUG", nil) == true, "Transition to Available succeeded")
check(fsm.get_state() == Types.STATE_AVAILABLE, "FSM back in Available state")

# 6. StationConfig
var cfg = StationConfig()
check(cfg.max_grid_power_kw == 150.0, "Default max grid power = 150 kW")
check(cfg.grid_phases == 3, "Default 3 phases")
cfg.load_from_map({"max_grid_power_kw": 250.0, "evse_count": 8})
check(cfg.max_grid_power_kw == 250.0, "Config updated to 250 kW")
check(cfg.evse_count == 8, "EVSE count updated to 8")

# 7. Errors & Safety Flags
var err_ground = StationError(ErrorCode.ERR_GROUND_FAILURE, ErrorSeverity.CRITICAL, "RCD 30mA trip", 1)
check(err_ground.requires_immediate_power_cutoff() == true, "Ground failure requires cutoff")
check(err_ground.is_latched == true, "Ground failure is latched")

var err_net = StationError(ErrorCode.ERR_CSMS_DISCONNECTED, ErrorSeverity.MINOR, "WebSocket disconnected", 0)
check(err_net.requires_immediate_power_cutoff() == false, "Network loss does not cut power")
check(err_net.is_latched == false, "Minor network loss is not latched")

print(string.format("[PASS] test_core.be passed with %d assertions verified.", total_assertions))
