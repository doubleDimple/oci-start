package com.doubledimple.ociserver.service.oracle;

import com.doubledimple.ocicommon.param.ApiResponse;

public interface BootVolumeService {


    ApiResponse handleShrink(String instanceDetailId, Long diskNum);
}
