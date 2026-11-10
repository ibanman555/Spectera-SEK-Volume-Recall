# Spectera SEK Individual Volume Presets

**Shareable kit — version 1.0 | November 2026**

A Windows utility to **save and recall a different headphone volume for every paired Sennheiser Spectera SEK beltpack** on **one base station**. Trigger SAVE and RECALL directly with the **Elgato Stream Deck System → Open** action, or use **Stream Deck MidiFire → Bome MIDI Translator Pro** if you prefer MIDI-triggered automation. **No Companion or SoundBase is required.**

This is an independent community utility, **not an official Sennheiser product**. It uses Sennheiser's documented SSCv2 API. Verify compatibility on your own firmware before show use. No Sennheiser code or logos are included.

## What it does

- Read every **paired** SEK entry from the base station (including disconnected and powered-off devices).
- Export each SEK's unique `mtUid`, name, serial number and stored headphone volume to a **CSV**.
- **Save** the current base-station-stored volume settings for all paired SEKs with one button, backing up the previous CSV.
- Assign each SEK an **individual** desired headphone volume in dB in that CSV.
- Preview current versus desired values without changing anything.
- Apply only changed values through `PUT /api/mts/paired/all/{mtUid}`, and read back each changed value.
- Write an operation log in the `Logs` folder.
- Include **all currently paired SEK records** rather than assuming a fixed quantity (works with 16, 22 or another supported number).

It does **not** alter routing, RF channels, microphone gain, output mix levels, min/max headphone limits, or any DiGiCo console setting. When an SEK connects later, confirm on your firmware that its stored setting is applied as expected. The API documentation distinguishes *paired* devices from *currently connected* devices.

## Requirements

- Windows 10/11 with **Windows PowerShell 5.1** and `curl.exe` available.
- A Spectera base station on a network accessible from the Windows computer, with a **WebUI password already configured**.
- A Windows account that can run local scripts.
- **Choose either trigger option:** Elgato Stream Deck **System → Open** (no Bome or MidiFire needed), **or** the Stream Deck MidiFire plugin and Bome MIDI Translator Pro. The PowerShell script can also be run directly without Stream Deck.
- A trusted, private control network. The example commands below use `-TrustLocalCertificate`, which disables the certificate-verification check for the local HTTPS connection.

## Files included in this ZIP

| File | Purpose |
|---|---|
| `SEK-Volumes.ps1` | Main API script: Setup, List, Export, **Save**, Preview, Apply |
| `Recall-SEK-Volumes.vbs` | Hidden RECALL launcher for Stream Deck **System → Open** or Bome's Execute File action |
| `Save-SEK-Volumes.vbs` | Hidden SAVE launcher for Stream Deck **System → Open** or Bome's Execute File action |
| `CSV-EXAMPLE-DO-NOT-USE.csv` | Fake identifiers only, for format reference |
| `QUICK-START.txt` | Short setup and Bome/MidiFire instructions |
| `README.md` | Detailed guide |
| `LICENSE.txt` | MIT redistribution license |

**Never distribute** your generated `spectera-password.dat`, `spectera-base-ip.txt`, `sek-volume-presets.csv`, or any files in `Logs` or `PresetBackups`. The distributed ZIP contains none of these.

## 1. Install

Extract the files directly into `C:\Spectera` (not a nested folder):

```text
C:\Spectera\SEK-Volumes.ps1
C:\Spectera\Recall-SEK-Volumes.vbs
C:\Spectera\Save-SEK-Volumes.vbs
C:\Spectera\CSV-EXAMPLE-DO-NOT-USE.csv
C:\Spectera\README.md
C:\Spectera\QUICK-START.txt
```

If you choose another folder, browse to the actual `.vbs` file in Stream Deck or adjust Bome's **Parameters** path in section 7. The hidden launchers resolve `SEK-Volumes.ps1` relative to their own location.

## 2. One-time Setup: enter your base-station IP and password

Open **Windows PowerShell** under the same Windows account that will run Stream Deck or Bome. Paste:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Spectera\SEK-Volumes.ps1" -Mode Setup
```

The script asks for your base-station **IPv4 address** and then your Spectera **WebUI password**. It creates two **local-only** files:

- `spectera-base-ip.txt`: Your base-station address.
- `spectera-password.dat`: Windows DPAPI-encrypted password tied to that Windows user/computer.

Do not share these files. Run Setup again if you change the IP/password. You can also override the saved IP for a visible test with `-BaseIP 192.168.1.100`; one script instance addresses **one** base station.

## 3. Read-only connection test

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Spectera\SEK-Volumes.ps1" -Mode List -TrustLocalCertificate
```

Expect a table of **all paired SEK entries**, including disconnected ones. If it fails, first check connection, TCP port 443, credentials, and firmware/API support. A separate read-only test is:

