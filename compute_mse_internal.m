% 如果不想放在末尾，也可以将上面的 calc_norm_mse 调用改为直接的循环实现
function avg_mse = compute_mse_internal(data_mat, ref_norm)
    [n_ch, ~] = size(data_mat);
    mse_accum = 0;
    
    for ch = 1:n_ch
        sig = data_mat(ch, :);
        % 1. 通道数据标准化
        sig_norm = (sig - mean(sig)) / std(sig);
        
        % 2. 极性校正：计算相关性
        % 脑磁信号的方向取决于传感器位置，可能与电信号反相
        % 如果相关性为负，将信号翻转，否则 MSE 会因为反相而巨大
        if (sig_norm * ref_norm') < 0 
            sig_norm = -sig_norm;
        end
        
        % 3. 计算该通道的 MSE
        mse_accum = mse_accum + mean((sig_norm - ref_norm).^2);
    end
    
    % 返回所有通道的平均 MSE
    avg_mse = mse_accum / n_ch;
end