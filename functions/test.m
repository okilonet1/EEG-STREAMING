host = "127.0.0.1";
port = 6700;   % default RCS 2 port

rcs = tcpclient(host, port, "Timeout", 5);

% Send a harmless status query
cmd = "GETSTATUS" + newline;
write(rcs, cmd, "string");

pause(0.1);  % give RCS time to reply

response = read(rcs, rcs.NumBytesAvailable, "string");
disp(response);
