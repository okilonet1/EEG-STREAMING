function S = bv_rda_client(cmd, varargin)
% BrainVision Recorder RDA v2 client (nV payload -> µV).
%
% USAGE:
%   S = bv_rda_client('open', host, port, nCh, fs)
%   X = bv_rda_client('pull', winSec)   % returns [nCh x N] double (µV)
%   S = bv_rda_client('close')

persistent T NCH FS BUF POS

switch lower(cmd)
    case 'open'
        host = varargin{1};  port = varargin{2};
        NCH  = varargin{3};  FS   = varargin{4};

        % 10 s circular buffer
        BUF = zeros(NCH, FS*10, 'double');
        POS = 0;

        % Open RDA TCP
        T = tcpclient(host, port, 'Timeout', 10, 'ConnectTimeout', 10);
        T.InputBufferSize = 32*1024*1024;




        fprintf('[bv_rda_client] mode: nV -> µV (divide by 1000)\n');
        S = struct('ok', true, 'nCh', NCH, 'fs', FS, 'mode', 'nv');
        return

        % case 'pull'
        %     assert(~isempty(T) && isvalid(T), 'RDA not open.');
        %     winSec = varargin{1};
        %     need   = max(1, ceil(winSec*FS));

        %     % Wait up to 1.0 s to accumulate at least one full Data message
        %     t0 = tic;
        %     while toc(t0) < 1.0
        %         if T.NumBytesAvailable < 8
        %             pause(0.001); continue
        %         end



        %         % ---- RDA message header: [int32 nSize, int32 nType] ----
        %         h = typecast(read_exact(T,8), 'int32');
        %         nSize = double(h(1));
        %         nType = double(h(2));       % 4 == Data

        %         if (nSize <= 0) || (nSize > 1e9)
        %             discard(T,1); continue   % desync guard
        %         end

        %         if nType ~= 4
        %             if T.NumBytesAvailable < nSize, pause(0.001); continue, end
        %             discard(T, nSize);
        %             continue
        %         end

        %         % ---- Data sub-header ----
        %         if T.NumBytesAvailable < 12, pause(0.001); continue, end
        %         d = typecast(read_exact(T,12), 'int32');
        %         nPoints  = double(d(2));
        %         nVals    = NCH * nPoints;
        %         bytesDat = nVals * 4;

        %         if T.NumBytesAvailable < bytesDat, pause(0.001); continue, end

        %         % ---- nV -> µV scaling ----
        %         raw = read_exact(T, bytesDat);
        %         nv  = typecast(raw, 'int32');
        %         x   = double(nv) / 1000;
        %         x   = reshape(x, [NCH, nPoints]);

        %         % Push into circular buffer
        %         k   = size(x,2);
        %         idx = mod((POS+(1:k))-1, size(BUF,2))+1;
        %         BUF(:,idx) = x;
        %         POS = idx(end);

        %         % Skip any marker tail
        %         remA = nSize - (12 + bytesDat);
        %         remB = (nSize - 8) - (12 + bytesDat);
        %         rem  = remA; if rem < 0 || rem > 10e6, rem = remB; end
        %         if rem > 0
        %             if T.NumBytesAvailable < rem, pause(0.001); continue, end
        %             discard(T, rem);
        %         end

        %         if k > 0, break; end
        %     end

        %     % ===== return most recent samples =====
        %     need = min(need, size(BUF,2));
        %     if need == 0
        %         S = zeros(NCH,1);
        %     else
        %         tail = mod((POS-(need-1):POS)-1, size(BUF,2))+1;
        %         S = BUF(:,tail);
        %     end


        %     return

    case 'pull'
        assert(~isempty(T) && isvalid(T), 'RDA not open.');
        winSec = varargin{1};
        need   = max(1, ceil(winSec*FS));

        % Read until we accumulate at least NEED samples (or timeout)
        collected = 0;
        t0 = tic;
        while (collected < need) && (toc(t0) < 2.0)  % allow up to 2 s to fill
            if T.NumBytesAvailable < 8
                pause(0.001);
                continue
            end

            % ---- RDA message header: [int32 nSize, int32 nType] ----
            h = typecast(read_exact(T,8), 'int32');
            nSize = double(h(1));
            nType = double(h(2));       % 4 == Data

            if (nSize <= 0) || (nSize > 1e9)
                discard(T,1);
                continue   % desync guard
            end

            if nType ~= 4
                if T.NumBytesAvailable < nSize, pause(0.001); continue, end
                discard(T, nSize);       % skip non-Data payload
                continue
            end

            % ---- Data sub-header: [int32 nBlock, int32 nPoints, int32 nMarkers] ----
            if T.NumBytesAvailable < 12, pause(0.001); continue, end
            d = typecast(read_exact(T,12), 'int32');
            nPoints  = double(d(2));
            nVals    = NCH * nPoints;
            bytesDat = nVals * 4;       % int32 container

            if T.NumBytesAvailable < bytesDat, pause(0.001); continue, end

            % ---- nV -> µV scaling ----
            raw = read_exact(T, bytesDat);
            nv  = typecast(raw, 'int32');
            x   = double(nv) / 1000;                  % convert to microVolts
            x   = reshape(x, [NCH, nPoints]);

            % Push into circular buffer
            k   = size(x,2);
            idx = mod((POS+(1:k))-1, size(BUF,2))+1;
            BUF(:,idx) = x;
            POS = idx(end);
            collected = collected + k;

            % ---- Skip marker tail (two size conventions) ----
            remA = nSize - (12 + bytesDat);          % payload excludes 8B header
            remB = (nSize - 8) - (12 + bytesDat);    % payload includes 8B header
            rem  = remA; if rem < 0 || rem > 10e6, rem = remB; end
            if rem > 0
                if T.NumBytesAvailable < rem, pause(0.001); continue, end
                discard(T, rem);
            end
        end

        % If still short, wait a bit more (grace period)
        if collected < need
            t1 = tic;
            while (collected < need) && (toc(t1) < 1.0)
                pause(0.01);
                % passive wait; more blocks will be read next pull call
                % (optional: you could loop back to actively read here again)
                collected = min(collected + T.NumBytesAvailable, need); %#ok<NASGU>
            end
        end

        % ===== return most recent samples =====
        have = min(need, size(BUF,2));
        if have == 0 || POS == 0
            S = zeros(NCH, need);
            return
        end
        take = min(need, have);
        tail = mod((POS-(take-1):POS)-1, size(BUF,2))+1;
        S = BUF(:,tail);
        return


    case 'close'
        try, clear T; end %#ok<TRYNC>
        NCH=[]; FS=[]; BUF=[]; POS=0;
        S = struct('ok', true);
        return

    otherwise
        error('Unknown command: %s', cmd);
end
end

% ---- helpers ----
function b = read_exact(T, n)
while T.NumBytesAvailable < n
    pause(0.001);
end
b = read(T, n, 'uint8');
end

function discard(T, n)
read_exact(T, n);
end
