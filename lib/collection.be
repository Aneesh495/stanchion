# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# High-Performance Data Structures: Deque, RingBuffer, PriorityQueue, SortedSet
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

# Double-Ended Queue (Deque)
class Deque
    var items

    def init()
        self.items = []
    end

    def push_back(item)
        self.items.push(item)
    end

    def push_front(item)
        self.items.insert(0, item)
    end

    def pop_back()
        if self.items.size() == 0
            return nil
        end
        return self.items.pop()
    end

    def pop_front()
        if self.items.size() == 0
            return nil
        end
        var item = self.items[0]
        self.items.remove(0)
        return item
    end

    def peek_front()
        if self.items.size() == 0
            return nil
        end
        return self.items[0]
    end

    def peek_back()
        var n = self.items.size()
        if n == 0
            return nil
        end
        return self.items[n - 1]
    end

    def size()
        return self.items.size()
    end

    def is_empty()
        return self.items.size() == 0
    end

    def clear()
        self.items = []
    end

    def to_list()
        var res = []
        for x : self.items
            res.push(x)
        end
        return res
    end
end

# Fixed-Capacity Circular Ring Buffer for High-Rate Telemetry Time-Series
class RingBuffer
    var buffer
    var capacity
    var head
    var count

    def init(capacity)
        self.capacity = (capacity > 0) ? int(capacity) : 16
        self.buffer = []
        self.head = 0
        self.count = 0
    end

    def push(item)
        if self.buffer.size() < self.capacity
            self.buffer.push(item)
            self.count = self.buffer.size()
        else
            self.buffer[self.head] = item
            self.head = (self.head + 1) % self.capacity
            self.count = self.capacity
        end
    end

    def get(index)
        index = int(index)
        if index < 0 || index >= self.count
            return nil
        end
        if self.buffer.size() < self.capacity
            return self.buffer[index]
        else
            var actual_idx = (self.head + index) % self.capacity
            return self.buffer[actual_idx]
        end
    end

    def latest()
        if self.count == 0
            return nil
        end
        return self.get(self.count - 1)
    end

    def oldest()
        if self.count == 0
            return nil
        end
        return self.get(0)
    end

    def size()
        return self.count
    end

    def is_full()
        return self.count == self.capacity
    end

    def clear()
        self.buffer = []
        self.head = 0
        self.count = 0
    end

    def to_list()
        var res = []
        for i : 0 .. (self.count - 1)
            res.push(self.get(i))
        end
        return res
    end
end

# Binary Heap Priority Queue (Min-Heap by default, support custom comparator)
class PriorityQueue
    var heap
    var is_min_heap

    def init(is_min_heap)
        self.heap = []
        self.is_min_heap = (is_min_heap != nil) ? bool(is_min_heap) : true
    end

    def _compare(a, b)
        # Each item expected to be a map: {'priority': number, 'value': any}
        # Or a raw number
        var prio_a = 0.0
        var prio_b = 0.0
        if isinstance(a, map) && a.contains("priority")
            prio_a = real(a["priority"])
        else
            prio_a = real(a)
        end
        if isinstance(b, map) && b.contains("priority")
            prio_b = real(b["priority"])
        else
            prio_b = real(b)
        end

        if self.is_min_heap
            return prio_a < prio_b
        else
            return prio_a > prio_b
        end
    end

    def push(item)
        self.heap.push(item)
        self._sift_up(self.heap.size() - 1)
    end

    def pop()
        var n = self.heap.size()
        if n == 0
            return nil
        end
        var top = self.heap[0]
        var last = self.heap.pop()
        if self.heap.size() > 0
            self.heap[0] = last
            self._sift_down(0)
        end
        return top
    end

    def peek()
        if self.heap.size() == 0
            return nil
        end
        return self.heap[0]
    end

    def size()
        return self.heap.size()
    end

    def is_empty()
        return self.heap.size() == 0
    end

    def _sift_up(idx)
        while idx > 0
            var parent = (idx - 1) / 2
            if self._compare(self.heap[idx], self.heap[parent])
                # Swap
                var temp = self.heap[idx]
                self.heap[idx] = self.heap[parent]
                self.heap[parent] = temp
                idx = parent
            else
                break
            end
        end
    end

    def _sift_down(idx)
        var n = self.heap.size()
        while true
            var left = 2 * idx + 1
            var right = 2 * idx + 2
            var best = idx

            if left < n && self._compare(self.heap[left], self.heap[best])
                best = left
            end
            if right < n && self._compare(self.heap[right], self.heap[best])
                best = right
            end

            if best != idx
                var temp = self.heap[idx]
                self.heap[idx] = self.heap[best]
                self.heap[best] = temp
                idx = best
            else
                break
            end
        end
    end
end

# Sorted Set of Unique Elements with Binary Search Lookup
class SortedSet
    var items

    def init()
        self.items = []
    end

    def contains(val)
        var idx = self._binary_search(val)
        return (idx >= 0 && idx < self.items.size() && self.items[idx] == val)
    end

    def add(val)
        var n = self.items.size()
        if n == 0
            self.items.push(val)
            return true
        end
        var idx = self._binary_search(val)
        if idx < n && self.items[idx] == val
            return false
        end
        self.items.insert(idx, val)
        return true
    end

    def remove(val)
        var idx = self._binary_search(val)
        if idx < self.items.size() && self.items[idx] == val
            self.items.remove(idx)
            return true
        end
        return false
    end

    def size()
        return self.items.size()
    end

    def to_list()
        var res = []
        for x : self.items
            res.push(x)
        end
        return res
    end

    def _binary_search(val)
        var low = 0
        var high = self.items.size() - 1
        while low <= high
            var mid = (low + high) / 2
            if self.items[mid] == val
                return mid
            elif self.items[mid] < val
                low = mid + 1
            else
                high = mid - 1
            end
        end
        return low
    end
end

var Collection = {
    "Deque": Deque,
    "RingBuffer": RingBuffer,
    "PriorityQueue": PriorityQueue,
    "SortedSet": SortedSet
}

return Collection
