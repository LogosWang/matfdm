function postprocess_matfdm(Y, t_out, p, outdir)
% 与 main.m 完全一致的保存 + 后处理。main 和 run_ckpt 共用, 保证不漂移。
% Y: M x nt 状态轨迹; t_out: 1 x nt 采样时刻; p: 参数; outdir: 输出文件夹。
% main.m 里把"落盘 + 绘图"整段替换为:  postprocess_matfdm(Y, t_out, p, outdir);
 
if ~exist(outdir,'dir'), mkdir(outdir); end
savepng = @(name) exportgraphics(gcf, fullfile(outdir,[name '.png']), 'Resolution', 300);
 
N = p.nx*p.ny;  ny = p.ny;  nx = p.nx;  nt = numel(t_out);
 
% ---------- 从 Y 重建场 ----------
V_t  = reshape(Y(     1:  N,:), ny,nx,nt);  I_t  = reshape(Y(  N+1:2*N,:), ny,nx,nt);
Cr_t = reshape(Y(2*N+1:3*N,:), ny,nx,nt);   Fe_t = reshape(Y(3*N+1:4*N,:), ny,nx,nt);
Ni_t = reshape(Y(4*N+1:5*N,:), ny,nx,nt);   Si_t = reshape(Y(5*N+1:6*N,:), ny,nx,nt);
b = 6*N;
O_t       = Y(b+     1:b+  ny,:);  Cr2O3_t = Y(b+  ny+1:b+2*ny,:);
Fe3O4_t   = Y(b+2*ny+1:b+3*ny,:);  NiFe2O4_t = Y(b+3*ny+1:b+4*ny,:);
SiO2_t    = Y(b+4*ny+1:b+5*ny,:);
 
% ---------- 落盘: 完整时间轨迹 ----------
save(fullfile(outdir,'fields_timeseries.mat'), ...
     'V_t','I_t','Cr_t','Fe_t','Ni_t','Si_t', ...
     'O_t','Cr2O3_t','Fe3O4_t','NiFe2O4_t','SiO2_t','t_out','p','-v7.3');
 
% ---------- 落盘: 最终时刻快照 ----------
writematrix(V_t (:,:,end), fullfile(outdir,'V_final.csv'));
writematrix(I_t (:,:,end), fullfile(outdir,'I_final.csv'));
writematrix(Cr_t(:,:,end), fullfile(outdir,'Cr_final.csv'));
writematrix(Fe_t(:,:,end), fullfile(outdir,'Fe_final.csv'));
writematrix(Ni_t(:,:,end), fullfile(outdir,'Ni_final.csv'));
writematrix(Si_t(:,:,end), fullfile(outdir,'Si_final.csv'));
writematrix(O_t      (:,end), fullfile(outdir,'O_final.csv'));
writematrix(Cr2O3_t  (:,end), fullfile(outdir,'Cr2O3_final.csv'));
writematrix(Fe3O4_t  (:,end), fullfile(outdir,'Fe3O4_final.csv'));
writematrix(NiFe2O4_t(:,end), fullfile(outdir,'NiFe2O4_final.csv'));
writematrix(SiO2_t   (:,end), fullfile(outdir,'SiO2_final.csv'));
 
% ================= 绘图 (与 main 一致, -nodisplay 下正常保存 png) =================
x = (0:nx-1)*p.dx;  y = (0:ny-1)*p.dy;  j_mid = round(ny/2);
idx = 1:10:nt;  colors = parula(numel(idx));
 
% --- 图 1-6: 2D 场沿 x 的 profile ---
fields_2D = {V_t,I_t,Cr_t,Fe_t,Ni_t,Si_t};
labels_2D = {'Vacancy','Interstitial','Cr','Fe','Ni','Si'};
for f = 1:6
    figure(f); clf; hold on; box on;
    for k = 1:numel(idx)
        i = idx(k);
        plot(x, squeeze(fields_2D{f}(j_mid,:,i)), 'LineWidth',2.5, ...
             'Color',colors(k,:), 'DisplayName',sprintf('t = %.2e s', t_out(i)));
    end
    xlabel('x (nm)','FontSize',24); ylabel([labels_2D{f} ' Concentration'],'FontSize',24)
    title(sprintf('%s, dose rate = %.2g dpa/s', labels_2D{f}, p.dose_rate),'FontSize',18)
    set(gca,'FontSize',20); legend('show','Location','best','FontSize',14);
    savepng(sprintf('%s_profile_x', labels_2D{f}));
