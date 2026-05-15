function dO = dOdt(CCr,CFe,CNi,CSi,CO,J_O,kCr,kNi,kSi,dy)
[ny,nx]=size(CO);
dO = zeros(ny,1);
grad = zeros(ny,1);
for i = 1:ny
    if i ==1
        grad(i,1)=0.0;
    elseif i == ny
        jghost=-J_O(i-1,1);
        grad(i,1)=(jghost-J_O(i-1,1))/dy;
    else
        grad(i,1) = (J_O(i,1)-J_O(i-1,1))/dy;
    end
end
dO=-grad-3*kCr*CO(:,1).*CCr(:,1)-kNi*CO(:,1).*CNi(:,1)-2*kSi*CO(:,1).*CSi(:,1);
dO(1,1) = 0.0;

end