function postprocess_decouple(Y1, t1, Y2, t2, p, outdir)
% decouple 两段式后处理。
%   Y1/t1: 辐照段切片 (M x nt1);  Y2/t2: 氧化段切片 (M x nt2, 曝露钟从0起)
%   p:     取 p1 (含原始 dose_rate 与 p.dose)
%
% 图的归属:
%   缺陷/金属 x-profile 与界面列: 两段各出一套 (_irr / _oxi)
%   O 沿 GB、氧化物厚度、成分叠加、时空热图: 只用氧化段切片
% csv:
%   生产同名 *_final.csv = 氧化段末态;  另存 6 个 2D 场的 *_irrfinal.csv = 辐照段末态
% mat:
%   fields_timeseries.mat = 氧化段重建场 (辐照段原始轨迹由 driver 存 irr_timeseries.mat)

if ~exist(outdir,'dir'), mkdir(outdir); end
savepng = @(name) exportgraphics(gcf, fullfile(outdir,[name '.png']), 'Resolution', 300);

N = p.nx*p.ny;  ny = p.ny;  nx = p.nx;
nt1 = numel(t1);  nt2 = numel(t2);

% ---------- 重建场: 辐照段 ----------
V_1  = reshape(Y1(     1:  N,:), ny,nx,nt1);  I_1  = reshape(Y1(  N+1:2*N,:), ny,nx,nt1);
Cr_1 = reshape(Y1(2*N+1:3*N,:), ny,nx,nt1);   Fe_1 = reshape(Y1(3*N+1:4*N,:), ny,nx,nt1);
Ni_1 = reshape(Y1(4*N+1:5*N,:), ny,nx,nt1);   Si_1 = reshape(Y1(5*N+1:6*N,:), ny,nx,nt1);

% ---------- 重建场: 氧化段 ----------
V_t  = reshape(Y2(     1:  N,:), ny,nx,nt2);  I_t  = reshape(Y2(  N+1:2*N,:), ny,nx,nt2);
Cr_t = reshape(Y2(2*N+1:3*N,:), ny,nx,nt2);   Fe_t = reshape(Y2(3*N+1:4*N,:), ny,nx,nt2);
Ni_t = reshape(Y2(4*N+1:5*N,:), ny,nx,nt2);   Si_t = reshape(Y2(5*N+1:6*N,:), ny,nx,nt2);
b = 6*N;
O_t       = Y2(b+     1:b+  ny,:);  Cr2O3_t   = Y2(b+  ny+1:b+2*ny,:);
Fe3O4_t   = Y2(b+2*ny+1:b+3*ny,:);  FeCr2O4_t = Y2(b+3*ny+1:b+4*ny,:);
SiO2_t    = Y2(b+4*ny+1:b+5*ny,:);

% ---------- 落盘: 氧化段完整轨迹 ----------
t_out = t2;
save(fullfile(outdir,'fields_timeseries.mat'), ...
     'V_t','I_t','Cr_t','Fe_t','Ni_t','Si_t', ...
     'O_t','Cr2O3_t','Fe3O4_t','FeCr2O4_t','SiO2_t','t_out','p','-v7.3');

% ---------- 落盘: 氧化段末态 (生产同名) ----------
writematrix(V_t (:,:,end), fullfile(outdir,'V_final.csv'));
writematrix(I_t (:,:,end), fullfile(outdir,'I_final.csv'));
writematrix(Cr_t(:,:,end), fullfile(outdir,'Cr_final.csv'));
writematrix(Fe_t(:,:,end), fullfile(outdir,'Fe_final.csv'));
writematrix(Ni_t(:,:,end), fullfile(outdir,'Ni_final.csv'));
writematrix(Si_t(:,:,end), fullfile(outdir,'Si_final.csv'));
writematrix(O_t      (:,end), fullfile(outdir,'O_final.csv'));
writematrix(Cr2O3_t  (:,end), fullfile(outdir,'Cr2O3_final.csv'));
writematrix(Fe3O4_t  (:,end), fullfile(outdir,'Fe3O4_final.csv'));
writematrix(FeCr2O4_t(:,end), fullfile(outdir,'FeCr2O4_final.csv'));
writematrix(SiO2_t   (:,end), fullfile(outdir,'SiO2_final.csv'));

% ---------- 落盘: 辐照段末态 (RIS 对标) ----------
writematrix(V_1 (:,:,end), fullfile(outdir,'V_irrfinal.csv'));
writematrix(I_1 (:,:,end), fullfile(outdir,'I_irrfinal.csv'));
writematrix(Cr_1(:,:,end), fullfile(outdir,'Cr_irrfinal.csv'));
writematrix(Fe_1(:,:,end), fullfile(outdir,'Fe_irrfinal.csv'));
writematrix(Ni_1(:,:,end), fullfile(outdir,'Ni_irrfinal.csv'));
writematrix(Si_1(:,:,end), fullfile(outdir,'Si_irrfinal.csv'));

