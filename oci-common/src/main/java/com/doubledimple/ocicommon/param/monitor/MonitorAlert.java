package com.doubledimple.ocicommon.param.monitor;

import lombok.AllArgsConstructor;
import lombok.Data;

@Data
@AllArgsConstructor
public class MonitorAlert {

    private String instanceId;
    private String type;    //CPU_HIGH
    private String message; //CPU 负载过高: 95%
}
