function rcs = rcs2_connect(host, port)
    rcs = tcpclient(string(host), double(port), "Timeout", 3);
end

function resp = rcs2_send(rcs, cmd)
    write(rcs, string(cmd) + newline, "string");
    pause(0.1);
    n = rcs.NumBytesAvailable;
    if n > 0
        resp = strtrim(string(read(rcs, n, "string")));
    else
        resp = "";
    end
end
