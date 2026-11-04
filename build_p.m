function p = build_p(drate)
% 非 decouple 模式 (辐照与氧化同时, run_ckpt) 的参数。
% 物理参数全部来自 build_p_decouple, 不在这里另存一份; 这里只改模式不同的量。
p = build_p_decouple(0);        % dose = 0: irr_time = 0, 本模式没有预辐照段
p.dose_rate = drate;            % 全程辐照的剂量率 (dpa/s), run_ckpt 按它分目录
p.t_end     = p.oxi_time;       % 总时长 = decouple 氧化段时长
end
