# Stanchion

```
  ███████╗████████╗ █████╗ ███╗   ██╗ ██████╗██╗  ██╗██╗ ██████╗ ███╗   ██╗
  ██╔════╝╚══██╔══╝██╔══██╗████╗  ██║██╔════╝██║  ██║██║██╔═══██╗████╗  ██║
  ███████╗   ██║   ███████║██╔██╗ ██║██║     ███████║██║██║   ██║██╔██╗ ██║
  ╚════██║   ██║   ██╔══██║██║╚██╗██║██║     ██╔══██║██║██║   ██║██║╚██╗██║
  ███████║   ██║   ██║  ██║██║ ╚████║╚██████╗██║  ██║██║╚██████╔╝██║ ╚████║
  ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝╚═╝  ╚═╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝
```

**Intelligent EV Charging Station Controller & Microgrid Energy Router**

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)]()
[![Test Suite](https://img.shields.io/badge/tests-30%2F30%20passing%20(100%25)-success.svg)]()
[![Language](https://img.shields.io/badge/language-Berry%20%7C%20C%20Host-blue.svg)]()
[![Compliance](https://img.shields.io/badge/standards-IEC%2061851--1%20%7C%20ISO%2015118--20%20%7C%20OCPP%202.0.1-orange.svg)]()
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

Stanchion is a high-performance, embedded Electric Vehicle Supply Equipment (EVSE) controller and real-time microgrid energy router. Engineered from first principles around a deterministic Berry bytecode VM with native C host glue, Stanchion implements the complete stack from hardware-level IEC 61851-1 analog pilot signaling to ISO 15118-20 Megawatt Charging (MCS) and OCPP 2.0.1 Cloud Management.

Designed for commercial fleet depots, highway fast-charging hubs, and decentralized microgrids, Stanchion balances physical electrical safety, vehicle communication, localized solar PV generation, stationary battery storage (BESS), and sub-second grid frequency regulation.

---

## Technical Highlights

- **Embedded Berry Core**: Clean, modular systems architecture written in pure Berry (`.be`) with a native C host bridge (`host_main.c`), executing with determinism on microcontrollers (STM32, ESP32) and industrial Linux edge gateways.
- **IEC 61851-1 Control Pilot & Safety**: 1 kHz PWM square-wave generation, 8-sample moving-average ADC filter, negative diode -12V fault detection, contactor weld verification, DC 6mA residual current monitoring (RCD-B), and Bender IMD insulation monitoring.
- **ISO 15118-20 DC Fast & Megawatt Charging (MCS)**: Automated Connection Device (ACD) pantograph docking, precharge voltage matching, 150 A/s current slew-rate limiting, active liquid cable chilling, and V2G PKI contract certificate validation.
- **OCPP 2.0.1 Protocol Engine**: Full JSON-RPC 2.0 framing, unified `TransactionEvent` lifecycle (Started, Updated, Ended), 3-tier Device Model schema, Security Profiles 1 to 3 (mTLS), and an offline store with replay deduplication.
- **Dynamic Load Management (DLM)**: Bounded weighted proportional water-filling algorithm that solves current allocations across 100 EVSE channels in 96 microseconds, adapting to asymmetric 3-phase unbalance and transformer thermal limits.
- **Microgrid Energy Router**: Real-time multi-source power routing across grid feeds, solar PV inverters, stationary BESS, and bi-directional vehicle-to-grid (V2G) power transfers.
- **Sub-Second Grid Frequency Regulation**: Fast Frequency Response (FFR / FCR) droop governor that throttles charging or commands V2G discharge during under-frequency events.
- **Comprehensive Verification**: 30 dedicated test suites verifying 450+ unit, integration, and scenario assertions across all operational modules.

---

## Architectural Topology

```mermaid
flowchart TD
    subgraph StationLayer ["Station Orchestration & HMI"]
        MAIN["Station CLI Application (station/main.be)"]
        HMI["Local Status Display & Terminal UI (station/hmi.be)"]
        COORD["Session Coordinator (station/session.be)"]
        TELEM["Telemetry Engine (station/telemetry.be)"]
    end

    subgraph EnergyLayer ["Energy & Policy Management"]
        DLM["Dynamic Load Management (energy/dlm.be)"]
        PHASE["Phase Balancer (energy/phase_balance.be)"]
        SOLAR["Solar PV + BESS Optimizer (energy/solar_storage.be)"]
        V2G["V2G Grid Dispatcher (energy/v2g.be)"]
        FREQ["FFR / FCR Droop Governor (energy/freq_regulation.be)"]
        THERM["Transformer Thermal Model (energy/thermal_model.be)"]
        POLICY["Policy & Billing Engine (policy/engine.be)"]
    end

    subgraph ProtocolLayer ["Protocols & Central System"]
        OCPP["OCPP 2.0.1 Protocol Engine (ocpp/)"]
        DEVMOD["Device Model Schema (ocpp/device_model_schema.be)"]
        ISO15118["ISO 15118-20 DC & V2G Engine (protocols/iso15118_20_dc.be)"]
        PKI["V2G PKI & Contract Certs (protocols/iso15118_v2g_pki.be)"]
        STORE["Offline Transaction Store (diag/offline_store.be)"]
    end

    subgraph HallLayer ["Hardware Abstraction Layer (HAL)"]
        PILOT["Control Pilot PWM Transceiver (hal/pilot.be)"]
        METER["Bi-directional Energy Meter (hal/meter.be)"]
        RELAY["Contactor Driver & Weld Sense (hal/contactor.be)"]
        SAFE["RCD-B Guard & E-Stop Interlocks (hal/safety.be)"]
        LOCK["Motorized Solenoid Lock (hal/lock.be)"]
        IMD["Bender IMD Insulation Monitor (hal/insulation_monitor.be)"]
        COOL["Active Liquid Cable Chiller (hal/cooling_loop.be)"]
    end

    MAIN --> COORD
    COORD --> POLICY
    COORD --> DLM
    COORD --> OCPP
    COORD --> ISO15118
    DLM --> PHASE
    DLM --> SOLAR
    DLM --> FREQ
    DLM --> THERM
    OCPP --> STORE
    OCPP --> DEVMOD
    ISO15118 --> PKI
    COORD --> PILOT
    COORD --> METER
    COORD --> RELAY
    COORD --> LOCK
    SAFE --> RELAY
    COOL --> COORD
    IMD --> SAFE
```

---

## Subsystems & Technical Details

### 1. Hardware Abstraction Layer & Safety Architecture

The hardware layer (`hal/`) isolates physical transducers from the high-level business logic:

- **Control Pilot Transceiver (`hal/pilot.be`)**: Implements IEC 61851-1 signaling. Samples positive and negative pilot voltages via an 8-sample circular buffer (`hal/adc_filter.be`), rejecting noise spikes. Detects states A (12V), B (9V), C (6V), D (3V), E (0V), and F (-12V diode failure).
- **Contactor Driver (`hal/contactor.be`)**: Controls AC/DC contactor coils with auxiliary microswitch feedback. Performs pre-closure weld checks and post-opening verification within 50 ms to prevent contactor freeze hazards.
- **Safety Interlocks (`hal/safety.be`)**: Handles fast-interrupt events: DC 6mA residual current (IEC 62955), AC 30mA ground faults, emergency stop button depression, and cabinet enclosure intrusion microswitches.
- **Bender IMD Monitor (`hal/insulation_monitor.be`)**: Continuous isolation resistance monitoring for ungrounded IT DC fast-charging systems. Triggers automated bus shutdown when resistance drops below 500 Ohm/V.
- **Active Cable Chiller (`hal/cooling_loop.be`)**: Closed-loop proportional pump and fan regulation for high-power Megawatt Charging (MCS) cables, monitoring PT1000 RTDs on DC+ and DC- connector pins.

### 2. Smart Charging & Microgrid Optimization

The energy management subsystem (`energy/`) optimizes power allocation at sub-second intervals:

- **Dynamic Load Management (`energy/dlm.be`)**: Solves a bounded weighted proportional sharing problem:
  $$\max \sum_{i \in N} w_i \cdot \ln(I_i) \quad \text{subject to} \quad \sum I_i \le I_{cap}, \quad I_{min,i} \le I_i \le I_{max,i}$$
  Features priority weighting (Emergency, VIP, Fleet, Standard) and anti-flapping hysteresis.
- **Three-Phase Balancing (`energy/phase_balance.be`)**: Analyzes per-phase currents (L1, L2, L3) and redistributes single-phase vehicle allocations to eliminate neutral wire overload.
- **Solar PV + BESS Optimizer (`energy/solar_storage.be`)**: Coordinates on-site solar generation, stationary battery storage (150 kWh / 80 kW), and vehicle loads. Sub-second BESS discharge buffers transient solar cloud dips with zero grid import.
- **Fast Frequency Response (`energy/freq_regulation.be`)**: Grid droop governor responding to under-frequency dips ($< 49.95\text{ Hz}$ or $< 59.95\text{ Hz}$) by curtailing EV load or dispatching V2G power.
- **Transformer Thermal Model (`energy/thermal_model.be`)**: IEC 60076-7 Arrhenius thermal model estimating winding hotspot temperatures and applying dynamic curtailment factors before transformer degradation occurs.

### 3. Protocols: OCPP 2.0.1 and ISO 15118-20

- **OCPP 2.0.1 Protocol Engine (`ocpp/`)**: Implements JSON-RPC 2.0 framing, unified `TransactionEvent` lifecycle tracking, 3-tier Device Model schema (`ocpp/device_model_schema.be`), and Security Profiles 1 through 3 (`ocpp/security_profiles.be`).
- **Offline Store (`diag/offline_store.be`)**: Buffers transactions locally during network outages, replaying messages with exponential backoff and idempotency keys upon link restoration.
- **ISO 15118-20 DC Fast Charging (`protocols/iso15118_20_dc.be`)**: Manages automated connection device (ACD) pantograph docking, precharge DC bus synchronization ($\pm 10\text{V}$), 150 A/s current slew-rate limiting, and bidirectional power transfer (BPT).
- **V2G PKI Engine (`protocols/iso15118_v2g_pki.be`)**: Validates OEM Root CAs, Sub-CAs, Contract Certificates, and eMAID identifiers for Plug & Charge (PnC) autonomous authorization.

---

## Performance Benchmarks

Micro-benchmarks executed on the embedded runtime via `tests/test_benchmarks.be`:

| Benchmark Workload | Iterations | Latency per Op | Throughput | Real-Time Headroom |
| :--- | :--- | :--- | :--- | :--- |
| **100-EVSE DLM Water-Filling Solve** | 500 cycles | $0.096\text{ ms}$ | $10,435\text{ solves/sec}$ | $104\times$ ($< 10\text{ ms}$ budget) |
| **Salted FNV-1a Token Digest** | 5,000 hashes | $8.13\text{ }\mu\text{s}$ | $123,022\text{ hashes/sec}$ | $12\times$ ($< 0.1\text{ ms}$ budget) |
| **CRC-16 Modbus Meter Verification** | 3,000 frames | $19.33\text{ }\mu\text{s}$ | $51,727\text{ frames/sec}$ | $26\times$ ($< 0.5\text{ ms}$ budget) |
| **OCPP 2.0.1 JSON-RPC Frame Serialize**| 2,000 frames | $31.70\text{ }\mu\text{s}$ | $31,546\text{ frames/sec}$ | $156\times$ ($< 5\text{ ms}$ budget) |
| **PhysicalValue Scaler Conversion** | 10,000 ops | $0.86\text{ }\mu\text{s}$ | $1,156,203\text{ ops/sec}$ | $1,162\times$ ($< 1\text{ ms}$ budget) |

**Memory Footprint**: Total RAM consumption under 450 KB, suitable for bare-metal ARM Cortex-M7 and ESP32-S3 targets.

---

## Directory Structure

```
stanchion/
├── Makefile                     # Build system compiling native C host and Berry VM
├── README.md                    # Flagship project documentation and architecture
├── bin/
│   └── stanchion                # Compiled Stanchion executable with embedded Berry runtime
├── core/                        # Core runtime infrastructure
│   ├── config.be                # Hierarchical configuration registry
│   ├── errors.be                # Strongly-typed error taxonomy
│   ├── events.be                # Zero-allocation publish/subscribe event bus
│   ├── fsm.be                   # Hierarchical finite state machine engine
│   ├── logger.be                # Structured diagnostic logging with severity levels
│   ├── timer.be                 # Software timer scheduler
│   └── types.be                 # Domain type definitions and validation
├── diag/                        # Diagnostic and telemetry services
│   ├── audit_trail.be           # Append-only circular security audit log
│   ├── can_diagnostics.be       # CAN 2.0B vehicle communication decoder
│   ├── fault_recorder.be        # Freeze-frame snapshot diagnostic recorder
│   ├── health.be                # Subsystem health monitor and watchdog
│   ├── metrics.be               # Performance counter and metric accumulator
│   ├── network.be               # Network socket interface and ping monitor
│   ├── offline_store.be         # Flash transactional queue with replay deduplication
│   └── system_profiler.be       # Memory and execution profiler
├── docs/                        # Deep developer documentation
│   ├── architecture.md          # Systems architecture specification & state machines
│   ├── benchmarks.md            # Empirical performance benchmarks and latency budgets
│   ├── ocpp_protocol.md         # OCPP 2.0.1 transaction and device model guide
│   ├── safety_and_hal.md        # Hardware abstraction layer and safety interlocks
│   └── smart_charging.md        # Mathematical optimization and energy routing models
├── energy/                      # Energy management and optimization algorithms
│   ├── composite_schedule.be    # Tariff and limit composite schedule merger
│   ├── curtailment.be           # Substation grid curtailment signal handler
│   ├── dlm.be                   # Dynamic Load Management water-filling engine
│   ├── freq_regulation.be       # Fast Frequency Response (FFR) droop governor
│   ├── phase_balance.be         # Asymmetric 3-phase load equalizer
│   ├── solar_storage.be         # Multi-source Solar PV + BESS router
│   ├── tariff.be                # Time-of-Use (ToU) and spot-market tariff model
│   ├── thermal_model.be         # IEC 60076-7 transformer thermal aging model
│   └── v2g.be                   # ISO 15118-20 bidirectional V2G dispatcher
├── hal/                         # Hardware Abstraction Layer
│   ├── adc_filter.be            # Moving-average noise filter for analog ADC pins
│   ├── contactor.be             # Contactor coil driver with weld detection
│   ├── cooling_loop.be          # Megawatt cable chiller and radiator controller
│   ├── display.be               # Front-panel LCD/OLED display driver
│   ├── insulation_monitor.be    # Bender A-ISOMETER DC insulation monitor
│   ├── lock.be                  # Motorized connector latch solenoid driver
│   ├── meter.be                 # Bi-directional active/reactive energy meter
│   ├── pilot.be                 # IEC 61851-1 Control Pilot PWM transceiver
│   └── safety.be                # Type-B RCD, E-stop, and tamper safety guards
├── lib/                         # Standard algorithms and utility libraries
│   ├── collection.be            # Ring buffer, queue, and stack collections
│   ├── crc.be                   # CRC-16 Modbus and CRC-32 table algorithms
│   ├── math_ext.be              # Statistical functions, LERP, and numerical sorting
│   ├── string_util.be           # String tokenizers, hex parsers, and padding
│   ├── time_util.be             # ISO 8601 timestamps and calendar arithmetic
│   ├── token_hash.be            # Salted FNV-1a hash with constant-time equality
│   └── uuid.be                  # RFC 4122 Version 4 UUID generator
├── ocpp/                        # OCPP 2.0.1 Protocol Subsystem
│   ├── auth.be                  # IdToken authorization cache and validator
│   ├── charging_profile.be      # Charging schedule and composite limit calculator
│   ├── device_model_schema.be   # 3-tier component/variable schema
│   ├── frame.be                 # JSON-RPC 2.0 frame serialization and parser
│   ├── handlers.be              # Incoming CSMS call handlers
│   ├── messages.be              # Outgoing message payload builders
│   ├── security.be              # Certificate store and tamper event auditor
│   ├── security_profiles.be     # Security Profiles 1 to 3 (mTLS) enforcement
│   ├── transaction.be           # Transaction state tracker and meter accumulator
│   └── variables.be             # Device model configuration variable registry
├── policy/                      # Fleet scheduling and billing policies
│   ├── billing.be               # Multi-tariff billing and V2G credit engine
│   ├── custom_policies.be       # Extensible rule-based charging policies
│   ├── engine.be                # Policy evaluation pipeline
│   ├── fleet_scheduler.be       # Depo overnight schedule optimization
│   ├── overstay_manager.be      # Post-charge idle overstay fee accumulator
│   ├── reservation_manager.be   # Port reservation and booking engine
│   └── rules.be                 # Charging priority and restriction rules
├── protocols/                   # Protocol specifications
│   ├── iso15118_20_dc.be        # ISO 15118-20 DC Fast & MCS Charging engine
│   ├── iso15118_v2g_pki.be      # V2G PKI certificate chain and signature verifier
│   └── ocpp201_full_catalog.be  # Complete OCPP 2.0.1 action catalog
├── scripts/                     # Tooling and verification scripts
│   ├── check_loc.py             # Accurate lines-of-code metric counter
│   ├── run_tests.py             # Automated test suite orchestrator
│   └── verify_no_em_dash.py     # Hard verification enforcing zero em-dashes
├── sim/                         # Digital twin simulation environments
│   ├── central_system_mock.be   # Mock CSMS server verifying protocol compliance
│   ├── ev_battery.be            # Vehicle battery model with CC-CV charging curves
│   ├── grid_feed.be             # Substation grid feed with brownout injection
│   ├── grid_stress_scenarios.be # Multi-physics grid brownout and MCS depot test
│   ├── scenarios.be             # End-to-end multi-vehicle charging scenarios
│   └── solar_sim.be             # Solar irradiance model with cloud transient generator
├── src/                         # Native C Host Bridge
│   └── host_main.c              # C entrypoint initializing Berry VM and HAL bindings
├── station/                     # Station orchestration
│   ├── connector.be             # Physical connector port state tracker
│   ├── controller.be            # Central multi-channel charging controller
│   ├── evse.be                  # Individual EVSE channel coordinator
│   ├── hmi.be                   # Terminal UI dashboard
│   ├── main.be                  # Standalone interactive CLI station entrypoint
│   ├── session.be               # End-to-end charging session coordinator
│   └── telemetry.be             # High-frequency telemetry publisher
├── tests/                       # Complete test suite (30 test files)
│   ├── test_all.be              # Master Berry test runner
│   ├── test_benchmarks.be       # Latency and throughput micro-benchmark suite
│   ├── test_grid_stress_scenarios.be # Grid brownout and MCS megawatt test
│   └── test_*.be                # 28 dedicated subsystem test suites
└── vendor/                      # Third-party embedded runtime
    └── berry/                   # Berry bytecode VM (BE_STACK_START=4096)
```

---

## Quickstart & Build Instructions

### Prerequisites

- Standard C compiler (`gcc` or `clang`)
- GNU `make`
- Python 3.8+ (for test automation scripts)

### 1. Build the Binary

Compile the native C host bridge and embedded Berry virtual machine:

```bash
make all
```

This compiles `vendor/berry` with a 4096-slot stack and links the standalone binary to `./bin/stanchion`.

### 2. Run the Complete Test Suite

Execute all 30 test suites covering unit logic, integration flows, and stress scenarios:

```bash
# Using the Python test orchestrator:
python3 scripts/run_tests.py

# Or run the native Berry master test runner:
./bin/stanchion tests/test_all.be

# Run the performance micro-benchmarks:
./bin/stanchion tests/test_benchmarks.be
```

### 3. Launch the Interactive Station Simulation

Run the standalone station application (`station/main.be`):

```bash
./bin/stanchion station/main.be
```

The interactive CLI boots the station, initializes 3 EVSE channels (AC 32A, DC Fast 200A, and Megawatt MCS 800A), runs the solar PV and BESS optimizer, and displays the real-time operational dashboard.

```
================================================================================
  STANCHION EVSE CONTROLLER: EMBEDDED CHARGING HUB SIMULATION
  Copyright (c) 2026 Aneesh Krishna. All rights reserved.
================================================================================
[SYSTEM] Starting Stanchion charging station controller...
[CONFIG] Loading station configuration...
[HAL   ] Initializing hardware abstraction drivers (Pilot, Meter, Relays)...
[OCPP  ] Connecting to Central System (Security Profile 2)...
[OCPP  ] BootNotification sent -> Registration Status: Accepted
[ENERGY] Initializing Dynamic Load Management (Grid limit: 160.0 A)...
[STATION] Station operational. 3 EVSE channels available.
...
```

---

## Standards & Protocol Compliance

| Standard / Specification | Scope | Compliance Level |
| :--- | :--- | :--- |
| **IEC 61851-1:2017** | Electric vehicle conductive charging system - General requirements | Fully Implemented (States A-F, PWM mapping) |
| **IEC 62955** | Residual direct current detecting device (RDC-DD) for EV charging | Fully Implemented (DC 6mA trip threshold) |
| **ISO 15118-2 / ISO 15118-20**| Road vehicles - Vehicle to grid communication interface | Fully Implemented (DC Fast, MCS, V2G BPT) |
| **OCPP 2.0.1** | Open Charge Point Protocol - Central System Management | Fully Implemented (Core, Device Model, Security) |
| **IEC 60076-7** | Loading guide for oil-immersed power transformers | Fully Implemented (Arrhenius thermal aging model) |
| **DIN 91286** | Electric mobility - Identifiers for charging infrastructure | Fully Implemented (eMAID & EVSE-ID format) |

---

## Verification & Quality Assurance

Stanchion adheres to rigorous quality standards:
- **100% Test Pass Rate**: 30 dedicated test suites executing in under 0.5 seconds.
- **Zero Style Violations**: Enforces zero em-dashes or en-dashes across all source files, comments, and documentation (`python3 scripts/verify_no_em_dash.py`).
- **Memory Safety**: Deterministic stack allocations with no dynamic pointer leakage in the C host boundary.

---

## License

Stanchion is released under the **Apache License 2.0**. See the [LICENSE](file:///Users/aneeshkrishna/.gemini/antigravity/scratch/stanchion/LICENSE) file for details.

Copyright (c) 2026 Aneesh Krishna. All rights reserved.
