function data_notched = deep_notch_filter(data, Fs, notch_freq)
    % 深度陷波滤波函数
    notch_bw = 10;
    fir_order = 400;
    
    % 计算归一化频率
    wn = [(notch_freq - notch_bw)/(Fs/2), (notch_freq + notch_bw)/(Fs/2)];
    
    % 设计FIR带阻滤波器
    b_notch = fir1(fir_order, wn, 'stop');
    
    % 级联多个滤波器以获得更深度的抑制
    data_notched = data;
    for cascade = 1:6
        temp_data = zeros(size(data_notched));
        for ch = 1:size(data_notched, 1)
            temp_data(ch, :) = filtfilt(b_notch, 1, data_notched(ch, :));
        end
        data_notched = temp_data;
    end
end
