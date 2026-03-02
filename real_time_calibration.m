function data_cali = real_time_calibration(data, Fs, refFreq, targetPeak)
    % 实时校准函数
    nChannels = size(data, 1);
    N_samples = size(data, 2);
    
    % 生成参考信号
    t_signal = (0:N_samples-1) / Fs;
    reference_sin = sin(2*pi*refFreq*t_signal);
    reference_cos = cos(2*pi*refFreq*t_signal);
    
    % 设计FIR滤波器
    fir_order = 100;
    cutoff_freq = [refFreq-5, refFreq+5];
    b_fir = fir1(fir_order, cutoff_freq/(Fs/2), 'bandpass');
    
    % 实时低通滤波器参数
    lp_cutoff = 2;
    [b_lp, a_lp] = butter(2, lp_cutoff/(Fs/2));
    
    % 初始化变量
    data_cali = zeros(size(data));
    
    for ch = 1:nChannels
        % 应用FIR带通滤波器
        filtered_signal = filter(b_fir, 1, data(ch, :));
        
        % 数字锁相放大
        I_component = filtered_signal .* reference_sin;
        Q_component = filtered_signal .* reference_cos;
        
        % 低通滤波提取直流分量
        I_smoothed = filtfilt(b_lp, a_lp, I_component);
        Q_smoothed = filtfilt(b_lp, a_lp, Q_component);
        
        % 计算测量幅度
        measured_amplitude = 2 * sqrt(I_smoothed.^2 + Q_smoothed.^2);
        
        % 计算实时校准因子
        min_amplitude = targetPeak * 0.01;
        realtime_factors = targetPeak ./ max(measured_amplitude, min_amplitude);
        
        % 应用增益（补偿群延迟）
        group_delay = fir_order/2;
        if group_delay < length(realtime_factors)
            compensated_gain = [realtime_factors(group_delay+1:end), ...
                               realtime_factors(end)*ones(1, group_delay)];
        else
            compensated_gain = realtime_factors;
        end
        
        data_cali(ch, :) = data(ch, :) .* compensated_gain;
    end
    
    % 二次基线校准
    initial_values = data_cali(:, 1);
    data_cali = data_cali - initial_values;
end