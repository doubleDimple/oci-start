package com.doubledimple.ocicommon.param;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * @version 1.0.0
 * @ClassName ThirdApiParam
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-30 14:53
 */
@Data
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class ThirdApiParam {

    private String sign;
    private String openInstanceNotify;

    private String instanceHelpNotify;

    private String openRegionNotify;

    private String installAppNotify;
}
