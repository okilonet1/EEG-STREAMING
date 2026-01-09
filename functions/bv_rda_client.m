function out = bv_rda_client(varargin)
% BV_RDA_CLIENT  Multi-stream BrainVision Recorder RDA client.
%
% Stream is keyed by (host,port), so you can have multiple streams open.
%
% Examples:
%   bv_rda_client('open', host, port, nCh, fs);
%   X = bv_rda_client(host, port, 'pull', 0.05);
%   bv_rda_client(host, port, 'debug', true);
%   bv_rda_client(host, port, 'close');   % closes one stream
%   bv_rda_client('close');               % closes all streams
%
% Optional convenience:
%   bv_rda_client(host, 'close');         % closes ALL streams on that host

persistent M
if isempty(M)
    M = containers.Map('KeyType','char','ValueType','any'); % key -> state struct
end

if nargin < 1
    error('bv_rda_client:MissingArgs', 'Need arguments.');
end

% -------------------------
% Parse calling convention
% -------------------------
cmds = ["open","pull","close","debug","list"];

a1 = varargin{1};
if ~ischar(a1) && ~isstring(a1)
    error('bv_rda_client:BadArg', 'First arg must be a command or host string.');
end
s1 = lower(string(a1));

% Case A: bv_rda_client('cmd', ...)
if any(s1 == cmds)
    cmd = char(s1);
    args = varargin(2:end);
    key = ''; host=''; port=[];
    mode = "global_cmd";

    % Case B: bv_rda_client(host, port, 'cmd', ...)
else
    host = char(string(varargin{1}));

    if nargin >= 2 && (ischar(varargin{2}) || isstring(varargin{2}))
        % Convenience: bv_rda_client(host,'close') closes all streams on that host
        cmd2 = lower(string(varargin{2}));
        if ~any(cmd2 == cmds)
            error('bv_rda_client:BadCmd', 'Unknown command: %s', string(varargin{2}));
        end
        cmd = char(cmd2);
        port = [];
        args = varargin(3:end);
        key = ''; % host-only operation
        mode = "host_cmd";
    else
        if nargin < 3
            error('bv_rda_client:MissingCmd', 'Expected bv_rda_client(host, port, cmd, ...).');
        end
        port = varargin{2};
        cmd3 = lower(string(varargin{3}));
        if ~any(cmd3 == cmds)
            error('bv_rda_client:BadCmd', 'Unknown command: %s', string(varargin{3}));
        end
        cmd = char(cmd3);
        args = varargin(4:end);
        key = make_key(host, port);
        mode = "stream_cmd";
    end
end

% -------------------------
% Dispatch
% -------------------------
switch cmd
    case 'open'
        % bv_rda_client('open', host, port, nCh, fs)
        if numel(args) < 4
            error('bv_rda_client:OpenArgs', 'Usage: bv_rda_client(''open'', host, port, nCh, fs)');
        end
        host = char(string(args{1}));
        port = args{2};
        nCh  = args{3};
        fs   = args{4};
        key  = make_key(host, port);

        % If already open, close and reopen cleanly
        if M.isKey(key)
            stOld = M(key);
            stOld = close_one(stOld);
            M.remove(key);
        end

        st = new_state();
        st.host = host;
        st.port = port;
        st.key  = key;
        st.NCH  = nCh;
        st.FS   = fs;

        st.BUF = zeros(st.NCH, st.FS*10, 'double');
        st.POS = 0;

        st.RX  = zeros(0,1,'uint8');
        st.DBG = false;
        st.ENDIAN   = "";
        st.SIZECONV = "";

        st.T = tcpclient(host, port, 'Timeout', 10, 'ConnectTimeout', 10);
        st.T.InputBufferSize = 64*1024*1024;

        M(key) = st;

        fprintf('[bv_rda_client] Connected %s | %d ch @ %d Hz\n', key, nCh, fs);
        out = struct('ok', true, 'host', host, 'port', port, 'key', key, 'nCh', nCh, 'fs', fs);
        return

    case 'pull'
        if mode ~= "stream_cmd"
            error('bv_rda_client:PullUsage', 'Usage: X = bv_rda_client(host, port, ''pull'', winSec)');
        end
        st = require_state(M, key);

        winSec = args{1};
        need = max(1, ceil(winSec * st.FS));

        st = ingest_from_socket(st, 0.15);

        if st.POS == 0
            out = zeros(st.NCH, need);
        else
            take = min(need, size(st.BUF,2));
            idx  = mod((st.POS-(take-1):st.POS)-1, size(st.BUF,2)) + 1;
            out  = st.BUF(:, idx);
        end
        M(key) = st;
        return

    case 'debug'
        if mode ~= "stream_cmd"
            error('bv_rda_client:DebugUsage', 'Usage: bv_rda_client(host, port, ''debug'', true|false)');
        end
        st = require_state(M, key);
        st.DBG = logical(args{1});
        M(key) = st;
        out = struct('ok', true, 'key', key, 'debug', st.DBG);
        return

    case 'list'
        ks = keys(M);
        info = cell(numel(ks),1);
        for i = 1:numel(ks)
            s = M(ks{i});
            info{i} = struct('key', s.key, 'host', s.host, 'port', s.port, 'nCh', s.NCH, 'fs', s.FS);
        end
        out = info;
        return

    case 'close'
        if mode == "global_cmd"
            % bv_rda_client('close') -> close all
            ks = keys(M);
            for i = 1:numel(ks)
                st = M(ks{i});
                st = close_one(st);
                M.remove(ks{i});
            end
            out = struct('ok', true, 'closed', 'all');
            return
        elseif mode == "host_cmd"
            % bv_rda_client(host,'close') -> close all streams for that host
            ks = keys(M);
            closed = {};
            for i = 1:numel(ks)
                st = M(ks{i});
                if strcmp(st.host, host)
                    st = close_one(st);
                    M.remove(ks{i});
                    closed{end+1} = ks{i}; %#ok<AGROW>
                end
            end
            out = struct('ok', true, 'closed_host', host, 'closed_keys', {closed});
            return
        else
            % bv_rda_client(host,port,'close') -> close one
            if M.isKey(key)
                st = M(key);
                st = close_one(st);
                M.remove(key);
                out = struct('ok', true, 'closed', key);
            else
                out = struct('ok', true, 'closed', key, 'note', 'not open');
            end
            return
        end