end
 
% --- 图 13: O 沿 y ---
figure(13); clf; hold on; box on;
for k = 1:numel(idx)
    i = idx(k);
    plot(y, O_t(:,i), 'LineWidth',2.5, 'Color',colors(k,:), ...
         'DisplayName',sprintf('t = %.2e s', t_out(i)));
end
xlabel('y (nm) — along GB','FontSize',24); ylabel('O Concentration','FontSize',24)
title(sprintf('O along GB, dose rate = %.2g dpa/s', p.dose_rate),'FontSize',18)
set(gca,'FontSize',20); legend('show','Location','best','FontSize',14);
savepng('O_along_GB');
 
% --- 图 14-17: 氧化物厚度沿 y ---
oxides_1D   = {Cr2O3_t, Fe3O4_t, NiFe2O4_t, SiO2_t};
oxide_lbl   = {'Cr_2O_3','Fe_3O_4','NiFe_2O_4','SiO_2'};
oxide_fname = {'Cr2O3','Fe3O4','NiFe2O4','SiO2'};
for f = 1:4
    figure(14+f); clf; hold on; box on;
    for k = 1:numel(idx)
        i = idx(k);
        plot(y, oxides_1D{f}(:,i), 'LineWidth',2.5, 'Color',colors(k,:), ...
             'DisplayName',sprintf('t = %.2e s', t_out(i)));
    end
    xlabel('y (nm) — along GB','FontSize',24); ylabel([oxide_lbl{f} ' thickness (nm)'],'FontSize',24)
    title(sprintf('%s along GB, dose rate = %.2g dpa/s', oxide_lbl{f}, p.dose_rate),'FontSize',18)
    set(gca,'FontSize',20); legend('show','Location','best','FontSize',14);
    savepng(sprintf('%s_along_GB', oxide_fname{f}));
end
 
% --- 图 19: 最终氧化物叠加 ---
figure(19); clf; hold on; box on;
plot(y, Cr2O3_t(:,end),  'LineWidth',3,'DisplayName','Cr_2O_3');
plot(y, Fe3O4_t(:,end),  'LineWidth',3,'DisplayName','Fe_3O_4');
plot(y, NiFe2O4_t(:,end),'LineWidth',3,'DisplayName','NiFe_2O_4');
plot(y, SiO2_t(:,end),   'LineWidth',3,'DisplayName','SiO_2');
plot(y, Cr2O3_t(:,end)+Fe3O4_t(:,end)+NiFe2O4_t(:,end)+SiO2_t(:,end), ...
     'LineWidth',3,'LineStyle','--','DisplayName','Total oxide');
xlabel('y (nm) — along GB','FontSize',24)
ylabel(sprintf('Oxide Concentration at t = %.2e s', t_out(end)),'FontSize',24)
title(sprintf('Oxide composition at end, dose rate = %.2g dpa/s', p.dose_rate),'FontSize',18)
set(gca,'FontSize',20); legend('show','Location','best','FontSize',14);
savepng('Oxide_composition_final');
 
% --- 图 20: log10(C_O) 时空热图 ---
figure(20); clf;
imagesc(t_out, y, log10(max(O_t,1e-20))); set(gca,'YDir','normal'); colorbar;
xlabel('t (s)','FontSize',20); ylabel('y (nm) — along GB','FontSize',20)
title(sprintf('log_{10}(C_O) over time, dose rate = %.2g dpa/s', p.dose_rate),'FontSize',18)
set(gca,'FontSize',16); savepng('O_spacetime_log');
 
% --- 图 21: Cr2O3 时空热图 ---
figure(21); clf;
imagesc(t_out, y, Cr2O3_t); set(gca,'YDir','normal'); colorbar;
xlabel('t (s)','FontSize',20); ylabel('y (nm) — along GB','FontSize',20)
title(sprintf('C_{Cr_2O_3} over time, dose rate = %.2g dpa/s', p.dose_rate),'FontSize',18)
set(gca,'FontSize',16); savepng('Cr2O3_spacetime');
 
fprintf('后处理完成, 全部输出 -> %s\n', outdir);
end
 