function J_r = Jreaction(Ci,k)
[ny,nx]=size(Ci);
J_r = zeros(ny,1);
for i=1:ny
    J_r(i,1) = -k*Ci(i,1);
end
end