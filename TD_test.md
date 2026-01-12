## 1) Network prerequisites

- TD machine can `telnet <RCS_IP> 6700` ✅
- RCS2 expects **CR (`\r`)** terminator (not `\n`)
- Recorder should already be in the right workspace/metadata state **before** you start recording (you already discovered this).

---

## 2) In TouchDesigner: create the TCP client

1. Add **TCP/IP DAT**
2. Set:

   - **Mode**: `Client`
   - **Network Address**: `<RCS_PC_IP>` (e.g., `192.168.50.209`)
   - **Port**: `6700`
   - **Active**: `On`

3. Rename the DAT to: `rcs_tcp`

This DAT will both **send** commands and **receive** replies.

---

## 3) Make sure TD sends the correct terminator (CR)

In Python, when sending commands, append `\r`:

- Marker format (from your working logs):

  - `AN:<label>;<type>\r`
  - Example: `AN:improv;Comment\r`

---

## 4) Add a Text DAT with Python functions

Create a **Text DAT** named `rcs_ctrl` and paste this:

```python
# rcs_ctrl (Text DAT)

import time

TCP = 'rcs_tcp'  # name of your TCP/IP DAT

def _d():
    return op(TCP)

def _clear():
    _d().clear()

def _send(cmd):
    # RCS2 requires CR terminator
    _d().send(cmd + '\r')

def _lines(timeout=0.3):
    # Collect any received lines for timeout seconds
    t0 = time.time()
    buf = ''
    while time.time() - t0 < timeout:
        txt = _d().text or ''
        if txt != buf:
            buf = txt
        time.sleep(0.01)
    # split on CR, strip LF just in case
    raw = buf.replace('\n', '')
    return [l.strip() for l in raw.split('\r') if l.strip()]

def is_recording():
    """Return True if RS:4 (recording/saving)"""
    _clear()
    _send('RS')
    ls = _lines(0.4)
    for l in ls:
        if l.startswith('RS:'):
            try:
                return int(l.split(':',1)[1]) == 4
            except:
                return False
    return False

def marker(label, kind='Comment'):
    """Send marker AN:<label>;<kind> only if recording."""
    if not is_recording():
        print('Not recording (need RS:4). Marker NOT sent.')
        return False

    _clear()
    _send(f'AN:{label};{kind}')
    ls = _lines(0.6)
    ok = any(l.startswith('AN:') and l.endswith(':OK') for l in ls)
    print('Marker reply:', ls)
    return ok
```

Now TD has:

- `op('rcs_ctrl').module.marker("improv")`

---

## 5) Trigger markers from TD events (recommended patterns)

### Option A — Button COMP

1. Drop a **Button COMP**
2. On its **Callbacks DAT** (created automatically), add:

```python
def onOffToOn(panelValue):
    op('rcs_ctrl').module.marker('improv', 'Comment')
    return
```

Do the same for other buttons (e.g., `fixed`, `StimOnset`, etc.)

---

### Option B — Keyboard In DAT (hotkeys)

1. Add a **Keyboard In DAT**
2. Add a DAT Execute DAT watching it
3. On key press:

```python
def onTableChange(dat):
    # last row often holds the latest key event; depends on your setup
    key = dat[1,'key']  # adjust indexing if needed
    if key == 'i':
        op('rcs_ctrl').module.marker('improv')
    elif key == 'f':
        op('rcs_ctrl').module.marker('fixed')
    return
```

---

### Option C — Timeline / CHOP events

If you have a CHOP that goes 0→1 at stimulus onset:

1. Add a **CHOP Execute DAT**
2. In `onOffToOn`:

```python
def onOffToOn(channel, sampleIndex, val, prev):
    op('rcs_ctrl').module.marker('StimOnset', 'Comment')
    return
```

---

## 6) Best practice: don’t query RS every single time (optional improvement)

If you’re sending markers at high rate, polling `RS` each time adds overhead.

Better:

- Maintain a global `isRecording` flag updated every ~0.5s by a Timer CHOP or script
- Only send markers when `isRecording == True`

If you want, I can give you a lightweight “state watcher” that updates a DAT/CHOP with RS/AQ/AP.

---

## 7) Quick end-to-end test in TD Textport

Open Textport and run:

```python
op('rcs_ctrl').module.is_recording()
op('rcs_ctrl').module.marker('test_marker')
```

If recording is running you should see `AN:test_marker;Comment:OK` in replies.

---
