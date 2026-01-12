function resp = rcs_send(rcs, cmd, useCRLF)
    if nargin < 3, useCRLF = false; end
    cmd = string(cmd);

    if useCRLF
        write(rcs, cmd + "\r\n", "string");
    else
        write(rcs, cmd + newline, "string");
    end

    % collect bytes for up to 1s
    resp = "";
    t0 = tic;
    while toc(t0) < 1.0
        n = rcs.NumBytesAvailable;
        if n > 0
            resp = resp + string(read(rcs, n, "string"));
            pause(0.05); % grab trailing bytes
        else
            pause(0.02);
        end
    end
    resp = strtrim(resp);
end