```powershell
Test-NetConnection YOUR_BASE_STATION_IP -Port 443
curl.exe -k --http1.1 --noproxy "*" -u controlSennheiser "https://YOUR_BASE_STATION_IP/api/mts/paired/all"
```

For the `curl.exe` test, enter your password interactively. **Never** put your password directly in a shell command or public screenshot.

## 4. Export the actual paired packs to CSV (read-only)

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Spectera\SEK-Volumes.ps1" -Mode Export -TrustLocalCertificate
```

Creates `C:\Spectera\sek-volume-presets.csv` from *your own hardware*. Export **refuses to overwrite** an existing CSV, to protect previous presets. If you intentionally want a fresh export, first back up and rename your existing CSV.

Example of the format (these IDs are **fake**):

```csv
mtUid,Name,Serial,VolumeDb
100000001,EXAMPLE SEK A,DEMO-SERIAL-A,-35.0
100000002,EXAMPLE SEK B,DEMO-SERIAL-B,-40.0
```

## 4a. One-button SAVE of current stored headphone volumes

Unlike `Export` (which will not overwrite an existing CSV), `Save` replaces the CSV with the **current headphone-volume settings stored by the Spectera base station** for every paired SEK, including powered-off packs. It first backs up the previous CSV in `C:\Spectera\PresetBackups\`. No volumes are changed on the base station.

Test the SAVE function visibly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Spectera\SEK-Volumes.ps1" -Mode Save -TrustLocalCertificate
```

For users choosing **Stream Deck MidiFire → Bome**, use a *different* MIDI Note/CC message and a second Bome translator for SAVE. Set its **Outgoing → Execute File** to:

**File to Execute**
```text
C:\Windows\System32\wscript.exe
```

**Parameters**
```text
//B //Nologo "C:\Spectera\Save-SEK-Volumes.vbs"
```

The hidden SAVE operation writes a dated log to `C:\Spectera\Logs\`. Your existing RECALL button continues using `Recall-SEK-Volumes.vbs`.

**SAVE overwrites any individually edited target values in the current CSV.** The timestamped backup preserves your last preset. It captures settings stored on the base station, not pack-local adjustments that have not synced back to it. If you want to save adjustments made on a beltpack, first ensure WebUI shows the new stored headphone volume.

## 5. Edit your desired volume values

Open `C:\Spectera\sek-volume-presets.csv` in Notepad or Excel. **Change only `VolumeDb`** for each pack. Keep the `mtUid` column exactly as exported, and **keep every row for every paired SEK**. Save the file in CSV format, not XLSX. The script matches packs by `mtUid`, NOT names, serial numbers, or list order.

Volume values are in dB and need to be in **0.5 dB increments**. The script validates each target against the pack's actual configured headphone minimum and maximum returned by the base station.

If you add, replace, unpair, or re-pair a pack, **re-export a fresh CSV**, then review/edit the new list. A paired-device mismatch stops the script rather than silently skipping devices.

## 6. Preview and test a single change, then apply

First **preview** (read-only):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Spectera\SEK-Volumes.ps1" -Mode Preview -TrustLocalCertificate
```

