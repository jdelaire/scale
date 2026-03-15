# Xiaomi S400 Packet Decoding

## Retrieving The BLE Key And MAC

This app cannot decode S400 advertisements without two device-specific values:

- the scale MAC address
- the 16-byte BLE encryption key, also called the `bind key`

Recommended workflow:

1. Add the scale to Xiaomi Home using the Xiaomi account you actually intend to keep using.
2. Complete at least one successful measurement in Xiaomi Home.
   This matters because community tooling reports that the S400 key is only reliably available after the scale has been onboarded and used.
3. Run [Xiaomi Cloud Tokens Extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor).
   The upstream README says it retrieves "tokens for all devices connected to Xiaomi cloud and encryption keys for BLE devices".
4. Authenticate with the same Xiaomi account used in Xiaomi Home.
5. Select the same Xiaomi server region used by that account, or let the tool check all regions.
6. Find the `Xiaomi Body Composition Scale S400` entry in the output.
7. Copy:
   - the MAC field into `DEFAULT_SCALE_MAC_ADDRESS`
   - the BLE key / encryption key field into `DEFAULT_BIND_KEY_HEX`

If you prefer Home Assistant, the [XiaomiGateway3](https://github.com/AlexxIT/XiaomiGateway3) cloud integration also documents that it can expose bind keys for BLE devices after authenticating against the same Mi Home account.

Important caveats:

- If you remove the scale from Xiaomi Home and add it again, Xiaomi may rotate the BLE key. Re-extract the values and update `.env`.
- Different tools label the same secret differently: `BLE key`, `bind key`, and `BLE encryption key` all refer to the same value here.
- When scanning with this app, fully quit Xiaomi Home first. Community S400 integrations report that the scale often connects back to Xiaomi Home immediately, which makes the local advertisement window easy to miss.

## Reference Chain

The S400 support in `export2garmin` lives in [`miscale/s400_ble.py`](https://github.com/RobertWojtowicz/export2garmin/blob/master/miscale/s400_ble.py). That script does not decode the packet itself; it delegates to the upstream `xiaomi-ble` parser. The Swift decoder in this app mirrors that behavior.

Relevant upstream files:

- `export2garmin/miscale/s400_ble.py`
- `xiaomi-ble/src/xiaomi_ble/parser.py`
- `xiaomi-ble/tests/test_parser.py`

## Advertisement Transport

- Transport: BLE service data
- Service UUID: `0xFE95` (`0000FE95-0000-1000-8000-00805F9B34FB`)
- Format: Xiaomi MiBeacon V5 encrypted advertisement
- Known S400 device IDs observed in `xiaomi-ble`: `0x30D9`, `0x3BD5`, `0x48CF`

This is important: the S400 data is not exposed as plain manufacturer data in the reference implementation. On iOS the app therefore reads `CBAdvertisementDataServiceDataKey` first and only keeps manufacturer data as debug context.

## MiBeacon Header

MiBeacon layout used here:

1. `frameControl` (`UInt16`, little-endian)
2. `deviceId` (`UInt16`, little-endian)
3. `packetCounter` (`UInt8`)
4. Optional MAC field if frame-control bit 4 is set
5. Optional capability bytes if frame-control bit 5 is set
6. Encrypted payload
7. Three nonce-extension bytes
8. Four-byte MIC tag

For S400 packets, the reference tests show MiBeacon V5 encrypted packets with frame-control `0x5948`, which means:

- version 5
- object present
- encrypted
- registered/bound
- MAC omitted from the frame

Because the MAC may be omitted, the app needs the scale MAC from user settings to build the AES-CCM nonce.

## Decryption

From `xiaomi-ble` MiBeacon v4/v5 logic:

- mode: AES-CCM
- key: 16-byte bind key
- tag length: 4 bytes
- associated data: `0x11`
- nonce: `reverse(mac) + data[2...4] + data[-7...-5]`

Where:

- `reverse(mac)` is the six-byte MAC in little-endian order
- `data[2...4]` are device ID low byte, device ID high byte, packet counter
- `data[-7...-5]` are the three bytes immediately before the MIC

## Measurement Object

After decryption, MiBeacon payload objects are parsed as:

1. object type (`UInt16`, little-endian)
2. object length (`UInt8`)
3. object payload bytes

The S400 measurement object type is `0x6E16`. Its payload is 9 bytes and is unpacked in upstream code as:

```python
profile_id, data, _ = struct.unpack("<BII", xobj)
```

Only the middle `UInt32` is used for measurement fields:

- bits `0...10`: mass raw
- bits `11...17`: heart rate raw
- bits `18...31`: impedance raw

Scaling:

- `weightKg = massRaw / 10`
- `heartRateBpm = heartRateRaw + 50`
- `impedanceOhms = impedanceRaw / 10`

If `massRaw == 0`, the impedance field is treated as low-frequency impedance rather than the main impedance value.

## Timestamp

The reference stack does not extract a timestamp from the S400 advertisement because the `0x6E16` payload does not include one. `export2garmin` timestamps the reading when the packet is received. This app follows the same approach and uses the local receive time as the measurement timestamp.

## Final Measurement Logic

The reference `s400_ble.py` waits until these decoded fields are available before treating a weigh-in as complete:

- `Mass`
- `Impedance`
- `Impedance Low`
- `Heart Rate`

On real S400 hardware, some weigh-ins do not emit a heart-rate value even though the weight and both impedance values arrive correctly. To avoid dropping valid measurements, this app finalizes a session once these required fields are present:

- `Mass`
- `Impedance`
- `Impedance Low`

`Heart Rate` is treated as optional metadata and is stored when present.
