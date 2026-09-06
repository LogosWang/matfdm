function [JCr_x, JFe_x, JNi_x, JSi_x, JCr_y, JFe_y, JNi_y, JSi_y] = ...
    J_all_via_medium(CCr, CFe, CNi, CSi, media, D, f0, dx, dy, sign_media, cfloor)
fcorr = (1 - f0) / f0;

% 介质(V/I)不再取 log。原来写的是
%     g_X = dlog C_X + s*dlog m ;  J_X = -C_f*m_f*D*(g_X + corr)
% 其中 m_f*dlog m 这一项在 m -> 0 时是 有限 x 无穷, 只能靠给 log 加地板去截,
% 而地板放在哪儿都错: 放在 V_init 上会把边界回流的恢复梯度抹成 0 (V 被钉死在
% 0, 步长塌到 6e-7 s); 放到 realmin 则回复力近乎奇异, 同样卡步长。
%
% 但这一项本来就是个恒等式:   m * dlog m == m * (dm/m) == dm
% 所以把 m_f 乘进括号, 直接写成 dm 的差分, 奇点解析地消掉:
%     m_f*g_X    = m_f*dlog C_X + s*dm
%     m_f*G_x    = sum C_f*D*(m_f*dlog C_X) + s*S_f*dm
%     m_f*corr   = fcorr*(m_f*G_x)/S_f
%     J_X        = -C_f*D*[ (m_f*g_X) + (m_f*corr) ]      (m_f 已在括号内)
% 于是介质只通过 m_f (乘在 dlog C 上, 有限) 和 dm (普通差分, 精确) 出现,
% media 可以精确为 0 而不产生任何问题, 也不需要介质地板。
% 金属浓度仍需 log, 但它们量级 1e-3~0.7, cfloor 远在下方, 只是防 log(0)。
if nargin < 11 || isempty(cfloor), cfloor = 1e-12; end

log_CCr = log(max(CCr, cfloor));   log_CFe = log(max(CFe, cfloor));
log_CNi = log(max(CNi, cfloor));   log_CSi = log(max(CSi, cfloor));

% ====== x 方向所有面 ======
m_f   = 0.5*(media(:,1:end-1) + media(:,2:end));
CCr_f = 0.5*(CCr(:,1:end-1)   + CCr(:,2:end));
CFe_f = 0.5*(CFe(:,1:end-1)   + CFe(:,2:end));
CNi_f = 0.5*(CNi(:,1:end-1)   + CNi(:,2:end));
CSi_f = 0.5*(CSi(:,1:end-1)   + CSi(:,2:end));
S_f   = CCr_f*D(1) + CFe_f*D(2) + CNi_f*D(3) + CSi_f*D(4);

dm    = (media(:,2:end) - media(:,1:end-1))/dx;          % == m_f*dlog m, 精确
a_Cr  = m_f.*(log_CCr(:,2:end) - log_CCr(:,1:end-1))/dx + sign_media*dm;
a_Fe  = m_f.*(log_CFe(:,2:end) - log_CFe(:,1:end-1))/dx + sign_media*dm;
a_Ni  = m_f.*(log_CNi(:,2:end) - log_CNi(:,1:end-1))/dx + sign_media*dm;
a_Si  = m_f.*(log_CSi(:,2:end) - log_CSi(:,1:end-1))/dx + sign_media*dm;

G_x    = CCr_f*D(1).*a_Cr + CFe_f*D(2).*a_Fe + CNi_f*D(3).*a_Ni + CSi_f*D(4).*a_Si;
corr_x = fcorr * G_x ./ S_f;

JCr_x = -CCr_f * D(1) .* (a_Cr + corr_x);
JFe_x = -CFe_f * D(2) .* (a_Fe + corr_x);
JNi_x = -CNi_f * D(3) .* (a_Ni + corr_x);
JSi_x = -CSi_f * D(4) .* (a_Si + corr_x);

% ====== y 方向所有面 ======
m_f   = 0.5*(media(1:end-1,:) + media(2:end,:));
CCr_f = 0.5*(CCr(1:end-1,:)   + CCr(2:end,:));
CFe_f = 0.5*(CFe(1:end-1,:)   + CFe(2:end,:));
CNi_f = 0.5*(CNi(1:end-1,:)   + CNi(2:end,:));
CSi_f = 0.5*(CSi(1:end-1,:)   + CSi(2:end,:));
S_f   = CCr_f*D(1) + CFe_f*D(2) + CNi_f*D(3) + CSi_f*D(4);

dm    = (media(2:end,:) - media(1:end-1,:))/dy;
a_Cr  = m_f.*(log_CCr(2:end,:) - log_CCr(1:end-1,:))/dy + sign_media*dm;
a_Fe  = m_f.*(log_CFe(2:end,:) - log_CFe(1:end-1,:))/dy + sign_media*dm;
a_Ni  = m_f.*(log_CNi(2:end,:) - log_CNi(1:end-1,:))/dy + sign_media*dm;
a_Si  = m_f.*(log_CSi(2:end,:) - log_CSi(1:end-1,:))/dy + sign_media*dm;

G_y    = CCr_f*D(1).*a_Cr + CFe_f*D(2).*a_Fe + CNi_f*D(3).*a_Ni + CSi_f*D(4).*a_Si;
corr_y = fcorr * G_y ./ S_f;

JCr_y = -CCr_f * D(1) .* (a_Cr + corr_y);
JFe_y = -CFe_f * D(2) .* (a_Fe + corr_y);
JNi_y = -CNi_f * D(3) .* (a_Ni + corr_y);
JSi_y = -CSi_f * D(4) .* (a_Si + corr_y);
end