Check the `StoredDb` and `TargetDb` values. For the first write test, leave all exported target values unchanged **except one SEK**; choose a **lower, safe** volume, and make sure earphones are **not in anyone's ears**. Then run **Apply** visibly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Spectera\SEK-Volumes.ps1" -Mode Apply -TrustLocalCertificate
```

Only different values are written. The script reads back the stored volume after each change and saves a dated log under `C:\Spectera\Logs\`. Confirm the result in WebUI, and check an offline SEK's volume after it connects. Then edit the complete CSV to all desired levels, run Preview again, and run Apply. Use caution with any change that **increases** headphone levels.

## 7. Stream Deck button options: native launch OR MidiFire/Bome

### Option A — Native Stream Deck System → Open (simplest)

**No Bome, MidiFire, or Companion is required for this option.** The provided Windows `.vbs` launchers run the corresponding PowerShell operation hidden, under the current Windows user account.

1. Complete **Setup**, **List**, **Export**, **Preview**, and the first visible one-pack **Apply** test in sections 2–6.
2. In **Elgato Stream Deck** on Windows, select an unused button.
3. Drag **System → Open** onto the button.
4. Set **App / File** to:
   ```text
   C:\Spectera\Recall-SEK-Volumes.vbs
   ```
5. Title the button **RECALL SEK VOLUMES**.
6. Optionally configure another **System → Open** button pointing to:
   ```text
   C:\Spectera\Save-SEK-Volumes.vbs
   ```
   Title it **SAVE SEK VOLUMES**. SAVE captures the volumes **stored at the base station** and backs up the previous CSV; it does **not** change pack volumes.

Before relying on Stream Deck, double-click the respective `.vbs` in File Explorer to verify Windows Script Host launches it, then check `C:\Spectera\Logs\`. Verify the same Windows account is used for credential Setup and Stream Deck. There is **no on-button success/error feedback** from the hidden launcher; review the log if an action appears not to work. If `.vbs` file associations are restricted by Windows policy, use the MIDI/Bome method below or run the PowerShell command visibly for troubleshooting.

### Option B — Stream Deck MIDIFire → Bome MIDI Translator Pro

Use this if you already route other show controls through Bome, or need MIDI-based triggering. **This is an alternative to Option A, not an additional requirement.**

**Download MIDIFire (Windows):** [MIDIFire — latest GitHub release](https://github.com/ibanman555/MIDIFire/releases/latest) · [source code and installation guide](https://github.com/ibanman555/MIDIFire). MIDIFire is a free, open-source Windows Stream Deck MIDI plugin distributed through GitHub rather than the Elgato Marketplace. Under the latest release's **Assets**, download `com.koop.streamdeck-midi.streamDeckPlugin` (not GitHub's source-code ZIP), then double-click it to install through Stream Deck. In the Stream Deck software, add **MIDIFire → Fire MIDI** to a key and select the MIDI output that Bome receives. See the MIDIFire repository for system requirements and plugin setup. The plugin is optional; **Option A needs neither MIDIFire nor Bome**.

There is **no universal MIDIFire profile included**, because each user's MIDI port, MIDI message and Stream Deck configuration can differ. Use any unused Note On or CC message you can identify inside Bome.

**Illustrative MIDI trigger:** MIDI Note On, channel 16, note 110, velocity 127. Avoid conflicts with other existing Bome translators or rig controls. Configure your Stream Deck **MIDIFire** button to send this MIDI message over a port that Bome can receive (for example a virtual MIDI port supported by your setup).

In **Bome MIDI Translator Pro**:

1. Enable the MIDI input port that receives the MidiFire message.
2. Create a preset such as `Spectera SEK Volume Recall`.
3. Create a translator with **Incoming = the same MIDI Note On** you sent from MidiFire. Avoid triggering on Note Off/release.
4. Set **Outgoing** to `Execute File` with:

   **File to Execute**

   ```text
   C:\Windows\System32\wscript.exe
   ```

   **Parameters**

   ```text
   //B //Nologo "C:\Spectera\Recall-SEK-Volumes.vbs"
   ```

5. Save your Bome project. Press the Stream Deck button once to invoke the saved per-SEK volumes.
6. Inspect the newest log in `C:\Spectera\Logs\` to confirm the result. The operation is silent and short-lived; it does not run as a persistent service.

**Debugging:** If the Bome trigger isn't received, use Bome's MIDI input monitor to confirm the message/port. If the button launches but the script fails, run the **visible** `-Mode Apply` command from section 6 to see the error. Do not troubleshoot with a hidden process.

## Important security and operational notes

- `-TrustLocalCertificate` uses curl's `insecure` setting and skips the base station's server certificate verification. Only use it on a trusted LAN. To enable verification, provision/trust the base station's certificate and omit the switch in both direct commands and the `.vbs` launcher.
- Authentication uses HTTP Basic **inside HTTPS** to Sennheiser's documented user `controlSennheiser`. The password is protected at rest using DPAPI on the local Windows user account. The runtime sends a Basic Authorization header to `curl.exe` through redirected stdin, **not via the process command line**. The password is briefly materialized in process memory.
- The script uses Sennheiser's `/api/ssc/usagemark` convention to coordinate API writes. This is **advisory**, not a lock. Avoid simultaneous configuration writes in WebUI, LinkDesk or SoundBase during Apply.
- Only API reads are used by `List`, `Export`, and `Preview`. `Apply` updates the stored `headphoneVolume` property, and temporarily writes/releases the usage marker. The script does not intentionally update other SEK properties.
- `-Mode Apply` validates that the CSV includes exactly the current paired SEK IDs. Offline devices can have stored settings updated, but test your firmware's sync behavior before relying on show-day recall.
- `-Mode Setup` will replace the locally saved base-station IP and password. It won't change volumes.
- Keep backups of your private CSV, and do not share logs, real pack serial numbers, base-station network details or credentials without your organization's approval.
- The `.vbs` silent launchers run as the active Windows user, whether started by **Stream Deck System → Open** or **Bome**; they will **not** work with a DPAPI credential saved under a different Windows user.

## API documentation

- https://docs.cloud.sennheiser.com/en-us/api-docs/spectera/usage.html
- https://docs.cloud.sennheiser.com/en-us/api-docs/spectera/open-api-specification-18-3.html

## Notes about testing

This shareable release uses the **all-paired-packs API logic** that was confirmed working in its original environment. **The new interactive setup/IP-file handling is a packaging change and has not been tested on every Windows/Spectera firmware combination**. Users must run List → Export → Preview → one-pack Apply and verify settings on their own rig before relying on it.