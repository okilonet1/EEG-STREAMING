function bv_gsrcs2_terminal()
% RCS2_TERMINAL  Interactive MATLAB "terminal" for BrainVision Recorder via RCS2.
%
% What it does:
%   - Connects to RCS2 over TCP.
%   - Gives you a REPL prompt (like a terminal).
%   - Aliases map to canonical RCS commands (CR-terminated).
%   - If you type a valid raw RCS command (e.g., AP, RS, AN:..., 1:..., etc.),
%     it sends it directly.
%   - Prints responses from RCS, then prompts again.
%
% IMPORTANT:
%   - RCS2 commands are ASCII terminated by CR '\r' (0x0D), NOT '\n'.
%
% Aliases:
%   o | open                  -> O
%   mon | monitor | m         -> M
%   s | start | rec           -> S
%   stop | end | q            -> Q
%   marker:improv | m:improv  -> AN:improv;Comment (default type=Comment)
%   marker:fixed;Stimulus     -> AN:fixed;Stimulus
%   getstate | state | gs     -> query AP, AQ, RS and print readable text
%   x | exit | quit           -> close and exit
%
% Metadata helpers (optional):
%   ws:<path>                 -> 1:<path>
%   exp:<n>                   -> 2:<n>
%   subj:<id>                 -> 3:<id>
%   sa:<name>                 -> SA:<name>
%   sn:<serial>               -> SN:<serial>
%
% Raw passthrough:
%   - If your input looks like a valid RCS command, it will be sent as-is.
%   - To force-send anything, use: raw:<cmd>
%
% Example:
%   rcs2_terminal
%   rcs> open
%   rcs> ws:C:\Vision\Workfiles\aCH160.rwksp
%   rcs> exp:1
%   rcs> subj:Jacob
%   rcs> sn:0599
%   rcs> m
%   rcs> start
%   rcs> m:improv
%   rcs> state
%   rcs> stop
%   rcs> x

clc;

%% ========= CONFIG (EDIT THESE) =========
RCS_IP   = "192.168.50.216";
RCS_PORT = 6700;

fprintf("Connecting to RCS2 at %s:%d ...\n", RCS_IP, RCS_PORT);

rcs = tcpclient(RCS_IP, RCS_PORT, "Timeout", 3);
configureTerminator(rcs, "CR");   % RCS uses '\r'

% Drain any greeting lines (e.g., RS:1)
drainPrint(rcs, 0.7, "INIT");

fprintf("\nRCS2 terminal ready. Type 'help' for commands.\n\n");

