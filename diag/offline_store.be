# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Persistent Offline Transaction Journal, Crash Recovery & Replay Spooler
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import collection as Col
import json

var Deque = Col["Deque"]

class OfflineJournalEntry
    var journal_id
    var action_type
    var payload
    var timestamp_sec
    var is_replayed

    def init(jid, act, payload, t_sec)
        self.journal_id = int(jid)
        self.action_type = str(act)
        self.payload = (payload != nil) ? payload : {}
        self.timestamp_sec = int(t_sec)
        self.is_replayed = false
    end
end

class OfflineStore
    var spool_queue
    var next_journal_id
    var max_capacity
    var replayed_history

    def init(capacity)
        self.max_capacity = (capacity != nil) ? int(capacity) : 500
        self.spool_queue = Deque()
        self.next_journal_id = 1
        self.replayed_history = []
    end

    # Enqueue an unacknowledged message to the offline persistent journal
    def append_entry(action_type, payload, timestamp_sec)
        if self.spool_queue.size() >= self.max_capacity
            # Evict oldest entry if storage quota is full
            self.spool_queue.pop_front()
        end
        var entry = OfflineJournalEntry(self.next_journal_id, action_type, payload, timestamp_sec)
        self.next_journal_id = self.next_journal_id + 1
        self.spool_queue.push_back(entry)
        return entry.journal_id
    end

    # Replay all spooled messages to an outbound dispatch callback upon network reconnection
    def replay_all(dispatch_fn)
        var replayed_count = 0
        while !self.spool_queue.is_empty()
            var entry = self.spool_queue.peek_front()
            var ok = false
            try
                ok = bool(dispatch_fn(entry.action_type, entry.payload))
            except .. as err
                print("[OfflineStore Replay Error] " + str(err))
                break # Stop replaying on network dispatch failure
            end

            if ok
                entry.is_replayed = true
                self.replayed_history.push(entry)
                self.spool_queue.pop_front()
                replayed_count = replayed_count + 1
            else
                # Connection dropped again during replay, retain remaining spool
                break
            end
        end
        return replayed_count
    end

    def pending_count()
        return self.spool_queue.size()
    end

    def is_empty()
        return self.spool_queue.is_empty()
    end

    def clear()
        self.spool_queue.clear()
        self.replayed_history = []
    end
end

return OfflineStore