end

end

% =========================
% ===== state helpers =====
% =========================

function key = make_key(host, port)
key = sprintf('%s:%d', char(string(host)), double(port));
end

function st = new_state()
st = struct( ...
    'key','', 'host','', 'port',[], ...
    'T',[], 'NCH',[], 'FS',[], ...
    'BUF',[], 'POS',0, ...
    'RX',[], 'DBG',false, ...
    'ENDIAN',"", 'SIZECONV',"");
end

function st = require_state(M, key)
if ~M.isKey(key)
    error('bv_rda_client:NotOpen', 'Stream %s not open. Call bv_rda_client(''open'', host, port, nCh, fs) first.', key);
end
st = M(key);
if isempty(st.T) || ~isvalid(st.T)
    error('bv_rda_client:BadSocket', 'Stream %s socket is not valid.', key);
end
end

function st = close_one(st)
try
    if ~isempty(st.T) && isvalid(st.T)
        clear st.T
    end
catch
end
fprintf('[bv_rda_client] Closed %s\n', st.key);
st.T=[]; st.BUF=[]; st.POS=0; st.RX=zeros(0,1,'uint8'); st.ENDIAN=""; st.SIZECONV="";
end

% =========================
% ===== ingest/parse ======
% =========================

function st = ingest_from_socket(st, timeBudget)
t0 = tic;
while toc(t0) < timeBudget
    nb = st.T.NumBytesAvailable;
    if nb > 0
        newBytes = read(st.T, nb, 'uint8');
        if ~isempty(newBytes)
            st.RX(end+1:end+numel(newBytes),1) = newBytes(:);
        end
    end

    [st, progressed] = parse_rx_messages(st);
    if ~progressed
        if nb == 0
            if st.DBG
                fprintf('[RDA:%s] no parse progress (NumBytesAvailable=%d, RX=%d bytes)\n', ...
                    st.key, st.T.NumBytesAvailable, numel(st.RX));
            end
            break
        end
    end
end
end

function [st, progressed] = parse_rx_messages(st)
progressed = false;

