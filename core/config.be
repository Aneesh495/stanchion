# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Configuration Repository, Grid Parameters & Station Defaults
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

class StationConfig
    var station_id
    var model
    var vendor
    var firmware_version
    var max_grid_power_kw
    var max_grid_current_a
    var nominal_voltage_v
    var grid_phases
    var evse_count
    var ocpp_csms_url
    var heartbeat_interval_sec
    var meter_sample_interval_sec
    var offline_authorization_enabled
    var default_auth_cache_ttl_sec

    def init()
        self.station_id = "STANCHION-DEPOT-01"
        self.model = "Stanchion-HyperCharge-150"
        self.vendor = "Stanchion Power Systems"
        self.firmware_version = "1.0.0"

        # Grid Infrastructure Limits
        self.max_grid_power_kw = 150.0
        self.max_grid_current_a = 217.0 # At 400V 3-phase
        self.nominal_voltage_v = 230.0  # L-N (400V L-L)
        self.grid_phases = 3
        self.evse_count = 4

        # Cloud & Communication Settings
        self.ocpp_csms_url = "wss://csms.stanchion-cloud.net/ocpp201"
        self.heartbeat_interval_sec = 60
        self.meter_sample_interval_sec = 10
        self.offline_authorization_enabled = true
        self.default_auth_cache_ttl_sec = 86400 # 24 hours
    end

    def to_map()
        return {
            "station_id": self.station_id,
            "model": self.model,
            "vendor": self.vendor,
            "firmware_version": self.firmware_version,
            "max_grid_power_kw": self.max_grid_power_kw,
            "max_grid_current_a": self.max_grid_current_a,
            "nominal_voltage_v": self.nominal_voltage_v,
            "grid_phases": self.grid_phases,
            "evse_count": self.evse_count,
            "ocpp_csms_url": self.ocpp_csms_url,
            "heartbeat_interval_sec": self.heartbeat_interval_sec,
            "meter_sample_interval_sec": self.meter_sample_interval_sec,
            "offline_authorization_enabled": self.offline_authorization_enabled,
            "default_auth_cache_ttl_sec": self.default_auth_cache_ttl_sec
        }
    end

    def load_from_map(m)
        if m == nil return end
        if m.contains("station_id") self.station_id = str(m["station_id"]) end
        if m.contains("model") self.model = str(m["model"]) end
        if m.contains("vendor") self.vendor = str(m["vendor"]) end
        if m.contains("firmware_version") self.firmware_version = str(m["firmware_version"]) end
        if m.contains("max_grid_power_kw") self.max_grid_power_kw = real(m["max_grid_power_kw"]) end
        if m.contains("max_grid_current_a") self.max_grid_current_a = real(m["max_grid_current_a"]) end
        if m.contains("nominal_voltage_v") self.nominal_voltage_v = real(m["nominal_voltage_v"]) end
        if m.contains("grid_phases") self.grid_phases = int(m["grid_phases"]) end
        if m.contains("evse_count") self.evse_count = int(m["evse_count"]) end
        if m.contains("ocpp_csms_url") self.ocpp_csms_url = str(m["ocpp_csms_url"]) end
        if m.contains("heartbeat_interval_sec") self.heartbeat_interval_sec = int(m["heartbeat_interval_sec"]) end
        if m.contains("meter_sample_interval_sec") self.meter_sample_interval_sec = int(m["meter_sample_interval_sec"]) end
        if m.contains("offline_authorization_enabled") self.offline_authorization_enabled = bool(m["offline_authorization_enabled"]) end
        if m.contains("default_auth_cache_ttl_sec") self.default_auth_cache_ttl_sec = int(m["default_auth_cache_ttl_sec"]) end
    end
end

return StationConfig
