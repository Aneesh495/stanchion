/*
 * Stanchion: Intelligent EV Charging Station Controller & Energy Management System
 * High-performance Native C Embedding Host for Berry Runtime
 *
 * Copyright (c) 2026 Aneesh Krishna
 * Licensed under the Apache License, Version 2.0
 */

#include "stanchion.h"
#include "../vendor/berry/src/berry.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/time.h>
#include <sys/resource.h>

#if defined(__APPLE__)
#include <mach/mach.h>
#endif

/* Monotonic timestamp in microseconds */
uint64_t stanchion_monotonic_us(void)
{
    struct timespec ts;
#if defined(CLOCK_MONOTONIC_RAW)
    clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
#elif defined(CLOCK_MONOTONIC)
    clock_gettime(CLOCK_MONOTONIC, &ts);
#else
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (uint64_t)tv.tv_sec * 1000000ULL + (uint64_t)tv.tv_usec;
#endif
    return (uint64_t)ts.tv_sec * 1000000ULL + (uint64_t)(ts.tv_nsec / 1000);
}

/* Monotonic timestamp in milliseconds */
uint64_t stanchion_monotonic_ms(void)
{
    return stanchion_monotonic_us() / 1000ULL;
}

/* Real-time wallclock in milliseconds since Unix epoch */
uint64_t stanchion_realtime_epoch_ms(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (uint64_t)tv.tv_sec * 1000ULL + (uint64_t)(tv.tv_usec / 1000);
}

/* Resident set size in kilobytes */
static uint64_t get_rss_kb(void)
{
#if defined(__APPLE__)
    struct mach_task_basic_info info;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &count) == KERN_SUCCESS) {
        return (uint64_t)(info.resident_size / 1024);
    }
    return 0;
#else
    struct rusage usage;
    if (getrusage(RUSAGE_SELF, &usage) == 0) {
        return (uint64_t)usage.ru_maxrss;
    }
    return 0;
#endif
}

/* Berry Native Bridge Functions */

static int native_monotonic_us(bvm *vm)
{
    be_pushint(vm, (bint)stanchion_monotonic_us());
    be_return(vm);
}

static int native_monotonic_ms(bvm *vm)
{
    be_pushint(vm, (bint)stanchion_monotonic_ms());
    be_return(vm);
}

static int native_realtime_ms(bvm *vm)
{
    be_pushint(vm, (bint)stanchion_realtime_epoch_ms());
    be_return(vm);
}

static int native_sleep_ms(bvm *vm)
{
    if (be_top(vm) >= 1) {
        int ms = be_toint(vm, 1);
        if (ms > 0) {
            struct timespec req;
            req.tv_sec = ms / 1000;
            req.tv_nsec = (ms % 1000) * 1000000L;
            nanosleep(&req, NULL);
        }
    }
    be_return_nil(vm);
}

static int native_rss_kb(bvm *vm)
{
    be_pushint(vm, (bint)get_rss_kb());
    be_return(vm);
}

static int native_version(bvm *vm)
{
    be_pushstring(vm, STANCHION_VERSION_STRING);
    be_return(vm);
}

void stanchion_register_native_module(bvm *vm)
{
    be_regfunc(vm, "host_monotonic_us", native_monotonic_us);
    be_regfunc(vm, "host_monotonic_ms", native_monotonic_ms);
    be_regfunc(vm, "host_realtime_ms", native_realtime_ms);
    be_regfunc(vm, "host_sleep_ms", native_sleep_ms);
    be_regfunc(vm, "host_rss_kb", native_rss_kb);
    be_regfunc(vm, "host_version", native_version);
}

/* Bootstrap search paths in Berry */
static void setup_import_paths(bvm *vm, const char *base_dir)
{
    const char *paths[] = {
        "lib",
        "core",
        "hal",
        "ocpp",
        "energy",
        "policy",
        "station",
        "diag",
        "sim",
        "tests",
        NULL
    };

    char code[1024];
    for (int i = 0; paths[i] != NULL; ++i) {
        if (base_dir && strlen(base_dir) > 0) {
            snprintf(code, sizeof(code),
                     "import sys; sys.path().push('%s/%s')", base_dir, paths[i]);
        } else {
            snprintf(code, sizeof(code),
                     "import sys; sys.path().push('%s')", paths[i]);
        }
        be_loadbuffer(vm, "path_setup", code, strlen(code));
        be_pcall(vm, 0);
        be_pop(vm, 1);
    }
}

int main(int argc, char **argv)
{
    bvm *vm = be_vm_new();
    if (!vm) {
        fprintf(stderr, "Error: failed to initialize Berry virtual machine\n");
        return 1;
    }

    stanchion_register_native_module(vm);

    /* Setup paths relative to current working directory */
    setup_import_paths(vm, ".");

    int exit_code = 0;

    if (argc > 1) {
        if (strcmp(argv[1], "-e") == 0 && argc > 2) {
            const char *code = argv[2];
            int res = be_loadbuffer(vm, "cmdline", code, strlen(code));
            if (res == BE_OK) {
                res = be_pcall(vm, 0);
                if (res != BE_OK) {
                    fprintf(stderr, "Runtime error in -e expression: %s\n",
                            be_tostring(vm, -1));
                    exit_code = 1;
                }
            } else {
                fprintf(stderr, "Compile error in -e expression: %s\n",
                        be_tostring(vm, -1));
                exit_code = 1;
            }
        } else {
            const char *script_file = argv[1];
            int res = be_loadfile(vm, script_file);
            if (res == BE_OK) {
                res = be_pcall(vm, 0);
                if (res != BE_OK) {
                    fprintf(stderr, "Runtime error in script %s: %s\n",
                            script_file, be_tostring(vm, -1));
                    exit_code = 1;
                }
            } else {
                fprintf(stderr, "Compile error in script %s: %s\n",
                        script_file, be_tostring(vm, -1));
                exit_code = 1;
            }
        }
    } else {
        printf("Stanchion v%s - Intelligent EV Charging Station Controller\n",
               STANCHION_VERSION_STRING);
        printf("Usage: stanchion <script.be> [args...]\n");
        printf("Running default station simulation...\n");

        int res = be_loadfile(vm, "station/main.be");
        if (res == BE_OK) {
            res = be_pcall(vm, 0);
            if (res != BE_OK) {
                fprintf(stderr, "Runtime error in station/main.be: %s\n",
                        be_tostring(vm, -1));
                exit_code = 1;
            }
        } else {
            fprintf(stderr, "Could not open station/main.be: %s\n",
                    be_tostring(vm, -1));
            exit_code = 1;
        }
    }

    be_vm_delete(vm);
    return exit_code;
}
