% 交换算子：交换路径中两个站点位置
% Input: route -- 路径向量; idx1, idx2 -- 交换位置
% Output: newRoute -- 交换后的路径
function newRoute = swap(route, idx1, idx2)
    if idx1 < 1 || idx1 > length(route) || idx2 < 1 || idx2 > length(route)
        error('Invalid indices');
    end
    newRoute = route;
    newRoute([idx1, idx2]) = route([idx2, idx1]);
end
