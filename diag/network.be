# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Virtual WebSocket Network Manager, Exponential Backoff & Jitter Emulation
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math

class ConnectionState
    static var DISCONNECTED      = "Disconnected"
    static var CONNECTING        = "Connecting"
    static var CONNECTED         = "Connected"
    static var RECONNECT_BACKOFF = "ReconnectBackoff"
end

class NetworkManager
    var state
    var server_url
    var retry_count
    var base_backoff_sec
    var max_backoff_sec
    var current_backoff_sec
    var next_reconnect_epoch_sec
    var simulated_packet_loss_pct
    var simulated_latency_ms
    var last_heartbeat_time_sec

    def init(url, base_backoff, max_backoff)
        self.server_url = str(url)
        self.state = ConnectionState.DISCONNECTED
        self.retry_count = 0
        self.base_backoff_sec = (base_backoff != nil) ? int(base_backoff) : 2
        self.max_backoff_sec = (max_backoff != nil) ? int(max_backoff) : 60
        self.current_backoff_sec = self.base_backoff_sec
        self.next_reconnect_epoch_sec = 0
        self.simulated_packet_loss_pct = 0.0
        self.simulated_latency_ms = 15.0
        self.last_heartbeat_time_sec = 0
    end

    def connect_success()
        self.state = ConnectionState.CONNECTED
        self.retry_count = 0
        self.current_backoff_sec = self.base_backoff_sec
        self.next_reconnect_epoch_sec = 0
    end

    def trigger_disconnect(timestamp_sec)
        self.state = ConnectionState.RECONNECT_BACKOFF
        # Exponential backoff: base * 2^retries capped at max
        var multiplier = 1
        for i : 1 .. self.retry_count
            multiplier = multiplier * 2
            if multiplier > 32 break end
        end
        var backoff = self.base_backoff_sec * multiplier
        if backoff > self.max_backoff_sec
            backoff = self.max_backoff_sec
        end
        self.current_backoff_sec = backoff
        self.next_reconnect_epoch_sec = int(timestamp_sec) + self.current_backoff_sec
        self.retry_count = self.retry_count + 1
    end

    def check_reconnect(current_epoch_sec)
        current_epoch_sec = int(current_epoch_sec)
        if self.state == ConnectionState.RECONNECT_BACKOFF
            if current_epoch_sec >= self.next_reconnect_epoch_sec
                self.state = ConnectionState.CONNECTING
                return true # Attempt reconnection now
            end
        end
        return false
    end

    def is_connected()
        return self.state == ConnectionState.CONNECTED
    end

    def get_state()
        return self.state
    end
end

return NetworkManager
