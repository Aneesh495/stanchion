# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Motorized Connector Lock Actuator & Optical Position Feedback
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import types as Types

class ConnectorLock
    var evse_id
    var state
    var is_locked
    var motor_active
    var retry_count
    var max_retries

    def init(evse_id)
        self.evse_id = int(evse_id)
        self.state = Types.LOCK_UNLOCKED
        self.is_locked = false
        self.motor_active = false
        self.retry_count = 0
        self.max_retries = 3
    end

    # Command lock motor to engage lock pin into EV inlet
    def lock()
        self.motor_active = true
        self.state = Types.LOCK_MOVING
        # Simulate successful optical feedback engagement
        self.is_locked = true
        self.state = Types.LOCK_LOCKED
        self.motor_active = false
        self.retry_count = 0
        return true
    end

    # Command lock motor to retract lock pin
    def unlock()
        self.motor_active = true
        self.state = Types.LOCK_MOVING
        self.is_locked = false
        self.state = Types.LOCK_UNLOCKED
        self.motor_active = false
        self.retry_count = 0
        return true
    end

    # Simulate mechanical blockage fault
    def trigger_jam_fault()
        self.state = Types.LOCK_FAULT
        self.is_locked = false
        self.motor_active = false
    end

    def is_connector_locked()
        return self.is_locked && (self.state == Types.LOCK_LOCKED)
    end

    def is_faulted()
        return self.state == Types.LOCK_FAULT
    end

    def get_state()
        return self.state
    end
end

return ConnectorLock
