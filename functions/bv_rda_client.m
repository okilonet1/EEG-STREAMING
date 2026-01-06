function S = bv_rda_client(cmd, varargin)
% BrainVision Recorder RDA v2 client (int32 nV payload -> µV).
%
% Robust to:
%   - TCP fragmentation (byte accumulator)
%   - nSize convention (includes header vs excludes header)
%   - Header endianness (auto-detect little vs big)

persistent T NCH FS BUF POS RX DBG ENDIAN SIZECONV

switch lower(cmd)
    case 'open'
        ENDIAN   = "";
        SIZECONV = "";   % "includes_header" or "excludes_header"

        host = varargin{1};  port = varargin{2};
        NCH  = varargin{3};  FS   = varargin{4};

        BUF = zeros(NCH, FS*10, 'double'); % 10s ring buffer
        POS = 0;

        T = tcpclient(host, port, 'Timeout', 10, 'ConnectTimeout', 10);
        T.InputBufferSize = 64*1024*1024;

        RX     = zeros(0,1,'uint8'); % empty column accumulator
        DBG    = false;
        ENDIAN = "";                 % "little" or "big" once detected

        fprintf('[bv_rda_client] Connected %s:%d | %d ch @ %d Hz | nV->µV (/1000)\n', host, port, NCH, FS);
        S = struct('ok', true, 'nCh', NCH, 'fs', FS);
        return

    case 'pull'
        assert(~isempty(T) && isvalid(T), 'RDA not open.');
        winSec = varargin{1};
        need   = max(1, ceil(winSec * FS));

        ingest_from_socket(0.15);  % give real Recorder enough time

        if POS == 0
            S = zeros(NCH, need);
            return
        end

        take = min(need, size(BUF,2));
        idx  = mod((POS-(take-1):POS)-1, size(BUF,2)) + 1;
        S    = BUF(:, idx);
        return

    case 'debug'
        DBG = logical(varargin{1});
        S = struct('ok', true, 'debug', DBG);
        return

    case 'close'
        try
            if ~isempty(T) && isvalid(T), clear T; end
        catch
        end
        T=[]; NCH=[]; FS=[]; BUF=[]; POS=0; RX=zeros(0,1,'uint8'); DBG=false; ENDIAN="";
        S = struct('ok', true);
        return

    otherwise
        error('Unknown command: %s', cmd);
end

% =========================
% === Nested functions ====
% =========================

    function ingest_from_socket(timeBudget)
        t0 = tic;
        while toc(t0) < timeBudget
            nb = T.NumBytesAvailable;
            if nb > 0
                newBytes = read(T, nb, 'uint8');
                if ~isempty(newBytes)
                    RX(end+1:end+numel(newBytes),1) = newBytes(:);
                end
            end

            progressed = parse_rx_messages();
            if ~progressed
                if nb == 0
                    if DBG
                        fprintf('[RDA] no parse progress (NumBytesAvailable=%d, RX=%d bytes)\n', ...
                            T.NumBytesAvailable, numel(RX));
                    end
                    break
                end
            end
        end
    end

    function progressed = parse_rx_messages()
        progressed = false;

        while numel(RX) >= 8
            % --- Read header bytes ---
            hb = RX(1:8);

            % --- Interpret header both ways ---
            hLittle = typecast(hb, 'int32');
            hBig    = swapbytes(hLittle);

            % Choose endianness if not decided yet
            if ENDIAN == ""
                [okL, szL, tyL] = header_plausible(hLittle);
                [okB, szB, tyB] = header_plausible(hBig);

                if okL && ~okB
                    ENDIAN = "little";
                elseif okB && ~okL
                    ENDIAN = "big";
                elseif okL && okB
                    % both plausible: default to little (common), but keep flexible
                    ENDIAN = "little";
                else
                    % Neither plausible: slide 1 byte and continue resync
                    if DBG
                        fprintf('[RDA] bad header (little: size=%d type=%d | big: size=%d type=%d) -> slide\n', ...
                            double(hLittle(1)), double(hLittle(2)), double(hBig(1)), double(hBig(2)));
                    end
                    RX(1) = [];
                    progressed = true;
                    continue
                end

                if DBG
                    fprintf('[RDA] detected header endianness: %s\n', ENDIAN);
                end
            end

            if ENDIAN == "big"
                h = hBig;
            else
                h = hLittle;
            end

            nSize = double(h(1));
            nType = double(h(2));

            % sanity (if insane, resync)
            if ~isfinite(nSize) || nSize < 0 || nSize > 1e8
                if DBG
                    fprintf('[RDA] insane nSize=%g nType=%g -> slide\n', nSize, nType);
                end
                RX(1) = [];
                progressed = true;
                continue
            end

            % Two size conventions:
            total_excludes = nSize + 8; % nSize excludes header
            total_includes = nSize;     % nSize includes header

            have = numel(RX);
            cand = [];
            if total_includes >= 8 && total_includes <= have, cand(end+1) = total_includes; end %#ok<AGROW>
            if total_excludes >= 8 && total_excludes <= have, cand(end+1) = total_excludes; end %#ok<AGROW>

            if isempty(cand)
                return
            end

            % If we already know the convention, use it directly
            if SIZECONV == "includes_header"
                total = total_includes;
            elseif SIZECONV == "excludes_header"
                total = total_excludes;
            else
                % Detect size convention by "which one leaves us aligned"
                total = choose_total_and_maybe_set_conv(total_includes, total_excludes, nType);
            end


            msg = RX(1:total);
            RX(1:total) = [];
            progressed = true;

            payload = msg(9:end);

            if DBG
                fprintf('[RDA] type=%d nSize=%d chosenTotal=%d payload=%d rxRemain=%d\n', ...
                    nType, nSize, total, numel(payload), numel(RX));
            end

            if nType == 4
                process_data_message(payload);
            end
        end
    end

    function [ok, sz, ty] = header_plausible(h)
        sz = double(h(1)); ty = double(h(2));
        ok = isfinite(sz) && isfinite(ty) && sz > 0 && sz < 1e7 && ty >= 1 && ty <= 100;
    end

    function total = choose_total_and_maybe_set_conv(total_includes, total_excludes, nType)
        % Decide whether nSize includes the 8-byte header.
        % Prefer the candidate that:
        %   (a) validates Data payload if nType==4
        %   (b) leaves the next header plausible (alignment test)

        candidates = [];
        if total_includes >= 8 && total_includes <= numel(RX), candidates(end+1) = total_includes; end %#ok<AGROW>
        if total_excludes >= 8 && total_excludes <= numel(RX), candidates(end+1) = total_excludes; end %#ok<AGROW>
        candidates = unique(candidates);

        if numel(candidates) == 1
            total = candidates(1);
            % Set convention from the one available
            if total == total_includes, SIZECONV = "includes_header"; else, SIZECONV = "excludes_header"; end
            if DBG, fprintf('[RDA] SIZECONV locked: %s\n', SIZECONV); end
            return
        end

        % Score candidates
        scores = zeros(size(candidates));

        for i = 1:numel(candidates)
            tot = candidates(i);

            % 1) If it's Data, validate payload structure strongly
            if nType == 4
                if validates_data_message(RX(1:tot))
                    scores(i) = scores(i) + 10;
                else
                    scores(i) = scores(i) - 10;
                end
            end

            % 2) Alignment test: after consuming tot bytes, does the next header look plausible?
            if numel(RX) >= tot + 8
                next8 = RX(tot+1:tot+8);
                h = typecast(next8, 'int32');
                if ENDIAN == "big"
                    h = swapbytes(h);
                end
                if header_plausible(h)
                    scores(i) = scores(i) + 3;
                else
                    scores(i) = scores(i) - 1;
                end
            end
        end

        % Pick best score; tie-breaker: prefer "includes_header" for BrainVision
        [~, j] = max(scores);
        total = candidates(j);

        if total == total_includes
            SIZECONV = "includes_header";
        else
            SIZECONV = "excludes_header";
        end

        if DBG, fprintf('[RDA] SIZECONV locked: %s (scores: %s)\n', SIZECONV, mat2str(scores)); end
    end

    function ok = validates_data_message(msg)
        % msg includes header; payload begins at byte 9
        ok = false;
        if numel(msg) < 8+12, return; end
        pl = msg(9:end);
        if numel(pl) < 12, return; end

        d = typecast(pl(1:12), 'int32');
        if ENDIAN == "big"
            d = swapbytes(d);
        end
        nPoints = double(d(2));
        if ~isfinite(nPoints) || nPoints < 1 || nPoints > (FS*10)
            return
        end

        bytesDat = NCH * nPoints * 4;
        if numel(pl) < (12 + bytesDat)
            return
        end
        ok = true;
    end


