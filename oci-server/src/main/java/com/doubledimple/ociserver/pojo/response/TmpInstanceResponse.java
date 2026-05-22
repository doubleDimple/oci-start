package com.doubledimple.ociserver.pojo.response;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.ociserver.pojo.domain.dto.User;
import com.oracle.bmc.core.model.Instance;
import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName TmpInstanceResponse
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-04-18 14:08
 */
@Data
public class TmpInstanceResponse {

    private User user;
    private String newInstanceId;
    private String cloneBootVolumeId;
    private Instance instance;

    //是否需要删除临时实例 false:不删除,  true:删除
    private boolean deleteInsFlag;

    private String tmpBootVolumeId;

    private InstanceDetails instanceDetails;
}
