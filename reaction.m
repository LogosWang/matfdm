function doxi = reaction(CO,Ci,k)
doxi = k*CO(:,1).*Ci(:,1);
end