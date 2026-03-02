function [data_clean, spike_counts] = remove_spikes_gradient(data, threshold_multiplier)
    % REMOVE_SPIKES_GRADIENT 基于梯度的去尖峰算法 (适合强背景信号)
    % 原理：尖峰在时域上可能被强信号掩盖，但在差分域(斜率)上非常显著。
    % 输入:
    %   data: [通道 x 时间] 数据矩阵
    %   threshold_multiplier: 阈值倍数 (建议 4-6)
    
    [n_ch, n_samples] = size(data);
    data_clean = data;
    spike_counts = zeros(n_ch, 1);
    
    % 遍历通道
    for i = 1:n_ch
        raw_sig = data(i, :);
        
        % 1. 计算一阶差分 (Gradient)
        % diff_sig(t) = sig(t+1) - sig(t)
        % 补一个0保持长度一致
        grad = [0, diff(raw_sig)];
        
        % 2. 统计差分的波动情况
        % 使用中位数绝对偏差 (MAD) 估计标准差，抗离群点干扰能力强
        grad_median = median(grad);
        grad_mad = median(abs(grad - grad_median));
        grad_sigma = 1.4826 * grad_mad; % 转换为等效标准差
        
        % 3. 检测尖峰
        % 如果某点的斜率异常大，则认为是尖峰的起始或结束
        is_spike_edge = abs(grad - grad_median) > (threshold_multiplier * grad_sigma);
        
        % 膨胀检测范围：因为差分检测到的是边缘，我们需要覆盖整个尖峰
        % 使用简单的膨胀 (dilate) 逻辑：如果某点是边缘，其前后1-2个点也是尖峰
        spike_mask = is_spike_edge;
        if sum(spike_mask) > 0
            % 简单的形态学膨胀：将标记点左右各扩展1个点
            spike_mask = conv(double(spike_mask), [1 1 1], 'same') > 0;
            
            % 4. 修复 (线性插值)
            % 找到所有尖峰区域的索引
            bad_indices = find(spike_mask);
            good_indices = find(~spike_mask);
            
            % 如果全是坏点或全是好点，跳过
            if ~isempty(bad_indices) && ~isempty(good_indices)
                % 对坏点进行插值替换
                data_clean(i, bad_indices) = interp1(good_indices, raw_sig(good_indices), bad_indices, 'pchip');
                spike_counts(i) = length(bad_indices);
            end
        end
    end
end