/*
 * Rotorflight Voice Telemetry
 * State change notifications for voice announcements
 */

#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "common/time.h"

#define RF_VOICE_FRAME_ID 0x50

typedef enum {
    RF_VOICE_DISARMED = 0,
    RF_VOICE_ARMED = 1,
    RF_VOICE_ARM_FAILED = 2,
    RF_VOICE_ANGLE = 3,
    RF_VOICE_HORIZON = 4,
    RF_VOICE_ACRO = 5,
    RF_VOICE_ALTHOLD = 6,
    RF_VOICE_FAILSAFE = 7,
    RF_VOICE_LANDING = 8,
    RF_VOICE_LANDED = 9,
    RF_VOICE_RESCUE = 10,
    RF_VOICE_RTH = 11,
    RF_VOICE_HOME = 12,
    RF_VOICE_GOV_ON = 13,
    RF_VOICE_GOV_OFF = 14,
    RF_VOICE_AUTO = 15,
    RF_VOICE_BAILOUT = 16,
    RF_VOICE_SIG_LOST = 17,
    RF_VOICE_SIG_OK = 18,
    RF_VOICE_TELEM_LOST = 19,
    RF_VOICE_TELEM_OK = 20,
    RF_VOICE_CELL_LOW = 21,
    RF_VOICE_CELL_CRIT = 22,
    RF_VOICE_ESC_HOT = 23,
    RF_VOICE_SIG_WEAK = 24,
    RF_VOICE_SIG_CRIT = 25,
    RF_VOICE_FLIGHT_DONE = 26,
    RF_VOICE_GPS_FIX = 27,
    RF_VOICE_GPS_NOFIX = 28
} rf_voice_event_e;

void rfVoiceInit(void);
void rfVoiceUpdate(timeUs_t currentTimeUs);
bool rfVoiceHasEvent(void);
rf_voice_event_e rfVoiceGetEvent(void);
void rfVoiceClearEvent(void);
void rfVoicePlayEvent(rf_voice_event_e event);