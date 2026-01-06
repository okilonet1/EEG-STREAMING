function stream_out(data, protocol, target, varargin)
% STREAM_OUT  Send data from MATLAB to external apps/devices.
%
% Key TouchDesigner mode:
%   stream_out(val, "tcp_server_line", "", 9000)   % MATLAB is TCP server, sends "val\n"
%
% Other modes:
%   stream_out(mat, "tcp_server",      "", 9000)   % TEXT table (rows)
%   stream_out(mat, "tcp",        "127.0.0.1", 9000)
%   stream_out(vec, "udp",        "192.168.1.20", 8000) % binary float32
%   stream_out(vec, "serial",     "/dev/cu.EEG-ESP32", 115200)
%   stream_out([],  "close",      "", 9000)        % close tcpserver on port (optional)
%   stream_out([],  "close",      "", 0, "all")    % close everything

arguments
    data
    protocol   {mustBeTextScalar}
    target     {mustBeTextScalar}
end

arguments (Repeating)
    varargin
end

% persistent handles
persistent tc srv sp u udpTarget udpPort

NL = char(10);

switch lower(string(protocol))

    % =========================================================
    % TCP SERVER (ONE VALUE PER LINE) - TouchDesigner TCP/IP DAT
    % =========================================================
    case "tcp_server_line"
        if numel(varargin) < 1
            error("tcp_server_line requires port number");
        end
        port = varargin{1};

        % Ensure server exists
        if isempty(srv) || ~isvalid(srv)
            srv = tcpserver("0.0.0.0", port);
            srv.ConnectionChangedFcn = @(src,evt) tcp_connection_logger(src,evt);
            fprintf("[stream_out] TCP server (LINE) listening on port %d\n", port);
        end

        % No client -> skip quietly
        if ~srv.Connected
            return
        end

        % Accept numeric scalar only (clean)
        if isempty(data) || ~isnumeric(data) || ~isscalar(data) || ~isfinite(data)
            return
        end

        % One value per line, clean (no spaces)
        line = sprintf('%.6f\n', double(data));  % adjust precision if you want
        try
            write(srv, uint8(line), "uint8");
        catch E
            warning(E.identifier, '[stream_out] TCP server (LINE) write failed: %s', E.message);
            try, clear srv; end %#ok<TRYNC>
            srv = [];
        end


        % ============================
        % TCP CLIENT (TEXT TABLE)
        % ============================
    case "tcp"
        if numel(varargin) < 1
            error("tcp requires port number");
        end
        port = varargin{1};

        payloadText = build_text_payload(data, NL);

        if isempty(tc) || ~isvalid(tc)
            try
                tc = tcpclient(target, port, 'Timeout', 1, 'ConnectTimeout', 1);
                fprintf("[stream_out] TCP client (TEXT) connected to %s:%d\n", target, port);
            catch E
                warning(E.identifier, '[stream_out] TCP client connect failed to %s:%d: %s', ...
                    target, port, E.message);
                return
            end
        end



        try
            write(tc, payloadText, "uint8");
        catch E
            warning(E.identifier, '[stream_out] TCP client write failed: %s', E.message);
            try, clear tc; end %#ok<TRYNC>
            tc = [];
        end


        % ============================
        % TCP SERVER (TEXT TABLE)
        % ============================
    case "tcp_server"
        if numel(varargin) < 1
            error("tcp_server requires port number");
        end
        port = varargin{1};

        if isempty(srv) || ~isvalid(srv)
            try
                srv = tcpserver("0.0.0.0", port);
                srv.ConnectionChangedFcn = @(src,evt) tcp_connection_logger(src,evt);
                fprintf("[stream_out] TCP server (TEXT) listening on port %d\n", port);
            catch E
                warning(E.identifier, '[stream_out] TCP server start failed on port %d: %s', ...
                    port, E.message);
                return
            end
        end

        if ~srv.Connected
            return
        end

        payloadText = build_text_payload(data, NL);

        try
            write(srv, payloadText, "uint8");
        catch E
            warning(E.identifier, '[stream_out] TCP server write failed: %s', E.message);
            try, clear srv; end %#ok<TRYNC>
            srv = [];
        end


        % ============================
        % UDP (binary float32)  [persistent socket for speed]
        % ============================
    case "udp"
        if numel(varargin) < 1
            error("udp requires port number");
        end
        port = varargin{1};

        if ~isnumeric(data)
            error("udp expects numeric data (packed as float32).");
        end

        if isempty(u) || ~isvalid(u)
            u = udpport("datagram");
            udpTarget = "";
            udpPort   = [];
        end

        payload = typecast(single(data(:)), 'uint8');
        payload = payload(:)';

        udpTarget = string(target);
        udpPort   = port;

        try
            write(u, payload, target, port);
        catch E
            warning(E.identifier, '[stream_out] UDP write failed: %s', E.message);
            try, clear u; end %#ok<TRYNC>
            u = [];
        end


        % ============================
        % SERIAL (binary float32 + newline)
        % ============================
    case "serial"
        if numel(varargin) < 1
            error("serial requires baud rate");
        end
        baud = varargin{1};

        if ~isnumeric(data)
            error("serial expects numeric data (packed as float32).");
        end

        if isempty(sp) || ~isvalid(sp)
            sp = serialport(target, baud);
            configureTerminator(sp, "LF");
            fprintf("[stream_out] Serial connected: %s @ %d\n", target, baud);
        end

        payload = typecast(single(data(:)), 'uint8');
        payload = payload(:)';

        write(sp, payload, "uint8");
        write(sp, uint8(10), "uint8");


        % ============================
        % CLOSE / CLEANUP
        % ============================
    case "close"
        portToClose = [];
        closeAll = false;

        if ~isempty(varargin)
            portToClose = varargin{1};
        end
        if numel(varargin) >= 2
            closeAll = strcmpi(string(varargin{2}), "all");
        end

        if ~isempty(srv) && isvalid(srv)
            try
                if isempty(portToClose) || portToClose == 0 || srv.Port == portToClose
                    fprintf('[stream_out] Closing TCP server on port %d\n', srv.Port);
                    try, clear srv; end %#ok<TRYNC>
                    srv = [];
                end
            catch
                try, clear srv; end %#ok<TRYNC>
                srv = [];
            end
        end

        if closeAll
            if ~isempty(tc) && isvalid(tc), try, clear tc; end, tc=[]; end %#ok<TRYNC>
            if ~isempty(sp) && isvalid(sp), try, clear sp; end, sp=[]; end %#ok<TRYNC>
            if ~isempty(u)  && isvalid(u),  try, clear u;  end, u=[];  end %#ok<TRYNC>
        end
        return

    otherwise
        error("Unknown protocol. Use 'tcp', 'tcp_server', 'tcp_server_line', 'udp', 'serial', or 'close'.");
end

end


% ---------- helper: TouchDesigner-friendly TEXT payload ----------
function payloadText = build_text_payload(data, NL)
if isnumeric(data)
    if ismatrix(data)
        lines = join(compose('%.5f', data), " ", 2); % nRows x 1 string
        frameStr = join(lines, NL) + NL;            % ensure trailing newline
    else
        frameStr = join(compose('%.5f', data(:).'), " ") + NL;
    end
    payloadText = uint8(char(frameStr));
    return
end

s = string(data);
if strlength(s) == 0
    payloadText = uint8(NL);
    return
end

c = char(s);
if c(end) ~= NL
    c(end+1) = NL;
end
payloadText = uint8(c);
end
