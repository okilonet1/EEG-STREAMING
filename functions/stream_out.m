function stream_out(data, protocol, target, varargin)
% STREAM_OUT  Sends arbitrary data from MATLAB to an external device.
%
% USAGE:
%   stream_out(data, "tcp",        "127.0.0.1", 9000)   % MATLAB = client (TEXT table for TouchDesigner)
%   stream_out(data, "tcp_server", "",           9000)   % MATLAB = server (TEXT table, TouchDesigner-friendly)
%   stream_out(data, "udp",        "192.168.1.20", 8000)
%   stream_out(data, "serial",     "/dev/cu.EEG-ESP32", 115200)

arguments
    data       {mustBeNumeric}
    protocol   {mustBeTextScalar}
    target     {mustBeTextScalar}
end

arguments (Repeating)
    varargin
end

% ---------- persistent handles (declare ONCE) ----------
persistent tc srv sp   % tc = tcpclient, srv = tcpserver, sp = serialport

% Default payload for binary protocols = float32 row vector as bytes
payload = typecast(single(data(:)), 'uint8');
payload = payload(:)';

switch lower(protocol)

    % ============================
    % TCP CLIENT (TEXT TABLE for TouchDesigner)
    % ============================
    case "tcp"
        if numel(varargin) < 1
            error("TCP requires port number");
        end
        port = varargin{1};

        % ---- Build text payload as plain char ----
        if isnumeric(data)
            if ismatrix(data)
                [nRows, ~] = size(data);
                buf = '';  % char buffer
                for r = 1:nRows
                    % "v1 v2 ... vN"
                    line = sprintf('%.5f ', data(r, :));
                    line = strtrim(line);                 % remove trailing space
                    buf  = sprintf('%s%s\n', buf, line);  % append line + newline
                end
                frameStr = buf; % char
            else
                % Fallback: vector or higher-dim -> flatten as single line
                line = sprintf('%.5f ', data(:));
                frameStr = [strtrim(line) sprintf('\n')]; % char
            end
        else
            frameStr = char(data);
            if isempty(frameStr) || frameStr(end) ~= sprintf('\n')
                frameStr = [frameStr sprintf('\n')];
            end
        end

        payloadText = uint8(frameStr);   % UTF-8-compatible bytes

        % ---- Ensure TCP client exists ----
        if isempty(tc) || ~isvalid(tc)
            try
                tc = tcpclient(target, port, 'Timeout', 1);
                fprintf("[stream_out] TCP client (TEXT) connected to %s:%d\n", target, port);
            catch E
                warning(E.identifier, '[stream_out] TCP client connect failed to %s:%d: %s', ...
                    target, port, E.message);
                return;
            end
        end

        % ---- Send the text ----
        try
            write(tc, payloadText, "uint8");
        catch E
            warning(E.identifier, '[stream_out] TCP client write failed: %s', E.message);
            clear tc;
            tc = [];
        end



        % ============================
        % TCP SERVER (TEXT TABLE for TouchDesigner)
        % ============================
    case "tcp_server"
        if numel(varargin) < 1
            error("TCP server requires port number");
        end
        port = varargin{1};

        % ---- Ensure TCP server exists ----
        if isempty(srv) || ~isvalid(srv)
            try
                srv = tcpserver("0.0.0.0", port);
                fprintf("[stream_out] TCP server (TEXT) listening on port %d\n", port);
                srv.ConnectionChangedFcn = @(src, evt) tcp_connection_logger(src, evt);

            catch E
                warning(E.identifier, '[stream_out] TCP server start failed on port %d: %s', ...
                    port, E.message);
                return;
            end
        end

        % ---- Build text payload as plain char (same format as client) ----
        if isnumeric(data)
            if ismatrix(data)
                [nRows, ~] = size(data);
                buf = '';  % char buffer
                for r = 1:nRows
                    line = sprintf('%.5f ', data(r, :));
                    line = strtrim(line);
                    buf  = sprintf('%s%s\n', buf, line);
                end
                frameStr = buf;
            else
                line = sprintf('%.5f ', data(:));
                frameStr = [strtrim(line) sprintf('\n')];
            end
        else
            frameStr = char(data);
            if isempty(frameStr) || frameStr(end) ~= sprintf('\n')
                frameStr = [frameStr sprintf('\n')];
            end
        end

        payloadText = uint8(frameStr);   % UTF-8-compatible bytes

        % ---- Try writing; ignore "no client" errors quietly ----
        try
            write(srv, payloadText, "uint8");
        catch E
            % If there's no client yet, MATLAB throws this specific message.
            % We just ignore that case instead of warning/clearing the server.
            if contains(E.message, 'A TCP/IP client must be connected')
                % no clients connected yet -> just skip this frame
                return;
            end

            % Real error: warn and reset
            warning(E.identifier, '[stream_out] TCP server write failed: %s', E.message);
            clear srv;
            srv = [];
        end



        % ============================
        % UDP (binary float32)
        % ============================


    case "udp"
        if numel(varargin) < 1
            error("UDP requires port number");
        end
        port = varargin{1};

        u = udpport("datagram");
        write(u, payload, target, port);
        clear u

        % ============================
        % SERIAL / BLUETOOTH (binary)
        % ============================
    case "serial"
        if numel(varargin) < 1
            error("Serial requires baud rate");
        end
        baud = varargin{1};

        if isempty(sp) || ~isvalid(sp)
            sp = serialport(target, baud);
            configureTerminator(sp, "LF");
            fprintf("[stream_out] Serial connected: %s @ %d\n", target, baud);
        end

        write(sp, payload, "uint8");
        write(sp, uint8(10), "uint8");   % newline terminator

        % ============================
        % CLOSE / CLEANUP (port-aware)
        % ============================
    case "close"
        % Optional: port number to close
        portToClose = [];
        if ~isempty(varargin)
            portToClose = varargin{1};   % e.g. VIS_PORT
        end

        % ---- Close only this function's tcpserver on that port (if any) ----
        if ~isempty(srv) && isvalid(srv)
            try
                if isempty(portToClose) || srv.Port == portToClose
                    fprintf('[stream_out] Closing TCP server on port %d\n', srv.Port);
                    clear srv;
                    srv = [];
                end
            catch
                % If srv.Port is unsupported for some reason, just clear it
                clear srv;
                srv = [];
            end
        end

        % NOTE: we do NOT touch tc or sp here, so other TCP clients / serial
        % connections created via stream_out stay alive.
        return;

    otherwise
        error("Unknown protocol. Use 'tcp', 'tcp_server', 'udp', or 'serial'.");
end
end