while numel(st.RX) >= 8
    hb = st.RX(1:8);

    hLittle = typecast(hb, 'int32');
    hBig    = swapbytes(hLittle);

    if st.ENDIAN == ""
        [okL, ~, ~] = header_plausible(hLittle);
        [okB, ~, ~] = header_plausible(hBig);

        if okL && ~okB
            st.ENDIAN = "little";
        elseif okB && ~okL
            st.ENDIAN = "big";
        elseif okL && okB
            st.ENDIAN = "little";
        else
            if st.DBG
                fprintf('[RDA:%s] bad header (little: size=%d type=%d | big: size=%d type=%d) -> slide\n', ...
                    st.key, double(hLittle(1)), double(hLittle(2)), double(hBig(1)), double(hBig(2)));
            end
            st.RX(1) = [];
            progressed = true;
            continue
        end

        if st.DBG
            fprintf('[RDA:%s] detected header endianness: %s\n', st.key, st.ENDIAN);
        end
    end

    h = hLittle;
    if st.ENDIAN == "big"
        h = hBig;
    end

    nSize = double(h(1));
    nType = double(h(2));

    if ~isfinite(nSize) || nSize < 0 || nSize > 1e8
        if st.DBG
            fprintf('[RDA:%s] insane nSize=%g nType=%g -> slide\n', st.key, nSize, nType);
        end
        st.RX(1) = [];
        progressed = true;
        continue
    end

    total_excludes = nSize + 8; % nSize excludes header
    total_includes = nSize;     % nSize includes header

    have = numel(st.RX);
    cand = [];
    if total_includes >= 8 && total_includes <= have, cand(end+1) = total_includes; end %#ok<AGROW>
    if total_excludes >= 8 && total_excludes <= have, cand(end+1) = total_excludes; end %#ok<AGROW>
    if isempty(cand), return; end

    if st.SIZECONV == "includes_header"
        total = total_includes;
    elseif st.SIZECONV == "excludes_header"
        total = total_excludes;
    else
        [st, total] = choose_total_and_set_conv(st, total_includes, total_excludes, nType);
    end


    msg = st.RX(1:total);
    st.RX(1:total) = [];
    progressed = true;

    payload = msg(9:end);

    if st.DBG
        fprintf('[RDA:%s] type=%d nSize=%d chosenTotal=%d payload=%d rxRemain=%d\n', ...
            st.key, nType, nSize, total, numel(payload), numel(st.RX));
    end

    if nType == 4
        st = process_data_message(st, payload);
    end
end
end

function [ok, sz, ty] = header_plausible(h)
sz = double(h(1)); ty = double(h(2));
ok = isfinite(sz) && isfinite(ty) && sz > 0 && sz < 1e7 && ty >= 1 && ty <= 100;
end

function [st, total] = choose_total_and_set_conv(st, total_includes, total_excludes, nType)
candidates = unique([total_includes, total_excludes]);
scores = -inf(size(candidates));

for i = 1:numel(candidates)
    tot = candidates(i);
    if tot < 8 || tot > numel(st.RX)
        continue
    end

    sc = 0;

    % Data payload validity test
    if nType == 4
        if validates_data_message(st, st.RX(1:tot))
            sc = sc + 10;
        else
            sc = sc - 10;
        end
    end

    % Next-header plausibility
    if numel(st.RX) >= tot + 8
        next8 = st.RX(tot+1:tot+8);
        h = typecast(next8, 'int32');
        if st.ENDIAN == "big"
            h = swapbytes(h);
        end
        if header_plausible(h)
            sc = sc + 3;
        else
            sc = sc - 1;
        end
    end

    scores(i) = sc;
end

best = max(scores);
bestIdx = find(scores == best);

% Tie-breaker: prefer includes_header (total_includes) for BrainVision
if numel(bestIdx) > 1
    j = find(candidates(bestIdx) == total_includes, 1);
    if ~isempty(j)
        total = total_includes;
    else
        total = candidates(bestIdx(1));
    end
else
    total = candidates(bestIdx);
end

if total == total_includes
    st.SIZECONV = "includes_header";
else
    st.SIZECONV = "excludes_header";
end

if st.DBG
    fprintf('[RDA:%s] SIZECONV locked: %s (scores=%s)\n', ...
        st.key, st.SIZECONV, mat2str(scores));
end
end

function ok = validates_data_message(st, msg)
ok = false;
if numel(msg) < 8+12, return; end
pl = msg(9:end);
if numel(pl) < 12, return; end

d = typecast(pl(1:12), 'int32');
if st.ENDIAN == "big"
    d = swapbytes(d);
end
nPoints = double(d(2));
if ~isfinite(nPoints) || nPoints < 1 || nPoints > (st.FS*10)
    return
end

bytesDat = st.NCH * nPoints * 4;
if numel(pl) < (12 + bytesDat)
    return
end
ok = true;
end

function st = process_data_message(st, payload)
if numel(payload) < 12, return; end

d = typecast(payload(1:12), 'int32');
if st.ENDIAN == "big"
    d = swapbytes(d);
end
nPoints = double(d(2));
if ~isfinite(nPoints) || nPoints < 1 || nPoints > 1e6
    return
end

bytesDat = st.NCH * nPoints * 4;
if numel(payload) < (12 + bytesDat)
    return
end

raw = payload(13 : 12 + bytesDat);

% float32 µV first
v = typecast(raw, 'single');
if st.ENDIAN == "big"
    v = swapbytes(v);
end
x = reshape(double(v), [st.NCH, nPoints]);

% sanity fallback to int32 nV -> µV
if any(~isfinite(x(:))) || max(abs(x(:))) > 1e5
    nv = typecast(raw, 'int32');
    if st.ENDIAN == "big"
        nv = swapbytes(nv);
    end
    x = reshape(double(nv) / 1000, [st.NCH, nPoints]);
end

k = size(x,2);
idx = mod((st.POS+(1:k))-1, size(st.BUF,2)) + 1;
st.BUF(:, idx) = x;
st.POS = idx(end);
end
