% 插入算子：将站点从原位移至目标位置
% Input: original_path -- 原路径; city_index -- 待移站点索引; position -- 目标位置
% Output: new_path -- 插入后的路径
function new_path = insert(original_path, city_index, position)
    if position < 1 || position > length(original_path) + 1
        error('Position out of bounds.');
    end
    city = original_path(city_index);
    new_path = [original_path(1:position-1), city, original_path(position:end)];
    new_path(new_path == city & (1:length(new_path)) ~= position) = [];
end
