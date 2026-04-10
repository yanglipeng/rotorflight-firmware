/*
 * This file is part of Rotorflight.
 *
 * Rotorflight is free software. You can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Rotorflight is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this software. If not, see <https://www.gnu.org/licenses/>.
 */

#include "types.h"
#include "platform.h"

#ifdef USE_TELEMETRY

#include "common/unit.h"

#include "pg/pg_ids.h"
#include "pg/telemetry.h"


PG_REGISTER_WITH_RESET_TEMPLATE(telemetryConfig_t, telemetryConfig, PG_TELEMETRY_CONFIG, 6);

PG_RESET_TEMPLATE(telemetryConfig_t, telemetryConfig,
    .telemetry_inverted = false,
    .halfDuplex = 1,
    .pinSwap = 0,
    .gpsNoFixLatitude = 0,
    .gpsNoFixLongitude = 0,
    .frsky_coordinate_format = FRSKY_FORMAT_DMS,
    .frsky_unit = UNIT_METRIC,
    .frsky_vfas_precision = 0,
    .hottAlarmSoundInterval = 5,
    .report_cell_voltage = true,
    .flysky_sensors = {
        IBUS_SENSOR_TYPE_TEMPERATURE,
        IBUS_SENSOR_TYPE_RPM_FLYSKY,
        IBUS_SENSOR_TYPE_EXTERNAL_VOLTAGE
    },
    .mavlink_mah_as_heading_divisor = 0,
    .crsf_telemetry_mode = CRSF_TELEMETRY_MODE_NATIVE,
    .crsf_telemetry_link_rate = 250,
    .crsf_telemetry_link_ratio = 8,
    .telemetry_sensors = {
        TELEM_BATTERY_VOLTAGE,
        TELEM_BATTERY_CURRENT,
        TELEM_BATTERY_CONSUMPTION,
        TELEM_ESC_TEMP,
        TELEM_MOTOR_TEMP,
        TELEM_RPM,
        TELEM_FLIGHT_MODE,
        TELEM_ARMING_FLAGS,
#ifdef USE_GPS
        TELEM_GPS,
        TELEM_GPS_SATS,
        TELEM_GPS_HOME_DISTANCE,
        TELEM_GPS_HOME_DIRECTION,
#endif
        0, 0, 0, 0
    },
    .telemetry_interval = {
        100,
        100,
        1000,
        500,
        500,
        100,
        250,
        500,
#ifdef USE_GPS
        200,
        1000,
        500,
        1000,
#endif
        0, 0, 0, 0
    },
);

#endif
