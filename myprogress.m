function status = myprogress(t, ~, flag, t_end)
    status = 0;
    if isempty(t)        % init/done 时 t 可能为空或异常,直接跳过
        return;
    end
    fprintf('t = %.4e   (%.1f%%)\n', t(end), 100*t(end)/t_end);
end