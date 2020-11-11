# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Subsystem Health Supervisor & Software Watchdog Monitor
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

class SubsystemHealth
    var name
    var last_heartbeat_epoch_sec
    var is_healthy
    var fault_count
    var timeout_threshold_sec

    def init(name, timeout_threshold_sec)
        self.name = str(name)
        self.timeout_threshold_sec = (timeout_threshold_sec != nil) ? int(timeout_threshold_sec) : 10
        self.last_heartbeat_epoch_sec = 0
        self.is_healthy = true
        self.fault_count = 0
    end

    def ping(timestamp_sec)
        self.last_heartbeat_epoch_sec = int(timestamp_sec)
        self.is_healthy = true
    end

    def check(current_epoch_sec)
        current_epoch_sec = int(current_epoch_sec)
        if self.last_heartbeat_epoch_sec > 0
            if (current_epoch_sec - self.last_heartbeat_epoch_sec) > self.timeout_threshold_sec
                self.is_healthy = false
                self.fault_count = self.fault_count + 1
                return false # Stalled!
            end
        end
        return true
    end
end

class HealthSupervisor
    var subsystems

    def init()
        self.subsystems = {}
    end

    def register_subsystem(name, timeout_sec)
        self.subsystems[str(name)] = SubsystemHealth(name, timeout_sec)
    end

    def ping(name, timestamp_sec)
        if self.subsystems.contains(name)
            self.subsystems[name].ping(timestamp_sec)
        end
    end

    def evaluate_all(current_epoch_sec)
        var all_ok = true
        for name : self.subsystems.keys()
            if !self.subsystems[name].check(current_epoch_sec)
                all_ok = false
            end
        end
        return all_ok
    end

    def get_status_report()
        var rep = {}
        for name : self.subsystems.keys()
            var s = self.subsystems[name]
            rep[name] = {
                "healthy": s.is_healthy,
                "fault_count": s.fault_count,
                "last_seen_sec": s.last_heartbeat_epoch_sec
            }
        end
        return rep
    end
end

return HealthSupervisor
