function [JCr_x, JFe_x, JNi_x, JSi_x, JCr_y, JFe_y, JNi_y, JSi_y] = ...
    J_all_via_medium(CCr, CFe, CNi, CSi, media, D, f0, dx, dy, sign_media)
fcorr = (1 - f0) / f0;

log_CCr = log(CCr); log_CFe = log(CFe); log_CNi = log(CNi); log_CSi = log(CSi);
log_m   = log(media);

% ====== x 方向所有面 ======
m_f   = 0.5*(media(:,1:end-1) + media(:,2:end));
CCr_f = 0.5*(CCr(:,1:end-1)   + CCr(:,2:end));
CFe_f = 0.5*(CFe(:,1:end-1)   + CFe(:,2:end));
CNi_f = 0.5*(CNi(:,1:end-1)   + CNi(:,2:end));
CSi_f = 0.5*(CSi(:,1:end-1)   + CSi(:,2:end));
S_f   = CCr_f*D(1) + CFe_f*D(2) + CNi_f*D(3) + CSi_f*D(4);

dlogm = (log_m(:,2:end)   - log_m(:,1:end-1))/dx;
g_Cr  = (log_CCr(:,2:end) - log_CCr(:,1:end-1))/dx + sign_media*dlogm;
g_Fe  = (log_CFe(:,2:end) - log_CFe(:,1:end-1))/dx + sign_media*dlogm;
g_Ni  = (log_CNi(:,2:end) - log_CNi(:,1:end-1))/dx + sign_media*dlogm;
g_Si  = (log_CSi(:,2:end) - log_CSi(:,1:end-1))/dx + sign_media*dlogm;

G_x = CCr_f*D(1).*g_Cr + CFe_f*D(2).*g_Fe + CNi_f*D(3).*g_Ni + CSi_f*D(4).*g_Si;
corr_x = fcorr * G_x ./ S_f;

JCr_x = -CCr_f .* m_f * D(1) .* (g_Cr + corr_x);
JFe_x = -CFe_f .* m_f * D(2) .* (g_Fe + corr_x);
JNi_x = -CNi_f .* m_f * D(3) .* (g_Ni + corr_x);
JSi_x = -CSi_f .* m_f * D(4) .* (g_Si + corr_x);

% ====== y 方向所有面 ======
m_f   = 0.5*(media(1:end-1,:) + media(2:end,:));
CCr_f = 0.5*(CCr(1:end-1,:)   + CCr(2:end,:));
CFe_f = 0.5*(CFe(1:end-1,:)   + CFe(2:end,:));
CNi_f = 0.5*(CNi(1:end-1,:)   + CNi(2:end,:));
CSi_f = 0.5*(CSi(1:end-1,:)   + CSi(2:end,:));
S_f   = CCr_f*D(1) + CFe_f*D(2) + CNi_f*D(3) + CSi_f*D(4);

dlogm = (log_m(2:end,:)   - log_m(1:end-1,:))/dy;
g_Cr  = (log_CCr(2:end,:) - log_CCr(1:end-1,:))/dy + sign_media*dlogm;
g_Fe  = (log_CFe(2:end,:) - log_CFe(1:end-1,:))/dy + sign_media*dlogm;
g_Ni  = (log_CNi(2:end,:) - log_CNi(1:end-1,:))/dy + sign_media*dlogm;
g_Si  = (log_CSi(2:end,:) - log_CSi(1:end-1,:))/dy + sign_media*dlogm;

G_y = CCr_f*D(1).*g_Cr + CFe_f*D(2).*g_Fe + CNi_f*D(3).*g_Ni + CSi_f*D(4).*g_Si;
corr_y = fcorr * G_y ./ S_f;

JCr_y = -CCr_f .* m_f * D(1) .* (g_Cr + corr_y);
JFe_y = -CFe_f .* m_f * D(2) .* (g_Fe + corr_y);
JNi_y = -CNi_f .* m_f * D(3) .* (g_Ni + corr_y);
JSi_y = -CSi_f .* m_f * D(4) .* (g_Si + corr_y);
end