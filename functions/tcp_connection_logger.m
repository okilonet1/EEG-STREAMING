function tcp_connection_logger(src, evt)
% Logs client connect/disconnect events for tcpserver

timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');

if evt.Connected
    fprintf('[%s] Client CONNECTED: IP=%s  Port=%d\n', ...
        timestamp, evt.ClientAddress, evt.ClientPort);
else
    fprintf('[%s] Client DISCONNECTED: IP=%s  Port=%d\n', ...
        timestamp, evt.ClientAddress, evt.ClientPort);
end