while true
    cmd = input("rcs> ", "s");
    cmd = strtrim(cmd);
    if cmd == ""
        continue
    end

    % ----- help -----
    if any(strcmpi(cmd, ["help","h","?"]))
        printHelp();
        continue
    end

    % ----- exit -----
    if any(strcmpi(cmd, ["x","exit","quit"]))
        fprintf("Closing connection...\n");
        try, clear rcs; end %#ok<TRYNC>
        break
    end

    % ----- getstate -----
    if any(strcmpi(cmd, ["getstate","state","gs"]))
        prettyState(rcs);
        continue
    end

    % ----- OPEN -----
    if any(strcmpi(cmd, ["o","open"]))
        send(rcs, "O");
        drainPrint(rcs, 1.0, "OPEN");
        continue
    end

    % ----- MONITOR -----
    if any(strcmpi(cmd, ["mon","monitor","m"]))
        send(rcs, "M");
        drainPrint(rcs, 1.5, "MON");
        continue
    end

    % ----- START RECORD -----
    if any(strcmpi(cmd, ["s","start","rec","record"]))
        send(rcs, "S");
        drainPrint(rcs, 1.5, "START");
        continue
    end

    % ----- STOP RECORD -----
    if any(strcmpi(cmd, ["stop","end","q"]))
        send(rcs, "Q");
        drainPrint(rcs, 1.5, "STOP");
        continue
    end

    % ----- MARKER shortcuts: "marker:xxx" or "m:xxx" -----
    if startsWith(lower(cmd), "marker:") || startsWith(lower(cmd), "m:")
        payload = regexprep(cmd, '^(marker:|m:)\s*', '', 'ignorecase');
        payload = strtrim(payload);

        % Support "improv" (default type Comment) OR "improv;Comment"
        label = payload;
        mtype = "Comment";
        if contains(payload, ";")
            parts = split(payload, ";");
            label = strtrim(parts(1));
            mtype = strtrim(parts(2));
        end

        send(rcs, "AN:" + label + ";" + mtype);
        drainPrint(rcs, 1.2, "MARK");
        continue
    end

    % ----- convenience metadata setters -----
    if startsWith(lower(cmd), "ws:")
        send(rcs, "1:" + string(extractAfter(cmd, 3)));
        drainPrint(rcs, 2.0, "WS");
        continue
    end

    if startsWith(lower(cmd), "exp:")
        send(rcs, "2:" + string(extractAfter(cmd, 4)));
        drainPrint(rcs, 1.2, "EXP");
        continue
    end

    if startsWith(lower(cmd), "subj:")
        send(rcs, "3:" + string(extractAfter(cmd, 5)));
        drainPrint(rcs, 1.2, "SUBJ");
        continue
    end

    if startsWith(lower(cmd), "sn:")
        send(rcs, "SN:" + string(extractAfter(cmd, 3)));
        drainPrint(rcs, 1.2, "SN");
        continue
    end

    if startsWith(lower(cmd), "sa:")
        send(rcs, "SA:" + string(extractAfter(cmd, 3)));
        drainPrint(rcs, 1.2, "SA");
        continue
    end

    % ----- raw forced passthrough -----
    if startsWith(lower(cmd), "raw:")
        rawCmd = strtrim(string(extractAfter(cmd, 4)));
        send(rcs, rawCmd);
        drainPrint(rcs, 1.5, "RAW");
        continue
    end

    % ----- raw passthrough (safe): send if it looks like an RCS command -----
    if isValidRCSCommand(cmd)
        send(rcs, cmd);
        drainPrint(rcs, 1.5, "RCS");
    else
        fprintf("Unrecognized alias or invalid RCS command.\n");
        fprintf("Type 'help' for aliases, or use raw:<cmd> to force-send.\n");
    end
end

end

%% ===================== helpers =====================
function send(rcs, cmd)
% Send cmd terminated by CR (NOT LF)
cmd = string(cmd);
write(rcs, uint8([char(cmd) 13]), "uint8"); % 13 = '\r'
fprintf("[SENT] %s\\r\n", cmd);
end

function drainPrint(rcs, maxSec, tag)
% Drain and print all CR-terminated lines for up to maxSec seconds
t0 = tic;
printed = false;
while toc(t0) < maxSec
    if rcs.NumBytesAvailable > 0
        try
            line = strtrim(string(readline(rcs)));
            if line ~= ""
                fprintf("  [%s] %s\n", tag, line);
                printed = true;
            end
        catch
            % waiting for terminator
        end
    else
        pause(0.02);
    end
end
if ~printed
    fprintf("  [%s] (no reply lines)\n", tag);
end
end

function prettyState(rcs)
% Query AP, AQ, RS and print human-readable meaning
apLine = queryFor(rcs, "AP", 1.0);
aqLine = queryFor(rcs, "AQ", 1.0);
rsLine = queryFor(rcs, "RS", 1.0);

[apStr, aqStr, rsStr] = decodeStates(apLine, aqLine, rsLine);

fprintf("\n=========== STATE ===========\n");
fprintf("App (AP): %s\n", apStr);
fprintf("Acq (AQ): %s\n", aqStr);
fprintf("Rec (RS): %s\n", rsStr);
fprintf("Raw: AP='%s'  AQ='%s'  RS='%s'\n", apLine, aqLine, rsLine);
fprintf("=============================\n\n");
end

function line = queryFor(rcs, cmd, timeoutSec)
% Send cmd and return first matching "<cmd>:<val>" line (or empty).
send(rcs, cmd);

t0 = tic;
line = "";
while toc(t0) < timeoutSec
    if rcs.NumBytesAvailable > 0
        try
            ln = strtrim(string(readline(rcs)));
            fprintf("  [STATE] %s\n", ln);
            if startsWith(ln, cmd + ":")
                line = ln;
                return
            end
        catch
        end
    else
        pause(0.02);
    end
end
end