% Calibration runs are data-only by default.  Keep MAT/CSV outputs required
% by metric extraction, but skip all figure construction and PNG export.
% Set CALIB_ENABLE_PLOTS=1 explicitly to restore the original plots.
enable_plots = strtrim(getenv('CALIB_ENABLE_PLOTS'));
is_calibration = isfield(p,'case_tag') && ~isempty(p.case_tag);
if is_calibration && ~any(strcmpi(enable_plots, {'1','true','yes','on'}))
    fprintf('后处理完成 (decouple, no plots), MAT/CSV -> %s\n', outdir);
    return
end

% ================= 绘图 =================
x = (0:nx-1)*p.dx;  y = (0:ny-1)*p.dy;  j_mid = round(ny/2);
idx1 = 1:10:nt1;  colors1 = parula(numel(idx1));
idx2 = 1:10:nt2;  colors2 = parula(numel(idx2));
tit_irr = sprintf('dose = %g dpa @ %.2g dpa/s (irradiation)', p.dose, p.dose_rate);
tit_oxi = sprintf('dose = %g dpa (oxidation, %g h)', p.dose, t2(end)/3600);

% --- 图 1-6: 2D 场沿 x 的 profile, 辐照段 ---
fields_1 = {V_1,I_1,Cr_1,Fe_1,Ni_1,Si_1};
labels   = {'Vacancy','Interstitial','Cr','Fe','Ni','Si'};
for f = 1:6
    figure(f); clf; hold on; box on;
    for k = 1:numel(idx1)
        i = idx1(k);
        plot(x, squeeze(fields_1{f}(j_mid,:,i)), 'LineWidth',2.5, ...
             'Color',colors1(k,:), 'DisplayName',sprintf('t = %.2e s', t1(i)));
    end
    xlabel('x (nm)','FontSize',24); ylabel([labels{f} ' Concentration'],'FontSize',24)
    title(sprintf('%s, %s', labels{f}, tit_irr),'FontSize',18)
    set(gca,'FontSize',20); legend('show','Location','best','FontSize',14);
    savepng(sprintf('%s_profile_x_irr', labels{f}));
end

% --- 图 7-12: 2D 场沿 x 的 profile, 氧化段 ---
fields_2 = {V_t,I_t,Cr_t,Fe_t,Ni_t,Si_t};
for f = 1:6
    figure(6+f); clf; hold on; box on;
    for k = 1:numel(idx2)
        i = idx2(k);
        plot(x, squeeze(fields_2{f}(j_mid,:,i)), 'LineWidth',2.5, ...
             'Color',colors2(k,:), 'DisplayName',sprintf('t = %.2e s', t2(i)));
    end
    xlabel('x (nm)','FontSize',24); ylabel([labels{f} ' Concentration'],'FontSize',24)
    title(sprintf('%s, %s', labels{f}, tit_oxi),'FontSize',18)
    set(gca,'FontSize',20); legend('show','Location','best','FontSize',14);
    savepng(sprintf('%s_profile_x_oxi', labels{f}));
end

% --- 图 13: O 沿 y (氧化段) ---
figure(13); clf; hold on; box on;
for k = 1:numel(idx2)
    i = idx2(k);
    plot(y, O_t(:,i), 'LineWidth',2.5, 'Color',colors2(k,:), ...
         'DisplayName',sprintf('t = %.2e s', t2(i)));
end
xlabel('y (nm) — along GB','FontSize',24); ylabel('O Concentration','FontSize',24)
title(sprintf('O along GB, %s', tit_oxi),'FontSize',18)
set(gca,'FontSize',20); legend('show','Location','best','FontSize',14);
savepng('O_along_GB');

% --- 图 14-18: 氧化物厚度沿 y (氧化段) ---
oxides_1D   = {Cr2O3_t, Fe3O4_t, FeCr2O4_t, SiO2_t};
oxide_lbl   = {'Cr_2O_3','Fe_3O_4','FeCr_2O_4','SiO_2'};
oxide_fname = {'Cr2O3','Fe3O4','FeCr2O4','SiO2'};
for f = 1:4
    figure(13+f); clf; hold on; box on;
    for k = 1:numel(idx2)
        i = idx2(k);
        plot(y, oxides_1D{f}(:,i), 'LineWidth',2.5, 'Color',colors2(k,:), ...
             'DisplayName',sprintf('t = %.2e s', t2(i)));
    end
    xlabel('y (nm) — along GB','FontSize',24); ylabel([oxide_lbl{f} ' thickness (nm)'],'FontSize',24)
    title(sprintf('%s along GB, %s', oxide_lbl{f}, tit_oxi),'FontSize',18)
    set(gca,'FontSize',20); legend('show','Location','best','FontSize',14);
    savepng(sprintf('%s_along_GB', oxide_fname{f}));