% function process_data_message(payload)
%     if numel(payload) < 12, return, end

%     d = typecast(payload(1:12), 'int32');
%     if ENDIAN == "big"
%         d = swapbytes(d);
%     end

%     nPoints = double(d(2));
%     if ~isfinite(nPoints) || nPoints < 1 || nPoints > 1e6
%         return
%     end

%     bytesDat = NCH * nPoints * 4;
%     if numel(payload) < (12 + bytesDat)
%         return
%     end

%     raw = payload(13:(12 + bytesDat));
%     nv  = typecast(raw, 'int32');
%     if ENDIAN == "big"
%         nv = swapbytes(nv);
%     end

%     x   = reshape(double(nv) / 1000, [NCH, nPoints]); % µV

%     k   = size(x,2);
%     idx = mod((POS+(1:k))-1, size(BUF,2)) + 1;
%     BUF(:, idx) = x;
%     POS = idx(end);

% end

    function process_data_message(payload)
        if numel(payload) < 12, return, end

        % --- Data subheader: [int32 nBlock, int32 nPoints, int32 nMarkers] ---
        d = typecast(payload(1:12), 'int32');
        if ENDIAN == "big"
            d = swapbytes(d);
        end
        nPoints = double(d(2));

        if ~isfinite(nPoints) || nPoints < 1 || nPoints > 1e6
            return
        end

        % --- Only decode the sample matrix portion; ignore marker tail bytes ---
        bytesDat = NCH * nPoints * 4;     % 4 bytes/sample (float32 or int32)
        if numel(payload) < (12 + bytesDat)
            return
        end

        raw = payload(13 : 12 + bytesDat);

        % --- Try float32 µV first (common for BrainVision RDA) ---
        v = typecast(raw, 'single');
        if ENDIAN == "big"
            v = swapbytes(v);
        end
        x = reshape(double(v), [NCH, nPoints]);  % assume already µV

        % --- Sanity check; if insane, fall back to int32 nV -> µV ---
        % (EEG typically within a few hundred µV; be generous)
        if any(~isfinite(x(:))) || max(abs(x(:))) > 1e5
            nv = typecast(raw, 'int32');
            if ENDIAN == "big"
                nv = swapbytes(nv);
            end
            x = reshape(double(nv) / 1000, [NCH, nPoints]);  % nV -> µV
        end

        % Push into circular buffer
        k   = size(x,2);
        idx = mod((POS+(1:k))-1, size(BUF,2)) + 1;
        BUF(:, idx) = x;
        POS = idx(end);
    end

end
