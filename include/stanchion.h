/*
 * Stanchion: Intelligent EV Charging Station Controller & Energy Management System
 * Native Host Interface & Berry C Extension Bridge
 *
 * Copyright (c) 2026 Aneesh Krishna
 * Licensed under the Apache License, Version 2.0
 */

#ifndef STANCHION_H
#define STANCHION_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Version descriptors */
#define STANCHION_VERSION_MAJOR 1
#define STANCHION_VERSION_MINOR 0
#define STANCHION_VERSION_PATCH 0
#define STANCHION_VERSION_STRING "1.0.0"

/* Forward declaration of Berry VM */
struct bvm;
typedef struct bvm bvm;

/* High-precision timing primitives */
uint64_t stanchion_monotonic_us(void);
uint64_t stanchion_monotonic_ms(void);
uint64_t stanchion_realtime_epoch_ms(void);

/* Native C module registration for Berry */
void stanchion_register_native_module(bvm *vm);

#ifdef __cplusplus
}
#endif

#endif /* STANCHION_H */
