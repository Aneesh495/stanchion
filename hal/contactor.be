# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Power Contactor Driver, Auxiliary Feedback & Contact Weld Detection
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import types as Types

class Contactor
    var evse_id
    var state
    var command_closed
    var auxiliary_feedback_closed
    var cycles_count
    var max_rated_cycles
    var weld_detected
    var last_operation_ms

    def init(evse_id)
        self.evse_id = int(evse_id)
        self.state = Types.CONTACTOR_OPEN
        self.command_closed = false
        self.auxiliary_feedback_closed = false
        self.cycles_count = 0
        self.max_rated_cycles = 100000
        self.weld_detected = false
        self.last_operation_ms = 0
    end

    # Command contactor to CLOSE (energize coil)
    def close(timestamp_ms)
        if self.weld_detected
            print("[Contactor Critical] Refusing to close welded contactor on EVSE " + str(self.evse_id))
            return false
        end
        self.command_closed = true
        self.state = Types.CONTACTOR_CLOSED
        self.cycles_count = self.cycles_count + 1
        self.last_operation_ms = int(timestamp_ms)
        return true
    end

    # Command contactor to OPEN (de-energize coil)
    def open(timestamp_ms)
        self.command_closed = false
        self.state = Types.CONTACTOR_OPEN
        self.last_operation_ms = int(timestamp_ms)
        return true
    end

    # Process hardware auxiliary switch feedback and downstream voltage sense
    # downstream_voltage_detected: true if voltage sensor detects line voltage on EV plug pins
    def update_hardware_feedback(aux_closed, downstream_voltage_detected)
        self.auxiliary_feedback_closed = bool(aux_closed)

        # Contact weld check:
        # If coil is commanded OPEN, but auxiliary contact is closed or voltage is detected downstream,
        # the contactor is physically welded shut!
        if !self.command_closed && (self.auxiliary_feedback_closed || downstream_voltage_detected)
            self.weld_detected = true
            self.state = Types.CONTACTOR_WELDED
            return false # Weld fault!
        end

        # Discrepancy check: coil commanded closed but auxiliary open
        if self.command_closed && !self.auxiliary_feedback_closed
            self.state = Types.CONTACTOR_FAULT
            return false
        end

        if self.command_closed
            self.state = Types.CONTACTOR_CLOSED
        else
            self.state = Types.CONTACTOR_OPEN
        end
        return true
    end

    def is_closed()
        return self.state == Types.CONTACTOR_CLOSED
    end

    def is_open()
        return self.state == Types.CONTACTOR_OPEN
    end

    def is_welded()
        return self.weld_detected
    end

    def get_cycles_remaining()
        var rem = self.max_rated_cycles - self.cycles_count
        return (rem > 0) ? rem : 0
    end

    def reset_weld_latch_technician()
        self.weld_detected = false
        self.command_closed = false
        self.state = Types.CONTACTOR_OPEN
    end
end

return Contactor
