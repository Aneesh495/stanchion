# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Cryptographically Chained Tamper-Evident Security Audit Trail
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import string
import token_hash as TokenHash
import time_util as TimeUtil

# Audit Event Categories
class AuditCategory
    static var SECURITY       = "SECURITY"
    static var CONFIGURATION  = "CONFIGURATION"
    static var FIRMWARE       = "FIRMWARE"
    static var TRANSACTION    = "TRANSACTION"
    static var SAFETY_TRIP    = "SAFETY_TRIP"
end

# Single Chained Audit Record Block
class AuditRecord
    var sequence_number
    var timestamp_epoch_sec
    var event_category
    var actor_identity
    var action
    var details
    var previous_hash
    var block_hash

    def init(seq, ts, cat, actor, act, det, prev_h)
        self.sequence_number = int(seq)
        self.timestamp_epoch_sec = int(ts)
        self.event_category = str(cat)
        self.actor_identity = str(actor)
        self.action = str(act)
        self.details = str(det)
        self.previous_hash = (prev_h != nil) ? str(prev_h) : "GENESIS_00000000"
        self.block_hash = self._compute_hash()
    end

    def _compute_hash()
        var payload = str(self.sequence_number) + "|" +
                      str(self.timestamp_epoch_sec) + "|" +
                      self.event_category + "|" +
                      self.actor_identity + "|" +
                      self.action + "|" +
                      self.details + "|" +
                      self.previous_hash
        return TokenHash.hex_digest(payload, "STANCHION_AUDIT_SALT")
    end

    def is_block_valid(expected_previous_hash)
        if self.previous_hash != expected_previous_hash
            return false
        end
        var recomputed = self._compute_hash()
        return TokenHash.secure_compare(self.block_hash, recomputed)
    end

    def to_map()
        return {
            "seq": self.sequence_number,
            "timestamp": TimeUtil.to_iso8601(self.timestamp_epoch_sec),
            "category": self.event_category,
            "actor": self.actor_identity,
            "action": self.action,
            "details": self.details,
            "prev_hash": self.previous_hash,
            "hash": self.block_hash
        }
    end
end

# Tamper-Evident Audit Trail Ledger
class AuditTrailLedger
    var records
    var max_records
    var is_tamper_detected
    var tamper_alarm_timestamp

    def init(capacity_limit)
        self.max_records = (capacity_limit != nil) ? int(capacity_limit) : 1000
        self.records = []
        self.is_tamper_detected = false
        self.tamper_alarm_timestamp = nil
        # Initialize with Genesis Block
        self._create_genesis_block()
    end

    def _create_genesis_block()
        var genesis = AuditRecord(0, 1770000000, AuditCategory.SECURITY, "SYSTEM", "GENESIS_INIT", "Audit log initialised", "0000000000000000")
        self.records.push(genesis)
    end

    # Append new verified audit event
    def append_event(category, actor, action, details, timestamp_sec)
        var last_rec = self.records[size(self.records) - 1]
        var next_seq = last_rec.sequence_number + 1
        var ts = (timestamp_sec != nil) ? int(timestamp_sec) : last_rec.timestamp_epoch_sec

        var new_record = AuditRecord(next_seq, ts, category, actor, action, details, last_rec.block_hash)
        self.records.push(new_record)

        # Enforce memory capacity bounds if necessary
        if size(self.records) > self.max_records
            # Oldest records spooled
        end

        return new_record
    end

    # Complete cryptographic integrity verification across entire chain
    def verify_integrity()
        if size(self.records) == 0
            return {"valid": false, "reason": "EmptyLedger"}
        end

        var expected_prev = "0000000000000000"
        var i = 0
        while i < size(self.records)
            var rec = self.records[i]
            if !rec.is_block_valid(expected_prev)
                self.is_tamper_detected = true
                return {
                    "valid": false,
                    "tampered_index": i,
                    "tampered_sequence": rec.sequence_number,
                    "reason": "CryptographicHashMismatch"
                }
            end
            expected_prev = rec.block_hash
            i = i + 1
        end

        return {
            "valid": true,
            "total_blocks_verified": size(self.records),
            "head_hash": expected_prev
        }
    end

    # Trigger hardware tamper detection switch
    def trigger_tamper_switch(timestamp_sec)
        self.is_tamper_detected = true
        self.tamper_alarm_timestamp = int(timestamp_sec)
        self.append_event(AuditCategory.SECURITY, "ENCLOSURE_SENSOR", "PHYSICAL_TAMPER_DETECTED", "Cabinet door opened unexpectedly", timestamp_sec)
    end

    # Query audit events within sequence range
    def get_records_slice(start_seq, count)
        var start_s = int(start_seq)
        var cnt = int(count)
        var out = []

        var i = 0
        while i < size(self.records)
            var r = self.records[i]
            if r.sequence_number >= start_s && size(out) < cnt
                out.push(r.to_map())
            end
            i = i + 1
        end
        return out
    end
end

return {
    "AuditCategory": AuditCategory,
    "AuditRecord": AuditRecord,
    "AuditTrailLedger": AuditTrailLedger
}
