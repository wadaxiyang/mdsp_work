function data_cleaned = apply_ale_lms(data, Fs, delay_ms, M, mu)
    % APPLY_ALE_LMS 实现基于 NLMS 的自适应谱线增强器
    % 输入:
    %   data: [Channels x Time] 输入数据
    %   Fs: 采样率
    %   delay_ms: 延迟量 (毫秒)
    %   M: 滤波器阶数 (Taps)
    %   mu: 归一化步长 (建议 0.01 - 0.5)
    % 输出:
    %   data_cleaned: 提取出的周期性信号 (ALE输出)
    
    [n_ch, n_samples] = size(data);
    data_cleaned = zeros(n_ch, n_samples);
    
    % 将延迟转换为采样点数
    D = round(delay_ms / 1000 * Fs);
    
    % 正则化参数 (防止分母为0)
    epsilon = 1e-6; 
    
    fprintf('  LMS 进度: ');
    
    for ch = 1:n_ch
        x = data(ch, :); % 输入信号 (含噪声)
        y = zeros(1, n_samples); % 滤波器输出 (预测的信号)
        
        % LMS 权重初始化 (全零)
        w = zeros(M, 1);
        
        % 遍历时间点
        % 从 D+M 开始，确保有足够的数据构建输入向量
        for n = (D + M):n_samples
            % 1. 构建输入向量 (Delayed Input)
            % u(n) = [x(n-D), x(n-D-1), ..., x(n-D-M+1)]
            u = x(n - D : -1 : n - D - M + 1)'; 
            
            % 2. 计算滤波器输出 (预测值)
            y_curr = w' * u;
            
            % 3. 计算误差 (期望信号 - 预测值)
            % 期望信号 d(n) 就是当前的观测值 x(n)
            e = x(n) - y_curr;
            
            % 4. NLMS 权重更新
            % w(n+1) = w(n) + mu * e(n) * u(n) / (u'u + epsilon)
            u_power = u' * u + epsilon; % 输入信号的能量
            w = w + (mu / u_power) * e * u;
            
            % 5. 保存输出
            % y(n) 是信号成分，e(n) 是噪声成分
            y(n) = y_curr;
        end
        
        data_cleaned(ch, :) = y;
        
        % 简单的进度显示
        if mod(ch, 20) == 0
            fprintf('%d..', ch);
        end
    end
    fprintf(' 完成\n');
end