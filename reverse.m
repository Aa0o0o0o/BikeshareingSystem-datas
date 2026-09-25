% 逆序算子：反转路径中一段子序列
% Input: route -- 路径向量; startIdx, endIdx -- 反转起止位置
% Output: newRoute -- 反转后的路径
function newRoute = reverse(route, startIdx, endIdx)
    if startIdx < 1 || endIdx > length(route) || startIdx >= endIdx
        error('Invalid indices');
    end
    newRoute = route;
    newRoute(startIdx:endIdx) = route(endIdx:-1:startIdx);
end
