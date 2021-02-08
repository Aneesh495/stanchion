# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# EVSE Bay Reservation & Schedule Collision Detection (OCPP 2.0.1)
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math
import math_ext as MathExt
import time_util as TimeUtil

# Reservation Status Codes (OCPP 2.0.1 ReserveNowStatusEnumType)
class ReserveNowStatus
    static var ACCEPTED     = "Accepted"
    static var FAULTED      = "Faulted"
    static var OCCUPIED     = "Occupied"
    static var REJECTED     = "Rejected"
    static var UNAVAILABLE  = "Unavailable"
end

# Single Bay Reservation Entry
class ReservationEntry
    var reservation_id
    var evse_id
    var id_token
    var group_id_token
    var start_epoch_sec
    var expiry_epoch_sec
    var is_active
    var is_preemptible

    def init(res_id, evse_num, token_str, group_token, start_epoch, expiry_epoch, preemptible)
        self.reservation_id = int(res_id)
        self.evse_id = int(evse_num)
        self.id_token = str(token_str)
        self.group_id_token = (group_token != nil) ? str(group_token) : nil
        self.start_epoch_sec = int(start_epoch)
        self.expiry_epoch_sec = int(expiry_epoch)
        self.is_active = true
        self.is_preemptible = (preemptible != nil) ? preemptible : false
    end

    def is_expired_at(current_epoch)
        return int(current_epoch) >= self.expiry_epoch_sec
    end

    def to_map()
        return {
            "reservationId": self.reservation_id,
            "evseId": self.evse_id,
            "idToken": self.id_token,
            "groupIdToken": self.group_id_token,
            "start": TimeUtil.to_iso8601(self.start_epoch_sec),
            "expiry": TimeUtil.to_iso8601(self.expiry_epoch_sec),
            "active": self.is_active,
            "preemptible": self.is_preemptible
        }
    end
end

# EVSE Bay Reservation Supervisor
class ReservationManager
    var max_reservations
    var active_reservations
    var total_evse_count

    def init(evse_count)
        self.total_evse_count = (evse_count != nil) ? int(evse_count) : 4
        self.max_reservations = 100
        self.active_reservations = {} # Keyed by reservation_id
    end

    # Handle ReserveNow request
    def reserve_now(res_id, evse_id, id_token, group_token, start_epoch, expiry_epoch, is_emergency)
        var r_id = int(res_id)
        var target_evse = int(evse_id)

        # Check EVSE bounds
        if target_evse < 0 || target_evse > self.total_evse_count
            return {"status": ReserveNowStatus.REJECTED, "reason": "InvalidEVSEId"}
        end

        # Check for time window validity
        if int(expiry_epoch) <= int(start_epoch)
            return {"status": ReserveNowStatus.REJECTED, "reason": "ExpiryMustBeAfterStart"}
        end

        # Check for schedule collision on requested EVSE
        var collision_res = self._check_collision(target_evse, start_epoch, expiry_epoch)
        if collision_res["has_collision"]
            var existing_res = collision_res["conflicting_reservation"]
            if is_emergency && existing_res.is_preemptible
                # Preempt lower-priority reservation
                existing_res.is_active = false
                self.active_reservations.remove(existing_res.reservation_id)
            else
                return {"status": ReserveNowStatus.OCCUPIED, "reason": "BayAlreadyReserved"}
            end
        end

        var entry = ReservationEntry(r_id, target_evse, id_token, group_token, start_epoch, expiry_epoch, !is_emergency)
        self.active_reservations[r_id] = entry

        return {"status": ReserveNowStatus.ACCEPTED, "reservation": entry.to_map()}
    end

    # Cancel active reservation
    def cancel_reservation(res_id)
        var r_id = int(res_id)
        if self.active_reservations.contains(r_id)
            self.active_reservations.remove(r_id)
            return true
        end
        return false
    end

    # Verify if an arriving card swipe matches the reservation on an EVSE
    def check_authorization_for_bay(evse_id, id_token, group_token, current_epoch)
        var target_evse = int(evse_id)
        var now_t = int(current_epoch)

        # Look for any active reservation on this EVSE (or station-wide pool evse_id == 0)
        for r_id : self.active_reservations.keys()
            var r = self.active_reservations[r_id]
            if (r.evse_id == target_evse || r.evse_id == 0) && r.is_active
                # Check if current time falls within reservation window
                if now_t >= r.start_epoch_sec && now_t <= r.expiry_epoch_sec
                    # Match by id_token or group_token
                    if r.id_token == str(id_token) || (r.group_id_token != nil && r.group_id_token == str(group_token))
                        # Valid reservation matched!
                        return {"authorized": true, "reservation_id": r.reservation_id}
                    else
                        # Bay is reserved by someone else!
                        return {"authorized": false, "reason": "ReservedForDifferentDriver"}
                    end
                end
            end
        end

        # No active reservation on this bay: anyone can use it
        return {"authorized": true, "reservation_id": nil}
    end

    # Periodic cleanup of expired reservations
    def purge_expired(current_epoch)
        var now_t = int(current_epoch)
        var expired_ids = []

        for r_id : self.active_reservations.keys()
            var r = self.active_reservations[r_id]
            if r.is_expired_at(now_t)
                expired_ids.push(r_id)
            end
        end

        var count = 0
        var i = 0
        while i < size(expired_ids)
            self.active_reservations.remove(expired_ids[i])
            count = count + 1
            i = i + 1
        end
        return count
    end

    def _check_collision(evse_id, start_epoch, expiry_epoch)
        var start_t = int(start_epoch)
        var exp_t = int(expiry_epoch)

        for r_id : self.active_reservations.keys()
            var r = self.active_reservations[r_id]
            if (r.evse_id == evse_id || r.evse_id == 0 || evse_id == 0) && r.is_active
                # Interval overlap: max(start1, start2) < min(end1, end2)
                var max_start = (start_t > r.start_epoch_sec) ? start_t : r.start_epoch_sec
                var min_end = (exp_t < r.expiry_epoch_sec) ? exp_t : r.expiry_epoch_sec
                if max_start < min_end
                    return {"has_collision": true, "conflicting_reservation": r}
                end
            end
        end
        return {"has_collision": false, "conflicting_reservation": nil}
    end
end

return {
    "ReserveNowStatus": ReserveNowStatus,
    "ReservationEntry": ReservationEntry,
    "ReservationManager": ReservationManager
}
