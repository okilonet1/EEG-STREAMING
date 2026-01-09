function stream_out(data, protocol, target, varargin)
% STREAM_OUT  Sends data from MATLAB to an external device.
%
% Clean TCP (TouchDesigner TCP/IP DAT Server):
%   - Each call sends newline-terminated text
%   - Supports MULTIPLE concurrent TCP connections (per ip:port)
%
% USAGE:
%   stream_out(0.123, "tcp", "192.168.50.219", 7006)
%   stream_out(0.456, "tcp", "192.168.50.219", 7007)
%   stream_out("0.123\n", "tcp", "192.168.50.219", 7006)
%   stream_out(0, "close", "", 7006)     % closes any tcp clients on port 7006
%   stream_out(0, "close", "", [])       % closes ALL tcp clients

arguments
    data
    protocol   {mustBeTextScalar}
    target     {mustBeTextScalar}
end
arguments (Repeating)
    varargin
end

persistent TCPMAP   % containers.Map key="ip:port" value=tcpclient

if isempty(TCPMAP)
    TCPMAP = containers.Map('KeyType','char','ValueType','any');
end

proto = lower(string(protocol));

switch proto
    case "tcp"
        if numel(varargin) < 1
            error("TCP requires port number");
        end
        port = varargin{1};

        % ---- Build clean text payload: 1 value per line by default ----
        if isnumeric(data)
            if isscalar(data)
                frameStr = sprintf('%.6f\n', double(data));
            else
                % If vector/matrix, send each element on a new line (clean "latest line" use)
                v = double(data(:));
                frameStr = sprintf('%.6f\n', v);
            end
        else
            frameStr = char(data);
            if isempty(frameStr) || frameStr(end) ~= newline
                frameStr = [frameStr newline];
            end
        end
        payloadText = uint8(frameStr);

        key = sprintf('%s:%d', string(target), port);
        key = char(key);

        % ---- Ensure TCP client exists for this ip:port ----
        if ~TCPMAP.isKey(key) || isempty(TCPMAP(key)) || ~isvalid(TCPMAP(key))
            try
                tc = tcpclient(target, port, 'Timeout', 1, 'ConnectTimeout', 1);
                TCPMAP(key) = tc;
                fprintf("[stream_out] TCP connected to %s\n", key);
            catch E
                warning(E.identifier, "[stream_out] TCP connect failed to %s: %s", key, E.message);
                % Remove bad entry if present
                if TCPMAP.isKey(key), remove(TCPMAP, key); end
                return
            end
        end

        % ---- Write ----
        try
            tc = TCPMAP(key);
            write(tc, payloadText, "uint8");
        catch E
            warning(E.identifier, "[stream_out] TCP write failed to %s: %s", key, E.message);
            try
                if TCPMAP.isKey(key), remove(TCPMAP, key); end
            catch
            end
        end

    case "close"
        % Optional port filter: close only clients on this port
        portToClose = [];
        if ~isempty(varargin)
            portToClose = varargin{1};  % [] => close all
        end

        keys = TCPMAP.keys;
        for i = 1:numel(keys)
            k = keys{i};
            tc = TCPMAP(k);

            % parse port from key "...:PORT"
            parts = split(string(k), ":");
            p = str2double(parts(end));

            if isempty(portToClose) || isequal(portToClose, []) || p == portToClose
                try
                    clear tc; %#ok<CLALL>
                catch
                end
                try
                    remove(TCPMAP, k);
                catch
                end
                fprintf("[stream_out] Closed TCP %s\n", k);
            end
        end

    otherwise
        error("Unknown protocol. Use 'tcp' or 'close'.");
end
end
