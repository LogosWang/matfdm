function postprocess_onlyRIS(Y, t_out, p, outdir)
% onlyRIS 专用后处理。适配 onlyRIS/RIS_profile_plots.ipynb。
%
% 为什么单独一个函数: postprocess_matfdm 被 run_ckpt 和一堆 maincp*/de* 入口共用,
% postprocess_decouple 被 run_ckpt_decouple 用, 两个都不能因为 onlyRIS 的需要而改。
% 这里只做一层包装: 先跑通用后处理, 再把 notebook 要读的那几个 csv 换成
% 它期望的形状。其它输出(png / fields_timeseries.mat / V,I,O,氧化物 csv)原样保留。
%
% notebook 的读法:
%     data   = np.loadtxt(f'dose{dose}dpa/{el}_final.csv', delimiter=',')
%     c_half = np.atleast_2d(data)[-1] * 100      # 取最后一行 -> at.%
%     x_half = np.linspace(0, L_X, c_half.size)   # 0 = GB, 向体内
% 所以它要的是【一行】沿 x 的 profile, 长度 = nx, 第 1 个元素在 GB 上。
% 通用后处理写的是 ny×nx 的二维快照, 末行碰巧也是一条 x-profile —— 能读, 但
% "取末行"只是巧合(取的是 j=ny 那一条)。这里改成沿 y 平均的单行, 让它名副其实。

if ~exist(outdir,'dir'), mkdir(outdir); end

% ---------- 1. 通用后处理: png / mat / 全部 csv ----------
postprocess_matfdm(Y, t_out, p, outdir);

% ---------- 2. 把 4 个金属的 *_final.csv 换成沿 y 平均的单行 x-profile ----------
N = p.nx*p.ny;  ny = p.ny;  nx = p.nx;
metals = {'Cr', 2*N+1:3*N; 'Fe', 3*N+1:4*N; 'Ni', 4*N+1:5*N; 'Si', 5*N+1:6*N};
fprintf('[post] 写 onlyRIS 格式的 x-profile (单行, 长度 %d, x=0 在 GB):\n', nx);
for k = 1:size(metals,1)
    C2D  = reshape(Y(metals{k,2}, end), ny, nx);   % 末时刻的 ny×nx 快照
    prof = mean(C2D, 1);                           % 沿 GB 方向平均 -> 1×nx
    % onlyRIS 段没有沿 y 的驱动(无氧化反应), 场本该沿 y 均匀。这里量一下,
    % 若不均匀说明平均掩盖了真实的 y 结构, 出个提示而不是静默。
    spread = max(max(C2D,[],1) - min(C2D,[],1)) / max(max(abs(prof)), realmin);
    writematrix(prof, fullfile(outdir, [metals{k,1} '_final.csv']));
    fprintf('       %-3s  GB=%.4f  体内=%.4f  沿 y 最大相对离散 %.2e\n', ...
            metals{k,1}, prof(1), prof(end), spread);
    if spread > 1e-3
        warning('postprocess_onlyRIS:yNonUniform', ...
            '%s 沿 y 的相对离散 %.2e > 1e-3, 沿 y 平均可能掩盖了真实的 y 结构。', ...
            metals{k,1}, spread);
    end
end
fprintf('[post] 完整二维快照仍在 fields_timeseries.mat 里 (Cr_t 等, ny×nx×nt)\n');
end