function [apStr, aqStr, rsStr] = decodeStates(apLine, aqLine, rsLine)
apVal = parseVal(apLine);
aqVal = parseVal(aqLine);
rsVal = parseVal(rsLine);

% AP: application state
if isempty(apVal)
    apStr = "Unknown (no AP reply)";
elseif apVal == 1
    apStr = "Recorder open / running";
elseif apVal == 0
    apStr = "Recorder closed / not running";
elseif apVal < 0
    apStr = sprintf("Recorder error / failed to open (AP:%d)", apVal);
else
    apStr = sprintf("Unknown AP:%d", apVal);
end

% AQ: acquisition
if isempty(aqVal)
    aqStr = "Unknown (no AQ reply)";
elseif aqVal == 1
    aqStr = "Acquisition running";
elseif aqVal == 0
    aqStr = "Acquisition stopped";
else
    aqStr = sprintf("Unknown AQ:%d", aqVal);
end

% RS: recorder state (friendly names)
if isempty(rsVal)
    rsStr = "Unknown (no RS reply)";
else
    switch rsVal
        case 0
            rsStr = "Idle / Ready";
        case 1
            rsStr = "Monitoring";
        case 2
            rsStr = "Test / Preview";
        case 3
            rsStr = "Armed / Waiting";
        case 4
            rsStr = "Recording / Saving";
        case 5
            rsStr = "Paused";
        case 6
            rsStr = "Stopping / Finalizing";
        otherwise
            rsStr = sprintf("Unknown (RS:%d)", rsVal);
    end
end
end

function v = parseVal(line)
v = [];
if strlength(line) == 0 || ~contains(line, ":")
    return
end
parts = split(string(line), ":");
if numel(parts) < 2
    return
end
numstr = strtrim(parts(2));
tmp = str2double(numstr);
if ~isnan(tmp)
    v = tmp;
end
end

function tf = isValidRCSCommand(cmd)
% Heuristic: does this look like a real RCS command?
% This lets you type raw RCS commands directly (AP, RS, AN:..., 1:..., etc.)
cmdU = upper(strtrim(string(cmd)));

% Single-letter core commands (known)
if ismember(cmdU, ["O","M","S","Q"])
    tf = true; return
end

% Two-letter status queries (known)
if ismember(cmdU, ["AP","AQ","RS"])
    tf = true; return
end

% Common prefixes (known)
knownPrefixes = ["AN:","SN:","SA:","WF","WN","RF","RD","1:","2:","3:"];
for p = knownPrefixes
    if startsWith(cmdU, p)
        tf = true; return
    end
end

% Digit + colon (generic)
if ~isempty(regexp(cmdU, '^\d+:', 'once'))
    tf = true; return
end

% Uppercase letters + colon (generic)
if ~isempty(regexp(cmdU, '^[A-Z]+:', 'once'))
    tf = true; return
end

tf = false;
end

function printHelp()
fprintf("\nAliases:\n");
fprintf("  o | open                 -> O (open Recorder)\n");
fprintf("  mon | monitor | m        -> M (monitoring)\n");
fprintf("  s | start | rec          -> S (start recording)\n");
fprintf("  stop | end | q           -> Q (stop recording)\n");
fprintf("  marker:improv            -> AN:improv;Comment\n");
fprintf("  m:fixed;Stimulus         -> AN:fixed;Stimulus\n");
fprintf("  getstate | state | gs    -> query AP/AQ/RS + human-readable\n\n");

fprintf("Metadata helpers:\n");
fprintf("  ws:<path>                -> 1:<path> (workspace)\n");
fprintf("  exp:<n>                  -> 2:<n> (experiment number)\n");
fprintf("  subj:<id>                -> 3:<id> (subject id)\n");
fprintf("  sa:<name>                -> SA:<name> (select amplifier)\n");
fprintf("  sn:<serial>              -> SN:<serial> (LiveAmp serial)\n\n");

fprintf("Raw commands:\n");
fprintf("  You can type valid RCS commands directly (AP, RS, AN:..., 1:..., etc.).\n");
fprintf("  To force-send anything: raw:<cmd>\n\n");

fprintf("Exit:\n");
fprintf("  x | exit | quit\n\n");

fprintf("Tip: Metadata MUST be sent before 'start' to ensure recording works.\n\n");
end
