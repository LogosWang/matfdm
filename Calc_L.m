function L = Calc_L(media,CCr,CFe,CNi,CSi,D,f0)
L=zeros(4,4);
C=[CCr,CFe,CNi,CSi];
for i=1:4
    for j = 1:4
        if i==j
            L(i,j)=C(i)*media*D(i)*(1+((1-f0)/f0)*(C(i)*media*D(i))/(sum(C.*D)*media));
        else
            L(i,j)=((1-f0)/f0)*(C(i)*media*D(i)*C(j)*media*D(j))/(sum(C.*D)*media);
        end
    end
end
end