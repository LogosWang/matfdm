function status = myprogress(t, ~, flag, t_end)
    persistent last_pct
    status = 0;
    
    if strcmp(flag, 'init')
        last_pct = -1;
        return;
    end
    if strcmp(flag, 'done') || isempty(t)
        return;
    end
    
    pct = floor(100 * t(end) / t_end);     % 当前进度整数百分位
    if pct > last_pct
        fprintf('t = %.4e   (%d%%)\n', t(end), pct);
        last_pct = pct;
    end
end