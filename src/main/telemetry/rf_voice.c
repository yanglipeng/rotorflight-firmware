/*
 * Rotorflight Voice Telemetry
 * State change notifications for voice announcements
 */

#include "telemetry/rf_voice.h"

#include "fc/runtime_config.h"
#include "flight/failsafe.h"
#include "flight/mixer.h"
#include "sensors/battery.h"

static rf_voice_event_t currentEvent = RF_VOICE_DISARMED;
static bool eventPending = false;
static uint8_t lastArmingState = 0;
static uint8_t lastFlightMode = 0;
static uint8_t lastFailsafePhase = 0;
static uint8_t lastGovState = 0;

void rfVoiceInit(void)
{
    currentEvent = RF_VOICE_DISARMED;
    eventPending = false;
    lastArmingState = 0;
    lastFlightMode = 0;
    lastFailsafePhase = 0;
    lastGovState = 0;
}

void rfVoiceUpdate(timeUs_t currentTimeUs)
{
    uint8_t newArmingState = ARMING_FLAG(ARMED) ? 1 : 0;
    uint8_t newFlightMode = 0;
    uint8_t newFailsafePhase = failsafePhase();
    uint8_t newGovState = 0;

    if (FLIGHT_MODE(FAILSAFE_MODE)) {
        newFlightMode = 1;
    } else if (FLIGHT_MODE(GPS_RESCUE_MODE)) {
        newFlightMode = 2;
    } else if (FLIGHT_MODE(RESCUE_MODE)) {
        newFlightMode = 3;
    } else if (FLIGHT_MODE(HORIZON_MODE)) {
        newFlightMode = 4;
    } else if (FLIGHT_MODE(ANGLE_MODE)) {
        newFlightMode = 5;
    } else if (FLIGHT_MODE(ALTHOLD_MODE)) {
        newFlightMode = 6;
    }

#ifdef USE_GOVERNOR
    newGovState = getGovernorState();
#endif

    if (newArmingState != lastArmingState) {
        if (newArmingState && !isArmingDisabled()) {
            rfVoicePlayEvent(RF_VOICE_ARMED);
        } else if (!newArmingState && lastArmingState) {
            rfVoicePlayEvent(RF_VOICE_DISARMED);
        }
        lastArmingState = newArmingState;
    }

    if (newFlightMode != lastFlightMode) {
        switch (newFlightMode) {
            case 1:
                rfVoicePlayEvent(RF_VOICE_FAILSAFE);
                break;
            case 2:
                rfVoicePlayEvent(RF_VOICE_RESCUE);
                break;
            case 3:
                rfVoicePlayEvent(RF_VOICE_RESCUE);
                break;
            case 4:
                rfVoicePlayEvent(RF_VOICE_HORIZON);
                break;
            case 5:
                rfVoicePlayEvent(RF_VOICE_ANGLE);
                break;
            case 6:
                rfVoicePlayEvent(RF_VOICE_ALTHOLD);
                break;
            default:
                break;
        }
        lastFlightMode = newFlightMode;
    }

    if (newFailsafePhase != lastFailsafePhase) {
        switch (newFailsafePhase) {
            case FAILSAFE_LANDING:
                rfVoicePlayEvent(RF_VOICE_LANDING);
                break;
            case FAILSAFE_LANDED:
                rfVoicePlayEvent(RF_VOICE_LANDED);
                break;
            default:
                break;
        }
        lastFailsafePhase = newFailsafePhase;
    }

#ifdef USE_GOVERNOR
    if (newGovState != lastGovState) {
        if (newGovState > 0 && lastGovState == 0) {
            rfVoicePlayEvent(RF_VOICE_GOV_ON);
        } else if (newGovState == 0 && lastGovState > 0) {
            rfVoicePlayEvent(RF_VOICE_GOV_OFF);
        }
        lastGovState = newGovState;
    }
#endif

    if (!ARMING_FLAG(ARMED)) {
        uint8_t batteryCellCount = batteryCellCount();
        if (batteryCellCount > 0) {
            if (telemetrySensorValue(TELEM_BATTERY_CELL_VOLTAGE) < 350) {
                rfVoicePlayEvent(RF_VOICE_CELL_CRIT);
            } else if (telemetrySensorValue(TELEM_BATTERY_CELL_VOLTAGE) < 370) {
                rfVoicePlayEvent(RF_VOICE_CELL_LOW);
            }
        }
    }
}

bool rfVoiceHasEvent(void)
{
    return eventPending;
}

rf_voice_event_e rfVoiceGetEvent(void)
{
    return currentEvent;
}

void rfVoiceClearEvent(void)
{
    eventPending = false;
}

void rfVoicePlayEvent(rf_voice_event_e event)
{
    if (!eventPending) {
        currentEvent = event;
        eventPending = true;
    }
}