end

% --- 图 19: 最终氧化物叠加 (氧化段末态) ---
figure(19); clf; hold on; box on;
plot(y, Cr2O3_t(:,end),  'LineWidth',3,'DisplayName','Cr_2O_3');
plot(y, Fe3O4_t(:,end),  'LineWidth',3,'DisplayName','Fe_3O_4');
plot(y, FeCr2O4_t(:,end),'LineWidth',3,'DisplayName','FeCr_2O_4');
plot(y, SiO2_t(:,end),   'LineWidth',3,'DisplayName','SiO_2');
plot(y, Cr2O3_t(:,end)+Fe3O4_t(:,end)+FeCr2O4_t(:,end)+SiO2_t(:,end), ...
     'LineWidth',3,'LineStyle','--','DisplayName','Total oxide');
xlabel('y (nm) — along GB','FontSize',24)
ylabel(sprintf('Oxide thickness at t = %.2e s (nm)', t2(end)),'FontSize',24)
title(sprintf('Oxide composition at end, %s', tit_oxi),'FontSize',18)
set(gca,'FontSize',20); legend('show','Location','best','FontSize',14);
savepng('Oxide_composition_final');

% --- 图 20: log10(C_O) 时空热图 (氧化段) ---
figure(20); clf;
imagesc(t2, y, log10(max(O_t,1e-20))); set(gca,'YDir','normal'); colorbar;
xlabel('t (s) — oxidation','FontSize',20); ylabel('y (nm) — along GB','FontSize',20)
title(sprintf('log_{10}(C_O) over time, %s', tit_oxi),'FontSize',18)
set(gca,'FontSize',16); savepng('O_spacetime_log');

% --- 图 21: Cr2O3 时空热图 (氧化段) ---
figure(21); clf;
imagesc(t2, y, Cr2O3_t); set(gca,'YDir','normal'); colorbar;
xlabel('t (s) — oxidation','FontSize',20); ylabel('y (nm) — along GB','FontSize',20)
title(sprintf('C_{Cr_2O_3} over time, %s', tit_oxi),'FontSize',18)
set(gca,'FontSize',16); savepng('Cr2O3_spacetime');

% --- 图 22-25: 界面列沿 y, 辐照段 ---
elems_1  = {Cr_1, Fe_1, Ni_1, Si_1};
elem_lbl = {'Cr','Fe','Ni','Si'};
for f = 1:4
    figure(21+f); clf; hold on; box on;
    for k = 1:numel(idx1)
        i = idx1(k);
        plot(y, squeeze(elems_1{f}(:,1,i)), 'LineWidth',2.5, 'Color',colors1(k,:), ...
             'DisplayName',sprintf('t = %.2e s', t1(i)));
    end
    xlabel('y (nm) — along GB','FontSize',24)
    ylabel([elem_lbl{f} ' at x = 1 (interface)'],'FontSize',24)
    title(sprintf('%s interface column, %s', elem_lbl{f}, tit_irr),'FontSize',18)
    set(gca,'FontSize',20); legend('show','Location','best','FontSize',14);
    savepng(sprintf('%s_interface_along_GB_irr', elem_lbl{f}));
end

% --- 图 26-29: 界面列沿 y, 氧化段 ---
elems_2 = {Cr_t, Fe_t, Ni_t, Si_t};
for f = 1:4
    figure(25+f); clf; hold on; box on;
    for k = 1:numel(idx2)
        i = idx2(k);
        plot(y, squeeze(elems_2{f}(:,1,i)), 'LineWidth',2.5, 'Color',colors2(k,:), ...
             'DisplayName',sprintf('t = %.2e s', t2(i)));
    end
    xlabel('y (nm) — along GB','FontSize',24)
    ylabel([elem_lbl{f} ' at x = 1 (interface)'],'FontSize',24)
    title(sprintf('%s interface column, %s', elem_lbl{f}, tit_oxi),'FontSize',18)
    set(gca,'FontSize',20); legend('show','Location','best','FontSize',14);
    savepng(sprintf('%s_interface_along_GB_oxi', elem_lbl{f}));
end

fprintf('后处理完成 (decouple), 全部输出 -> %s\n', outdir);
end
